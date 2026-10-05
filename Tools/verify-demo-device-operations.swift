import FirmingoKit
import Foundation

/// Host-only multiwindow regression checks use isolated SDK-local journals and never contact a device.
@main struct VerifyDemoDeviceOperations {
    /// Runs deterministic coordination checks and reports failures without a top-level Swift error trap.
    @MainActor static func main() async {
        do { try await validate() }
        catch { print("Demo device coordination failed: \(error)"); exit(1) }
    }

    /// Checks competing windows, stale context, corrupt storage, cancellation and controller gates.
    @MainActor private static func validate() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let folder = root.appendingPathComponent(".build/device-operations-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: folder) }
            catch { print("Coordination check cleanup failed: \(error)") }
        }
        let store = InstallationRecordStore(directory: folder)
        let first = try record(uploadID: 1)
        let second = try record(uploadID: 2)

        let winners = try await withThrowingTaskGroup(of: UUID?.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    do { return try await store.beginManagedRun() }
                    catch DemoOperationError.busy { return nil }
                }
            }
            var winners: [UUID] = []
            for try await token in group { if let token { winners.append(token) } }
            return winners
        }
        guard winners.count == 1, let winner = winners.first else { throw Failure("competing Runs were not exclusive") }
        try await expect(.busy) { _ = try await store.beginFirmwareInstallation() }
        try await expect(.busy) { _ = try await store.beginManagedReview(first) }
        try await expect(.busy) { try await store.clearManaged(expected: nil) }
        await store.finishDeviceOperation(UUID())
        try await expect(.busy) { _ = try await store.beginManagedRun() }
        try await expect(.invalidReservation) { try await store.saveManaged(first, operation: UUID()) }
        await store.finishDeviceOperation(winner)
        try await expect(.invalidReservation) { try await store.saveManaged(first, operation: winner) }
        let firmware = try await store.beginFirmwareInstallation()
        try await expect(.busy) { _ = try await store.beginManagedRun() }
        try await expect(.invalidReservation) { try await store.saveManaged(first, operation: firmware) }
        await store.finishDeviceOperation(firmware)
        print("Twelve competing Runs: one reservation; overlapping install/review/clear and stale owners rejected")

        let stale = WorkbenchBuildModel(records: store)
        await stale.restoreContext()
        guard stale.contextLoaded, stale.pendingRecord == nil else { throw Failure("initial window context") }
        let bindingURL = folder.appendingPathComponent("resident.json")
        let binding: [String: Any] = ["schema": 1, "board": "nano_rp2040_connect", "profile": "nano-managed-v1",
            "deviceID": "0102030405060708", "residentELFSHA256": String(repeating: "0", count: 64),
            "firmwareImageSHA256": String(repeating: "1", count: 64), "apiAddress": 0x10022ca0]
        try JSONSerialization.data(withJSONObject: binding).write(to: bindingURL)
        stale.selectService(folder.appendingPathComponent("intentionally-missing.wasm"))
        stale.selectResident(bindingURL)
        try await wait(stale)
        stale.trustedResident = true
        guard stale.canBuild else { throw Failure("explicit controller selection") }
        let operation = try await store.beginManagedRun()
        try await store.saveManaged(first, operation: operation)
        await store.finishDeviceOperation(operation)
        try await expect(.pendingManagedTransaction) { _ = try await store.beginManagedRun() }
        try await expect(.pendingManagedTransaction) { _ = try await store.beginFirmwareInstallation() }
        try await expect(.contextChanged) { try await store.clearManaged(expected: nil) }
        try await expect(.contextChanged) { _ = try await store.beginManagedReview(second) }
        let snapshot = try SketchSourceSnapshot(documentID: UUID(), revision: 1, filename: "Test.ino",
            source: "void setup() {}\nvoid loop() {}\n")
        let workbench = WorkbenchModel()
        stale.run(snapshot, workbench: workbench)
        try await wait(stale)
        guard stale.pendingRecord == first, stale.result == nil, stale.contextLoaded, !workbench.isManagedOperation,
              stale.status == DemoOperationError.pendingManagedTransaction.localizedDescription else {
            throw Failure("stale window reached compilation or did not refresh its journal")
        }
        print("Stale empty window: Run blocked before compiler loading; pending transaction refreshed without connection")

        let review = try await store.beginManagedReview(first)
        try await expect(.busy) { try await store.clearManaged(expected: first) }
        await store.finishDeviceOperation(review)
        try await store.clearManaged(expected: first)
        let next = try await store.beginManagedRun()
        try await store.saveManaged(second, operation: next)
        await store.finishDeviceOperation(next)
        stale.checkOutcome(workbench: workbench)
        try await wait(stale)
        guard stale.pendingRecord == second, stale.status == DemoOperationError.contextChanged.localizedDescription,
              !workbench.isManagedOperation, workbench.session == nil else { throw Failure("stale outcome review reached a connection") }
        let old = WorkbenchBuildModel(records: store)
        await old.restoreContext()
        try await store.clearManaged(expected: second)
        let third = try await store.beginManagedRun()
        try await store.saveManaged(first, operation: third)
        await store.finishDeviceOperation(third)
        old.clearContext()
        try await wait(old)
        guard old.pendingRecord == first, try await store.loadManaged() == first,
              old.status == DemoOperationError.contextChanged.localizedDescription else { throw Failure("stale clear erased a newer transaction") }
        print("Stale review/clear: newer transaction preserved and window refreshed; no read-only connection attempted")

        let latest = folder.appendingPathComponent("managed-latest.json")
        try Data("corrupt".utf8).write(to: latest)
        do { _ = try await store.beginManagedRun(); throw Failure("corrupt context allowed Run") }
        catch is DecodingError { /* Corruption must propagate before any reservation is granted. */ }
        do { _ = try await store.beginFirmwareInstallation(); throw Failure("corrupt context allowed replacement") }
        catch is DecodingError { /* Complete-image replacement cannot silently bypass unknown managed context. */ }
        try await expect(.contextChanged) { try await store.clearManaged(expected: first) }
        let corrupt = WorkbenchBuildModel(records: store)
        await corrupt.restoreContext()
        guard !corrupt.contextLoaded else { throw Failure("corrupt restored context enabled Run") }
        corrupt.clearContext()
        try await wait(corrupt)
        guard corrupt.contextLoaded, try await store.loadManaged() == nil else { throw Failure("explicit corruption clear") }
        let retained = folder.appendingPathComponent("managed-0102030405060708-1112131415161718-1.json")
        guard FileManager.default.fileExists(atPath: retained.path) else { throw Failure("clear erased retained history") }
        print("Corrupt journals: both deployment routes blocked until explicit clear; transaction history retained")

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.beginManagedRun()
        }
        do { _ = try await cancelled.value; throw Failure("cancelled action acquired a reservation") }
        catch is CancellationError { /* A cancelled request must leave the store available to another window. */ }
        let available = try await store.beginManagedRun()
        await store.finishDeviceOperation(available)
        let blocked = folder.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        do {
            _ = try await InstallationRecordStore(directory: blocked).beginManagedRun()
            throw Failure("storage failure allowed deployment")
        } catch is CocoaError { /* Unreadable context must fail closed without granting device access. */ }
        stale.stop(); old.stop(); corrupt.stop()
        print("Cancelled requests/storage failure: no reservation granted; subsequent explicit action remains available")
    }

    /// Builds validated synthetic persistence data, never an executable artifact or hardware association.
    private static func record(uploadID: Int) throws -> ManagedUploadRecord {
        let fields: [String: Any] = ["version": 1, "deviceID": "0102030405060708", "bootID": "1112131415161718",
            "boardID": "nano_rp2040_connect", "targetID": 1, "format": "nano-managed-v1", "uploadID": uploadID,
            "size": 336, "sha256": String(repeating: "2", count: 64),
            "residentELFSHA256": String(repeating: "0", count: 64), "firmwareImageSHA256": String(repeating: "1", count: 64)]
        return try JSONDecoder().decode(ManagedUploadRecord.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    /// Asserts a specific app coordination failure instead of accepting unrelated I/O/compiler errors.
    private static func expect(_ expected: DemoOperationError, action: () async throws -> Void) async throws {
        do { try await action(); throw Failure("expected coordination rejection") }
        catch let error as DemoOperationError {
            guard error == expected else { throw Failure("wrong coordination rejection") }
        }
    }

    /// Yields to window-owned tasks with a finite deadline; no network operation is permitted by these checks.
    @MainActor private static func wait(_ model: WorkbenchBuildModel) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isBusy {
            guard ContinuousClock.now < end else { model.cancel(); throw Failure("controller deadline") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Names the violated observable invariant in this host integration harness.
    private struct Failure: Error {
        /// Human-readable regression detail.
        let detail: String
        /// Records the failed contract without hiding its cause behind a boolean assertion.
        init(_ detail: String) { self.detail = detail }
    }
}
