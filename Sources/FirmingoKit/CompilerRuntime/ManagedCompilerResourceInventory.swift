import Foundation

/// Closed version-one asset inventory for the single implemented stateless Nano recipe; no recipe inference.
struct ManagedCompilerResourceInventory: Sendable {
    /// Exact finite local resource roles; paths cannot be supplied by a sketch or host app.
    static let fileBounds = ["manifest.json": 16_384, "host.html": 512 * 1024,
                             "LICENSE-MIT": 16_384, "LICENSE-APACHE": 16_384, "catalogue.json": 128 * 1024,
                             "Firmingo-Compiler-LICENSE": 65_536, "compiler-package.json": 16_384, "compiler-sources.json": 512 * 1024]
    /// Fixed compiler filename, usable only after the SDK-pinned distribution review passes.
    static let servicePath = "compiler.wasm"
    /// Fixed recipe shared by all compatible resident builds; no service copy per descriptor is needed.
    static let recipeIdentifier = "nano-stateless-clang-22.1.8-v1-experimental"
    /// Exact facade/linker/flags identity supported by this SDK.
    static let recipeSHA256 = "b7869f6fc863e1905deb6974408c6e7dc63943a1fb3e342a357fdf757b1e23d9"
    /// Finite metadata for all nonservice resources.
    let files: [File]
    /// Review asserted by the independently SDK-pinned inventory, never by a host-selected file.
    let serviceApproved: Bool

    /// An exact file capability declaration, with limits enforced before path construction or reads.
    struct File: Sendable {
        /// One fixed nonsymlink leaf resource name.
        let path: String
        /// Exact positive bytes within this role's bound.
        let bytes: Int
        /// Exact lowercase SHA-256.
        let sha256: String
    }

    /// Parses at most 16 KiB/1024 tokens with strict scalar types, duplicate-key rejection and closed keys.
    /// Integrity anchoring precedes this call in the loader; this schema cannot promote hardware support.
    init(data: Data) throws {
        do {
            let root = try WireJSON.parse(data, maximumBytes: 16_384, maximumTokens: 1024)
            try Self.keys(root, ["schema", "recipe", "service", "files"])
            guard try root.required("schema").uint32() == 1 else { throw ManagedCompilerResourceError.incompatibleInventory }
            let recipe = try root.required("recipe")
            try Self.keys(recipe, ["identifier", "sha256", "board", "profile", "sourceContract", "qualification"])
            guard try recipe.required("identifier").string() == Self.recipeIdentifier,
                  try recipe.required("sha256").string() == Self.recipeSHA256,
                  try recipe.required("board").string() == FirmingoBoard.nanoRP2040Connect.rawValue,
                  try recipe.required("profile").string() == ManagedSketchBuildRequest.Profile.nanoManagedV1.rawValue,
                  try recipe.required("sourceContract").string() == "nano-stateless-facade-v1",
                  try recipe.required("qualification").string() == "experimental-unqualified" else {
                throw ManagedCompilerResourceError.incompatibleInventory
            }
            let service = try root.required("service")
            try Self.keys(service, ["path", "bytes", "sha256", "abi", "distributionReview"])
            let review = try service.required("distributionReview").string()
            guard try service.required("path").string() == Self.servicePath,
                  try service.required("bytes").uint32() == UInt32(VerifiedManagedToolchain.serviceBytes),
                  try service.required("sha256").string() == VerifiedManagedToolchain.serviceSHA256,
                  try service.required("abi").uint32() == 2,
                  review == "pending" || review == "approved" else { throw ManagedCompilerResourceError.incompatibleInventory }
            serviceApproved = review == "approved"
            let entries = try root.required("files").array()
            guard entries.count == Self.fileBounds.count else { throw ManagedCompilerResourceError.incompatibleInventory }
            var seen: Set<String> = []
            var files: [File] = []
            for entry in entries {
                try Self.keys(entry, ["path", "bytes", "sha256"])
                let path = try entry.required("path").string()
                let bytes = try entry.required("bytes").uint32()
                let hash = try entry.required("sha256").string()
                guard let maximum = Self.fileBounds[path], seen.insert(path).inserted,
                      bytes > 0, bytes <= maximum, NanoManagedContract.isHex(hash, bytes: 32) else {
                    throw ManagedCompilerResourceError.incompatibleInventory
                }
                if path == "manifest.json", hash != VerifiedManagedToolchain.manifestSHA256 {
                    throw ManagedCompilerResourceError.incompatibleInventory
                }
                files.append(File(path: path, bytes: Int(bytes), sha256: hash))
            }
            self.files = files
        } catch { throw ManagedCompilerResourceError.incompatibleInventory }
    }

    /// Rejects unknown fields instead of silently extending asset or approval authority.
    private static func keys(_ value: WireJSON.Value, _ names: [String]) throws {
        guard Set(try value.object().keys) == Set(names.map { Data($0.utf8) }) else {
            throw ManagedCompilerResourceError.incompatibleInventory
        }
    }
}
