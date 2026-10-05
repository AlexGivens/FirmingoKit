import Foundation

/// Local catalogue/association failures; none authorizes compilation, connection or a device write.
public enum ManagedCatalogueError: Error, LocalizedError, Sendable {
    /// The supplied catalogue does not match its independently trusted byte identity.
    case integrityMismatch
    /// Unsupported schema, excessive input or conflicting build metadata.
    case invalidCatalogue
    /// Descriptor metadata does not match the reviewed experimental Nano recipe contract.
    case invalidDescriptor
    /// The caller's explicitly selected immutable build is not in this catalogue.
    case missingBuild
    /// A persisted device association is malformed or uses an unsupported evidence schema.
    case invalidAssociation
    /// The association names a different immutable firmware-build descriptor.
    case associationMismatch

    /// Gives a bounded explanation while keeping hash identity distinct from installed-image proof.
    public var errorDescription: String? {
        switch self {
        case .integrityMismatch: "The firmware catalogue does not match its trusted SHA-256. Supply the exact reviewed catalogue bytes."
        case .invalidCatalogue: "The firmware catalogue is malformed, excessive or contains conflicting builds."
        case .invalidDescriptor: "The firmware build metadata does not match the reviewed experimental Nano recipe."
        case .missingBuild: "The selected firmware build is absent from this catalogue. Review the exact build selection again."
        case .invalidAssociation: "The saved device association is invalid or uses an unsupported schema."
        case .associationMismatch: "The device association belongs to a different firmware build. Review the installed-firmware evidence before deployment."
        }
    }
}
