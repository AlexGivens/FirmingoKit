import Foundation

/// Local release/artifact/preflight failures, all occurring before any device write.
public enum FirmwareLifecycleError: Error, LocalizedError, Sendable, Equatable {
    /// Invalid or unsupported schema, metadata, release source, or board recipe.
    case invalidManifest(String)
    /// The selected manifest has no exact board/profile entry.
    case missingArtifact
    /// Bytes fail integrity, UF2 layout, or flash-range checks.
    case invalidImage(String)
    /// An image was offered for a different host-selected board.
    case boardMismatch

    /// A short description suitable for host presentation.
    public var errorDescription: String? {
        switch self {
        case .invalidManifest(let reason): "Invalid Firmingo release manifest: \(reason)."
        case .missingArtifact: "The release has no image for the selected board and profile."
        case .invalidImage(let reason): "Invalid Firmingo firmware image: \(reason)."
        case .boardMismatch: "The firmware image does not match the selected board."
        }
    }
}
