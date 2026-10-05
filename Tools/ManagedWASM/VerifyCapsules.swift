import Foundation
import FirmingoKit
import CryptoKit

/// Development-only check consumes real WASM-linked ELF using SDK source preparation and capsule validation.
@main struct VerifyCapsules {
    /// Validates both executable development outputs without any connection or device-changing operation.
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let directory = root.appendingPathComponent(".build/managed-wasm/results")
        let recipe = try Data(contentsOf: root.appendingPathComponent("Tools/ManagedWASM/Recipe/manifest.json"))
        let recipeHash = SHA256.hash(data: recipe).map { String(format: "%02x", $0) }.joined()
        let toolchain = try Data(contentsOf: root.appendingPathComponent(".build/managed-wasm/toolchain-manifest.json"))
        let toolchainHash = SHA256.hash(data: toolchain).map { String(format: "%02x", $0) }.joined()
        let provenance = try ManagedELFProvenance(compiler: "Clang/LLD 22.1.8 ABI-two WASI service, Node development runner",
            recipeIdentifier: "nano-stateless-clang-22.1.8-v1-experimental", recipeSHA256: recipeHash,
            toolchainSHA256: toolchainHash)
        // These resident/image hashes are deliberately synthetic. The outputs must never reach hardware.
        let resident = try ManagedResidentBinding(deviceID: "0102030405060708", residentELFSHA256: String(repeating: "0", count: 64),
            firmwareImageSHA256: String(repeating: "1", count: 64), apiAddress: 0x10022ca0)
        for name in ["Blink.ino", "Console.ino"] {
            let source = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            let snapshot = try SketchSourceSnapshot(documentID: UUID(), revision: 1, filename: name, source: source)
            let request = try ManagedSketchBuildRequest(snapshot: snapshot, board: .nanoRP2040Connect, profile: .nanoManagedV1, resident: resident)
            let prepared = try await ManagedSketchPreprocessor.prepare(request)
            let elf = try Data(contentsOf: directory.appendingPathComponent(name + ".elf"))
            let result = try await ManagedELFConverter.convert(elf, prepared: prepared, provenance: provenance)
            try result.capsule.bytes.write(to: directory.appendingPathComponent(name + ".fms"))
            try result.reportJSON.write(to: directory.appendingPathComponent(name + ".report.json"))
            try JSONEncoder().encode(result.receipt).write(to: directory.appendingPathComponent(name + ".receipt.json"))
            print("\(name): real WASM ELF \(elf.count) bytes → validated FMS1 \(result.capsule.bytes.count) bytes, SHA-256 \(result.capsule.sha256). Synthetic resident; never upload.")
        }
    }
}
