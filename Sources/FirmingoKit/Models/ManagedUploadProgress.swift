/// Bounded per-chunk staging notifications. These describe RAM transfer, never installation success.
public enum ManagedUploadProgress: Sendable {
    /// Begin acknowledged a zero-byte stage. Hosts may save this early record for later inspection.
    case accepted(ManagedUploadRecord)
    /// A correlated response acknowledged exactly this cumulative byte count.
    case transferred(ManagedUploadRecord, received: UInt32)
    /// Finish verified the capsule in RAM; a separate explicit commit request is required.
    case verified(ManagedUploadRecord)
}
