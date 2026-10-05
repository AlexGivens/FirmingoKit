import FirmingoKit
import Foundation

/// Development-only journal validation; all outputs are beneath .build and no ROM backend is invoked.
@main struct VerifyDemoJournal {
    /// Checks durable save/load, independent operation files, corrupt latest context, and storage failure.
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let output = root.appendingPathComponent(".build/demo-journal-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let store = InstallationRecordStore(directory: output.appendingPathComponent("records", isDirectory: true))
        guard try await store.loadLatest() == nil else { throw Failure.unexpectedRecord }
        let fixture = root.appendingPathComponent("Tests/FirmingoKitTests/Fixtures/lifecycle")
        let manifest = try FirmingoReleaseManifest(data: Data(contentsOf: fixture.appendingPathComponent("synthetic-manifest.json")),
                                                   trustedSource: fixture.appendingPathComponent("synthetic-manifest.json"))
        let hex = try String(contentsOf: fixture.appendingPathComponent("synthetic.uf2.hex"), encoding: .utf8)
        let bytes = try Data(hex.split(whereSeparator: { $0.isWhitespace }).map {
            guard let byte = UInt8($0, radix: 16) else { throw Failure.invalidFixture }
            return byte
        })
        let image = try FirmingoFirmwareImage(bytes: bytes, manifest: manifest, board: .nanoRP2040Connect, profile: .application)
        let plan = try FirmingoInstallationPlan(image: image, selectedBoard: .nanoRP2040Connect, hostPlatform: .macOS)
        let backend = JournalBackend()
        let installer = FirmingoInstaller(backend: backend)
        let volume = try await backend.inspect(volumeURL: output)
        let token = try await installer.prepare(plan: plan, volume: volume, confirmedPhysicalBoard: .nanoRP2040Connect)
        let journal = try await store.save(token.record)
        guard try await store.loadLatest() == token.record,
              try JSONDecoder().decode(FirmwareInstallationRecord.self, from: Data(contentsOf: journal)) == token.record else {
            throw Failure.unexpectedRecord
        }
        let second = try await installer.prepare(plan: plan, volume: volume, confirmedPhysicalBoard: .nanoRP2040Connect)
        _ = try await store.save(second.record)
        guard try await store.loadLatest() == second.record,
              try JSONDecoder().decode(FirmwareInstallationRecord.self, from: Data(contentsOf: journal)) == token.record else {
            throw Failure.unexpectedRecord
        }
        try Data("{}".utf8).write(to: journal.deletingLastPathComponent().appendingPathComponent("latest.json"))
        do {
            _ = try await store.loadLatest()
            throw Failure.corruptRecordAccepted
        } catch is DecodingError { /* Corrupt context must never become execution authority. */ }
        let blocked = output.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        do {
            _ = try await InstallationRecordStore(directory: blocked).save(token.record)
            throw Failure.storageFailureAccepted
        } catch is CocoaError { /* A journal failure must propagate to the awaited SDK callback. */ }
        print("Demo journal save/load, retained operations, corrupt context, and storage failure checks passed. Outputs: \(output.path)")
    }

    /// Explicit assertion failures keep this check independent of test framework/runtime discovery.
    private enum Failure: Error {
        /// Unexpected persistence round-trip or latest operation.
        case unexpectedRecord
        /// Broken literal parser fixture.
        case invalidFixture
        /// Invalid saved context was accepted.
        case corruptRecordAccepted
        /// Storage failure was silently acknowledged.
        case storageFailureAccepted
    }

    /// Read-only fake attachment for issuing prepared context; its writer always fails if called.
    private actor JournalBackend: FirmwareProgrammingBackend {
        /// Separate namespace from every hardware backend.
        nonisolated let identifier = "journal-check"
        /// Returns only synthetic process-local metadata, without inspecting USB or writing a file.
        func inspect(volumeURL: URL) throws -> FirmwareBootloaderVolume {
            try FirmwareBootloaderVolume(backendID: identifier, instanceID: "synthetic", mountURL: volumeURL,
                                         infoSHA256: String(repeating: "1", count: 64))
        }
        /// Programming is forbidden in this host-storage check.
        func write(image: FirmingoFirmwareImage, to volume: FirmwareBootloaderVolume,
                   willWrite: @escaping @Sendable () async throws -> Void,
                   progress: @escaping @Sendable (Int) async throws -> Void) throws {
            throw Failure.storageFailureAccepted
        }
    }
}
