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
    /// Exact source-built service with reviewed paired-source delivery; supplied explicitly, not bundled.
    static let serviceSHA256 = "a7648688ae9e349304c576804367b66b68b22185060a847a2e292675329ca493"
    /// Exact approved module size, checked before reading or instantiating bytes.
    static let serviceBytes = 101_194_565
    /// Runtime manifest anchor, refreshed only by deliberate reviewed SDK-local staging.
    static let manifestSHA256 = "9fbf7807c22468083fd38fcf7870bd3c71b1b6d002b849631aa7a5cb31572c47"

    /// Loads packaged independent resources and a host-selected service, hashing off the main actor.
    /// There is no default sibling path, download, compiler subprocess or board side effect.
    @concurrent static func load(serviceURL: URL) async throws -> Self {
        try Task.checkCancellation()
        guard serviceURL.isFileURL, let root = ManagedCompilerBundle.root() else {
            throw ManagedCompilerError.unavailable("select a local approved WASM service and include the SDK runtime bundle")
        }
        // Verify paired source/notice documentation for an explicit service as well as bundled loading.
        _ = try await VerifiedManagedResources.load(root: root)
        let manifestData = try boundedRead(root.appendingPathComponent("manifest.json"), maximum: 16_384)
        guard digest(manifestData) == manifestSHA256 else { throw ManagedCompilerError.unavailable("runtime manifest integrity mismatch") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.schema == 1, manifest.serviceABI == 2,
              manifest.recipe == "nano-stateless-clang-22.1.8-v1-experimental",
              manifest.recipeSHA256 == "b7869f6fc863e1905deb6974408c6e7dc63943a1fb3e342a357fdf757b1e23d9",
              manifest.compilerPackageSHA256 == "4cbdf856304063dbac59a27ea8703f74ffedbc534521b0d40d13013913d4dba5",
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

    /// Preserves explicit-service error semantics while bounding chunk temporaries and reserving one owned snapshot.
    private static func boundedRead(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximum else {
            throw ManagedCompilerError.unavailable("missing or excessive resource")
        }
        let handle = try FileHandle(forReadingFrom: url)
        do {
            var data = Data()
            data.reserveCapacity(size)
            while true {
                try Task.checkCancellation()
                let count = try autoreleasepool {
                    guard let chunk = try handle.read(upToCount: min(1024 * 1024, maximum - data.count + 1)), !chunk.isEmpty else {
                        return 0
                    }
                    guard chunk.count <= maximum - data.count else {
                        throw ManagedCompilerError.unavailable("resource grew beyond its bound")
                    }
                    data.append(chunk)
                    return chunk.count
                }
                if count == 0 { break }
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
