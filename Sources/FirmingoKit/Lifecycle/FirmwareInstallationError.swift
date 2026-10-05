import Foundation

/// Distinguishes validation/pre-write failure from uncertain programming and failed verification.
public enum FirmwareInstallationError: Error, LocalizedError, Sendable {
    /// Invalid request, persisted context, backend behavior, or target metadata.
    case invalidRequest(String)
    /// No direct programming backend is implemented on this platform.
    case unsupportedPlatform
    /// Another operation holds this installer or attachment; nothing is queued automatically.
    case busy
    /// Selection no longer denotes the inspected attachment; a new explicit selection is needed.
    case targetChanged
    /// The write gate was never passed; includes the record and original cause.
    case notStarted(record: FirmwareInstallationRecord, underlying: any Error)
    /// A write was permitted; flash may have changed even when accepted bytes are zero.
    case uncertain(record: FirmwareInstallationRecord, underlying: any Error)
    /// Read-only hello verification failed; transfer observations remain in the supplied record.
    case verificationFailed(record: FirmwareInstallationRecord, underlying: any Error)
    /// Both operation and cleanup/persistence failures occurred; retain both instead of erasing the cause.
    case cleanupFailed(underlying: any Error, cleanup: any Error)

    /// Two-sentence-or-shorter host description; underlying causes remain available in associated values.
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason): "Cannot prepare Firmingo installation: \(reason)."
        case .unsupportedPlatform: "Direct Firmingo programming is unavailable on this platform. Use the guided computer transfer route."
        case .busy: "A device-changing operation is already active."
        case .targetChanged: "The bootloader attachment changed. Select the physical target again."
        case .notStarted: "Firmingo programming did not start. Review the failure and prepare a new request."
        case .uncertain: "Firmingo programming has an unknown outcome. Keep the operation record and request verification or a new ROM reinstall."
        case .verificationFailed: "Post-transfer hello verification failed. The selected image remains unverified."
        case .cleanupFailed: "The operation and resource cleanup both failed."
        }
    }
}
