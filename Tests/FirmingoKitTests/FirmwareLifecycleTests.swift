import Foundation
import Testing
@testable import FirmingoKit

/// Release integrity and reviewable planning tests; no filesystem writer or board is involved.
struct FirmwareLifecycleTests {
    /// Independent literal UF2 bytes establish reversed-block ordering, digest, and sector boundaries.
    @Test func goldenImage() throws {
        let image = try LifecycleFixtures.image()
        #expect(image.bytes.count == 1024)
        #expect(image.entry.sha256 == "3081bc65e24e5fb98dec86bd956dfbf375366e73696dda7d71e38cf1e679ca5f")
        #expect(image.blockCount == 2)
        #expect(image.payloadRange == 0x10000000..<0x10000200)
        #expect(image.affectedFlashRange == 0x10000000..<0x10001000)
        #expect(image.entry.qualification == "compile-tested")
        #expect(image.manifestSHA256.count == 64)
        #expect(image.releaseSource == (try LifecycleFixtures.source()))
    }
    /// The actual observed four-file index parses without making its provisional artifacts qualified.
    @Test func observedReleaseIndex() throws {
        let data = try LifecycleFixtures.data("observed-manifest.json")
        let manifest = try FirmingoReleaseManifest(data: data, trustedSource: LifecycleFixtures.source())
        #expect(manifest.files.count == 4)
        for board in FirmingoBoard.allCases {
            for profile in [FirmingoDevice.Backend.application, .uart] {
                let file = try manifest.entry(for: board, profile: profile)
                #expect(file.fqbn == FirmwareReleaseContract.fqbn(for: board))
                #expect(file.firmwareVersion == "0.1.0")
                #expect(file.qualification == "compile-tested")
            }
        }
    }
    /// Missing exact selections never choose the other board or profile merely because it is RP2040.
    @Test func missingSelectionAndWrongBoardPlan() throws {
        let manifest = try LifecycleFixtures.manifest()
        #expect(throws: FirmwareLifecycleError.missingArtifact) {
            try manifest.entry(for: .raspberryPiPico, profile: .application)
        }
        #expect(throws: FirmwareLifecycleError.missingArtifact) {
            try manifest.entry(for: .nanoRP2040Connect, profile: .uart)
        }
        #expect(throws: FirmwareLifecycleError.boardMismatch) {
            try FirmingoInstallationPlan(image: LifecycleFixtures.image(), selectedBoard: .raspberryPiPico, hostPlatform: .macOS)
        }
    }
    /// Local corruption and truncation fail acquisition integrity even when UF2 headers look valid.
    @Test func mismatchedAcquisition() throws {
        let bytes = try LifecycleFixtures.bytes()
        let manifest = try LifecycleFixtures.manifest()
        for altered in [Data(bytes.dropLast()), bytes + Data([0]), Data(repeating: 0, count: bytes.count)] {
            #expect(throws: FirmwareLifecycleError.self) {
                try FirmingoFirmwareImage(bytes: altered, manifest: manifest, board: .nanoRP2040Connect, profile: .application)
            }
        }
    }
    /// Integrity alone cannot accept malformed magic, flags, family, payload, or block sequencing.
    @Test(arguments: [0, 4, 8, 16, 20, 24, 28, 288, 508])
    func invalidUF2Fields(offset: Int) throws {
        var bytes = try LifecycleFixtures.bytes()
        bytes[offset] ^= 1
        #expect(throws: FirmwareLifecycleError.self) { try LifecycleFixtures.image(bytes) }
    }
    /// Duplicate numbers, missing blocks, address wrapping, EEPROM/RAM destinations, and gaps fail.
    @Test(arguments: [UInt32(0), 0x10000000, 0x10001000, 0x101ff000, 0x10fff000, 0x20000000, 0xffffff00])
    func invalidUF2Addresses(address: UInt32) throws {
        let bytes = try LifecycleFixtures.replacing(12, with: address)
        #expect(throws: FirmwareLifecycleError.self) { try LifecycleFixtures.image(bytes) }
    }
    /// All blocks must be present exactly once; a complete block count is checked against file size.
    @Test func incompleteAndDuplicateBlocks() throws {
        let duplicate = try LifecycleFixtures.replacing(20, with: 0)
        #expect(throws: FirmwareLifecycleError.self) { try LifecycleFixtures.image(duplicate) }
        let bytes = try LifecycleFixtures.bytes()
        #expect(throws: FirmwareLifecycleError.self) { try LifecycleFixtures.image(Data(bytes.prefix(512))) }
        #expect(throws: FirmwareLifecycleError.self) { try UF2ImageLayout(bytes: Data(), board: .nanoRP2040Connect) }
        #expect(throws: FirmwareLifecycleError.self) {
            try UF2ImageLayout(bytes: Data(repeating: 0, count: FirmwareReleaseContract.maximumImageBytes + 512), board: .nanoRP2040Connect)
        }
    }
    /// Unsupported schema/release/channel/format/signatures require review instead of silent fallback.
    @Test(arguments: ["schema_version", "product", "version", "release_channel", "artifact_format", "signatures"])
    func unsupportedManifest(field: String) throws {
        var object = try LifecycleFixtures.object()
        object[field] = field == "schema_version" ? 2 : "unsupported"
        #expect(throws: FirmwareLifecycleError.self) { try LifecycleFixtures.manifest(object) }
    }
    /// Required provenance fields cannot be silently omitted or synthesized by Codable.
    @Test(arguments: ["path", "board_id", "profile", "firmware_version", "bytes", "sha256", "fqbn",
                      "flash_bytes", "static_ram_bytes", "qualification", "build_report_sha256"])
    func missingFileMetadata(field: String) throws {
        var object = try LifecycleFixtures.object()
        var files = try #require(object["files"] as? [[String: Any]])
        files[0].removeValue(forKey: field)
        object["files"] = files
        #expect(throws: FirmwareLifecycleError.self) { try LifecycleFixtures.manifest(object) }
    }
    /// Wrong recipes, traversal/URLs, malformed hashes, budgets, booleans, and inflated evidence fail.
    @Test func invalidFileMetadata() throws {
        let variations: [(String, Any)] = [
            ("board_id", "rp2040"), ("profile", "baseline"), ("firmware_version", "0.1.1"),
            ("path", "../firmingo.uf2"), ("path", "/firmingo.uf2"), ("path", "https://example.invalid/file.uf2"),
            ("path", "nano_rp2040_connect/application/%2e%2e.uf2"), ("path", "a\\b.uf2"),
            ("sha256", String(repeating: "A", count: 64)), ("build_report_sha256", "00"),
            ("fqbn", "rp2040:rp2040:rpipico"), ("bytes", true), ("bytes", 0), ("bytes", 513),
            ("bytes", FirmwareReleaseContract.maximumImageBytes + 512),
            ("flash_bytes", 0), ("flash_bytes", 1048577), ("static_ram_bytes", 196609),
            ("qualification", "hardware-qualified"), ("signature", "unverified")
        ]
        for (field, value) in variations {
            var object = try LifecycleFixtures.object()
            var files = try #require(object["files"] as? [[String: Any]])
            files[0][field] = value
            object["files"] = files
            #expect(throws: FirmwareLifecycleError.self) { try LifecycleFixtures.manifest(object) }
        }
    }
    /// Exact decoded duplicate keys, duplicate board/profile entries, empty lists, and excess work fail.
    @Test func duplicateAndBoundedManifest() throws {
        var object = try LifecycleFixtures.object()
        let files = try #require(object["files"] as? [[String: Any]])
        for value in [[], files + files, Array(repeating: files[0], count: 5)] {
            object["files"] = value
            #expect(throws: FirmwareLifecycleError.self) { try LifecycleFixtures.manifest(object) }
        }
        let text = String(decoding: try LifecycleFixtures.data("synthetic-manifest.json"), as: UTF8.self)
        let duplicate = text.replacingOccurrences(of: "\"schema_version\": 1", with: "\"schema_version\": 1, \"schema_\\u0076ersion\": 1")
        for data in [Data(duplicate.utf8), Data((text + "x").utf8), Data(repeating: 32, count: 16385)] {
            #expect(throws: FirmwareLifecycleError.self) {
                try FirmingoReleaseManifest(data: data, trustedSource: LifecycleFixtures.source())
            }
        }
        // Consumer-specific manifest bounds must not relax the original FMGO parser defaults.
        #expect(throws: FirmingoError.self) { try WireJSON.parse(Data(repeating: 32, count: 4097)) }
    }
    /// Provenance disallows credential-bearing, mutable-query, remote-file, and insecure URLs.
    @Test(arguments: ["http://example.invalid/manifest.json", "https://user:password@example.invalid/file",
                      "https://example.invalid/file?token=value", "https://example.invalid/file#fragment",
                      "file://other-host/manifest.json", "ftp://example.invalid/manifest.json"])
    func unsafeSources(text: String) throws {
        let source = try #require(URL(string: text))
        #expect(throws: FirmwareLifecycleError.self) {
            try FirmingoReleaseManifest(data: LifecycleFixtures.data("synthetic-manifest.json"), trustedSource: source)
        }
    }
    /// Nano and iOS guidance cannot imply an implemented writer, physical identity, or rollback.
    @Test func nanoPlans() throws {
        let image = try LifecycleFixtures.image()
        let mac = try FirmingoInstallationPlan(image: image, selectedBoard: .nanoRP2040Connect, hostPlatform: .macOS)
        let ios = try FirmingoInstallationPlan(image: image, selectedBoard: .nanoRP2040Connect, hostPlatform: .iOS)
        #expect(!mac.canExecuteWithSDK && !ios.canExecuteWithSDK)
        #expect(mac.requiresPhysicalTargetSelection)
        #expect(mac.steps.map(\.id) == [.review, .closeSessions, .enterROM, .selectTarget, .transfer, .verify])
        #expect(ios.steps.map(\.id) == [.review, .closeSessions, .useComputer, .enterROM, .selectTarget, .transfer, .verify])
        #expect(mac.steps.first(where: { $0.id == .enterROM })?.instruction.contains("REC and GND") == true)
        #expect(mac.recoveryInstructions.contains("unknown"))
        #expect(mac.recoveryInstructions.contains("never resume"))
        #expect(mac.dataEffect.contains("no preservation"))
        #expect(mac.verificationLimitations.contains("cannot attest"))
    }
    /// Pico guidance uses its own BOOTSEL procedure and never repurposes Nano physical authorization.
    @Test func picoPlanAndLocalSource() throws {
        var object = try LifecycleFixtures.object()
        let observed = try FirmingoReleaseManifest(data: LifecycleFixtures.data("observed-manifest.json"), trustedSource: LifecycleFixtures.source())
        let entry = try observed.entry(for: .raspberryPiPico, profile: .uart)
        var files = try #require(object["files"] as? [[String: Any]])
        files[0]["path"] = entry.path
        files[0]["board_id"] = entry.board.rawValue
        files[0]["profile"] = entry.profile.rawValue
        files[0]["fqbn"] = entry.fqbn
        object["files"] = files
        let manifest = try FirmingoReleaseManifest(data: JSONSerialization.data(withJSONObject: object),
                                                 trustedSource: URL(fileURLWithPath: "/host-selected/manifest.json"))
        let image = try FirmingoFirmwareImage(bytes: LifecycleFixtures.bytes(), manifest: manifest, board: .raspberryPiPico, profile: .uart)
        let plan = try FirmingoInstallationPlan(image: image, selectedBoard: .raspberryPiPico, hostPlatform: .macOS)
        #expect(plan.steps.first(where: { $0.id == .enterROM })?.instruction.contains("Hold BOOTSEL") == true)
        #expect(!plan.recoveryInstructions.contains("REC"))
        #expect(!plan.canExecuteWithSDK)
        #expect(plan.image.entry.profile == .uart)
    }

    /// Local acquisition uses explicit selected files, propagates missing-file errors, and bounds reads.
    @Test func boundedLocalAcquisition() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error, "Could not remove local artifact test workspace") }
        }
        let manifest = directory.appendingPathComponent("selected.json")
        let image = directory.appendingPathComponent("arbitrary-name.bin")
        try LifecycleFixtures.data("synthetic-manifest.json").write(to: manifest)
        try LifecycleFixtures.bytes().write(to: image)
        let result = try await FirmingoFirmwareImage.load(trustedManifestURL: manifest, imageURL: image,
                                                         board: .nanoRP2040Connect, profile: .application)
        #expect(result.bytes.count == 1024)
        #expect(result.releaseSource == manifest)
        try (LifecycleFixtures.bytes() + Data([0])).write(to: image)
        await #expect(throws: FirmwareLifecycleError.self) {
            try await FirmingoFirmwareImage.load(trustedManifestURL: manifest, imageURL: image,
                                                board: .nanoRP2040Connect, profile: .application)
        }
        try Data(repeating: 32, count: 16385).write(to: manifest)
        await #expect(throws: FirmwareLifecycleError.self) {
            try await FirmingoFirmwareImage.load(trustedManifestURL: manifest, imageURL: image,
                                                board: .nanoRP2040Connect, profile: .application)
        }
        try FileManager.default.removeItem(at: manifest)
        do {
            _ = try await FirmingoFirmwareImage.load(trustedManifestURL: manifest, imageURL: image,
                                                    board: .nanoRP2040Connect, profile: .application)
            Issue.record("Missing local manifest unexpectedly produced an image")
        } catch {
            // Foundation can report missing files through either POSIX streams or Cocoa URL reads.
            // Check the underlying missing-file cause rather than assuming a Cocoa wrapper type.
            let failure = error as NSError
            #expect((failure.domain == NSPOSIXErrorDomain && failure.code == 2) ||
                    (failure.domain == NSCocoaErrorDomain && failure.code == CocoaError.fileReadNoSuchFile.rawValue))
        }
    }
    /// A cancelled acquisition never returns an artifact; remote URLs and directories are rejected.
    @Test func cancelledAndInvalidLocalAcquisition() async throws {
        let source = try LifecycleFixtures.source()
        await #expect(throws: FirmwareLifecycleError.self) {
            try await FirmingoFirmwareImage.load(trustedManifestURL: source, imageURL: source,
                                                board: .nanoRP2040Connect, profile: .application)
        }
        let directory = FileManager.default.temporaryDirectory
        await #expect(throws: CocoaError.self) {
            try await FirmingoFirmwareImage.load(trustedManifestURL: directory, imageURL: directory,
                                                board: .nanoRP2040Connect, profile: .application)
        }
        await #expect(throws: CancellationError.self) {
            try await withThrowingTaskGroup(of: FirmingoFirmwareImage.self) { group in
                // Children added to a cancelled group start cancelled, without scheduling assumptions.
                group.cancelAll()
                group.addTask {
                    try await FirmingoFirmwareImage.load(trustedManifestURL: directory, imageURL: directory,
                                                        board: .nanoRP2040Connect, profile: .application)
                }
                for try await _ in group { Issue.record("Cancelled local acquisition produced an image") }
            }
        }
    }
}
