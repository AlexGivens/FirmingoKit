import Foundation

/// One immutable FMGO frame; payload semantics belong to the session layer.
struct FMGOFrame: Equatable, Sendable {
    /// Wire type values, independent of transport direction.
    enum Kind: UInt8, Sendable {
        /// Host control request JSON.
        case request = 1
        /// Correlated device response JSON.
        case response = 2
        /// Channel-prefixed opaque serial bytes.
        case serial = 3
        /// Transaction-prefixed upload bytes.
        case upload = 4
        /// Uncorrelated event JSON (not emitted by the pinned firmware).
        case event = 5
    }
    /// Fixed header size in bytes.
    static let headerSize = 16
    /// Pinned device/pre-hello payload cap in bytes.
    static let maximumPayload = 4096
    /// How the payload is interpreted.
    let kind: Kind
    /// Nonzero for control/upload frames; zero for serial/events.
    let requestID: UInt32
    /// Opaque bytes, preserved without text conversion.
    let payload: Data

    /// Whether this kind and request ID satisfy the wire invariant.
    var hasValidID: Bool {
        (kind == .serial || kind == .event) ? requestID == 0 : requestID != 0
    }

    /// Produces explicit big-endian framing, rejecting invalid IDs and excessive payloads.
    func encoded(limit: Int = maximumPayload) throws -> Data {
        guard hasValidID, (512...Self.maximumPayload).contains(limit), payload.count <= limit else {
            throw FirmingoError.protocolViolation("invalid frame ID or payload length")
        }
        var bytes: [UInt8] = [0x46, 0x4d, 0x47, 0x4f, 1, kind.rawValue, 0, 0]
        Self.append(requestID, to: &bytes)
        Self.append(UInt32(payload.count), to: &bytes)
        var result = Data(bytes)
        result.append(payload)
        return result
    }

    /// Appends a u32 in network byte order without alignment assumptions.
    private static func append(_ value: UInt32, to bytes: inout [UInt8]) {
        for shift in stride(from: 24, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }

    /// Reads a validated four-byte range in network byte order.
    static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
