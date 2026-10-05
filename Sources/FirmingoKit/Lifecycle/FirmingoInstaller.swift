import Foundation

/// Serializes one-shot full-image programming, durable record gates, and explicit read-only verification.
/// A prepared token is consumed by execute, even on pre-write failure; no retry/resume/reconnect occurs.
public actor FirmingoInstaller {
    /// Trusted programming adapter; platform I/O and attachment inspection remain outside this actor.
    private let backend: any FirmwareProgrammingBackend
    /// Process-local origin identity for non-persistable execution tokens.
    private let identifier = UUID()
    /// Only the newest preparation can authorize this installer's next action.
    private var preparedID: UUID?
    /// Guards reentrancy while preparing, executing, or verifying.
    private var busy = false
    /// Current executing operation, checked by every callback against late delivery.
    private var executingID: UUID?
    /// Latest observations, including progress known before a persistence error.
    private var currentRecord: FirmwareInstallationRecord?
    /// Enforces exactly one before-write gate per backend invocation.
    private var gateInvoked = false
    /// Set only after the host acknowledges writeStarted and cancellation is checked.
    private var writePermitted = false

    /// Creates an installer around a trusted adapter without inspecting or writing.
    public init(backend: any FirmwareProgrammingBackend) { self.backend = backend }

    /// Revalidates selected ROM attachment and binds it to the host-confirmed physical model.
    /// Confirmation is a host/user assertion: generic ROM metadata cannot distinguish Nano/Pico.
    /// The token/record require a separate explicit execute request; a newer prepare expires the old one.
    public func prepare(plan: FirmingoInstallationPlan, volume: FirmwareBootloaderVolume,
                        confirmedPhysicalBoard: FirmingoBoard) async throws -> PreparedFirmwareInstallation {
        guard !busy else { throw FirmwareInstallationError.busy }
        preparedID = nil
        guard plan.hostPlatform == .macOS else { throw FirmwareInstallationError.unsupportedPlatform }
        guard plan.board == confirmedPhysicalBoard else { throw FirmwareLifecycleError.boardMismatch }
        guard volume.backendID == backend.identifier else {
            throw FirmwareInstallationError.invalidRequest("selection belongs to another backend")
        }
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        let current = try await backend.inspect(volumeURL: volume.mountURL)
        guard current == volume else { throw FirmwareInstallationError.targetChanged }
        try Task.checkCancellation()
        let record = FirmwareInstallationRecord(image: plan.image, volume: volume)
        preparedID = record.operationID
        return PreparedFirmwareInstallation(plan: plan, record: record, volume: volume, installerID: identifier)
    }

    /// Executes a process-local reviewed token once after a new explicit host request.
    /// `recordChanged` is ordered/awaited: save updates atomically before returning, especially
    /// writeStarted before the backend may create/write a UF2. Callback failure stops transfer.
    /// Supply all relevant active SDK sessions; idle consoles close/disconnect before writing.
    /// Pending serial/control or staged/committing managed work prevents execution.
    /// Failure/cancellation before the gate reports notStarted; after it, reports uncertainty with
    /// original cause/record. Transfer completion does not prove installation, reboot, or hello.
    public func execute(_ prepared: PreparedFirmwareInstallation, closing sessions: [FirmingoSession] = [],
                        recordChanged: @escaping @Sendable (FirmwareInstallationRecord) async throws -> Void) async throws -> FirmwareInstallationRecord {
        guard !busy else { throw FirmwareInstallationError.busy }
        guard prepared.installerID == identifier, preparedID == prepared.record.operationID else {
            throw FirmwareInstallationError.invalidRequest("execution token is expired, consumed, or belongs to another installer")
        }
        preparedID = nil
        busy = true
        executingID = prepared.record.operationID
        currentRecord = prepared.record
        gateInvoked = false
        writePermitted = false
        let lease = "\(backend.identifier):\(prepared.volume.instanceID)"
        var acquired = false
        defer { busy = false; executingID = nil }
        do {
            try Task.checkCancellation()
            try await FirmwareProgrammingLease.shared.acquire(lease)
            acquired = true
            try await recordChanged(prepared.record)
            for session in sessions { try await session.closeForFirmwareProgramming() }
            let current = try await backend.inspect(volumeURL: prepared.volume.mountURL)
            guard current == prepared.volume else { throw FirmwareInstallationError.targetChanged }
            try Task.checkCancellation()
            try await backend.write(image: prepared.plan.image, to: prepared.volume) { [self] in
                try await authorizeWrite(id: prepared.record.operationID, recordChanged: recordChanged)
            } progress: { [self] count in
                try await acceptProgress(count, id: prepared.record.operationID, recordChanged: recordChanged)
            }
            guard writePermitted, let record = currentRecord, record.transferredBytes == record.imageBytes else {
                throw FirmwareInstallationError.invalidRequest("backend did not complete its write gate and byte progress")
            }
            try Task.checkCancellation()
            let complete = try record.updated(state: .transferComplete)
            currentRecord = complete
            try await recordChanged(complete)
            await FirmwareProgrammingLease.shared.release(lease)
            return complete
        } catch {
            let record = currentRecord ?? prepared.record
            let failed = try record.updated(state: writePermitted ? .outcomeUnknown : .failedBeforeWrite, failure: error)
            currentRecord = failed
            var cause: any Error = error
            do { try await recordChanged(failed) }
            catch { cause = FirmwareInstallationError.cleanupFailed(underlying: cause, cleanup: error) }
            if acquired { await FirmwareProgrammingLease.shared.release(lease) }
            if writePermitted { throw FirmwareInstallationError.uncertain(record: failed, underlying: cause) }
            throw FirmwareInstallationError.notStarted(record: failed, underlying: cause)
        }
    }
    /// Persists writeStarted before permission for the first changing backend action.
    private func authorizeWrite(id: UUID,
                                recordChanged: @Sendable (FirmwareInstallationRecord) async throws -> Void) async throws {
        guard executingID == id, !gateInvoked, let record = currentRecord, record.state == .prepared else {
            throw FirmwareInstallationError.invalidRequest("invalid or repeated before-write callback")
        }
        try Task.checkCancellation()
        gateInvoked = true
        let started = try record.updated(state: .writeStarted)
        currentRecord = started
        try await recordChanged(started)
        try Task.checkCancellation()
        writePermitted = true
    }
    /// Retains locally accepted counts before persistence/cancellation can fail.
    private func acceptProgress(_ count: Int, id: UUID,
                                recordChanged: @Sendable (FirmwareInstallationRecord) async throws -> Void) async throws {
        guard executingID == id, writePermitted, let record = currentRecord,
              count > record.transferredBytes, count <= record.imageBytes else {
            throw FirmwareInstallationError.invalidRequest("nonmonotonic or excessive backend progress")
        }
        let progress = try record.updated(state: .writeStarted, transferredBytes: count)
        currentRecord = progress
        try Task.checkCancellation()
        try await recordChanged(progress)
    }

    /// Requests one fresh hello after transfer or an uncertain/restored operation, never a write.
    /// Matches board/profile/protocol/version and empty release targets; optional prior device ID
    /// is checked by inspection. There is no polling/reconnect retry. Matching identity is self-reported,
    /// not exact-image attestation or useful behavior. An uncertain write remains outcomeUnknown.
    /// The host must save the returned update or the record carried by verificationFailed.
    public func verify(_ record: FirmwareInstallationRecord, at endpoint: FirmingoEndpoint,
                       expectedDeviceID: String? = nil) async throws -> FirmwareInstallationRecord {
        guard let board = FirmingoBoard(rawValue: record.boardID) else {
            throw FirmwareInstallationError.invalidRequest("unsupported saved board")
        }
        return try await verify(record) {
            try await FirmingoInspector.inspect(at: endpoint, expectedBoard: board, expectedDeviceID: expectedDeviceID)
        }
    }
    /// Injects read-only inspection for deterministic tests without networking or hardware.
    func verify(_ record: FirmwareInstallationRecord,
                inspect: @Sendable () async throws -> FirmingoDevice) async throws -> FirmwareInstallationRecord {
        guard !busy else { throw FirmwareInstallationError.busy }
        guard [.writeStarted, .outcomeUnknown, .transferComplete, .helloMatched].contains(record.state) else {
            throw FirmwareInstallationError.invalidRequest("this operation has no programming attempt to verify")
        }
        busy = true
        defer { busy = false }
        do {
            try Task.checkCancellation()
            let device = try await inspect()
            guard device.protocolMajor == 1, device.boardID == record.boardID,
                  device.firmwareVersion == record.firmwareVersion, device.channels.count == 1,
                  device.channels[0].id == 1, device.channels[0].backend.rawValue == record.profile,
                  device.targets.isEmpty else { throw FirmingoError.identityMismatch }
            try Task.checkCancellation()
            let state: FirmwareInstallationRecord.State = record.state == .transferComplete || record.state == .helloMatched
                ? .helloMatched : .outcomeUnknown
            return try record.updated(state: state, device: device)
        } catch {
            let failed = try record.updated(state: record.state, failure: error)
            throw FirmwareInstallationError.verificationFailed(record: failed, underlying: error)
        }
    }
}
