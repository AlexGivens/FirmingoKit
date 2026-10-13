import CryptoKit
import Foundation

/// Immutable verified capabilities for one build; only these bytes reach the private resource origin.
struct VerifiedManagedToolchain: Sendable {
    /// Exact self-contained local HTML/worker/facade page, with no external runtime imports.
    let page: Data
    /// Exact ABI-two WASI service with a hard 256-MiB defined-memory maximum.
    let service: Data
    /// Digest of every source/flag recipe input used by the staged page.
    let recipeSHA256: String
    /// Deterministic digest binding the pinned runtime manifest and actual service identity.
    let toolchainSHA256: String
    /// Reviewed memory-bounded development service; redistribution remains pending.
    static let serviceSHA256 = "3e2544acf7f88f6f1d5fbce34648df8eb96dfff47afa242a3e008bc8f86e2f33"
    /// Exact approved module size, checked before reading or instantiating bytes.
    static let serviceBytes = 101_196_044
    /// Runtime manifest anchor, refreshed only by deliberate reviewed SDK-local staging.
    static let manifestSHA256 = "d6c7458d085e43d069bda0a16b1e2ed3931c51528118c3ecba862c08dc36cadc"

    /// Loads packaged independent resources and a host-selected service, hashing off the main actor.
    /// There is no default sibling path, download, compiler subprocess or board side effect.
    @concurrent static func load(serviceURL: URL) async throws -> Self {
        try Task.checkCancellation()
        guard serviceURL.isFileURL, let root = ManagedCompilerBundle.root() else {
            throw ManagedCompilerError.unavailable("select a local approved WASM service and include the SDK runtime bundle")
        }
        let manifestData = try boundedRead(root.appendingPathComponent("manifest.json"), maximum: 16_384)
        guard digest(manifestData) == manifestSHA256 else { throw ManagedCompilerError.unavailable("runtime manifest integrity mismatch") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.schema == 1, manifest.serviceABI == 2,
              manifest.recipe == "nano-stateless-clang-22.1.8-v1-experimental",
              manifest.recipeSHA256 == "b7869f6fc863e1905deb6974408c6e7dc63943a1fb3e342a357fdf757b1e23d9",
              manifest.compilerPackageSHA256 == "93f149a454b1fc1c60ea21775b7b860e99b1a4031f8c810fb1f5de3bc18c4fd4",
              manifest.files.count == 6, Set(manifest.files.map(\.path)) == ["host.html", "LICENSE-MIT", "LICENSE-APACHE", "Firmingo-Compiler-LICENSE", "compiler-package.json", "compiler-sources.json"] else {
            throw ManagedCompilerError.unavailable("incompatible runtime recipe")
        }
        var page = Data()
        for file in manifest.files {
            let data = try boundedRead(root.appendingPathComponent(file.path), maximum: 512 * 1024)
            guard data.count == file.bytes, digest(data) == file.sha256 else {
                throw ManagedCompilerError.unavailable("runtime resource integrity mismatch")
            }
            if file.path == "host.html" { page = data }
        }
        let service = try boundedRead(serviceURL, maximum: serviceBytes)
        guard service.count == serviceBytes, digest(service) == serviceSHA256 else {
            throw ManagedCompilerError.unavailable("select the reviewed memory-bounded ABI-two service")
        }
        try Task.checkCancellation()
        return Self(page: page, service: service, recipeSHA256: manifest.recipeSHA256,
                    toolchainSHA256: digest(Data((manifestSHA256 + ":" + serviceSHA256).utf8)))
    }

    /// Reads regular nonsymlink files with a byte cap and cancellation between fixed-size chunks.
    private static func boundedRead(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximum else {
            throw ManagedCompilerError.unavailable("missing or excessive resource")
        }
        let handle = try FileHandle(forReadingFrom: url)
        do {
            var data = Data()
            while true {
                try Task.checkCancellation()
                guard let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
                guard chunk.count <= maximum - data.count else { throw ManagedCompilerError.unavailable("resource grew beyond its bound") }
                data.append(chunk)
            }
            try handle.close()
            return data
        } catch {
            do { try handle.close() } catch { /* Preserve the original read/cancellation failure. */ }
            throw error
        }
    }
    /// Computes exact lowercase SHA-256 for source/asset identity.
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    /// Decoded only after the manifest's independently pinned digest passes.
    private struct Manifest: Decodable {
        /// Runtime manifest version.
        let schema: Int
        /// Required compiler export ABI.
        let serviceABI: Int
        /// Exact fixed stateless recipe.
        let recipe: String
        /// Recipe/source/flag identity.
        let recipeSHA256: String
        /// Exact imported compiler-source package, independently anchored with the runtime page.
        let compilerPackageSHA256: String
        /// Complete finite resource roles.
        let files: [File]
        /// One exact packaged resource, never an arbitrary archive path.
        struct File: Decodable {
            /// Reviewed fixed resource name.
            let path: String
            /// Declared exact bytes.
            let bytes: Int
            /// Declared SHA-256 checked against actual bytes.
            let sha256: String
        }
    }
}
