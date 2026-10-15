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
        /// Nano stateful ABI two, target two; data/BSS are reinitialized for every generation.
        case nanoManagedV2 = "nano-managed-v2"

        /// Reviewed compiler recipe for this exact format; no moving latest selection exists.
        var recipeIdentifier: String { self == .nanoManagedV1 ? "nano-stateless-clang-22.1.8-v1-experimental" : "nano-stateful-clang-22.1.8-v1-experimental" }
        /// Immutable recipe asset/flag identity, separate from firmware export and service identity.
        var recipeSHA256: String { self == .nanoManagedV1 ? "b7869f6fc863e1905deb6974408c6e7dc63943a1fb3e342a357fdf757b1e23d9" : "25def36c701dd5e527ba128215deb3f87c158e1c6eb6eb2fa7fd106b5f543868" }
        /// Exact firmware target ID associated with this versioned capsule format.
        var targetID: UInt32 { self == .nanoManagedV1 ? 1 : 2 }
    }

    /// Validates the explicit board/profile combination without connecting or choosing another firmware.
    public init(snapshot: SketchSourceSnapshot, board: FirmingoBoard, profile: Profile,
                resident: ManagedResidentBinding) throws {
        guard board == .nanoRP2040Connect else {
            throw SketchBuildError.unsupportedBoard
        }
        guard profile == resident.profile else { throw SketchBuildError.invalidProvenance }
        self.snapshot = snapshot
        self.board = board
        self.profile = profile
        self.resident = resident
    }
}
