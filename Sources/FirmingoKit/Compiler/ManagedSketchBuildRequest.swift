import Foundation

/// Offline source/target/resident selection for the pinned experimental managed-build contract.
/// It does not negotiate firmware capabilities or establish compiler/runtime/hardware support.
public struct ManagedSketchBuildRequest: Equatable, Sendable {
    /// Exact document revision, never read again from an editor during the build.
    public let snapshot: SketchSourceSnapshot
    /// Physical board model; the current managed format is Nano-specific.
    public let board: FirmingoBoard
    /// Explicit managed artifact/ABI profile, distinct from complete-firmware application/UART profiles.
    public let profile: Profile
    /// Host-verified exact resident association; no API address is inferred from hello or a sample.
    public let resident: ManagedResidentBinding

    /// Versioned artifact contract, not a promise that a local compiler recipe is available.
    public enum Profile: String, Sendable {
        /// Nano stateless ABI one, `nano-managed-v1`, target one, 4-KiB capsule limit.
        case nanoManagedV1 = "nano-managed-v1"
    }

    /// Validates the explicit board/profile combination without connecting or choosing another firmware.
    public init(snapshot: SketchSourceSnapshot, board: FirmingoBoard, profile: Profile,
                resident: ManagedResidentBinding) throws {
        guard board == .nanoRP2040Connect else {
            throw SketchBuildError.unsupportedBoard
        }
        self.snapshot = snapshot
        self.board = board
        self.profile = profile
        self.resident = resident
    }
}
