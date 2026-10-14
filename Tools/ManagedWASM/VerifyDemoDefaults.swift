import Foundation
import FirmingoKit

/// Host-only SDK/default-source controller checks use isolated journals and never connect, stage or commit.
@main struct VerifyDemoDefaults {
    /// Reports observable failures without a top-level trap or native UI inspection.
    @MainActor static func main() async {
        do { try await validate() }
        catch { print("Default demo checks failed: \(error)"); exit(1) }
    }

    /// Exercises shipped availability, explicit imports, provider changes, cancellation and fresh SDK revalidation.
    @MainActor private static func validate() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let folder = root.appendingPathComponent(".build/demo-default-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: folder) }
            catch { print("Default check cleanup failed: \(error)") }
        }
        let records = InstallationRecordStore(directory: folder)
        let actual = WorkbenchBuildModel(records: records)
        let workbench = WorkbenchModel()
        defer { actual.stop() }
        await actual.restoreContext(); await actual.restoreAssociations()
        actual.loadSDKResources(); try await wait(actual)
        let pending = ManagedCompilerResourceError.invalidFile("compiler.wasm").localizedDescription
        guard actual.catalogueSource == .bundled, actual.compilerSource == .bundled,
              actual.catalogue?.firmwareBuilds.isEmpty == true, actual.firmwareBuild == nil,
              !actual.bundledCompilerReady, actual.bundledCompilerReason == pending,
              !actual.canBuild, !actual.canRun(on: workbench), actual.association == nil,
              workbench.session == nil else { throw Failure("shipped startup: catalogue=\(actual.catalogue?.manifestSHA256 ?? "none"), reason=\(actual.bundledCompilerReason ?? "none"), ready=\(actual.bundledCompilerReady), status=\(actual.status)") }
        let bundledHash = actual.catalogue?.manifestSHA256
        actual.expectedCatalogueSHA256 = String(repeating: "0", count: 64)
        guard actual.catalogue?.manifestSHA256 == bundledHash else { throw Failure("unused development anchor discarded SDK metadata") }
        actual.buildBoard = .raspberryPiPico
        guard actual.firmwareBuilds.isEmpty, actual.catalogueUnavailableReason != nil else { throw Failure("Pico availability") }
        actual.buildBoard = .nanoRP2040Connect
        print("Actual SDK startup: empty verified catalogue, reviewed-but-absent compiler, no device/build/review/fallback")

        let fixtures = root.appendingPathComponent("Tests/FirmingoKitTests/Fixtures/compiler-catalogue")
        let manifest = fixtures.appendingPathComponent("catalogue.json")
        let bytes = try Data(contentsOf: manifest)
        let anchor = "7eb09989cbab271b0ba0350950fdc684a30a2ac2825488d58bcbfb3a32feba07"
        let catalogue = try await ManagedCompilerCatalogue.load(manifestJSON: bytes, expectedSHA256: anchor)
        guard let descriptor = catalogue.firmwareBuilds.first else { throw Failure("synthetic fixture missing") }
        actual.selectService(folder.appendingPathComponent("missing-service.wasm"))
        actual.expectedCatalogueSHA256 = anchor
        actual.selectCatalogue(manifest); try await wait(actual)
        actual.selectFirmwareBuild(descriptor.id)
        guard actual.catalogueSource == .development, actual.compilerSource == .development, actual.canBuild else {
            throw Failure("explicit imports did not select development sources")
        }
        actual.loadSDKResources()
        guard !actual.isBusy, actual.firmwareBuild?.id == descriptor.id, actual.canBuild else { throw Failure("late startup replaced explicit development choices") }
        actual.selectAssociation(fixtures.appendingPathComponent("association.json")); try await wait(actual)
        actual.trustedAssociation = true
        actual.saveAssociation(); try await wait(actual)
        actual.selectCatalogueSource(.bundled)
        guard actual.catalogue?.manifestSHA256 == bundledHash, actual.firmwareBuild == nil,
              actual.association == nil, !actual.trustedAssociation else { throw Failure("provider switch retained descriptor/review") }
        actual.selectCatalogueSource(.development)
        guard actual.catalogue == nil else { throw Failure("development source automatically restored an old import") }
        actual.selectCatalogue(manifest); try await wait(actual)
        actual.selectFirmwareBuild(descriptor.id)
        actual.selectCompilerSource(.bundled); try await wait(actual)
        guard actual.catalogueSource == .development, actual.firmwareBuild?.id == descriptor.id,
              actual.compilerSource == .bundled, actual.bundledCompilerReason == pending,
              actual.serviceName == "No compiler service selected", !actual.canBuild else { throw Failure("SDK failure fell back to old service or lost explicit development metadata") }
        actual.selectCompilerSource(.development)
        guard !actual.canBuild else { throw Failure("released service capability reused automatically") }
        actual.selectService(folder.appendingPathComponent("missing-service.wasm"))
        actual.expectedCatalogueSHA256 = String(repeating: "0", count: 64)
        actual.selectCatalogue(manifest); try await wait(actual)
        guard actual.catalogue == nil, actual.catalogueSource == .development,
              actual.compilerSource == .development, !actual.canBuild else { throw Failure("failed development import fell back to SDK metadata") }
        print("Explicit source transitions: no automatic reimport/fallback; old output/review/capability invalidated")

        // Synthetic loader injection tests UI observations only; the real SDK revalidates before every build.
        let observedReady = WorkbenchBuildModel(records: records, bundledCatalogueLoader: { catalogue }, bundledCompilerVerifier: {})
        defer { observedReady.stop() }
        observedReady.loadSDKResources(); try await wait(observedReady)
        guard observedReady.bundledCompilerReady, observedReady.firmwareBuild == nil else { throw Failure("injected readiness automatically selected a descriptor") }
        observedReady.selectFirmwareBuild(descriptor.id)
        workbench.address = "invalid"; workbench.port = "not-a-port"; workbench.board = .raspberryPiPico; workbench.backend = .uart
        guard observedReady.canBuild, !observedReady.canRun(on: workbench) else { throw Failure("offline SDK build required endpoint/device evidence") }
        let source = try SketchSourceSnapshot(documentID: UUID(), revision: 1, filename: "check.ino", source: "void setup() {}\nvoid loop() {}")
        observedReady.build(source); try await wait(observedReady)
        guard observedReady.status == pending, !observedReady.bundledCompilerReady, observedReady.bundledCompilerReason == pending,
              observedReady.offlineResult == nil, observedReady.result == nil,
              workbench.session == nil else { throw Failure("cached observation bypassed actual SDK verification") }
        print("Default compiler selection: actual SDK recheck rejects absent service before preprocessing/runtime/device I/O")

        let loader = ScriptedLoader(catalogue: catalogue)
        let failed = WorkbenchBuildModel(records: records, bundledCatalogueLoader: { try await loader.load() }, bundledCompilerVerifier: {})
        defer { failed.stop() }
        failed.loadSDKResources(); try await wait(failed)
        failed.selectFirmwareBuild(descriptor.id)
        await loader.fail()
        failed.loadSDKResources(); try await wait(failed)
        guard failed.catalogue == nil, failed.firmwareBuild == nil, !failed.bundledCompilerReady,
              failed.compilerSource == .bundled, failed.catalogueSource == .bundled,
              failed.bundledCompilerReason == ManagedCompilerResourceError.inventoryIntegrityMismatch.localizedDescription else {
            throw Failure("failed SDK reload retained usable metadata or fell back")
        }

        let loadGate = Gate()
        let cancelled = WorkbenchBuildModel(records: records, bundledCatalogueLoader: { await loadGate.suspend(); return catalogue }, bundledCompilerVerifier: {})
        defer { cancelled.stop() }
        cancelled.loadSDKResources(); try await entered(loadGate)
        cancelled.sourceChanged(revision: 2)
        await loadGate.release(); try await wait(cancelled)
        guard cancelled.catalogue == nil, !cancelled.bundledCompilerReady, cancelled.offlineResult == nil else { throw Failure("late cancelled catalogue published") }
        cancelled.loadSDKResources(); try await wait(cancelled)
        guard cancelled.catalogue?.manifestSHA256 == anchor, cancelled.bundledCompilerReady,
              cancelled.firmwareBuild == nil else { throw Failure("fresh SDK retry or explicit selection") }

        let verifyGate = Gate()
        let stopped = WorkbenchBuildModel(records: records, bundledCatalogueLoader: { catalogue }, bundledCompilerVerifier: { await verifyGate.suspend() })
        stopped.loadSDKResources(); try await entered(verifyGate)
        stopped.stop()
        await verifyGate.release(); try await wait(stopped)
        guard stopped.catalogue == nil, !stopped.bundledCompilerReady else { throw Failure("closed window published late readiness") }
        print("SDK failure/cancel/window closure: stale metadata/readiness discarded; explicit fresh retry works")
    }

    /// Simulates a subsequent SDK integrity failure without altering package resources or public trust anchors.
    private actor ScriptedLoader {
        /// Strict SDK-parsed synthetic metadata, never a bundled production descriptor.
        let catalogue: ManagedCompilerCatalogue
        /// Controlled failure introduced only by the harness.
        private var failing = false
        /// Captures immutable parsed test data.
        init(catalogue: ManagedCompilerCatalogue) { self.catalogue = catalogue }
        /// Models the next failed package load.
        func fail() { failing = true }
        /// Returns a verified fixture or the specific SDK error under test.
        func load() throws -> ManagedCompilerCatalogue {
            if failing { throw ManagedCompilerResourceError.inventoryIntegrityMismatch }
            return catalogue
        }
    }

    /// Deliberately ignores cancellation to prove controller checks reject a late dependency completion.
    private actor Gate {
        /// One finite test wait; the harness always releases it before returning.
        private var continuation: CheckedContinuation<Void, Never>?
        /// Observes entry without an arbitrary sleep establishing ordering.
        private(set) var entered = false
        /// A released gate permits subsequent fresh calls immediately.
        private var released = false
        /// Suspends until explicitly released, preserving the late-delivery race under test.
        func suspend() async {
            entered = true
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        /// Completes only the captured wait and leaves later calls available.
        func release() {
            released = true; continuation?.resume(); continuation = nil
        }
    }

    /// Bounds setup waiting; only the dependency's observable entry authorizes cancellation.
    private static func entered(_ gate: Gate) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await gate.entered) {
            guard ContinuousClock.now < end else { throw Failure("dependency entry deadline") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Gives window-owned operations a finite deadline without contacting a board.
    @MainActor private static func wait(_ model: WorkbenchBuildModel) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isBusy {
            guard ContinuousClock.now < end else { model.cancel(); throw Failure("controller deadline") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Names the failed observable invariant.
    private struct Failure: Error, CustomStringConvertible {
        /// Human-readable regression detail.
        let description: String
        /// Captures a useful failure without a programmer assertion on loaded metadata.
        init(_ description: String) { self.description = description }
    }
}
