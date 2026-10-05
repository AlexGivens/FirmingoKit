/// A validated hello snapshot. Identity is self-reported, not attestation of installed image bytes.
public struct FirmingoDevice: Equatable, Sendable {
    /// The selected protocol major, currently one.
    public let protocolMajor: UInt32
    /// Self-reported firmware name/version, not an exact image digest.
    public let firmwareVersion: String
    /// Stable board-port identity, unrelated to its IP address.
    public let deviceID: String
    /// Boot identity shared by connections in this boot.
    public let bootID: String
    /// Exact advertised board identifier.
    public let boardID: String
    /// Negotiated maximum payload bytes in either direction.
    public let maximumPayload: UInt32
    /// Authentication mode; the pinned contract uses open-development.
    public let authenticationMode: String
    /// Channel availability; hello does not acquire ownership.
    public let channels: [Channel]
    /// Advertised upload targets; presence alone does not qualify a compatible artifact or resident binding.
    public let targets: [UploadTarget]

    /// An advertised serial channel; a hello snapshot does not acquire it.
    public struct Channel: Equatable, Sendable {
        /// Channel identity, currently one.
        public let id: UInt32
        /// Application byte endpoint or hardware UART.
        public let backend: Backend
        /// Advertised controls, empty in the pinned firmware.
        public let controls: [String]
        /// Stream receive queue capacity in bytes.
        public let receiveQueueBytes: UInt32
        /// Stream transmit queue capacity in bytes.
        public let transmitQueueBytes: UInt32
        /// A momentary availability snapshot; does not grant ownership.
        public let isOwned: Bool
        /// Present only on the UART backend.
        public let uart: UART?
    }
    /// Backends with different configuration capabilities.
    public enum Backend: String, Sendable {
        /// Serial-shaped application data without baud controls.
        case application
        /// Hardware UART with advertised configuration.
        case uart
    }
    /// Validated current UART settings and advertised bounds.
    public struct UART: Equatable, Sendable {
        /// Requested baud rate, bits per second.
        public let baud: UInt32
        /// Hardware-selected baud rate, bits per second.
        public let actualBaud: UInt32
        /// Bits per data word, five through eight.
        public let dataBits: UInt32
        /// none, even, or odd parity.
        public let parity: String
        /// One or two stop bits.
        public let stopBits: UInt32
        /// Advertised configurable field names.
        public let configurable: [String]
        /// Advertised minimum baud rate.
        public let minimumBaud: UInt32
        /// Advertised maximum baud rate.
        public let maximumBaud: UInt32
    }
    /// Device-advertised transfer limits. The host must separately qualify format and resident binding.
    public struct UploadTarget: Equatable, Sendable {
        /// Target identity scoped to this device contract.
        public let id: UInt32
        /// Artifact format name, such as nano-managed-v1.
        public let format: String
        /// Maximum complete capsule bytes.
        public let maximumSize: UInt32
        /// Maximum chunk data bytes, also constrained by negotiated payload minus eight.
        public let maximumChunk: UInt32
        /// Authorization policy advertised by the firmware.
        public let authorization: String
    }
}
