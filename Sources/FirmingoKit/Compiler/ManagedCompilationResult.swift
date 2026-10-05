/// A real local compile/link result, distinct from upload, startup and useful hardware behavior.
public struct ManagedCompilationResult: Sendable {
    /// Validated capsule/report and immutable build-input receipt.
    public let artifact: ManagedSketchArtifact
    /// All bounded source/build messages, including notes accompanying errors/warnings.
    public let diagnostics: [SketchDiagnostic]
    /// Worker linear-memory size after compilation, not peak host-process memory.
    public let linearMemoryBytes: Int
}
