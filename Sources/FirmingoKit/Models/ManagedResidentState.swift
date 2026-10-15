import Foundation

/// Exact volatile RAM arena from a reviewed ABI-two resident export. It is reset for every generation.
/// This value is static build metadata; hello cannot attest its address or installed resident bytes.
public struct ManagedResidentState: Equatable, Sendable {
    /// Four-byte-aligned base of the resident-owned sketch arena, separate from heap and stacks.
    public let address: UInt32
    /// Arena extent in bytes; initialized data and BSS together must fit within this limit.
    public let capacityBytes: UInt32
    /// Reviewed firmware contract digest, independent of the compatible compiler recipe identity.
    public static let compilerContractSHA256 = "bd57a4db74bcdc5d592d3217957a7975124c6fe84481a5afbd38509c1e20c082"

    /// Rejects overflowing, unaligned or out-of-RP2040-RAM declarations; it does not inspect a board.
    public init(address: UInt32, capacityBytes: UInt32) throws {
        guard (4...4096).contains(capacityBytes), capacityBytes % 4 == 0, address % 4 == 0,
              address >= 0x20000000, address <= 0x20042000 - capacityBytes else {
            throw ManagedUploadError.invalidArtifact("Invalid ABI-two resident state arena")
        }
        self.address = address; self.capacityBytes = capacityBytes
    }
}
