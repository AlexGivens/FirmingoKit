import Foundation

/// Distinct source, target, provenance and linked-output failures; cancellation remains CancellationError.
public enum SketchBuildError: Error, LocalizedError, Sendable {
    /// Unsafe or excessive immutable input.
    case invalidInput(String)
    /// No reviewed managed artifact contract exists for this board/profile.
    case unsupportedBoard
    /// Unsupported source constructs with original source positions.
    case unsupportedSource([SketchDiagnostic])
    /// Missing or malformed host-supplied compiler/recipe/toolchain provenance.
    case invalidProvenance
    /// The ELF is not a bounded, stateless, fully linked Nano module.
    case invalidELF(String)

    /// Short host explanation; source diagnostics remain available in the associated value.
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let reason): "Invalid sketch input: \(reason)."
        case .unsupportedBoard: "This board has no reviewed managed-sketch build target. Select the experimental Nano profile."
        case .unsupportedSource: "This source uses unsupported preprocessing. Use the local Arduino facade include and unspliced physical lines."
        case .invalidProvenance: "Provide bounded compiler identity and exact recipe/toolchain hashes."
        case .invalidELF(let reason): "Invalid managed ELF: \(reason)."
        }
    }
}
