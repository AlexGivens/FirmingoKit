/// Host-supplied identity of the compiler, exact recipe and verified toolchain manifest used for an ELF.
/// Metadata syntax is validated; this value does not verify assets or attest that the compiler ran.
public struct ManagedELFProvenance: Equatable, Encodable, Sendable {
    /// Bounded compiler/version description, retained as text and never executed.
    public let compiler: String
    /// Versioned explicit recipe identifier, independent of the artifact format name.
    public let recipeIdentifier: String
    /// Digest of the exact recipe manifest, covering flags, facade/linker assets and ABI policy.
    public let recipeSHA256: String
    /// Digest of the verified toolchain manifest, covering compiler/runtime asset identity.
    public let toolchainSHA256: String

    /// Requires canonical SHA-256 and bounded metadata; caller owns trusted build/source association.
    public init(compiler: String, recipeIdentifier: String, recipeSHA256: String, toolchainSHA256: String) throws {
        guard !compiler.isEmpty, compiler.utf8.count <= 256, !compiler.utf8.contains(0),
              !recipeIdentifier.isEmpty, recipeIdentifier.utf8.count <= 96, recipeIdentifier.utf8.allSatisfy({
                  (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 58, 95].contains($0)
              }),
              NanoManagedContract.isHex(recipeSHA256, bytes: 32), NanoManagedContract.isHex(toolchainSHA256, bytes: 32) else {
            throw SketchBuildError.invalidProvenance
        }
        self.compiler = compiler
        self.recipeIdentifier = recipeIdentifier
        self.recipeSHA256 = recipeSHA256
        self.toolchainSHA256 = toolchainSHA256
    }
}
