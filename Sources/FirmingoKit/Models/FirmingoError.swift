import Foundation

/// Transport/session failures. Cancellation normally throws `CancellationError`; an attempted
/// managed commit preserves cancellation inside `ManagedUploadError.uncertainCommit` instead.
public enum FirmingoError: Error, Sendable, LocalizedError {
    /// The endpoint is not a numeric IPv4/IPv6 address with a nonzero port.
    case invalidEndpoint
    /// The peer violated the selected FMGO contract; this connection must close.
    case protocolViolation(String)
    /// A device rejected a request. The original machine code and message are retained.
    case deviceRejected(code: String, message: String)
    /// The advertised board, backend, or device does not match the host's explicit selection.
    case identityMismatch
    /// The selected operation is not valid in the current channel/session state.
    case invalidState
    /// Another command or write is already outstanding on this connection.
    case busy
    /// Some bytes may have reached the device; a disconnect or cancellation cannot establish execution.
    case uncertainOutcome(operation: String, underlying: any Error)
    /// The transport failed; the underlying platform error is retained.
    case transport(any Error)
    /// The transport closed or the host explicitly ended this session.
    case disconnected
    /// A bounded SDK connection, request, frame, idle, or backpressure deadline elapsed.
    case timedOut

    /// A concise description suitable for host presentation.
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Enter a numeric IP address and a port from 1 through 65535."
        case .protocolViolation(let detail): "Invalid Firmingo response: \(detail)."
        case .deviceRejected(let code, let message): "Firmingo rejected the request (\(code)): \(message)."
        case .identityMismatch: "The device does not match the selected board, backend, or device identity."
        case .invalidState: "The operation is unavailable in the current connection state."
        case .busy: "Another Firmingo operation is in progress."
        case .uncertainOutcome(let operation, _): "The outcome of \(operation) is unknown. Reconnect and confirm device behavior before sending it again."
        case .transport(let error): "The connection failed: \(error.localizedDescription)"
        case .disconnected: "The Firmingo connection closed."
        case .timedOut: "The Firmingo operation exceeded its SDK deadline."
        }
    }
}
