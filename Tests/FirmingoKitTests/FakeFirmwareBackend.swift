import Foundation
@testable import FirmingoKit

/// Deterministic programming adapter that copies non-executable fixtures only into actor-owned memory.
actor FakeFirmwareBackend: FirmwareProgrammingBackend {
    /// Stable fake namespace; each test attachment has its own unique lease key.
    nonisolated let identifier = "fake-rom-uf2-v1"
    /// Current selected attachment; mutation models USB re-enumeration.
    private var volume: FirmwareBootloaderVolume
    /// Deliberate failure/contract variant, never an actual filesystem failure.
    let mode: Mode
    /// Pauses immediately after write permission without timing assumptions.
    let entered = TestLatch()
    /// Test-controlled release while paused; cancellation is handled by the latch.
    let release = TestLatch()
    /// Complete locally accepted bytes for independent golden comparison.
    private(set) var accepted = Data()
    /// Number of backend write invocations, proving lack of implicit retry.
    private(set) var writeCalls = 0
    /// Number of complete synchronizations, separate from data acceptance.
    private(set) var synchronizations = 0

    /// Focused backend behaviors for state/uncertainty validation.
    enum Mode: Sendable {
        /// Bounded short writes then successful sync.
        case complete
        /// Permission error before write gate.
        case denied
        /// Error after an acknowledged partial transfer.
        case partialFailure
        /// Sync failure after all bytes.
        case syncFailure
        /// Cancellation/serialization boundary after the gate.
        case paused
        /// Adapter incorrectly repeats its gate.
        case repeatedGate
        /// Adapter returns success without calling gate or writing.
        case omittedGate
        /// Adapter reports a decreasing byte count.
        case badProgress
    }
    /// Configures an attachment with no I/O, timers, or external state.
    init(volume: FirmwareBootloaderVolume, mode: Mode = .complete) { self.volume = volume; self.mode = mode }
    /// Returns the current fake attachment if its explicit path still matches.
    func inspect(volumeURL: URL) throws -> FirmwareBootloaderVolume {
        guard volumeURL == volume.mountURL else { throw FirmwareInstallationError.targetChanged }
        return volume
    }
    /// Replaces the observation to model re-enumeration or ROM metadata changes.
    func change(to volume: FirmwareBootloaderVolume) { self.volume = volume }
    /// Drives the same bounded transfer loop used by the native backend without opening any file.
    func write(image: FirmingoFirmwareImage, to volume: FirmwareBootloaderVolume,
               willWrite: @escaping @Sendable () async throws -> Void,
               progress: @escaping @Sendable (Int) async throws -> Void) async throws {
        writeCalls += 1
        guard volume == self.volume else { throw FirmwareInstallationError.targetChanged }
        if mode == .denied { throw CocoaError(.fileWriteNoPermission) }
        if mode == .omittedGate { return }
        try await willWrite()
        await entered.signal()
        if mode == .paused { try await release.wait() }
        if mode == .repeatedGate { try await willWrite() }
        if mode == .badProgress { try await progress(100); try await progress(99); return }
        try await UF2FileTransfer.transfer(image.bytes) { [self] in try await accept($0) }
            synchronize: { [self] in try await sync() }
            progress: { try await progress($0) }
    }
    /// Retains a short known prefix, throwing only before accepting the next prefix.
    private func accept(_ bytes: Data) throws -> Int {
        if mode == .partialFailure, accepted.count >= 512 { throw CocoaError(.fileWriteUnknown) }
        let count = min(bytes.count, 512)
        accepted.append(bytes.prefix(count))
        return count
    }
    /// Distinguishes sync failure from complete host-file transfer.
    private func sync() throws {
        if mode == .syncFailure { throw CocoaError(.fileWriteUnknown) }
        synchronizations += 1
    }
}
