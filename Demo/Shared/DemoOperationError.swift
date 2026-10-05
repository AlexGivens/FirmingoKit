import Foundation

/// Host coordination failures detected before a connection, upload or firmware writer starts.
enum DemoOperationError: Error, LocalizedError, Equatable {
    /// Another window owns the app's device-operation reservation.
    case busy
    /// A retained managed transaction requires a separate review or explicit clear.
    case pendingManagedTransaction
    /// This window's reviewed journal no longer matches the current saved context.
    case contextChanged
    /// A journal update did not carry the current managed Run's reservation.
    case invalidReservation
    /// Saved device evidence changed after this window loaded or reviewed it.
    case associationChanged
    /// Unknown, malformed or conflicting host association schema cannot authorize Run.
    case invalidAssociationArchive
    /// The bounded host roster is full; explicit removal is required before adding another device.
    case associationLimit

    /// Explains the next user action without implying that a device operation occurred.
    var errorDescription: String? {
        switch self {
        case .busy: "Another window is performing a device operation. Wait for it to finish before requesting this action."
        case .pendingManagedTransaction: "A saved managed transaction requires review. Check or clear its context before requesting another deployment."
        case .contextChanged: "Saved run context changed in another window. Review the current context before requesting this action again."
        case .invalidReservation: "The device-operation reservation is no longer valid. No commit is authorized by this journal update."
        case .associationChanged: "Saved device associations changed. Reload and review the current evidence before requesting this action again."
        case .invalidAssociationArchive: "Saved device associations are invalid or use an unsupported schema. Offline Build remains available; Run requires readable saved evidence."
        case .associationLimit: "Sixteen device associations are already saved. Forget an existing association before adding another device."
        }
    }
}
