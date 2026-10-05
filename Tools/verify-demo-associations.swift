import FirmingoKit
import Foundation

/// Host-only persistence/controller checks; synthetic associations never reach a network connection or board.
@main struct VerifyDemoAssociations {
    /// Reports actionable harness failures without a top-level error trap.
    @MainActor static func main() async {
        do { try await validate() }
        catch { print("Association checks failed: \(error)"); exit(1) }
    }

    /// Covers restart, stale windows, exact descriptors, bounds, corrupt schemas and reservation gates.
    @MainActor private static func validate() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let folder = root.appendingPathComponent(".build/association-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: folder) }
            catch { print("Association cleanup failed: \(error)") }
        }
        let fixtures = root.appendingPathComponent("Tests/FirmingoKitTests/Fixtures/compiler-catalogue")
        let file = fixtures.appendingPathComponent("association.json")
        let first = try ManagedDeviceAssociation(recordJSON: Data(contentsOf: file))
        let second = try ManagedDeviceAssociation(deviceID: first.deviceID, firmwareBuildID: String(repeating: "a", count: 64),
            evidence: .hostConfirmedExistingFirmware)
        let store = InstallationRecordStore(directory: folder)
        guard try await store.loadAssociations().isEmpty else { throw Failure("absent roster") }
        let saved = try await store.saveAssociation(first, expected: [])
        let restartedStore = InstallationRecordStore(directory: folder)
        guard try await restartedStore.loadAssociations() == saved else { throw Failure("restart lost exact SDK record") }
        try await expect(.associationChanged) { _ = try await store.saveAssociation(second, expected: []) }
        let reservation = try await store.beginManagedRun(association: first)
        try await expect(.busy) { _ = try await store.saveAssociation(second, expected: saved) }
        try await expect(.busy) { _ = try await store.removeAssociation(deviceID: first.deviceID, expected: saved) }
        await store.finishDeviceOperation(reservation)
        let replaced = try await store.saveAssociation(second, expected: saved)
        try await expect(.associationChanged) { _ = try await store.beginManagedRun(association: first) }
        try await expect(.associationChanged) { _ = try await store.removeAssociation(deviceID: first.deviceID, expected: saved) }
        _ = try await store.saveAssociation(first, expected: replaced)
        print("Durable restart/CAS/active-operation gates: exact records preserved, stale actions rejected")

        let model = WorkbenchBuildModel(records: store)
        let workbench = WorkbenchModel()
        defer { model.stop() }
        await model.restoreContext(); await model.restoreAssociations()
        guard model.savedAssociations == saved, model.association == nil, model.firmwareBuild == nil,
              !model.trustedAssociation, !model.canRun(on: workbench) else { throw Failure("restart auto-selected or trusted evidence") }
        model.expectedCatalogueSHA256 = "7eb09989cbab271b0ba0350950fdc684a30a2ac2825488d58bcbfb3a32feba07"
        model.selectCatalogue(fixtures.appendingPathComponent("catalogue.json"))
        try await wait(model)
        model.selectFirmwareBuild(first.firmwareBuildID)
        model.selectService(folder.appendingPathComponent("missing-service.wasm"))
        model.selectSavedAssociation(first.deviceID)
        guard model.association == first, !model.trustedAssociation, model.canBuild, !model.canRun(on: workbench) else {
            throw Failure("restore granted review or blocked offline Build")
        }
        model.trustedAssociation = true
        guard model.canRun(on: workbench) else { throw Failure("reviewed saved evidence unavailable") }
        _ = try await store.saveAssociation(second, expected: saved)
        let source = try SketchSourceSnapshot(documentID: UUID(), revision: 1, filename: "check.ino", source: "void setup() {}\nvoid loop() {}")
        model.run(source, workbench: workbench)
        try await wait(model)
        guard model.status == DemoOperationError.associationChanged.localizedDescription,
              !model.trustedAssociation, model.savedAssociations == [second], model.offlineResult == nil,
              workbench.session == nil, !workbench.isManagedOperation else { throw Failure("stale Run gate: status=\(model.status), review=\(model.trustedAssociation), saved=\(model.savedAssociations.count), busy=\(workbench.isManagedOperation), session=\(workbench.session != nil)") }
        model.selectSavedAssociation(second.deviceID)
        guard model.association == nil, model.canBuild else { throw Failure("removed descriptor was silently rebound") }
        model.selectAssociation(file); try await wait(model)
        model.trustedAssociation = true
        model.saveAssociation(); try await wait(model)
        guard model.savedAssociations == saved, model.trustedAssociation else { throw Failure("explicit save") }
        _ = try await store.saveAssociation(second, expected: saved)
        model.forgetAssociation(); try await wait(model)
        guard model.savedAssociations == [second], !model.trustedAssociation,
              model.status == DemoOperationError.associationChanged.localizedDescription else { throw Failure("stale forget erased newer evidence") }
        model.forgetAssociation(deviceID: second.deviceID); try await wait(model)
        guard model.savedAssociations.isEmpty, model.association == nil else { throw Failure("orphaned descriptor could not be explicitly forgotten") }
        _ = try await store.saveAssociation(first, expected: [])
        model.reloadAssociations(); try await wait(model)
        model.selectSavedAssociation(first.deviceID)
        model.forgetAssociation(); try await wait(model)
        guard model.association == nil, model.savedAssociations.isEmpty, try await store.loadAssociations().isEmpty else { throw Failure("explicit forget") }
        print("Controller restart/exact descriptor/review/save/forget/stale Run: no compiler or connection attempted")

        var roster: [ManagedDeviceAssociation] = []
        for index in 0..<16 {
            let record = try ManagedDeviceAssociation(deviceID: String(format: "%016x", index), firmwareBuildID: first.firmwareBuildID,
                evidence: .hostConfirmedExistingFirmware)
            roster = try await store.saveAssociation(record, expected: roster)
        }
        let extra = try ManagedDeviceAssociation(deviceID: "ffffffffffffffff", firmwareBuildID: first.firmwareBuildID,
            evidence: .hostConfirmedExistingFirmware)
        try await expect(.associationLimit) { _ = try await store.saveAssociation(extra, expected: roster) }
        guard try await store.loadAssociations() == roster else { throw Failure("limit mutated roster") }
        let removed = try await store.removeAssociation(deviceID: roster[0].deviceID, expected: roster)
        guard removed == Array(roster.dropFirst()) else { throw Failure("forget altered unrelated devices") }
        roster = try await store.saveAssociation(roster[0], expected: removed)
        let archiveURL = folder.appendingPathComponent("device-associations-v1.json")
        let original = try Data(contentsOf: archiveURL)
        let encoded = try first.encodeRecord().base64EncodedString()
        let invalidArchives = [
            Data("corrupt".utf8),
            Data("{\"version\":2,\"records\":[]}".utf8),
            Data("{\"version\":1,\"records\":[],\"extra\":true}".utf8),
            Data("{\"version\":1,\"records\":[\"\(encoded)\",\"\(encoded)\"]}".utf8),
            Data("{\"version\":1,\"records\":[\"e30=\"]}".utf8),
            Data(repeating: 32, count: 16385)
        ]
        for bytes in invalidArchives {
            try bytes.write(to: archiveURL)
            try await rejects { _ = try await store.loadAssociations() }
            try await rejects { _ = try await store.beginManagedRun(association: first) }
            try await rejects { _ = try await store.saveAssociation(first, expected: []) }
            await model.restoreAssociations()
            guard !model.associationsLoaded, model.canBuild, !model.canRun(on: workbench) else { throw Failure("corrupt roster affected offline Build or enabled Run") }
        }
        try original.write(to: archiveURL)
        try FileManager.default.removeItem(at: archiveURL)
        let target = folder.appendingPathComponent("target.json")
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: archiveURL, withDestinationURL: target)
        try await expect(.invalidAssociationArchive) { _ = try await store.loadAssociations() }
        try FileManager.default.removeItem(at: archiveURL)
        try original.write(to: archiveURL)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.saveAssociation(extra, expected: roster)
        }
        do { _ = try await cancelled.value; throw Failure("cancelled storage action succeeded") }
        catch is CancellationError { /* Cancellation precedes mutation. */ }
        let blocked = folder.appendingPathComponent("not-directory")
        try Data().write(to: blocked)
        try await rejects { _ = try await InstallationRecordStore(directory: blocked).saveAssociation(first, expected: []) }
        guard try await store.loadAssociations() == roster else { throw Failure("cancel/storage failure changed evidence") }
        print("Bounds/schema/duplicate/invalid SDK records/symlink/cancellation/storage failure: fail closed, offline Build independent")
    }

    /// Requires the intended coordination error instead of accepting unrelated failures.
    private static func expect(_ expected: DemoOperationError, action: () async throws -> Void) async throws {
        do { try await action(); throw Failure("expected \(expected)") }
        catch let error as DemoOperationError {
            guard error == expected else { throw Failure("wrong coordination error: \(error)") }
        }
    }

    /// Asserts rejection while allowing each parser to preserve its own underlying cause.
    private static func rejects(action: () async throws -> Void) async throws {
        do { try await action() }
        catch { return }
        throw Failure("invalid storage accepted")
    }

    /// Gives window-owned operations a finite deadline without polling or connecting to hardware.
    @MainActor private static func wait(_ model: WorkbenchBuildModel) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isBusy {
            guard ContinuousClock.now < end else { model.cancel(); throw Failure("controller deadline") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Identifies the violated observable invariant.
    private struct Failure: Error, CustomStringConvertible {
        /// Regression detail printed by the harness entry point.
        let description: String
        /// Captures a useful failure instead of a boolean assertion.
        init(_ description: String) { self.description = description }
    }
}
