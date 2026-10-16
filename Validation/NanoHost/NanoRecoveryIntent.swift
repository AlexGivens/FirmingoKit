import Foundation

/// Durable host intent, distinct from the firmware transaction's unknown or terminal outcome.
enum NanoRecoveryIntent: String, Codable, Sendable {
    /// No commit call was admitted by this host for the saved transaction.
    case ramOnly
    /// Persisted before the one commit call; restoration can never regain commit capability.
    case commitIntent

    /// Only a known pre-commit operation may be retired after reboot without claiming a device abort.
    func requirePrecommitRetirement(bootChanged: Bool) throws {
        guard self == .ramOnly, bootChanged else { throw NanoGate.Rejected() }
    }
}
