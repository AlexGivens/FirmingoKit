/// Real local WASM compile/link result for a device-independent firmware-build selection.
/// Build success establishes structural packaging, not installed firmware, startup or useful behavior.
public struct ManagedOfflineCompilationResult: Sendable {
    /// Unbound FMS1 bytes, exact firmware requirements and immutable offline receipt.
    public let artifact: ManagedOfflineSketchArtifact
    /// Bounded source-mapped diagnostics, including accompanying warnings and notes.
    public let diagnostics: [SketchDiagnostic]
    /// Observed worker linear-memory bytes after the build, not host-process peak memory.
    public let linearMemoryBytes: Int
}
