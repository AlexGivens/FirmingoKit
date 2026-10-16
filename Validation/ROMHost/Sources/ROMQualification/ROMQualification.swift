import Foundation
import Darwin
import FirmingoKit

/// Explicit macOS developer qualification host over public SDK lifecycle APIs; no automatic discovery or programming.
@main struct ROMQualification {
    /// Prints usage or executes one explicitly selected action, returning failure on uncertainty.
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] {
            print("""
            ROMQualification preflight --manifest FILE --image FILE --output NEW_DIRECTORY
            ROMQualification inspect-volume --volume ROM_ROOT --output NEW_DIRECTORY
            ROMQualification install|paused-install --manifest FILE --image FILE --output NEW_DIRECTORY --volume ROM_ROOT --confirm-board nano_rp2040_connect
            ROMQualification verify --record FILE --output NEW_DIRECTORY --address NUMERIC_IP --device-id HEX_ID
            ROMQualification inspect-record --record FILE --output NEW_DIRECTORY
            Fixed reviewed Nano 0.1.0 application only. Install is an explicit device-changing action.
            paused-install stops after an accepted prefix; it never automatically continues.
            No binary assets, ROM discovery, reset, retry, resume, rollback or direct iOS programming.
            """)
            return
        }
        do { try await run(ROMArguments(args)) }
        catch {
            do { try FileHandle.standardError.write(contentsOf: Data((String(describing: error) + "\n").utf8)) }
            catch { exit(2) }
            exit(1)
        }
    }
    /// Acquires inputs before selecting a device; each branch owns a finite operation and fresh report.
    static func run(_ args: ROMArguments) async throws {
        switch args.command {
        case .inspectVolume:
            let backend = MacOSUF2ProgrammingBackend()
            let volume = try await backend.inspect(volumeURL: args.url("--volume"))
            let journal = try ROMJournal(directory: args.url("--output"), command: args.command.rawValue)
            try await journal.event("backend", volume.backendID)
            try await journal.event("instance", volume.instanceID)
            try await journal.event("infoSHA256", volume.infoSHA256)
            try await journal.event("selectionMeaning", "Generic RP2040 ROM attachment only; no model identification or write permission")
        case .preflight, .install, .pausedInstall:
            let image = try ROMCandidate.load(args)
            let plan = try FirmingoInstallationPlan(image: image, selectedBoard: .nanoRP2040Connect, hostPlatform: .macOS)
            let journal = try ROMJournal(directory: args.url("--output"), command: args.command.rawValue)
            try await journal.event("imageSHA256", image.entry.sha256)
            try await journal.event("manifestSHA256", image.manifestSHA256)
            try await journal.event("flashPayloadRange", String(image.payloadRange.lowerBound) + "..<" + String(image.payloadRange.upperBound))
            try await journal.event("dataEffect", plan.dataEffect)
            try await journal.event("recovery", plan.recoveryInstructions)
            if args.command == .preflight { return }
            let backend = MacOSUF2ProgrammingBackend()
            let volume = try await backend.inspect(volumeURL: args.url("--volume"))
            let installer = FirmingoInstaller(backend: backend)
            let prepared = try await installer.prepare(plan: plan, volume: volume, confirmedPhysicalBoard: .nanoRP2040Connect)
            try await journal.save(prepared.record)
            let paused = args.command == .pausedInstall
            _ = try await installer.execute(prepared) { record in
                try await journal.save(record)
                if paused && record.state == .writeStarted && record.transferredBytes >= 65536 {
                    try await journal.pauseAfterPrefix(record)
                }
            }
        case .inspectRecord, .verify:
            let record = try ROMCandidate.record(args.url("--record"))
            let journal = try ROMJournal(directory: args.url("--output"), command: args.command.rawValue)
            try await journal.save(record)
            try await journal.event("restoredContextOnly", "No attachment, session, execution token or write authority restored")
            if args.command == .inspectRecord {
                try await journal.event("recoveryMeaning", record.state == .writeStarted ? "Outcome unknown after restart; never resume or replay" : record.recoveryInstructions)
                return
            }
            let endpoint = try FirmingoEndpoint(address: args.value("--address"), port: 7420)
            let id = try args.value("--device-id")
            let installer = FirmingoInstaller(backend: MacOSUF2ProgrammingBackend())
            let checked: FirmwareInstallationRecord
            do { checked = try await installer.verify(record, at: endpoint, expectedDeviceID: id) }
            catch FirmwareInstallationError.verificationFailed(let saved, let cause) {
                try await journal.save(saved); throw cause
            }
            try await journal.save(checked)
            try await echo(endpoint: endpoint, deviceID: id)
            try await journal.event("binaryEcho", "256/256 exact bytes; hello is not installed-image attestation")
        }
    }
    /// Verifies actual useful application behavior once, preserving all byte values and bounding response time.
    static func echo(endpoint: FirmingoEndpoint, deviceID: String) async throws {
        let session = try await FirmingoSession.connect(to: endpoint, expectedBoard: .nanoRP2040Connect,
            expectedBackend: .application, expectedDeviceID: deviceID)
        do {
            guard session.device.firmwareVersion == "0.1.0", session.device.targets.isEmpty else { throw ROMFailure("Unexpected release hello.") }
            try await session.openConsole()
            let expected = Data((0...255).map { UInt8($0) }); try await session.sendSerial(expected)
            let actual = try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    var received = Data()
                    for try await part in session.serialBytes {
                        received.append(part)
                        guard received.count <= 256 else { throw ROMFailure("Excess echo bytes.") }
                        if received.count == 256 { return received }
                    }
                    throw ROMFailure("Echo ended early.")
                }
                group.addTask { try await Task.sleep(for: .seconds(5)); throw FirmingoError.timedOut }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw ROMFailure("Missing echo result.") }; return first
            }
            guard actual == expected else { throw ROMFailure("Binary echo mismatch.") }
            try await session.closeConsole(); await session.disconnect()
        } catch { await session.disconnect(); throw error }
    }
}
