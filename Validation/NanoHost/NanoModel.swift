import Foundation
import FirmingoKit
#if os(macOS)
import AppKit
#endif

/// Explicit qualification commands over public SDK APIs; no discovery, initial flashing or automatic upload.
@MainActor final class NanoModel: ObservableObject {
    /// Numeric endpoint selected by the operator; editing never opens a connection.
    @Published var address = "192.168.77.1"
    /// Operator-selected actual device ID, checked against every connected session.
    @Published var deviceID = ""
    /// Typed resident-only UF2 digest from separately reviewed installation/readback evidence.
    @Published var imageSHA = ""
    /// Human record explaining how the exact installed resident was established.
    @Published var evidenceNote = ""
    /// Optional actual GPIO observation, separate from installation evidence and startup status.
    @Published var observation = ""
    /// One of the two fixed compiled test sketches; no arbitrary artifact loading.
    @Published var sketch = "gpio"
    /// Bounded readable result; transaction success and observed behavior stay separate.
    @Published var status = "Prepare offline sketches first. No board is contacted at launch."
    /// Serializes all host commands and freezes inputs while an async operation runs.
    @Published var busy = false
    /// Explicit process mode for a fresh permission check; no association or device writes are available.
    let permissionCheckOnly = Bundle.main.bundleIdentifier == "com.firmingokit.nanopermission"
        || ProcessInfo.processInfo.arguments.contains("--nano-permission-check")
    /// Observable local one-shot policy, independent of firmware state.
    @Published private(set) var gate = NanoGate()
    /// Current run journal, available for explicit Share results.
    @Published private(set) var journal: URL?
    /// Verified offline results, never reconstructed from a saved filename or fake device ID.
    private var artifacts: [String: ManagedOfflineSketchArtifact] = [:]
    /// Connection holding only the current RAM-stage capability; never restored.
    private var session: FirmingoSession?
    /// Saved transaction supports read-only reconciliation after restart, never commit replay.
    private var record: ManagedUploadRecord?
    /// Sole owned host operation; cancellation propagates through the public SDK.
    private var task: Task<Void, Never>?
    /// Only read-only initial inspection may await permission under an inactive overlay.
    private var inspectionInProgress = false
    /// Bounded append-only-in-memory events, atomically saved after each state transition.
    private var events: [[String: String]] = []
    /// New run directory; prior runs are preserved.
    private var directory: URL?
    /// App-owned pointer to an unresolved transaction across process restarts.
    private var pendingURL: URL?
    /// Immutable generated prepared-SDK provenance, recorded without treating it as installed evidence.
    private var context: [String: String] = [:]
    /// Explicit automation mode permits offline compilation only; device connections remain unavailable.
    private let offlineOnly = ProcessInfo.processInfo.arguments.contains("--nano-offline")
    /// Independently selected automation nonce, or a fresh manual-run identity.
    private let runID: String = {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--nano-run"), index + 1 < args.count, let id = UUID(uuidString: args[index + 1]) { return id.uuidString }
        return UUID().uuidString
    }()

    /// Persists before advancing; no failure to save is treated as permission to commit.
    private func log(_ stage: String, _ detail: String) throws {
        guard events.count < 128, let journal else { throw CocoaError(.fileWriteUnknown) }
        events.append(["stage": stage, "detail": String(detail.prefix(1024))])
        let value: [String: Any] = ["schema": 1, "kind": "nano-sdk-hardware-qualification", "runID": runID, "events": events,
            "firmwareBuildID": NanoGate.buildID, "context": context, "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "hardwareQualified": false, "operationMode": permissionCheckOnly ? "read-only-permission-check" : "normal",
            "note": "Individual observations only; installation/startup/behavior and host platforms require separate review"]
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]).write(to: journal, options: .atomic)
        if offlineOnly {
            try FileHandle.standardError.write(contentsOf: Data(("FIRMINGO_NANO_STAGE:" + stage + "\n").utf8))
        }
    }

    /// Owns finite work and reports errors without automatically retrying any network command.
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        task = Task { @MainActor in
            do { try await operation() }
            catch {
                if let session { await session.disconnect(); self.session = nil }
                status = String(error.localizedDescription.prefix(1024))
                if offlineOnly {
                    do { try FileHandle.standardError.write(contentsOf: Data(("FIRMINGO_NANO_FAILURE:" + status + "\n").utf8)) }
                    catch { status += " Diagnostic export failed: " + error.localizedDescription }
                }
                if self.record != nil, self.gate.state == .staged || self.gate.state == .associated { self.gate.restore() }
                if self.journal != nil {
                    do { try log("failed-or-uncertain", status) }
                    catch { status += " Journal write failed: " + error.localizedDescription }
                }
            }
            busy = false; task = nil
            #if os(macOS)
            if offlineOnly {
                do {
                    if let journal {
                        let bytes = try Data(contentsOf: journal)
                        let files = self.artifacts.mapValues { $0.bytes.base64EncodedString() }
                        let value = ["report": bytes.base64EncodedString(), "capsules": files] as [String: Any]
                        let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                        try FileHandle.standardOutput.write(contentsOf: Data(("FIRMINGO_NANO_OFFLINE:" + encoded.base64EncodedString() + "\n").utf8))
                    }
                } catch { status = "Offline export failed: " + error.localizedDescription }
                NSApplication.shared.terminate(nil)
            }
            #endif
        }
    }

    /// Builds both immutable test sources through the prepared SDK without network or device evidence.
    func prepare() {
        perform {
            guard self.gate.state == .empty, let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { throw NanoGate.Rejected() }
            let directory = documents.appendingPathComponent("NanoQualification-" + self.runID, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            self.directory = directory; self.journal = directory.appendingPathComponent("report.json")
            self.pendingURL = documents.appendingPathComponent("nano-pending-upload.json")
            guard let contextURL = Bundle.main.url(forResource: "qualification-context", withExtension: "json") else { throw NanoGate.Rejected() }
            self.context = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: contextURL))
            guard self.context["consumerManifestSHA256"] == "d042dc7d3869949d8e311fff28c5d66327ba090ba2ec8ff149e3a12019d8ea8c" else { throw NanoGate.Rejected() }
            try self.log("offline-start", "No device operation")
            let catalogue = try await ManagedCompilerCatalogue.loadBundled()
            guard catalogue.manifestSHA256 == "e341bfc0385fea9b2b026dc624daa26cdeac33286f4bb07243b37c1c31837d0e",
                  try catalogue.build(id: NanoGate.buildID).firmwareImageSHA256 == NanoGate.imageSHA else { throw NanoGate.Rejected() }
            let compiler = ManagedSketchCompiler()
            for (name, source, digest) in [("gpio", "void setup() { pinMode(6, 1); }\nvoid loop() { digitalWrite(6, 1); delay(10); }\n", "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"),
                ("console", "void setup() { Serial.println(\"ready\"); }\nvoid loop() { int c = Serial.read(); if (c >= 0) Serial.write(uint8_t(c)); }\n", "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0")] {
                self.status = "Compiling " + name
                let snapshot = try SketchSourceSnapshot(documentID: UUID(), revision: 1, filename: name + ".ino", source: source)
                let request = try ManagedOfflineBuildRequest(snapshot: snapshot, catalogue: catalogue, firmwareBuildID: NanoGate.buildID)
                let result = try await compiler.build(request)
                guard result.artifact.sha256 == digest, result.artifact.compilerReceiptJSON != nil else { throw NanoGate.Rejected() }
                try result.artifact.bytes.write(to: directory.appendingPathComponent(name + ".fms"), options: .withoutOverwriting)
                try result.artifact.reportJSON.write(to: directory.appendingPathComponent(name + "-build-report.json"), options: .withoutOverwriting)
                self.artifacts[name] = result.artifact; try self.log("compiled-" + name, digest)
            }
            try self.gate.prepared()
            if let pendingURL = self.pendingURL, FileManager.default.fileExists(atPath: pendingURL.path) {
                let file = try FileHandle(forReadingFrom: pendingURL); let bytes = try file.read(upToCount: 8193) ?? Data(); try file.close()
                guard bytes.count <= 8192 else { throw NanoGate.Rejected() }
                self.record = try JSONDecoder().decode(ManagedUploadRecord.self, from: bytes)
                self.gate.restore(); self.deviceID = self.record?.deviceID ?? ""
                try self.log("restored-query-only", "Pending transaction restored without a commit capability")
                self.status = "Pending transaction restored. Check status; no commit can be replayed."
            } else { self.status = "Offline sketches verified. Select the actual Nano identity before inspection." }
            try self.log("offline-ready", "Both known capsules verified; no device association or operation performed")
        }
    }

    /// Connects once to the explicitly selected device and checks exact managed-target capabilities.
    private func connect(id: String) async throws -> FirmingoSession {
        guard !offlineOnly else { throw NanoGate.Rejected() }
        let endpoint = try FirmingoEndpoint(address: address)
        let connection = try await FirmingoSession.connect(to: endpoint, expectedBoard: .nanoRP2040Connect,
            expectedBackend: .application, expectedDeviceID: id)
        let device = connection.device
        guard device.firmwareVersion == "0.1.0-m9exp1", device.targets.count == 1,
              let target = device.targets.first, target.id == 1, target.format == "nano-managed-v1",
              target.maximumSize == 4096, target.maximumChunk == 1024, target.authorization == "physical-d2-gnd" else {
            await connection.disconnect(); throw NanoGate.Rejected()
        }
        return connection
    }

    /// Read-only hello inspection never creates a resident association or sends upload commands.
    func inspect() {
        perform {
            guard self.deviceID.utf8.count == 16 else { throw NanoGate.Rejected() }
            self.inspectionInProgress = true
            defer { self.inspectionInProgress = false }
            try self.log("inspection-start", "Read-only connection/hello; original five-second SDK deadline")
            let started = ContinuousClock.now
            self.status = "Inspecting. Approve a local-network prompt if shown; this attempt has a five-second deadline."
            let connection: FirmingoSession
            do { connection = try await self.connect(id: self.deviceID) }
            catch FirmingoError.timedOut {
                throw NSError(domain: "NanoInspection", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Inspection exceeded five seconds. Check the Nano connection and local-network permission, then explicitly choose Inspect again.",
                    NSUnderlyingErrorKey: FirmingoError.timedOut])
            }
            let device = connection.device
            await connection.disconnect()
            let elapsed = started.duration(to: .now).components
            try self.log("inspection-duration", String(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18))
            try self.gate.inspected(address: self.address, deviceID: device.deviceID, bootID: device.bootID)
            try self.log("inspected", "device=" + device.deviceID + " boot=" + device.bootID)
            self.status = "Hello/target checked. Review exact installed resident evidence separately."
        }
    }

    /// Operator action records an assertion of existing installed firmware, explicitly without attestation.
    func associate() {
        perform {
            guard !self.permissionCheckOnly else { throw NanoGate.Rejected() }
            var reviewed = self.gate
            try reviewed.associate(address: self.address, deviceID: self.deviceID, imageSHA: self.imageSHA, note: self.evidenceNote)
            try self.log("operator-associated", self.evidenceNote)
            self.gate = reviewed
            self.status = "Association recorded. Staging requires the separately authorized D2-to-GND arm."
        }
    }

    /// Saves the exact validated transaction before commit can become available.
    private func save(_ record: ManagedUploadRecord) throws {
        guard let pendingURL, let directory else { throw NanoGate.Rejected() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(record)
        let saved = directory.appendingPathComponent("upload-" + record.bootID + "-" + String(record.uploadID) + ".json")
        if FileManager.default.fileExists(atPath: saved.path) {
            guard try Data(contentsOf: saved) == bytes else { throw NanoGate.Rejected() }
        } else { try bytes.write(to: saved, options: .withoutOverwriting) }
        try bytes.write(to: pendingURL, options: .atomic)
        let file = try FileHandle(forWritingTo: pendingURL); try file.synchronize(); try file.close()
        self.record = record
    }

    /// Explicit RAM-only transfer rechecks device/boot/capabilities; no flash commit occurs here.
    func stage() {
        perform {
            guard !self.permissionCheckOnly else { throw NanoGate.Rejected() }
            guard self.gate.state == .associated, let artifact = self.artifacts[self.sketch] else { throw NanoGate.Rejected() }
            let connection = try await self.connect(id: self.deviceID); self.session = connection
            try self.gate.requireStage(address: self.address, deviceID: connection.device.deviceID, bootID: connection.device.bootID)
            let association = try ManagedDeviceAssociation(deviceID: self.deviceID, firmwareBuildID: NanoGate.buildID, evidence: .hostConfirmedExistingFirmware)
            let capsule = try artifact.bind(to: association)
            try self.log("stage-requested", capsule.sha256)
            let record = try await connection.stageManagedUpload(capsule)
            try self.save(record); try Task.checkCancellation(); try self.gate.staged(); try self.log("ram-verified", record.sha256)
            self.status = "RAM verified; flash is unchanged. Install once or abort before the session expires."
        }
    }

    /// Explicit slot replacement; persists intent and consumes the capability before the only commit call.
    func commit() {
        perform {
            guard !self.permissionCheckOnly else { throw NanoGate.Rejected() }
            guard let connection = self.session, let record = self.record else { throw NanoGate.Rejected() }
            try self.gate.requestCommit(); try self.save(record); try self.log("commit-attempted-once", record.sha256)
            self.status = "Commit requested. Any missing reply is uncertain; check status without replay."
            let snapshot = try await connection.commitManagedUpload(record); self.session = nil
            try self.log("commit-reply-" + snapshot.state.rawValue, snapshot.errorCode)
            self.status = "Commit reply: " + snapshot.state.rawValue + ". Check installation/startup separately."
        }
    }

    /// Explicit pre-commit abort disposes RAM staging; no post-commit abort or retry is offered.
    func abort() {
        perform {
            guard self.gate.state == .staged, let connection = self.session, let record = self.record else { throw NanoGate.Rejected() }
            _ = try await connection.abortManagedUpload(record); await connection.disconnect(); self.session = nil
            try self.gate.aborted(); try self.log("aborted", record.sha256); self.status = "RAM stage aborted; no flash commit."
        }
    }

    /// One fresh read-only status query, retaining failed/unknown outcomes instead of replaying commit.
    func reconcile() {
        perform {
            guard self.gate.state == .commitAttempted, let record = self.record else { throw NanoGate.Rejected() }
            let connection = try await self.connect(id: record.deviceID)
            let outcome: ManagedUploadReconciliation
            do { outcome = try await connection.reconcileManagedUpload(record) }
            catch { await connection.disconnect(); throw error }
            await connection.disconnect()
            switch outcome {
            case .unknown(let reason):
                try self.log("unknown", String(describing: reason)); self.status = "Outcome unknown: " + String(describing: reason)
            case .snapshot(let snapshot):
                try self.log("status-" + snapshot.state.rawValue, "error=" + snapshot.errorCode + " slotTouched=" + String(snapshot.slotTouched))
                if snapshot.state == .bootConfirmed { try self.gate.confirmed() }
                if snapshot.state == .aborted { try self.gate.aborted() }
                self.status = "Status: " + snapshot.state.rawValue + ", " + snapshot.errorCode + ". Startup is separate from useful behavior."
            }
        }
    }

    /// Checks all 256 byte values exactly through the public SDK after confirmed console-sketch startup.
    func echo() {
        perform {
            guard self.gate.state == .confirmed, let record = self.record,
                  record.sha256 == self.artifacts["console"]?.sha256 else { throw NanoGate.Rejected() }
            let connection = try await self.connect(id: record.deviceID)
            do {
                guard connection.device.bootID == record.bootID else { throw NanoGate.Rejected() }
                try await connection.openConsole()
                let expected = Data((0...255).map { UInt8($0) }); try await connection.sendSerial(expected)
                let received = try await withThrowingTaskGroup(of: Data.self) { group in
                    group.addTask {
                        var bytes = Data()
                        for try await chunk in connection.serialBytes {
                            bytes.append(chunk)
                            guard bytes.count <= 256 else { throw NanoGate.Rejected() }
                            if bytes.count == 256 { return bytes }
                        }
                        throw NanoGate.Rejected()
                    }
                    group.addTask { try await Task.sleep(for: .seconds(5)); throw FirmingoError.timedOut }
                    defer { group.cancelAll() }
                    guard let first = try await group.next() else { throw NanoGate.Rejected() }; return first
                }
                guard received == expected else {
                    let mismatch = zip(received, expected).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset ?? 0
                    throw NSError(domain: "NanoEcho", code: mismatch, userInfo: [NSLocalizedDescriptionKey: "Binary echo mismatch at offset \(mismatch)"])
                }
                try await connection.closeConsole(); await connection.disconnect()
                try self.log("binary-echo-observed", "256/256 bytes match, including NUL/CR/LF/0xff; no throughput or soak claim")
                self.status = "Exact 256-byte binary echo passed."
            } catch { await connection.disconnect(); throw error }
        }
    }

    /// Records only an operator's observed GPIO6 result, without promoting startup to automatic behavior proof.
    func recordGPIO() {
        perform {
            guard self.gate.state == .confirmed, let record = self.record,
                  record.sha256 == self.artifacts["gpio"]?.sha256, (8...512).contains(self.observation.utf8.count) else { throw NanoGate.Rejected() }
            try self.log("manual-gpio-observation", self.observation)
            self.status = "Manual observation recorded; no automatic GPIO measurement is claimed."
        }
    }

    /// Starts another explicit operation only after a known terminal result; prior evidence remains on disk.
    func next() {
        perform {
            try self.gate.next()
            if let pendingURL = self.pendingURL { try FileManager.default.removeItem(at: pendingURL) }
            self.record = nil; self.imageSHA = ""; self.evidenceNote = ""
            try self.log("next-explicit-operation", "Fresh inspection and association required"); self.status = "Select the next sketch and inspect again."
        }
    }

    /// Permission overlays may leave read-only inspection pending; background/cancel still ends it.
    /// All other work retains cancellation on inactivity; staged capability becomes query-only.
    func inactive(permitPendingInspection: Bool = false) {
        guard !offlineOnly else { return }
        if permitPendingInspection && inspectionInProgress {
            do { try log("inspection-inactive", "Read-only attempt may await permission within its original deadline") }
            catch { status = "Inspection journal failed: " + error.localizedDescription; task?.cancel() }
            return
        }
        task?.cancel()
        if gate.state == .staged {
            gate.restore()
            if let session { Task { await session.disconnect() }; self.session = nil }
            status = "Stage connection closed on inactivity. Check the saved transaction; no commit can be replayed."
        }
    }
}
