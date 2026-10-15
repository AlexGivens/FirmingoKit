import Foundation

/// Host-only one-shot policy; no metadata constructor establishes installed-image evidence.
struct NanoGate {
    /// Exact already qualified static descriptor and resident-only installation candidate.
    static let buildID = "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f"
    /// Exact resident-only image; the operator must establish its installed association separately.
    static let imageSHA = "35678c95c495c4e06227a992548be893305cc2375f7a6e561d0a7f66433e6983"
    /// State transitions require explicit host commands; restart never restores a commit capability.
    enum State { case empty, prepared, inspected, associated, staged, commitAttempted, confirmed, aborted }
    /// Current local admission state, separate from actual firmware transaction state.
    private(set) var state: State = .empty
    /// Exact numeric endpoint inspected before an association was reviewed.
    private(set) var address = ""
    /// Actual hello identity, never inferred from an endpoint or test fixture.
    private(set) var deviceID = ""
    /// Boot identity used to reject a changed device generation before staging.
    private(set) var bootID = ""

    /// Rejects transitions instead of silently recovering/replaying a device operation.
    struct Rejected: LocalizedError {
        /// Explains the missing/stale prerequisite without treating rejected operations as successful.
        var errorDescription: String? { "Qualification prerequisites are missing or changed. Reinspect the selected Nano and review its exact resident evidence." }
    }

    /// Offline preparation never implies a device association.
    mutating func prepared() throws {
        guard state == .empty else { throw Rejected() }; state = .prepared
    }

    /// Pins actual inspected identity and invalidates any earlier association on reinspection.
    mutating func inspected(address: String, deviceID: String, bootID: String) throws {
        guard state == .prepared || state == .inspected || state == .associated else { throw Rejected() }
        self.address = address; self.deviceID = deviceID; self.bootID = bootID; state = .inspected
    }

    /// Requires explicit matching operator selection and exact reviewed installation candidate, not hello attestation.
    mutating func associate(address: String, deviceID: String, imageSHA: String, note: String) throws {
        guard state == .inspected, self.address == address, self.deviceID == deviceID,
              imageSHA == Self.imageSHA, (8...512).contains(note.utf8.count) else { throw Rejected() }
        state = .associated
    }

    /// Revalidates current endpoint, identity and boot before a RAM-stage command can be admitted.
    func requireStage(address: String, deviceID: String, bootID: String) throws {
        guard state == .associated, self.address == address, self.deviceID == deviceID, self.bootID == bootID else { throw Rejected() }
    }

    /// Called only after the SDK verifies RAM staging and the host saves its transaction record.
    mutating func staged() throws {
        guard state == .associated else { throw Rejected() }; state = .staged
    }

    /// Consumed before the one SDK commit attempt; no failure path resets it for replay.
    mutating func requestCommit() throws {
        guard state == .staged else { throw Rejected() }; state = .commitAttempted
    }

    /// Restored records permit status queries only; they never restore a staged session/commit capability.
    mutating func restore() { state = .commitAttempted }

    /// Only actual matching boot-confirmed reconciliation permits completing this operation.
    mutating func confirmed() throws {
        guard state == .commitAttempted else { throw Rejected() }; state = .confirmed
    }

    /// Explicit pre-commit abort or a matching aborted status allows a later fresh operation.
    mutating func aborted() throws {
        guard state == .staged || state == .commitAttempted else { throw Rejected() }; state = .aborted
    }

    /// A new explicit test operation needs fresh inspection/association; previous records remain in the journal.
    mutating func next() throws {
        guard state == .confirmed || state == .aborted else { throw Rejected() }
        state = .prepared; address = ""; deviceID = ""; bootID = ""
    }
}
