import Foundation

/// Managed artifact/transaction failures, distinct from transport and FMGO response errors.
public enum ManagedUploadError: Error, Sendable, LocalizedError {
    /// Local bytes or metadata failed validation; no upload is started.
    case invalidArtifact(String)
    /// This board/backend/target combination has no reviewed SDK managed-upload contract.
    case unsupportedTarget
    /// A successful response envelope reported a failed or aborted transaction.
    case transactionFailed(ManagedUploadSnapshot)
    /// Commit may have been accepted; retain this record and query a fresh matching connection.
    /// The underlying rejection, cancellation, timeout, or protocol/transport cause is preserved.
    case uncertainCommit(record: ManagedUploadRecord, underlying: any Error)

    /// Short user-facing descriptions; the record and error code remain available to host logic.
    public var errorDescription: String? {
        switch self {
        case .invalidArtifact(let message): message
        case .unsupportedTarget: "This device does not advertise the reviewed Nano managed-upload target."
        case .transactionFailed(let snapshot): "Managed upload \(snapshot.state.rawValue) (\(snapshot.errorCode))."
        case .uncertainCommit: "The managed installation outcome is unknown. Query the saved transaction on a fresh connection; do not resend commit."
        }
    }
}
