import Foundation

/// Compiler resource/runtime failures separate from preprocessing, device failures and cancellation.
public enum ManagedCompilerError: Error, LocalizedError, Sendable {
    /// Missing/incompatible verified local runtime or service; no fallback compiler runs.
    case unavailable(String)
    /// Worker/bridge/navigation/content-process failure; its build is discarded.
    case runtime(String)
    /// Real compile/link rejection with all bounded structured diagnostics.
    case compilationFailed([SketchDiagnostic])
    /// End-to-end deadline exceeded; the page/worker is destroyed before return.
    case timedOut
    /// A second build tried to enter this compiler while another revision was active.
    case busy
    /// Short actionable description; diagnostics remain available in their associated value.
    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "Compiler unavailable: \(reason)."
        case .runtime(let reason): "Compiler runtime failed: \(reason)."
        case .compilationFailed: "Compilation failed. Review the source and linker diagnostics."
        case .timedOut: "Compilation exceeded its deadline. Start a new build to try again."
        case .busy: "A build is already active. Cancel it or wait for completion."
        }
    }
}
