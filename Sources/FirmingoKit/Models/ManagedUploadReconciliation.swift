/// One read-only reconciliation result; querying never retries or commits an upload.
public enum ManagedUploadReconciliation: Equatable, Sendable {
    /// A matching retained record, which may still be committing/installed or report failure.
    case snapshot(ManagedUploadSnapshot)
    /// The available evidence cannot establish this prior transaction's outcome.
    case unknown(Reason)

    /// Why RAM transaction evidence cannot be associated with the saved operation.
    public enum Reason: Equatable, Sendable {
        /// The selected connection reports a different physical identity.
        case deviceChanged
        /// Reboot lost RAM status and permits reuse of transaction IDs.
        case bootChanged
        /// The expected reviewed target is absent or incompatible on this connection.
        case targetUnavailable
        /// Firmware has no retained record for this ID, including a superseding transaction.
        case recordUnavailable(code: String)
        /// The response ID, size, or digest belongs to a different transaction.
        case recordMismatch
    }
}
