import Foundation
import Testing
@testable import FirmingoKit

/// Device-changing state-machine tests use fake memory sinks; fixture bytes never reach hardware.
struct FirmwareInstallerTests {
    /// Creates unique lease keys and a known generic ROM identity, without inspecting actual mounts.
    private func volume(instance: String = UUID().uuidString) throws -> FirmwareBootloaderVolume {
        try FirmwareBootloaderVolume(backendID: "fake-rom-uf2-v1", instanceID: instance,
                                     mountURL: URL(fileURLWithPath: "/fake-selected-ROM"),
                                     infoSHA256: String(repeating: "1", count: 64))
    }
    /// Builds the same local artifact plan used by other deterministic lifecycle tests.
    private func plan(platform: FirmingoInstallationPlan.HostPlatform = .macOS) throws -> FirmingoInstallationPlan {
        try FirmingoInstallationPlan(image: LifecycleFixtures.image(), selectedBoard: .nanoRP2040Connect, hostPlatform: platform)
    }
    /// Prepares an explicitly confirmed fake Nano and a process-local token for a separate execute call.
    private func prepared(_ installer: FirmingoInstaller, volume: FirmwareBootloaderVolume) async throws -> PreparedFirmwareInstallation {
        try await installer.prepare(plan: plan(), volume: volume, confirmedPhysicalBoard: .nanoRP2040Connect)
    }
    /// Supplies hello data derived from an independent firmware vector with explicit release version.
    private func device(version: String = "0.1.0", board: String = "nano_rp2040_connect",
                        backend: FirmingoDevice.Backend = .application, targets: [FirmingoDevice.UploadTarget] = []) throws -> FirmingoDevice {
        let frame = try ProtocolFixtures.frame("hello-response")
        let base = try FirmingoDevice.hello(from: frame, requestID: frame.requestID,
                                            expectedBoard: .nanoRP2040Connect, expectedDeviceID: nil)
        let channel = base.channels[0]
        return FirmingoDevice(protocolMajor: 1, firmwareVersion: version, deviceID: base.deviceID,
                              bootID: base.bootID, boardID: board, maximumPayload: base.maximumPayload,
                              authenticationMode: base.authenticationMode,
                              channels: [.init(id: 1, backend: backend, controls: channel.controls,
                                               receiveQueueBytes: channel.receiveQueueBytes, transmitQueueBytes: channel.transmitQueueBytes,
                                               isOwned: false, uart: nil)], targets: targets)
    }

    /// Inspection/preparation performs no write; awaited records distinguish permission, bytes, and completion.
    @Test func explicitOneShotExecution() async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume)
        let installer = FirmingoInstaller(backend: backend)
        let prepared = try await prepared(installer, volume: volume)
        #expect(await backend.writeCalls == 0)
        let sink = InstallationRecordSink()
        let result = try await installer.execute(prepared) { try await sink.save($0) }
        #expect(result.state == .transferComplete)
        #expect(result.observedDeviceID == nil)
        #expect(result.transferredBytes == result.imageBytes)
        #expect(try await backend.accepted == LifecycleFixtures.bytes())
        #expect(await sink.records.map(\.state) == [.prepared, .writeStarted, .writeStarted, .writeStarted, .transferComplete])
        #expect(await sink.records.map(\.transferredBytes) == [0, 0, 512, 1024, 1024])
        await #expect(throws: FirmwareInstallationError.self) { try await installer.execute(prepared) { try await sink.save($0) } }
        #expect(await backend.writeCalls == 1)
    }
    /// Board confirmation and platform/backend selection prevent wrong-target requests before writing.
    @Test func invalidSelections() async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume)
        let installer = FirmingoInstaller(backend: backend)
        await #expect(throws: FirmwareLifecycleError.boardMismatch) {
            try await installer.prepare(plan: plan(), volume: volume, confirmedPhysicalBoard: .raspberryPiPico)
        }
        await #expect(throws: FirmwareInstallationError.self) {
            try await installer.prepare(plan: plan(platform: .iOS), volume: volume, confirmedPhysicalBoard: .nanoRP2040Connect)
        }
        let changed = try FirmwareBootloaderVolume(backendID: "other", instanceID: volume.instanceID,
                                                  mountURL: volume.mountURL, infoSHA256: volume.infoSHA256)
        await #expect(throws: FirmwareInstallationError.self) { try await prepared(installer, volume: changed) }
        #expect(await backend.writeCalls == 0)
    }
    /// Same mount path after re-enumeration cannot authorize use of the former token.
    @Test func reenumerationBeforeExecution() async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume)
        let installer = FirmingoInstaller(backend: backend)
        let prepared = try await prepared(installer, volume: volume)
        await backend.change(to: try self.volume())
        do {
            _ = try await installer.execute(prepared) { _ in }
            Issue.record("Changed attachment reached a writer")
        } catch FirmwareInstallationError.notStarted(let record, let cause) {
            #expect(record.state == .failedBeforeWrite)
            #expect(record.transferredBytes == 0)
            #expect(cause is FirmwareInstallationError)
        }
        #expect(await backend.writeCalls == 0)
    }
    /// Permission denial/persistence failure before the gate cannot deliver any bytes to the sink.
    @Test func failedBeforeWriteGate() async throws {
        for mode in [FakeFirmwareBackend.Mode.denied, .complete] {
            let volume = try volume()
            let backend = FakeFirmwareBackend(volume: volume, mode: mode)
            let installer = FirmingoInstaller(backend: backend)
            let prepared = try await prepared(installer, volume: volume)
            let sink = InstallationRecordSink(failState: mode == .complete ? .writeStarted : nil)
            do {
                _ = try await installer.execute(prepared) { try await sink.save($0) }
                Issue.record("Expected failure before write permission")
            } catch FirmwareInstallationError.notStarted(let record, _) {
                #expect(record.state == .failedBeforeWrite)
                #expect(record.transferredBytes == 0)
            }
            #expect(await backend.accepted.isEmpty)
            await #expect(throws: FirmwareInstallationError.self) { try await installer.execute(prepared) { _ in } }
        }
    }
    /// Known partial/sync/callback failures remain unknown, including complete bytes with failed durability.
    @Test func failuresAfterGate() async throws {
        for mode in [FakeFirmwareBackend.Mode.partialFailure, .syncFailure, .complete] {
            let volume = try volume()
            let backend = FakeFirmwareBackend(volume: volume, mode: mode)
            let installer = FirmingoInstaller(backend: backend)
            let prepared = try await prepared(installer, volume: volume)
            let sink = InstallationRecordSink(failState: mode == .complete ? .transferComplete : nil)
            do {
                _ = try await installer.execute(prepared) { try await sink.save($0) }
                Issue.record("Expected uncertain programming")
            } catch FirmwareInstallationError.uncertain(let record, _) {
                #expect(record.state == .outcomeUnknown)
                #expect(record.transferredBytes == (mode == .partialFailure ? 512 : 1024))
            }
            #expect(await backend.writeCalls == 1)
            #expect(await sink.records.last?.state == .outcomeUnknown)
        }
    }
    /// Progress persistence failure stops the next chunk while preserving its accepted prefix.
    @Test func failedProgressPersistence() async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume)
        let installer = FirmingoInstaller(backend: backend)
        let prepared = try await prepared(installer, volume: volume)
        let sink = InstallationRecordSink(failProgress: true)
        do { _ = try await installer.execute(prepared) { try await sink.save($0) }; Issue.record("Expected unknown outcome") }
        catch FirmwareInstallationError.uncertain(let record, _) { #expect(record.transferredBytes == 512) }
        #expect(await backend.accepted.count == 512)
        #expect(await backend.synchronizations == 0)
    }
    /// Adapter contract violations cannot return a transfer-complete result.
    @Test(arguments: [FakeFirmwareBackend.Mode.omittedGate, .repeatedGate, .badProgress])
    func invalidBackendBehavior(mode: FakeFirmwareBackend.Mode) async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume, mode: mode)
        let installer = FirmingoInstaller(backend: backend)
        let prepared = try await prepared(installer, volume: volume)
        await #expect(throws: FirmwareInstallationError.self) { try await installer.execute(prepared) { _ in } }
        #expect(await backend.writeCalls == 1)
    }
    /// Actor reentrancy and distinct installer instances cannot overlap writes to one attachment.
    @Test func serializedAcrossInstallers() async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume, mode: .paused)
        let first = FirmingoInstaller(backend: backend)
        let second = FirmingoInstaller(backend: backend)
        let firstToken = try await prepared(first, volume: volume)
        let secondToken = try await prepared(second, volume: volume)
        let write = Task { try await first.execute(firstToken) { _ in } }
        try await backend.entered.wait()
        await #expect(throws: FirmwareInstallationError.self) { try await prepared(first, volume: volume) }
        await #expect(throws: FirmwareInstallationError.self) { try await second.execute(secondToken) { _ in } }
        #expect(await backend.writeCalls == 1)
        await backend.release.signal()
        #expect(try await write.value.state == .transferComplete)
        let thirdToken = try await prepared(second, volume: volume)
        #expect(try await second.execute(thirdToken) { _ in }.state == .transferComplete)
    }
    /// Cancellation after durable write permission is unknown even before any accepted prefix.
    @Test func cancelledAfterGate() async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume, mode: .paused)
        let installer = FirmingoInstaller(backend: backend)
        let prepared = try await prepared(installer, volume: volume)
        let sink = InstallationRecordSink()
        let write = Task { try await installer.execute(prepared) { try await sink.save($0) } }
        try await backend.entered.wait()
        write.cancel()
        do { _ = try await write.value; Issue.record("Expected uncertain cancellation") }
        catch FirmwareInstallationError.uncertain(let record, let cause) {
            #expect(record.state == .outcomeUnknown && record.transferredBytes == 0)
            #expect(cause is CancellationError)
        }
        #expect(await backend.accepted.isEmpty)
        #expect(await sink.records.last?.state == .outcomeUnknown)
        await #expect(throws: FirmwareInstallationError.self) { try await installer.execute(prepared) { _ in } }
    }
    /// Tokens from another installer or superseded preparation cannot be used to write.
    @Test func tokenOriginAndSuperseding() async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume)
        let first = FirmingoInstaller(backend: backend)
        let second = FirmingoInstaller(backend: backend)
        let old = try await prepared(first, volume: volume)
        _ = try await prepared(first, volume: volume)
        await #expect(throws: FirmwareInstallationError.self) { try await first.execute(old) { _ in } }
        await #expect(throws: FirmwareInstallationError.self) { try await second.execute(old) { _ in } }
        let beforeRejectedSelection = try await prepared(first, volume: volume)
        await #expect(throws: FirmwareLifecycleError.boardMismatch) {
            try await first.prepare(plan: plan(), volume: volume, confirmedPhysicalBoard: .raspberryPiPico)
        }
        await #expect(throws: FirmwareInstallationError.self) { try await first.execute(beforeRejectedSelection) { _ in } }
        #expect(await backend.writeCalls == 0)
    }
    /// Fresh hello matching records observations only; restored uncertainty remains unknown.
    @Test func verificationAndRestoredUncertainty() async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume)
        let installer = FirmingoInstaller(backend: backend)
        let prepared = try await prepared(installer, volume: volume)
        let transferred = try await installer.execute(prepared) { _ in }
        let hello = try device()
        let matched = try await installer.verify(transferred) { hello }
        #expect(matched.state == .helloMatched)
        #expect(matched.observedDeviceID == hello.deviceID)
        let unknown = try transferred.updated(state: .outcomeUnknown, transferredBytes: 512)
        let restored = try JSONDecoder().decode(FirmwareInstallationRecord.self, from: JSONEncoder().encode(unknown))
        let observed = try await installer.verify(restored) { hello }
        #expect(observed.state == .outcomeUnknown && observed.transferredBytes == 512)
        #expect(observed.observedBootID == hello.bootID)
        #expect(await backend.writeCalls == 1)
    }
    /// Wrong board/backend/version or transport failure never claims a verified installation.
    @Test func verificationFailures() async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume)
        let installer = FirmingoInstaller(backend: backend)
        let prepared = try await prepared(installer, volume: volume)
        let transferred = try await installer.execute(prepared) { _ in }
        for hello in [try device(version: "other"), try device(board: "raspberry_pi_pico"), try device(backend: .uart),
                      try device(targets: [.init(id: 1, format: "nano-managed-v1", maximumSize: 4096, maximumChunk: 1024, authorization: "physical-d2-gnd")])] {
            do { _ = try await installer.verify(transferred) { hello }; Issue.record("Unexpected verified hello") }
            catch FirmwareInstallationError.verificationFailed(let record, _) { #expect(record.state == .transferComplete) }
        }
        await #expect(throws: FirmwareInstallationError.self) { try await installer.verify(transferred) { throw FirmingoError.timedOut } }
        await #expect(throws: FirmwareInstallationError.self) { try await installer.verify(prepared.record) { try device() } }
        #expect(await backend.writeCalls == 1)
    }
    /// Persistence decoding rejects impossible counts, unknown schemas, profiles, hashes, and states.
    @Test func malformedSavedRecords() async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume)
        let installer = FirmingoInstaller(backend: backend)
        let record = try await prepared(installer, volume: volume).record
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(FirmwareInstallationRecord.self, from: data) == record)
        let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let changes: [(String, Any)] = [("version", 2), ("boardID", "rp2040"), ("profile", "unknown"),
                                      ("firmwareVersion", "0.2.0"), ("imageSHA256", "00"), ("transferredBytes", 1025),
                                      ("imageBytes", 0), ("state", "installed"), ("state", "transferComplete"),
                                      ("state", "helloMatched"), ("targetMountURL", "https://example.invalid/device")]
        for (field, value) in changes {
            var object = original; object[field] = value
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(FirmwareInstallationRecord.self, from: JSONSerialization.data(withJSONObject: object))
            }
        }
        let failure = NSError(domain: "test", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "\0e" + String(repeating: "\u{301}", count: 2000)])
        let bounded = try record.updated(state: .failedBeforeWrite, failure: failure)
        #expect(bounded.failureSummary?.utf8.count == 1023)
        #expect(bounded.failureSummary?.utf8.contains(0) == false)
        #expect(try JSONDecoder().decode(FirmwareInstallationRecord.self, from: JSONEncoder().encode(bounded)) == bounded)
        let failing = try await prepared(installer, volume: volume)
        await #expect(throws: FirmwareInstallationError.self) {
            try await installer.execute(failing) { _ in throw failure }
        }
        let fresh = try await prepared(installer, volume: volume)
        #expect(try await installer.execute(fresh) { _ in }.state == .transferComplete)
    }
    /// ROM labels are parsed strictly and normal directories never become hardware programming targets.
    @Test func romInfoAndNativeTargetRejection() async throws {
        let info = "UF2 Bootloader v3.0\r\nModel: Raspberry Pi RP2\r\nBoard-ID: RPI-RP2\r\n"
        try MacOSUF2ProgrammingBackend.validateROMInfo(Data(info.utf8))
        for text in [info + "Board-ID: RPI-RP2\n", info.replacingOccurrences(of: "RPI-RP2", with: "RP2350"),
                     info.replacingOccurrences(of: "Raspberry Pi RP2", with: "Nano"), info + "\0"] {
            #expect(throws: FirmwareInstallationError.self) { try MacOSUF2ProgrammingBackend.validateROMInfo(Data(text.utf8)) }
        }
        let native = MacOSUF2ProgrammingBackend()
        await #expect(throws: FirmwareInstallationError.self) { try await native.inspect(volumeURL: FileManager.default.temporaryDirectory) }
    }
    /// An owned idle console releases ownership and disconnects before the durable write gate.
    @Test func sessionsCloseBeforeWriting() async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume)
        let installer = FirmingoInstaller(backend: backend)
        let token = try await prepared(installer, volume: volume)
        let response = Data(#"{"ok":true,"result":{}}"#.utf8)
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                        responses: ["serial.open": [response], "serial.close": [response]])
        let session = try await ManagedUploadFixtures.connect(peer)
        try await session.openConsole()
        _ = try await installer.execute(token, closing: [session]) { record in
            if record.state == .writeStarted {
                #expect(await peer.closed)
                #expect(await peer.sentFrames.count == 3)
            }
        }
        let operations = try await peer.sentFrames.map { try WireJSON.parse($0.payload).required("op").string() }
        #expect(operations == ["hello", "serial.open", "serial.close"])
        await #expect(throws: FirmingoError.self) { try await session.openConsole() }
    }
    /// Pending control work and staged managed uploads prevent the programming adapter from running.
    @Test func unresolvedSessionsPreventWriting() async throws {
        let volume = try volume()
        let backend = FakeFirmwareBackend(volume: volume)
        let installer = FirmingoInstaller(backend: backend)
        let response = Data(#"{"ok":true,"result":{}}"#.utf8)
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"), responses: ["serial.open": [response]])
        let session = try await ManagedUploadFixtures.connect(peer)
        try await session.openConsole()
        let request = Task { try await session.serialStatus() }
        await peer.waitForSent(3)
        let pendingToken = try await prepared(installer, volume: volume)
        await #expect(throws: FirmwareInstallationError.self) {
            try await installer.execute(pendingToken, closing: [session]) { _ in }
        }
        #expect(!(await peer.closed))
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        let (managed, managedPeer, _) = try await ManagedUploadFixtures.staged()
        let stagedToken = try await prepared(installer, volume: volume)
        await #expect(throws: FirmwareInstallationError.self) {
            try await installer.execute(stagedToken, closing: [managed]) { _ in }
        }
        #expect(await managedPeer.sentFrames.count == 4)
        #expect(!(await managedPeer.closed))
        #expect(await backend.writeCalls == 0)
        await managed.disconnect()
    }
}
