import Foundation

/// Failures in SDK-owned bundled resource discovery, review and integrity; no fallback compiler runs.
/// These errors do not describe device identity or hardware qualification. File I/O errors and cancellation
/// propagate with their original causes. The explicit development-service API retains its existing errors.
public enum ManagedCompilerResourceError: Error, LocalizedError, Sendable, Equatable {
    /// The SDK resource bundle could not be located without an external search or environment override.
    case missingBundle
    /// The inventory bytes do not match the SDK's independently pinned resource-set identity.
    case inventoryIntegrityMismatch
    /// The bounded inventory uses an unsupported schema, recipe, role, identity or approval value.
    case incompatibleInventory
    /// A fixed resource role is absent, nonregular, symlinked, empty or exceeds its byte bound.
    case invalidFile(String)
    /// A resource's exact byte count or digest disagrees with the reviewed inventory.
    case resourceIntegrityMismatch(String)
    /// Compiler distribution review is pending; placing a service file in the bundle cannot bypass it.
    case serviceApprovalPending

    /// Short host-presentable reasons, distinct from successful metadata discovery or compilation.
    public var errorDescription: String? {
        switch self {
        case .missingBundle: "The FirmingoKit compiler resource bundle is missing. Include the package resources in the host app."
        case .inventoryIntegrityMismatch: "The bundled compiler inventory failed its integrity check. Use a consistent reviewed SDK resource set."
        case .incompatibleInventory: "The bundled compiler inventory is incompatible with this SDK. Use matching SDK code and resources."
        case .invalidFile(let path): "The bundled resource \(path) is missing or invalid. Use an intact SDK resource set."
        case .resourceIntegrityMismatch(let path): "The bundled resource \(path) failed its byte-count or digest check. Use an intact SDK resource set."
        case .serviceApprovalPending: "The bundled compiler service is unavailable while distribution review is pending. No compiler service is shipped in this SDK resource set."
        }
    }
}
