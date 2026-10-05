import Foundation

/// Validates the pinned release's bounded contiguous RP2040 UF2 layout, without executing bytes.
struct UF2ImageLayout {
    /// Payload byte interval, starting at the board's mapped flash base.
    let payloadRange: Range<UInt32>
    /// Conservative four-KiB erase-sector interval that can be affected by this payload.
    let eraseRange: Range<UInt32>
    /// Complete block count checked against every header and unique block number.
    let blockCount: Int

    /// Checks complete 512-byte blocks before decoding little-endian fields; no unaligned loads.
    /// Only family-present, 256-byte payload, zero-padded, contiguous flash images are accepted.
    /// Blocks can arrive in any file order; block numbers must cover the entire sequence exactly.
    init(bytes: Data, board: FirmingoBoard) throws {
        guard !bytes.isEmpty, bytes.count % 512 == 0,
              bytes.count <= FirmwareReleaseContract.maximumImageBytes else {
            throw FirmwareLifecycleError.invalidImage("incomplete or excessive UF2 blocks")
        }
        let data = Array(bytes)
        let count = bytes.count / 512
        var numbers = Set<UInt32>()
        for offset in stride(from: 0, to: data.count, by: 512) {
            let number = Self.u32(data, at: offset + 20)
            let address = Self.u32(data, at: offset + 12)
            guard Self.u32(data, at: offset) == 0x0a324655,
                  Self.u32(data, at: offset + 4) == 0x9e5d5157,
                  Self.u32(data, at: offset + 508) == 0x0ab16f30,
                  Self.u32(data, at: offset + 8) == 0x2000,
                  Self.u32(data, at: offset + 16) == 256,
                  Self.u32(data, at: offset + 24) == count,
                  Self.u32(data, at: offset + 28) == 0xe48bff56,
                  number < count, numbers.insert(number).inserted,
                  data[offset + 288..<offset + 508].allSatisfy({ $0 == 0 }) else {
                throw FirmwareLifecycleError.invalidImage("invalid UF2 header, padding, or block sequence")
            }
            // The bounded block number makes multiplication/addition safe before address comparison.
            guard address == FirmwareReleaseContract.flashStart + number * 256,
                  address < FirmwareReleaseContract.flashEnd(for: board),
                  FirmwareReleaseContract.flashEnd(for: board) - address >= 256 else {
                throw FirmwareLifecycleError.invalidImage("unsupported flash address or image layout")
            }
        }
        let end = FirmwareReleaseContract.flashStart + UInt32(count) * 256
        let eraseEnd = (end + 4095) & ~UInt32(4095)
        guard eraseEnd <= FirmwareReleaseContract.flashEnd(for: board) else {
            throw FirmwareLifecycleError.invalidImage("erase extent enters reserved flash")
        }
        payloadRange = FirmwareReleaseContract.flashStart..<end
        eraseRange = FirmwareReleaseContract.flashStart..<eraseEnd
        blockCount = count
    }
    /// Reads a little-endian u32 after the complete-block bounds check.
    private static func u32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<offset + 4].reversed().reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
