import Foundation
import AppKit
import FirmingoKit

/// Development-only macOS WebKit compiler check; synthetic resident bindings must never reach a board.
@main struct VerifyWebKit {
    /// Exercises real SDK verify/preprocess/WebKit-WASI/ELF/capsule stages without any connection or upload.
    @MainActor static func main() async {
        do { try await validate() } catch { print("WebKit validation failed: \(error)"); exit(1) }
    }
    /// Runs the development checks, propagating a failure to the command-line entry point.
    @MainActor static func validate() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let compiler = ManagedSketchCompiler(serviceURL: root.appendingPathComponent(".build/managed-wasm/compiler-bounded.wasm"))
        let resident = try ManagedResidentBinding(deviceID: "0102030405060708", residentELFSHA256: String(repeating:"0",count:64),
            firmwareImageSHA256: String(repeating:"1",count:64), apiAddress: 0x10022ca0)
        for name in ["Blink.ino", "Console.ino", "Syntax.ino"] {
            let source = try String(contentsOf: root.appendingPathComponent(".build/managed-wasm/results/"+name), encoding:.utf8)
            let request = try ManagedSketchBuildRequest(snapshot: SketchSourceSnapshot(documentID:UUID(), revision:1, filename:name,source:source),
                board:.nanoRP2040Connect,profile:.nanoManagedV1,resident:resident)
            do {
                let result = try await compiler.build(request) { phase in print("\(name): \(phase.rawValue)") }
                guard name != "Syntax.ino" else { throw ManagedCompilerError.runtime("expected syntax failure") }
                print("\(name): real WebKit FMS1 \(result.artifact.capsule.sha256); memory \(result.linearMemoryBytes)")
            } catch ManagedCompilerError.compilationFailed(let diagnostics) {
                guard name == "Syntax.ino", diagnostics.contains(where: { $0.severity == .error && $0.filename == name && $0.line == 1 }) else { throw ManagedCompilerError.runtime("unexpected diagnostics") }
                print("\(name): actual syntax failure with original line preserved")
            }
        }
    }
}
