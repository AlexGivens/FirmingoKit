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
        let count = try Self.validateBlocks(bytes: bytes, board: board) { number in
            FirmwareReleaseContract.flashStart + number * 256
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

    /// Validates the reviewed composite with whole UF2 erase groups, including erased resident tail padding.
    static func validateManagedInitial(bytes: Data, residentBlocks: UInt32) throws {
        guard residentBlocks > 0, residentBlocks <= 8192 else {
            throw FirmwareLifecycleError.invalidImage("invalid resident or managed-sector extent")
        }
        let alignedResidentBlocks = (residentBlocks + 15) & ~UInt32(15)
        guard bytes.count / 512 == Int(alignedResidentBlocks) + 16 else {
            throw FirmwareLifecycleError.invalidImage("incomplete ROM erase groups")
        }
        _ = try validateBlocks(bytes: bytes, board: .nanoRP2040Connect, erasedBlocks: residentBlocks..<alignedResidentBlocks) { number in
            number < alignedResidentBlocks ? FirmwareReleaseContract.flashStart + number * 256 :
                0x10200000 + (number - alignedResidentBlocks) * 256
        }
    }

    /// Applies the shared finite RP2040 header, sequence, padding and per-block flash bounds.
    private static func validateBlocks(bytes: Data, board: FirmingoBoard,
                                       erasedBlocks: Range<UInt32> = 0..<0,
                                       addressForBlock: (UInt32) -> UInt32) throws -> Int {
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
                  !erasedBlocks.contains(number) || data[offset + 32..<offset + 288].allSatisfy({ $0 == 0xff }),
                  data[offset + 288..<offset + 508].allSatisfy({ $0 == 0 }) else {
                throw FirmwareLifecycleError.invalidImage("invalid UF2 header, padding, or block sequence")
            }
            // The bounded block number makes multiplication/addition safe before address comparison.
            guard address == addressForBlock(number),
                  address < FirmwareReleaseContract.flashEnd(for: board),
                  FirmwareReleaseContract.flashEnd(for: board) - address >= 256 else {
                throw FirmwareLifecycleError.invalidImage("unsupported flash address or image layout")
            }
        }
        return count
    }
    /// Reads a little-endian u32 after the complete-block bounds check.
    private static func u32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<offset + 4].reversed().reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
