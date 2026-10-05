import FirmingoKit
import Foundation
import Observation

/// Sheet-owned presentation of artifact review, explicit execution and persisted SDK observations.
@MainActor @Observable
final class InstallationReviewModel {
    /// Shared app journal and device-action guard, injectable for deterministic host coordination checks.
    private let records: InstallationRecordStore
    /// Creates sheet-owned state using the same process-wide coordinator as managed Run.
    init(records: InstallationRecordStore = .shared) { self.records = records }
    /// Explicit board selection independent of an active or missing Firmingo connection.
    var board: FirmingoBoard = .nanoRP2040Connect
    /// Exact release profile expected for the selected complete image.
    var profile: FirmingoDevice.Backend = .application
    /// User-selected local release manifest; file selection alone is not publisher authentication.
    var manifestURL: URL?
    /// User-selected complete UF2; the SDK matches its bytes rather than this filename.
    var imageURL: URL?
    /// Explicit acknowledgement of host trust before parsing an unsigned local index.
    var trustsReleaseSource = false
    /// Last reviewable SDK plan, cleared when any selected input changes.
    private(set) var plan: FirmingoInstallationPlan?
    /// Current artifact validation status, always distinct from successful installation.
    private(set) var status = "Select a trusted Firmingo manifest and its complete UF2 image."
    /// Keeps selection stable throughout SDK acquisition, preparation, transfer or verification.
    private(set) var isValidating = false
    /// Owned cancellable SDK operation; permitted programming failures retain uncertainty.
    private var task: Task<Void, Never>?
    /// Prevents an older acquisition from publishing a plan after selection changes.
    private var generation = UUID()
    /// Explicit user-selected mounted ROM root; a label never selects a board automatically.
    var volumeURL: URL?
    /// User confirmation of the physical board model associated with that exact selection.
    var confirmsPhysicalBoard = false
    /// Last saved lifecycle observations, including uncertain outcomes restored after restart.
    private(set) var record: FirmwareInstallationRecord?
    /// Operation-specific journal for explicit sharing or inspection by the user.
    private(set) var recordURL: URL?
    /// Presentation-only endpoint for a new read-only hello request.
    var verificationAddress = "192.168.77.1"
    /// Explicit endpoint port; endpoint is never inferred from the ROM mount.
    var verificationPort = "7420"
    /// Direct programming is offered only on macOS by the current SDK adapter.
    private let backend = MacOSUF2ProgrammingBackend()
    /// Installer identity and process-local token survive while this sheet is open.
    private var installer: FirmingoInstaller?
    /// Consumed on every execution attempt; saved records never recreate it.
    private var prepared: PreparedFirmwareInstallation?

    /// The reviewed token is usable only for a new explicit action while this sheet is idle.
    var canInstall: Bool { prepared != nil && !isValidating }
    /// Physical selection and confirmation are required separately from artifact review.
    var canPrepare: Bool { plan != nil && volumeURL != nil && confirmsPhysicalBoard && !isValidating }
    /// Read-only verification is reachable for a completed or uncertain attempt, including restored context.
    var canVerify: Bool {
        guard let record, !isValidating else { return false }
        return [.writeStarted, .transferComplete, .outcomeUnknown, .helloMatched].contains(record.state)
    }

    /// Restores the latest journal without selecting a target, preparing execution, or connecting.
    func restoreLatest() async {
        let token = generation
        do {
            let saved = try await records.loadLatest()
            try Task.checkCancellation()
            guard generation == token, let saved, record == nil else { return }
            record = saved
            status = "Saved operation restored for review. No device action was performed."
        } catch {
            guard generation == token else { return }
            status = "Saved operation could not be read: \(error.localizedDescription)"
        }
    }

    /// Inspects an explicitly selected attachment and asks the SDK to prepare, without writing.
    func prepareInstallation() {
        guard canPrepare, let plan, let volumeURL else { return }
        let token = UUID()
        generation = token
        prepared = nil
        isValidating = true
        status = "Checking the selected ROM attachment…"
        let installer = installer ?? FirmingoInstaller(backend: backend)
        self.installer = installer
        task = Task { [weak self, backend] in
            do {
                let volume = try await backend.inspect(volumeURL: volumeURL)
                let preparation = try await installer.prepare(plan: plan, volume: volume, confirmedPhysicalBoard: plan.board)
                try Task.checkCancellation()
                guard let self, generation == token else { return }
                prepared = preparation
                record = preparation.record
                recordURL = nil
                status = "Target prepared. Installation requires a separate confirmation and replaces existing firmware/data without preservation guarantees."
                isValidating = false
                task = nil
            } catch {
                guard let self, generation == token else { return }
                status = error.localizedDescription
                isValidating = false
                task = nil
            }
        }
    }

    /// Executes only after the user's final confirmation; the SDK owns session close, target gates and transfer.
    func install(workbench: WorkbenchModel) {
        guard canInstall, !workbench.isManagedOperation, let prepared, let installer else { return }
        self.prepared = nil
        isValidating = true
        status = "Saving the operation and requesting Firmingo transfer…"
        let sessions = workbench.beginFirmwareOperation()
        task = Task { [weak self] in
            guard let self else { await workbench.finishFirmwareOperation(); return }
            var operation: UUID?
            do {
                operation = try await records.beginFirmwareInstallation()
                try Task.checkCancellation()
                let result = try await installer.execute(prepared, closing: sessions) { [records, weak self] update in
                    let url = try await records.save(update)
                    await self?.presentRecord(update, url: url)
                }
                record = result
                status = "Host transfer completed. Request a fresh hello; installation and exact image remain unverified."
            } catch {
                presentOperationError(error)
            }
            await workbench.finishFirmwareOperation()
            if let operation { await records.finishDeviceOperation(operation) }
            isValidating = false
            task = nil
        }
    }

    /// Performs one explicit fresh hello without retrying, resuming or replacing firmware.
    func verify() {
        guard canVerify, let record else { return }
        let endpoint: FirmingoEndpoint
        do {
            guard let port = UInt16(verificationPort), port != 0 else { throw FirmingoError.invalidEndpoint }
            endpoint = try FirmingoEndpoint(address: verificationAddress, port: port)
        } catch { status = error.localizedDescription; return }
        let installer = installer ?? FirmingoInstaller(backend: backend)
        self.installer = installer
        isValidating = true
        status = "Requesting a fresh hello from the selected numeric endpoint…"
        task = Task { [weak self] in
            do {
                let result = try await installer.verify(record, at: endpoint, expectedDeviceID: record.observedDeviceID)
                guard let self else { return }
                let url = try await records.save(result)
                presentRecord(result, url: url)
                status = result.state == .helloMatched
                    ? "Hello matched the selected release contract. Exact image and useful behavior remain unverified."
                    : "Hello matched, but the interrupted transfer's outcome remains unknown."
            } catch {
                self?.presentOperationError(error)
                if let saved = self?.record {
                    do {
                        guard let self else { return }
                        let url = try await records.save(saved)
                        recordURL = url
                    } catch { self?.status += " Saving verification context failed: \(error.localizedDescription)" }
                }
            }
            self?.isValidating = false
            self?.task = nil
        }
    }

    /// Presents durable updates without treating filesystem acceptance as installed-image success.
    private func presentRecord(_ record: FirmwareInstallationRecord, url: URL) {
        self.record = record
        recordURL = url
    }

    /// Preserves SDK failure observations and presents the underlying cause without claiming rollback.
    private func presentOperationError(_ error: any Error) {
        guard let failure = error as? FirmwareInstallationError else {
            status = error.localizedDescription
            return
        }
        var cause: any Error = error
        switch failure {
        case .notStarted(let saved, let underlying), .uncertain(let saved, let underlying), .verificationFailed(let saved, let underlying):
            record = saved
            cause = underlying
        default: break
        }
        status = "\(error.localizedDescription) \(cause.localizedDescription)"
    }

    /// Requires two explicit files and trust acknowledgement; no device selection or writer is implied.
    var canReview: Bool { manifestURL != nil && imageURL != nil && trustsReleaseSource && !isValidating }

    /// Requests SDK acquisition/validation only; it neither closes a console nor flashes a board.
    func review() {
        guard canReview, let manifestURL, let imageURL else { return }
        let selectedBoard = board
        let selectedProfile = profile
        let token = UUID()
        generation = token
        plan = nil
        prepared = nil
        confirmsPhysicalBoard = false
        isValidating = true
        status = "Reading and validating the selected release image…"
        task = Task { [weak self] in
            do {
                let image = try await FirmingoFirmwareImage.load(trustedManifestURL: manifestURL, imageURL: imageURL,
                                                                board: selectedBoard, profile: selectedProfile)
                try Task.checkCancellation()
                #if os(macOS)
                let platform = FirmingoInstallationPlan.HostPlatform.macOS
                #else
                let platform = FirmingoInstallationPlan.HostPlatform.iOS
                #endif
                let plan = try FirmingoInstallationPlan(image: image, selectedBoard: selectedBoard, hostPlatform: platform)
                guard let self, generation == token else { return }
                self.plan = plan
                status = "Image validated locally. Installation has not been performed."
                isValidating = false
                task = nil
            } catch {
                guard let self, generation == token else { return }
                status = error is CancellationError ? "Review cancelled." : error.localizedDescription
                isValidating = false
                task = nil
            }
        }
    }

    /// Cancels owned work and invalidates the prior result whenever a selected input changes.
    func invalidate() {
        generation = UUID()
        task?.cancel()
        task = nil
        isValidating = false
        plan = nil
        prepared = nil
        confirmsPhysicalBoard = false
        status = "Selection changed. Review the selected release image again."
    }

    /// Presents native file-picker failures without treating them as SDK installation attempts.
    func presentImportError(_ error: Error) {
        invalidate()
        status = error.localizedDescription
    }

    /// Expires only target authorization when the selected mount or physical confirmation changes.
    func invalidateTarget() {
        prepared = nil
        if plan != nil { status = "Target selection changed. Prepare the selected physical target again." }
    }

    /// Cancels owned work; a permitted write remains uncertain and its saved record stays available.
    func cancel() { task?.cancel() }
}
