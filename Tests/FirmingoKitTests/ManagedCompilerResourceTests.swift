import Foundation
import Testing
@testable import FirmingoKit

/// Actual SDK resource bytes and independently mutated inventories exercise fail-closed bundled loading.
struct ManagedCompilerResourceTests {
    /// Distinguishes the service-free source checkout from an explicitly prepared SDK distribution.
    private static var serviceBundled: Bool {
        guard let root = ManagedCompilerBundle.root() else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("compiler.wasm").path)
    }
    /// Exact reviewed firmware metadata supplies an experimental choice without inventing a binary or device identity.
    @Test func bundledCatalogueAndServiceAvailability() async throws {
        let catalogue = try await ManagedCompilerCatalogue.loadBundled()
        #expect(catalogue.manifestSHA256 == "e341bfc0385fea9b2b026dc624daa26cdeac33286f4bb07243b37c1c31837d0e")
        #expect(catalogue.firmwareBuilds.count == 1)
        #expect(catalogue.firmwareBuilds.first?.id == "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f")
        #expect(catalogue.firmwareBuilds.first?.firmwareCommit == "e0a79d1e47aa90d5dda02ccd284d40b9c2922c12")
        #expect(catalogue.firmwareBuilds.first?.apiAddress == 0x10022c9c)
        #expect(catalogue.unavailableReason(for: .nanoRP2040Connect) == nil)
        #expect(catalogue.unavailableReason(for: .raspberryPiPico) != nil)
        let resources = try await VerifiedManagedResources.load()
        #expect(!resources.page.isEmpty)
        if Self.serviceBundled {
            let toolchain = try await resources.toolchain()
            #expect(toolchain.service.count == VerifiedManagedToolchain.serviceBytes)
        } else {
            await #expect(throws: ManagedCompilerResourceError.invalidFile("compiler.wasm")) { _ = try await resources.toolchain() }
        }
    }

    /// Both default build overloads fail before preprocessing/WebKit and release the busy gate for fresh requests.
    @Test(.enabled(if: !ManagedCompilerResourceTests.serviceBundled)) func defaultCompilerFailsWithoutFallback() async throws {
        let compiler = ManagedSketchCompiler()
        await #expect(throws: ManagedCompilerResourceError.invalidFile("compiler.wasm")) { try await compiler.verifyResources() }
        let legacy = try CompilerFixtures.request(source: "int forbiddenGlobal = 1;\nvoid setup() {}\nvoid loop() {}")
        let offline = try await OfflineCompilerFixtures.request()
        await #expect(throws: ManagedCompilerResourceError.invalidFile("compiler.wasm")) { _ = try await compiler.build(legacy) }
        await #expect(throws: ManagedCompilerResourceError.invalidFile("compiler.wasm")) { _ = try await compiler.build(offline) }
        await #expect(throws: ManagedCompilerResourceError.invalidFile("compiler.wasm")) { _ = try await compiler.build(legacy) }
    }

    /// Anchoring precedes parsing; duplicate keys never change approval or schema interpretation.
    @Test func inventoryAnchorAndDuplicateKeys() async throws {
        let root = try #require(ManagedCompilerBundle.root())
        await #expect(throws: ManagedCompilerResourceError.inventoryIntegrityMismatch) {
            _ = try await VerifiedManagedResources.load(root: root, expectedSHA256: String(repeating: "0", count: 64))
        }
        let original = try String(contentsOf: root.appendingPathComponent("inventory.json"), encoding: .utf8)
        let bytes = Data((original.trimmingCharacters(in: .whitespacesAndNewlines).dropLast() + ",\"schema\":1}").utf8)
        #expect(throws: ManagedCompilerResourceError.incompatibleInventory) { _ = try ManagedCompilerResourceInventory(data: bytes) }
        await #expect(throws: ManagedCompilerResourceError.missingBundle) { _ = try await VerifiedManagedResources.load(root: nil) }
    }

    /// Closed roles, scalar types, recipe/board/ABI/source policy and exact service identity cannot be broadened by metadata.
    @Test(arguments: ["extra", "schema", "booleanSize", "serviceABI", "serviceHash", "servicePath", "approval",
                      "board", "profile", "recipe", "recipeHash", "source", "qualification", "path", "duplicate", "count", "bound", "digest", "runtime"])
    func incompatibleInventory(_ kind: String) throws {
        var object = try inventory()
        var recipe = try #require(object["recipe"] as? [String: Any])
        var service = try #require(object["service"] as? [String: Any])
        var files = try #require(object["files"] as? [[String: Any]])
        switch kind {
        case "extra": object["extra"] = true
        case "schema": object["schema"] = 10
        case "booleanSize": service["bytes"] = true
        case "serviceABI": service["abi"] = 1
        case "serviceHash": service["sha256"] = String(repeating: "0", count: 64)
        case "servicePath": service["path"] = "../compiler.wasm"
        case "approval": service["distributionReview"] = true
        case "board": recipe["board"] = "pico"
        case "profile": recipe["profile"] = "uf2"
        case "recipe": recipe["identifier"] = "latest"
        case "recipeHash": recipe["sha256"] = String(repeating: "0", count: 64)
        case "source": recipe["sourceContract"] = "arbitrary-arduino"
        case "qualification": recipe["qualification"] = "qualified"
        case "path": files[0]["path"] = "%2e%2e/manifest.json"
        case "duplicate": files[1] = files[0]
        case "count": files.removeLast()
        case "bound": files[0]["bytes"] = 16_385
        case "digest": files[1]["sha256"] = String(repeating: "A", count: 64)
        default: files[0]["sha256"] = String(repeating: "0", count: 64)
        }
        object["recipe"] = recipe; object["service"] = service; object["files"] = files
        let bytes = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ManagedCompilerResourceError.incompatibleInventory) { _ = try ManagedCompilerResourceInventory(data: bytes) }
        #expect(throws: ManagedCompilerResourceError.incompatibleInventory) {
            _ = try ManagedCompilerResourceInventory(data: Data(repeating: 32, count: 16_385))
        }
    }

    /// Every role, including licenses/catalogue, is independently verified; same-size byte changes fail.
    @Test(arguments: ["manifest.json", "host.html", "LICENSE-MIT", "LICENSE-APACHE", "catalogue.json",
                      "Firmingo-Compiler-LICENSE", "compiler-package.json", "compiler-sources.json",
                      "service-review.json", "service-source-notices.json", "service-LICENSES.txt", "service-FILE-NOTICES.txt", "consumer-package.json"])
    func corruptedResource(_ path: String) async throws {
        try await withCopy { root in
            let url = root.appendingPathComponent(path)
            var bytes = try Data(contentsOf: url)
            bytes[0] ^= 1
            try bytes.write(to: url)
            await #expect(throws: ManagedCompilerResourceError.resourceIntegrityMismatch(path)) {
                _ = try await VerifiedManagedResources.load(root: root)
            }
        }
    }

    /// Missing, oversized and symlinked local roles cannot become runtime capabilities or select another asset.
    @Test(arguments: ["missing", "oversized", "symlink", "rootSymlink"])
    func invalidFile(_ kind: String) async throws {
        try await withCopy { root in
            let url = root.appendingPathComponent("host.html")
            switch kind {
            case "missing":
                try FileManager.default.removeItem(at: url)
                await #expect(throws: ManagedCompilerResourceError.invalidFile("host.html")) { _ = try await VerifiedManagedResources.load(root: root) }
            case "oversized":
                let expected = try #require(ManagedCompilerResourceInventory(data: Data(contentsOf: root.appendingPathComponent("inventory.json"))).files.first { $0.path == "host.html" })
                try Data(repeating: 32, count: expected.bytes + 1).write(to: url)
                await #expect(throws: ManagedCompilerResourceError.invalidFile("host.html")) { _ = try await VerifiedManagedResources.load(root: root) }
            case "symlink":
                try FileManager.default.moveItem(at: url, to: root.appendingPathComponent("other.html"))
                try FileManager.default.createSymbolicLink(at: url, withDestinationURL: root.appendingPathComponent("other.html"))
                await #expect(throws: ManagedCompilerResourceError.invalidFile("host.html")) { _ = try await VerifiedManagedResources.load(root: root) }
            default:
                let link = root.appendingPathComponent("linked-root")
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
                await #expect(throws: ManagedCompilerResourceError.invalidFile("ManagedCompiler")) { _ = try await VerifiedManagedResources.load(root: link) }
            }
        }
    }

    /// Wrong service bytes fail despite approved metadata; callers cannot rewrite the independently pinned review.
    @Test func approvalGateAndServiceIdentity() async throws {
        try await withCopy { root in
            let url = root.appendingPathComponent("compiler.wasm")
            try Data([0, 97, 115, 109]).write(to: url)
            let reviewed = try await VerifiedManagedResources.load(root: root)
            await #expect(throws: ManagedCompilerResourceError.resourceIntegrityMismatch("compiler.wasm")) { _ = try await reviewed.toolchain() }
            var object = try inventory()
            var service = try #require(object["service"] as? [String: Any])
            service["distributionReview"] = "pending"; object["service"] = service
            let bytes = try JSONSerialization.data(withJSONObject: object)
            try bytes.write(to: root.appendingPathComponent("inventory.json"))
            await #expect(throws: ManagedCompilerResourceError.inventoryIntegrityMismatch) { _ = try await VerifiedManagedResources.load(root: root) }
            // Only internal test injection accepts this changed anchor; no public loader accepts it.
            let pending = try await VerifiedManagedResources.load(root: root, expectedSHA256: NanoManagedContract.digest(bytes))
            await #expect(throws: ManagedCompilerResourceError.serviceApprovalPending) { _ = try await pending.toolchain() }
            service["distributionReview"] = "approved"; object["service"] = service
            let approvedBytes = try JSONSerialization.data(withJSONObject: object)
            try approvedBytes.write(to: root.appendingPathComponent("inventory.json"))
            let approved = try await VerifiedManagedResources.load(root: root, expectedSHA256: NanoManagedContract.digest(approvedBytes))
            await #expect(throws: ManagedCompilerResourceError.resourceIntegrityMismatch("compiler.wasm")) { _ = try await approved.toolchain() }
            try FileManager.default.removeItem(at: url)
            await #expect(throws: ManagedCompilerResourceError.invalidFile("compiler.wasm")) { _ = try await approved.toolchain() }
        }
    }

    /// Pre-cancelled loading preserves CancellationError and a later metadata load remains usable.
    @Test func cancellationAndFreshLoad() async throws {
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ManagedCompilerCatalogue.loadBundled()
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        #expect(try await ManagedCompilerCatalogue.loadBundled().firmwareBuilds.count == 1)
        let compiler = ManagedSketchCompiler()
        let verification = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await compiler.verifyResources()
        }
        await #expect(throws: CancellationError.self) { try await verification.value }
        if Self.serviceBundled { try await compiler.verifyResources() }
        else { await #expect(throws: ManagedCompilerResourceError.invalidFile("compiler.wasm")) { try await compiler.verifyResources() } }
    }

    /// Loads current shipped metadata for independent mutation, never executable or deployment data.
    private func inventory() throws -> [String: Any] {
        let root = try #require(ManagedCompilerBundle.root())
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("inventory.json"))) as? [String: Any])
    }

    /// Isolates every filesystem mutation and reports cleanup failures rather than swallowing them.
    private func withCopy(_ action: (URL) async throws -> Void) async throws {
        let source = try #require(ManagedCompilerBundle.root())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FirmingoResources-" + UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: root)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { Issue.record(error, "Temporary resource cleanup failed") }
        }
        try await action(root)
    }
}
