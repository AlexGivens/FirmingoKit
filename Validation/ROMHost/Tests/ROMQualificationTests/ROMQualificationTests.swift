import Foundation
import Testing
@testable import ROMQualification

/// Every writing command requires explicit confirmation of the selected physical Nano.
@Test func writingRequiresExactModelConfirmation() throws {
    let base = ["install", "--manifest", "manifest", "--image", "image", "--output", "new", "--volume", "/Volumes/RPI-RP2"]
    #expect(throws: ROMFailure.self) { try ROMArguments(base) }
    #expect(throws: ROMFailure.self) { try ROMArguments(base + ["--confirm-board", "raspberry_pi_pico"]) }
    #expect(try ROMArguments(base + ["--confirm-board", "nano_rp2040_connect"]).command == .install)
}

/// Read-only actions cannot smuggle volume selection or programming options into their execution branches.
@Test func readOnlyActionsRejectWriteOptions() throws {
    let base = ["inspect-record", "--record", "record", "--output", "new"]
    #expect(try ROMArguments(base).command == .inspectRecord)
    #expect(throws: ROMFailure.self) { try ROMArguments(base + ["--volume", "/Volumes/RPI-RP2"]) }
    #expect(throws: ROMFailure.self) { try ROMArguments(base + ["--confirm-board", "nano_rp2040_connect"]) }
}

/// Explicit attachment inspection has no artifact/confirmation flags and cannot enter the execution branch.
@Test func volumeInspectionIsASeparateReadOnlyCommand() throws {
    let input = ["inspect-volume", "--volume", "/Volumes/RPI-RP2", "--output", "new"]
    #expect(try ROMArguments(input).command == .inspectVolume)
    #expect(throws: ROMFailure.self) { try ROMArguments(input + ["--confirm-board", "nano_rp2040_connect"]) }
    #expect(throws: ROMFailure.self) { try ROMArguments(input + ["--image", "image"]) }
}

/// Duplicate/unknown flags and malformed pairs are rejected before acquisition or output creation.
@Test func malformedCommandIntentFailsClosed() {
    for input in [[String](), ["install"], ["preflight", "--image"],
                  ["preflight", "--image", "a", "--image", "b", "--manifest", "m", "--output", "o"],
                  ["preflight", "--image", "a", "--manifest", "m", "--output", "o", "--execute", "yes"]] {
        #expect(throws: ROMFailure.self) { try ROMArguments(input) }
    }
}

/// Paused transfer is a distinct explicit writing action with the same physical selection requirements.
@Test func interruptedTransferIsNeverAnImplicitMode() throws {
    let input = ["paused-install", "--manifest", "m", "--image", "i", "--output", "o", "--volume", "v", "--confirm-board", "nano_rp2040_connect"]
    #expect(try ROMArguments(input).command == .pausedInstall)
    #expect(throws: ROMFailure.self) { try ROMArguments(["resume", "--record", "r", "--output", "o"]) }
}

/// Journal preparation cannot create files on any bootloader volume before the SDK write gate.
@Test func journalCannotUseBootloaderMountAsOutput() {
    #expect(throws: ROMFailure.self) { try ROMJournal(directory: URL(fileURLWithPath: "/Volumes/RPI-RP2/not-an-output"), command: "install") }
}

/// Existing evidence is never replaced, even when a later operation selects the same path.
@Test func outputDirectoryCannotBeReused() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("rom-qualification-test-" + UUID().uuidString)
    defer {
        do { try FileManager.default.removeItem(at: path) }
        catch { Issue.record(error) }
    }
    _ = try ROMJournal(directory: path, command: "preflight")
    #expect(throws: ROMFailure.self) { try ROMJournal(directory: path, command: "install") }
}

/// A substituted manifest fails the independently pinned candidate anchor before any image or volume is accessed.
@Test func substitutedArtifactFailsBeforeImageAcquisition() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("rom-qualification-input-" + UUID().uuidString)
    try Data("{}".utf8).write(to: path, options: .withoutOverwriting)
    defer {
        do { try FileManager.default.removeItem(at: path) }
        catch { Issue.record(error) }
    }
    let args = try ROMArguments(["preflight", "--manifest", path.path, "--image", "/no-image-is-read", "--output", "/no-output-is-created"])
    #expect(throws: ROMFailure.self) { try ROMCandidate.load(args) }
}
