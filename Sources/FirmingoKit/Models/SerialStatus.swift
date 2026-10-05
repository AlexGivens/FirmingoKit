/// A snapshot of channel-one counters and portable queue occupancy.
/// Counter values are not a flush barrier or proof of application consumption.
public struct SerialStatus: Equatable, Sendable {
    /// Bytes accepted by the backend since acquisition; saturates at UInt64.max.
    public let backendReceivedBytes: UInt64
    /// Bytes extracted from the backend since acquisition; not peer delivery.
    public let backendTransmittedBytes: UInt64
    /// Bytes in the portable queue toward the backend, excluding transport/backend queues.
    public let pendingToBackend: UInt32
    /// Bytes in the portable queue toward the peer, excluding transport/backend queues.
    public let pendingToPeer: UInt32
}
