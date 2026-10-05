import AppKit
import Foundation
import FirmingoKit

/// Development-only demo controller checks use SDK-local storage and synthetic bindings, without any board access.
@main struct VerifyDemoBuild {
    /// Reports actionable test failures without a top-level Swift error trap.
    @MainActor static func main() async {
        do { try await validate() } catch { print("Demo build validation failed: \(error)"); exit(1) }
    }
    /// Exercises real document builds, cancellation on edits and bounded restart-context handling.
    @MainActor static func validate() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let folder = root.appendingPathComponent(".build/managed-wasm/demo-check-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {
            do { try FileManager.default.removeItem(at:folder) }
            catch { print("Temporary SDK-local demo check cleanup failed: \(error)") }
        }
        let journal = InstallationRecordStore(directory:folder)
        let model = WorkbenchBuildModel(records:journal)
        await model.restoreContext()
        guard model.contextLoaded, model.pendingRecord == nil else { throw CocoaError(.fileReadCorruptFile) }
        let binding: [String:Any] = ["schema":1,"board":"nano_rp2040_connect","profile":"nano-managed-v1","deviceID":"0102030405060708",
            "residentELFSHA256":String(repeating:"0",count:64),"firmwareImageSHA256":String(repeating:"1",count:64),"apiAddress":0x10022ca0]
        let recordURL = folder.appendingPathComponent("resident.json")
        try JSONSerialization.data(withJSONObject:binding).write(to:recordURL)
        model.selectService(root.appendingPathComponent(".build/managed-wasm/compiler-bounded.wasm"))
        model.selectResident(recordURL)
        try await wait(model) { !model.isBusy }
        model.trustedResident = true
        guard model.canBuild else { throw ManagedCompilerError.runtime("explicit selections did not enable Build") }
        let source = "void setup() { pinMode(LED_BUILTIN, OUTPUT); }\nvoid loop() { digitalWrite(LED_BUILTIN, HIGH); delay(100); digitalWrite(LED_BUILTIN, LOW); delay(100); }\n"
        let first = try SketchSourceSnapshot(documentID:UUID(),revision:1,filename:"Blink.ino",source:source)
        model.build(first)
        try await wait(model) { model.status == "Compiling…" || !model.isBusy }
        guard model.isBusy else { throw ManagedCompilerError.runtime("worker completed before edit test") }
        model.sourceChanged(revision:2)
        try await wait(model) { !model.isBusy }
        guard model.result == nil else { throw ManagedCompilerError.runtime("stale document artifact returned") }
        print("Document edit during actual WASM compilation: no stale artifact returned")
        let second = try SketchSourceSnapshot(documentID:first.documentID,revision:2,filename:"Blink.ino",source:source)
        model.build(second)
        try await wait(model) { !model.isBusy }
        guard let result = model.result, result.artifact.receipt.sourceRevision == 2,
              result.artifact.capsule.sha256 == "018c94a4a49b71880d6f04aecbe08e809c8ecf49e4278261c45dad3ead205720" else {
            throw ManagedCompilerError.runtime("fresh revision did not compile independently")
        }
        print("Subsequent document revision: real WebKit capsule and exact revision receipt validated")
        model.selectionChanged()
        guard model.result == nil, !model.canBuild else { throw ManagedCompilerError.runtime("changed target retained a usable artifact") }
        print("Target selection change: artifact invalidated and record association requires review")
        model.trustedResident = true
        model.selectResident(recordURL)
        model.trustChanged()
        try await wait(model) { !model.isBusy }
        guard model.resident != nil, !model.trustedResident else { throw ManagedCompilerError.runtime("record import was cancelled by trust invalidation") }
        print("Resident reimport: previous trust revoked without cancelling the new metadata load")
        let savedFields: [String:Any] = ["version":1,"deviceID":"0102030405060708","bootID":"1112131415161718",
            "boardID":"nano_rp2040_connect","targetID":1,"format":"nano-managed-v1","uploadID":1,"size":336,
            "sha256":result.artifact.capsule.sha256,"residentELFSHA256":String(repeating:"0",count:64),
            "firmwareImageSHA256":String(repeating:"1",count:64)]
        let saved = try JSONDecoder().decode(ManagedUploadRecord.self,from:JSONSerialization.data(withJSONObject:savedFields))
        let operation = try await journal.beginManagedRun()
        try await journal.saveManaged(saved, operation: operation)
        await journal.finishDeviceOperation(operation)
        guard try await journal.loadManaged() == saved else { throw ManagedCompilerError.runtime("durable managed journal mismatch") }
        let history = folder.appendingPathComponent("managed-0102030405060708-1112131415161718-1.json")
        guard FileManager.default.fileExists(atPath:history.path) else { throw ManagedCompilerError.runtime("managed history missing") }
        print("Managed transaction journal: synchronized latest/history and exact restart record validated")
        try Data("corrupt".utf8).write(to:folder.appendingPathComponent("managed-latest.json"))
        let restored = WorkbenchBuildModel(records:InstallationRecordStore(directory:folder))
        await restored.restoreContext()
        guard !restored.contextLoaded else { throw ManagedCompilerError.runtime("corrupt journal permitted Run") }
        restored.clearContext()
        try await wait(restored) { !restored.isBusy }
        guard restored.contextLoaded, restored.pendingRecord == nil else { throw ManagedCompilerError.runtime("explicit clear failed") }
        print("Corrupt restart context: Run blocked until explicit clear; no connection or replay occurred")
        guard FileManager.default.fileExists(atPath:history.path) else { throw ManagedCompilerError.runtime("explicit clear erased journal history") }
        model.stop(); restored.stop()
    }
    /// Waits with a bounded deadline while yielding the main actor to real WebKit and UI state updates.
    @MainActor private static func wait(_ model: WorkbenchBuildModel, until condition: () -> Bool) async throws {
        let end = ContinuousClock.now.advanced(by:.seconds(70))
        while !condition() {
            guard ContinuousClock.now < end else { model.cancel(); throw ManagedCompilerError.timedOut }
            try await Task.sleep(for:.milliseconds(5))
        }
    }
}
