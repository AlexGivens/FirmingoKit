import AppKit
import Foundation
import FirmingoKit

/// Development-only controller checks use synthetic test metadata and real WASM, without connecting or uploading.
@main struct VerifyDemoCatalogue {
    /// Reports controlled failures without a top-level trap or any device access.
    @MainActor static func main() async {
        do { try await validate() }
        catch { print("Demo catalogue validation failed: \(error)"); exit(1) }
    }

    /// Checks exact SDK selection, offline revision cancellation, reviewed evidence gates and durable-context conflicts.
    @MainActor private static func validate() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let folder = root.appendingPathComponent(".build/managed-wasm/catalogue-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: folder) }
            catch { print("Temporary catalogue check cleanup failed: \(error)") }
        }
        let fixtures = root.appendingPathComponent("Tests/FirmingoKitTests/Fixtures/compiler-catalogue")
        let manifest = fixtures.appendingPathComponent("catalogue.json")
        let association = fixtures.appendingPathComponent("association.json")
        let hash = "7eb09989cbab271b0ba0350950fdc684a30a2ac2825488d58bcbfb3a32feba07"
        let descriptorID = "818e03b95a375fdeeb584ec1daf7261561bf918255dec3b14fb3b22e75750d4d"
        let journal = InstallationRecordStore(directory: folder)
        let model = WorkbenchBuildModel(records: journal)
        defer { model.stop() }
        await model.restoreContext()
        await model.restoreAssociations()
        model.selectService(root.appendingPathComponent(".build/managed-wasm/compiler-bounded.wasm"))
        model.expectedCatalogueSHA256 = hash
        model.selectCatalogue(manifest)
        try await wait(model)
        guard model.catalogue?.firmwareBuilds.count == 1, model.firmwareBuild == nil, !model.canBuild else {
            throw Failure("Catalogue import automatically selected a firmware build")
        }
        model.selectFirmwareBuild(String(repeating: "9", count: 64))
        guard model.firmwareBuild == nil else { throw Failure("Unknown ID silently selected another build") }
        model.selectFirmwareBuild(descriptorID)
        model.selectFirmwareBuild(String(repeating: "9", count: 64))
        guard !model.canBuild, model.firmwareBuild == nil else { throw Failure("Unknown selection retained an older usable build") }
        model.selectFirmwareBuild(descriptorID)
        let workbench = WorkbenchModel()
        defer { workbench.stopForWindowClose() }
        guard model.canBuild, !model.canRun(on: workbench), model.association == nil else { throw Failure("Offline/device evidence gate") }
        model.buildBoard = .raspberryPiPico
        guard model.firmwareBuilds.isEmpty, !model.canBuild, model.catalogueUnavailableReason != nil else { throw Failure("Pico availability") }
        model.buildBoard = .nanoRP2040Connect
        guard !model.canBuild else { throw Failure("Board change restored a latest build") }
        model.selectFirmwareBuild(descriptorID)
        print("SDK selection: no automatic/latest choice, unknown ID rejection and Pico unavailable")

        let source = "void setup() { pinMode(LED_BUILTIN, OUTPUT); }\nvoid loop() { digitalWrite(LED_BUILTIN, HIGH); delay(100); digitalWrite(LED_BUILTIN, LOW); delay(100); }\n"
        let snapshot = try SketchSourceSnapshot(documentID: UUID(), revision: 1, filename: "Blink.ino", source: source)
        // Deliberately unusable device settings prove offline Build never validates or connects to an endpoint.
        workbench.board = .raspberryPiPico; workbench.backend = .uart
        workbench.address = "invalid endpoint"; workbench.port = "invalid port"
        model.build(snapshot)
        try await wait(model, until: { model.status == "Compiling…" || !model.isBusy })
        guard model.isBusy else { throw Failure("Worker finished before source cancellation check") }
        model.sourceChanged(revision: 2)
        try await wait(model)
        guard model.offlineResult == nil, model.result == nil else { throw Failure("Stale source artifact survived") }
        let fresh = try SketchSourceSnapshot(documentID: snapshot.documentID, revision: 2, filename: "Blink.ino", source: source)
        model.build(fresh)
        try await wait(model)
        guard let built = model.offlineResult, model.result == nil,
              built.artifact.sha256 == "018c94a4a49b71880d6f04aecbe08e809c8ecf49e4278261c45dad3ead205720",
              built.artifact.receipt.sourceRevision == 2, built.artifact.receipt.firmwareBuildID == descriptorID,
              built.artifact.receipt.catalogueSHA256 == hash, model.association == nil else { throw Failure("Fresh offline build") }
        print("Real offline WebKit build: edit cancellation, fresh exact receipt and no device/endpoint dependency")

        model.selectAssociation(association)
        try await wait(model)
        guard model.association?.firmwareBuildID == descriptorID, !model.trustedAssociation, model.canBuild,
              model.offlineResult != nil, !model.canRun(on: workbench) else { throw Failure("Association import granted trust or invalidated offline output") }
        model.trustedAssociation = true
        model.build(fresh)
        model.trustedAssociation = false
        try await wait(model)
        guard model.offlineResult != nil, model.canBuild else { throw Failure("Device review revocation cancelled an offline build") }
        model.trustedAssociation = true
        guard !model.canRun(on: workbench) else { throw Failure("Wrong device board/backend enabled Run") }
        model.saveAssociation()
        try await wait(model)
        workbench.board = .nanoRP2040Connect; workbench.backend = .application
        workbench.address = "192.168.77.1"; workbench.port = "7420"
        model.selectionChanged()
        guard !model.trustedAssociation, model.canBuild, model.offlineResult == nil else { throw Failure("Device change review boundary") }
        // No Run is called with an empty durable journal; this harness never opens a connection.
        model.trustedAssociation = true
        guard model.canRun(on: workbench) else { throw Failure("Reviewed matching evidence did not enable explicit Run") }
        let restored = try requireAssociation(model.association)
        guard try built.artifact.bind(to: restored).resident.deviceID == "0102030405060708" else { throw Failure("Exact association binding") }
        model.trustedAssociation = false
        guard !model.canRun(on: workbench), model.canBuild else { throw Failure("Review revocation disabled offline Build") }
        print("Device evidence: import never grants trust; board/backend/selection and review gates remain separate")

        let mismatch: [String: Any] = ["version": 1, "deviceID": "0102030405060708", "firmwareBuildID": String(repeating: "8", count: 64), "evidence": "hostConfirmedExistingFirmware"]
        let mismatchURL = folder.appendingPathComponent("mismatch.json")
        try JSONSerialization.data(withJSONObject: mismatch).write(to: mismatchURL)
        model.selectAssociation(mismatchURL)
        try await wait(model)
        guard model.association == nil, !model.trustedAssociation, model.canBuild else { throw Failure("Mismatched association accepted") }
        model.selectAssociation(association)
        try await wait(model)
        model.trustedAssociation = true
        let savedFields: [String: Any] = ["version": 1, "deviceID": "0102030405060708", "bootID": "1112131415161718",
            "boardID": "nano_rp2040_connect", "targetID": 1, "format": "nano-managed-v1", "uploadID": 1,
            "size": built.artifact.bytes.count, "sha256": built.artifact.sha256,
            "residentELFSHA256": String(repeating: "0", count: 64), "firmwareImageSHA256": String(repeating: "1", count: 64)]
        let saved = try JSONDecoder().decode(ManagedUploadRecord.self, from: JSONSerialization.data(withJSONObject: savedFields))
        let operation = try await journal.beginManagedRun()
        try await journal.saveManaged(saved, operation: operation)
        await journal.finishDeviceOperation(operation)
        model.selectService(folder.appendingPathComponent("intentionally-missing.wasm"))
        guard !model.trustedAssociation, !model.canRun(on: workbench) else { throw Failure("Compiler resource change retained Run review") }
        model.trustedAssociation = true
        model.run(fresh, workbench: workbench)
        try await wait(model)
        guard model.pendingRecord == saved, model.offlineResult == nil, !workbench.isManagedOperation,
              model.status == DemoOperationError.pendingManagedTransaction.localizedDescription else { throw Failure("Stale window bypassed durable preflight") }
        print("Catalogue Run: stale durable context blocks before service loading, connection or staging")

        model.expectedCatalogueSHA256 = String(repeating: "0", count: 64)
        guard model.catalogue == nil, model.firmwareBuild == nil, model.association == nil, !model.canBuild else { throw Failure("Anchor edit retained prior metadata") }
        model.selectCatalogue(manifest)
        try await wait(model)
        guard model.catalogue == nil else { throw Failure("Incorrect trust anchor accepted") }
        model.expectedCatalogueSHA256 = hash
        model.selectCatalogue(manifest)
        model.expectedCatalogueSHA256 = String(repeating: "1", count: 64)
        try await wait(model)
        guard model.catalogue == nil else { throw Failure("Anchor change during import published stale metadata") }
        model.expectedCatalogueSHA256 = hash
        model.selectCatalogue(manifest); model.cancel()
        try await wait(model)
        guard model.catalogue == nil else { throw Failure("Cancelled catalogue import returned metadata") }
        model.selectCatalogue(manifest)
        try await wait(model)
        guard model.catalogue != nil, model.firmwareBuild == nil else { throw Failure("Fresh catalogue import failed or selected latest") }
        model.selectFirmwareBuild(descriptorID)
        let oversized = folder.appendingPathComponent("oversized.json")
        try Data(repeating: 32, count: 128 * 1024 + 1).write(to: oversized)
        model.selectCatalogue(oversized)
        try await wait(model)
        guard model.catalogue == nil, !model.canBuild else { throw Failure("Oversized catalogue retained prior selection") }
        let symlink = folder.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: manifest)
        do {
            _ = try await CompilerRecordReader.read(symlink, maximumBytes: 128 * 1024)
            throw Failure("Symlink metadata was accepted")
        } catch is CocoaError { /* Bounded importer rejects nonregular/symlink capabilities. */ }
        print("Imports: mismatched/oversized metadata, changed anchor, cancellation and symlink rejection")
    }

    /// Extracts an already validated association or reports a controlled harness failure.
    private static func requireAssociation(_ value: ManagedDeviceAssociation?) throws -> ManagedDeviceAssociation {
        guard let value else { throw Failure("Missing imported association") }
        return value
    }

    /// Yields the UI actor until a real controller condition holds, with bounded cancellation on timeout.
    @MainActor private static func wait(_ model: WorkbenchBuildModel, until condition: (() -> Bool)? = nil) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(70))
        while !(condition?() ?? !model.isBusy) {
            guard ContinuousClock.now < end else { model.cancel(); throw ManagedCompilerError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Focused validation error, never a firmware/device failure.
    private struct Failure: Error, CustomStringConvertible {
        /// Exact failed controller invariant.
        let description: String
        /// Retains the invariant as plain bounded test context.
        init(_ description: String) { self.description = description }
    }
}
