import Foundation

/// A single bounded frame assembler. The caller retains coalesced tails and drains ready frames.
/// Header failures are terminal; a fresh connection requires a fresh decoder.
struct FMGOFrameDecoder: Sendable {
    /// Validated payload cap; updated only between frames.
    private(set) var limit = FMGOFrame.maximumPayload
    /// Collected header and, only after validation, payload bytes.
    private var bytes: [UInt8] = []
    /// The validated header kind, absent while the header is incomplete.
    private var kind: FMGOFrame.Kind?
    /// The validated total length, absent while the header is incomplete.
    private var expectedSize: Int?
    /// A sticky terminal failure; no later bytes are accepted.
    private var failure: FirmingoError?

    /// Bytes held by this decoder, always at most header size plus negotiated payload.
    var bufferedByteCount: Int { bytes.count }

    /// Applies a peer offer at an empty frame boundary; retains the device's 4096-byte cap.
    mutating func negotiate(peerOffer: UInt32) throws {
        if let failure { throw failure }
        guard bytes.isEmpty, (512...65536).contains(peerOffer) else {
            throw FirmingoError.protocolViolation("invalid negotiation or partial frame")
        }
        limit = min(FMGOFrame.maximumPayload, Int(peerOffer))
    }

    /// Consumes at most the missing header or payload. Returns the exact consumed byte count.
    /// Even if the input includes a payload, its header is checked before copying any payload bytes.
    mutating func consume(_ input: Data) throws -> Int {
        if let failure { throw failure }
        let required = (expectedSize ?? FMGOFrame.headerSize) - bytes.count
        let count = min(required, input.count)
        bytes.append(contentsOf: input.prefix(count))
        if bytes.count == FMGOFrame.headerSize, expectedSize == nil {
            do {
                try validateHeader()
            } catch let error as FirmingoError {
                failure = error
                throw error
            }
        }
        return count
    }

    /// Removes a complete frame, retaining the negotiated cap for the next frame.
    mutating func takeFrame() -> FMGOFrame? {
        guard let kind, let expectedSize, bytes.count == expectedSize else { return nil }
        let frame = FMGOFrame(kind: kind, requestID: FMGOFrame.uint32(bytes, at: 8),
                              payload: Data(bytes.dropFirst(FMGOFrame.headerSize)))
        bytes.removeAll(keepingCapacity: true)
        self.kind = nil
        self.expectedSize = nil
        return frame
    }

    /// Validates every header field before converting or allocating for its declared payload.
    private mutating func validateHeader() throws {
        guard bytes.prefix(4).elementsEqual([0x46, 0x4d, 0x47, 0x4f]), bytes[6] == 0, bytes[7] == 0,
              let kind = FMGOFrame.Kind(rawValue: bytes[5]) else {
            throw FirmingoError.protocolViolation("invalid magic, flags, or frame type")
        }
        let frame = FMGOFrame(kind: kind, requestID: FMGOFrame.uint32(bytes, at: 8), payload: Data())
        guard frame.hasValidID else { throw FirmingoError.protocolViolation("invalid request ID") }
        guard bytes[4] == 1 else { throw FirmingoError.protocolViolation("unsupported protocol major") }
        let size = FMGOFrame.uint32(bytes, at: 12)
        guard size <= limit else { throw FirmingoError.protocolViolation("payload exceeds negotiated limit") }
        self.kind = kind
        expectedSize = FMGOFrame.headerSize + Int(size)
    }
}
