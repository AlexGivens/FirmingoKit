import Foundation
import FirmingoKit
import Observation

/// Owns exact document/catalogue compilation, separate reviewed device evidence, compatibility builds and durable Run context.
@MainActor @Observable final class WorkbenchBuildModel {
    /// Host-owned durable storage, injectable for SDK-local demo validation without production app data.
    private let records: InstallationRecordStore
    /// SDK-owned loading, injected only by internal controller harnesses to exercise cancellation and stale delivery.
    private let bundledCatalogueLoader: @Sendable () async throws -> ManagedCompilerCatalogue
    /// SDK-owned resource verification; the app does not interpret compiler manifests or decide approval.
    private let bundledCompilerVerifier: @Sendable () async throws -> Void
    /// Creates a window with SDK-only production defaults and optional host-only test boundaries.
    init(records: InstallationRecordStore = .shared,
         bundledCatalogueLoader: @escaping @Sendable () async throws -> ManagedCompilerCatalogue = { try await ManagedCompilerCatalogue.loadBundled() },
         bundledCompilerVerifier: @escaping @Sendable () async throws -> Void = { try await ManagedSketchCompiler().verifyResources() }) {
        self.records = records
        self.bundledCatalogueLoader = bundledCatalogueLoader
        self.bundledCompilerVerifier = bundledCompilerVerifier
    }
    /// Explicit resource source; a failed SDK load never selects a development file.
    enum ResourceSource: String, CaseIterable, Identifiable {
        /// Normal package-owned verified resource path.
        case bundled = "SDK package"
        /// Optional window-owned, independently verified development imports.
        case development = "Development import"
        /// Stable native picker identity.
        var id: String { rawValue }
    }
    /// Normal catalogue source, separate from the selected compiler source.
    private(set) var catalogueSource: ResourceSource = .bundled
    /// Normal compiler source; nil serviceURL does not imply a development fallback.
    private(set) var compilerSource: ResourceSource = .bundled
    /// Most recently verified immutable SDK metadata, never a selected descriptor or device.
    private var bundledCatalogue: ManagedCompilerCatalogue?
    /// Setup observation only; actual builds independently reverify all assets before compiling.
    private(set) var bundledCompilerReady = false
    /// SDK-issued reason why bundled compiler resources are unavailable, separate from metadata choices.
    private(set) var bundledCompilerReason: String? = "SDK compiler resources have not been checked yet."
    /// Explicit catalogue/offline flow or retained compatibility record flow; no implicit fallback occurs.
    enum SelectionMode: String, CaseIterable, Identifiable {
        /// Device-independent SDK selection from package metadata or explicit development imports.
        case catalogue = "Firmware catalogue"
        /// Existing explicit device-bound record workflow for compatibility and advanced development.
        case legacy = "Legacy resident record"
        /// Stable native picker identity.
        var id: String { rawValue }
    }
    /// Changing build mode expires output and device review, without selecting any firmware automatically.
    var selectionMode: SelectionMode = .catalogue {
        didSet { if selectionMode != oldValue { compilerSelectionChanged() } }
    }
    /// Independent offline board selection; it need not match a disconnected device inspection selection.
    var buildBoard: FirmingoBoard = .nanoRP2040Connect {
        didSet {
            if buildBoard != oldValue { selectedFirmwareBuildID = ""; association = nil; compilerSelectionChanged() }
        }
    }
    /// Anchor from independently reviewed provenance; edits discard prior catalogue selection and device evidence.
    var expectedCatalogueSHA256 = "" {
        didSet {
            if expectedCatalogueSHA256 != oldValue, catalogueSource == .development {
                catalogue = nil; selectedFirmwareBuildID = ""; association = nil; compilerSelectionChanged()
            }
        }
    }
    /// Verified SDK metadata only; no production or synthetic descriptor is embedded in the demo.
    private(set) var catalogue: ManagedCompilerCatalogue?
    /// Exact explicit descriptor identity, empty until the user chooses; never defaults to the first/latest entry.
    private(set) var selectedFirmwareBuildID = ""
    /// Strict restored real-device evidence, reviewed separately before Run and never required by offline Build.
    private(set) var association: ManagedDeviceAssociation?
    /// Bounded app-private roster, restored without choosing a device or granting review.
    private(set) var savedAssociations: [ManagedDeviceAssociation] = []
    /// A failed or incomplete roster read blocks catalogue Run while leaving offline Build independent.
    private(set) var associationsLoaded = false
    /// Rejects late startup/reload results after a newer explicit storage action.
    private var associationContextGeneration = UUID()
    /// Host review of evidence and installed-image limits; revocation cancels a Run but permits offline compilation.
    var trustedAssociation = false {
        didSet { if !trustedAssociation, isRunning { task?.cancel() } }
    }
    /// Device-independent result for an exact source/catalogue/descriptor selection.
    private(set) var offlineResult: ManagedOfflineCompilationResult?
    /// Distinguishes deployment cancellation from an unrelated offline build or metadata import.
    private var isRunning = false
    /// Host-selected reviewed service URL; no developer path or compiler fallback is built into the app.
    private var serviceURL: URL?
    /// Balanced security-scoped access retained for the compiler file while this window owns it.
    private var serviceScope = false
    /// Explicit trusted build/install record selection, never inferred from hello.
    private(set) var resident: ManagedResidentBinding?
    /// Host confirmation of record provenance/installed-image association; resets on any record change.
    var trustedResident = false
    /// Visible compiler file selection without exposing toolchain implementation in the normal editor flow.
    private(set) var serviceName = "No compiler service selected"
    /// Visible offline compiler/run state; compile success is never presented as hardware execution.
    private(set) var status = "Loading SDK resources; choose an exact available firmware build before compiling."
    /// Retained structured source messages; bounded by the SDK contract.
    private(set) var diagnostics: [SketchDiagnostic] = []
    /// Latest result for this source revision/selection, invalidated by any document or target change.
    private(set) var result: ManagedCompilationResult?
    /// Prevents overlapping builds, runs, reconciliation and imported selection changes.
    private(set) var isBusy = false
    /// True only after the bounded durable context read succeeded or an explicit clear completed.
    private(set) var contextLoaded = false
    /// Saved transaction blocks a new Run until the user explicitly resolves/discards its context.
    private(set) var pendingRecord: ManagedUploadRecord?
    /// Cancellable operation owned by this document window.
    private var task: Task<Void, Never>?
    /// Identifies the current operation and rejects late callbacks from old revisions.
    private var generation = UUID()
    /// Separately rejects late journal reads after context changes, while allowing restore during offline builds/imports.
    private var contextGeneration = UUID()
    /// Selected revision that must still match before staging or commit.
    private var revision: UInt64 = 0
    /// Strong ownership of a run/reconciliation connection for deterministic close on every path.
    private var runSession: FirmingoSession?

    /// Presents importer/snapshot failures without pretending a build started.
    func report(_ error: any Error) { status = error.localizedDescription }
    /// SDK-filtered exact build choices for the independently selected offline board.
    var firmwareBuilds: [ManagedFirmwareBuildDescriptor] { catalogue?.builds(for: buildBoard) ?? [] }
    /// Resolves the current explicit choice from SDK-issued entries; no missing-ID fallback exists.
    var firmwareBuild: ManagedFirmwareBuildDescriptor? { firmwareBuilds.first { $0.id == selectedFirmwareBuildID } }
    /// SDK metadata availability reason, distinct from service readiness and hardware qualification.
    var catalogueUnavailableReason: String? {
        guard let catalogue else { return "No verified catalogue is loaded for the selected resource source." }
        return catalogue.unavailableReason(for: buildBoard)
    }
    /// Enables catalogue Build independently of device association, endpoint, backend or saved upload context.
    var canBuild: Bool {
        guard !isBusy, compilerSource == .bundled ? bundledCompilerReady : serviceURL != nil else { return false }
        return selectionMode == .catalogue ? firmwareBuild != nil : resident != nil && trustedResident
    }

    /// Explicitly switches metadata providers, expiring output/evidence instead of selecting a latest descriptor.
    func selectCatalogueSource(_ source: ResourceSource) {
        guard !isBusy, source != catalogueSource else { return }
        catalogueSource = source
        catalogue = source == .bundled ? bundledCatalogue : nil
        selectedFirmwareBuildID = ""; association = nil; compilerSelectionChanged()
        if source == .bundled, bundledCatalogue == nil { loadSDKResources() }
    }
    /// Switches compiler providers and revokes old review; choosing SDK releases the unused imported file capability.
    func selectCompilerSource(_ source: ResourceSource) {
        guard !isBusy, source != compilerSource else { return }
        compilerSource = source
        if source == .bundled {
            if serviceScope, let serviceURL { serviceURL.stopAccessingSecurityScopedResource() }
            serviceScope = false; serviceURL = nil; serviceName = "No compiler service selected"
        }
        compilerSelectionChanged()
        if source == .bundled, !bundledCompilerReady { loadSDKResources() }
    }
    /// Loads SDK metadata and verifies compiler resources, never reconnecting or overriding completed development choices.
    /// The current package's empty catalogue and pending service remain explicit; retries require a host action.
    func loadSDKResources() {
        guard !isBusy, catalogueSource == .bundled || compilerSource == .bundled else { return }
        if catalogueSource == .bundled { catalogue = nil; selectedFirmwareBuildID = ""; association = nil }
        compilerSelectionChanged()
        bundledCatalogue = nil; bundledCompilerReady = false; bundledCompilerReason = nil
        let token = generation
        isBusy = true; status = "Verifying SDK resources…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await bundledCatalogueLoader()
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                bundledCatalogue = loaded
                if catalogueSource == .bundled { catalogue = loaded }
                if compilerSource == .bundled {
                    try await bundledCompilerVerifier()
                    try Task.checkCancellation()
                    guard generation == token else { throw CancellationError() }
                    bundledCompilerReady = true
                }
                status = loaded.firmwareBuilds.isEmpty ? "SDK resources verified; no firmware builds are available in its catalogue." :
                    "SDK resources verified. Choose an exact firmware build; device review is separate from offline Build."
            } catch {
                bundledCompilerReady = false
                if error is CancellationError {
                    bundledCatalogue = nil
                    if catalogueSource == .bundled { catalogue = nil }
                    bundledCompilerReason = "SDK resource loading cancelled. Reload SDK resources before using them."
                } else { bundledCompilerReason = error.localizedDescription }
                status = bundledCompilerReason ?? error.localizedDescription
            }
            isBusy = false; task = nil
        }
    }
    /// Review gate independent of busy state, rechecked after every deployment suspension.
    private var deviceAssociationReviewed: Bool {
        if selectionMode == .legacy { return resident != nil && trustedResident }
        return trustedAssociation && associationsLoaded && association != nil &&
            association?.firmwareBuildID == firmwareBuild?.id && savedAssociations.contains { $0 == association }
    }
    /// Run remains unavailable without real reviewed evidence and an idle matching Nano/application host selection.
    func canRun(on workbench: WorkbenchModel) -> Bool {
        canBuild && deviceAssociationReviewed && contextLoaded && pendingRecord == nil &&
        !workbench.isProgrammingFirmware && !workbench.isInspecting && !workbench.isConnecting &&
        workbench.board == .nanoRP2040Connect && workbench.backend == .application
    }
    /// Explains missing/mismatched device evidence without implying installed-image attestation.
    var associationUnavailableReason: String? {
        guard selectionMode == .catalogue else { return nil }
        guard let firmwareBuild else { return "Select an exact firmware build before associating a device." }
        guard let association else { return "Run needs a reviewed real-device association. Offline Build does not." }
        if association.firmwareBuildID != firmwareBuild.id { return "The device association belongs to another firmware build." }
        guard associationsLoaded else { return "Reload saved device evidence before Run. Offline Build remains available." }
        guard savedAssociations.contains(association) else { return "Review and explicitly save this association before Run." }
        return trustedAssociation ? nil : "Review the association evidence and installed-firmware limits before Run."
    }

    /// Loads host context only; restart never selects a build/device, grants trust or connects to hardware.
    func restoreAssociations() async {
        let token = associationContextGeneration
        trustedAssociation = false
        do {
            let saved = try await records.loadAssociations()
            try Task.checkCancellation()
            guard associationContextGeneration == token else { return }
            savedAssociations = saved; associationsLoaded = true
        } catch {
            guard associationContextGeneration == token else { return }
            associationsLoaded = false; savedAssociations = []
            status = "Saved associations could not be read: \(error.localizedDescription)"
        }
    }
    /// Explicitly refreshes stale evidence; every refresh requires renewed review even if bytes are unchanged.
    func reloadAssociations() {
        guard !isBusy else { return }
        associationContextGeneration = UUID(); isBusy = true
        task = Task { [weak self] in
            guard let self else { return }
            await restoreAssociations()
            isBusy = false; task = nil
        }
    }
    /// Restores only the exact selected device/build pair; missing catalogue IDs never select a replacement.
    func selectSavedAssociation(_ deviceID: String) {
        guard !isBusy, selectionMode == .catalogue else { return }
        association = nil; trustedAssociation = false
        guard associationsLoaded, let firmwareBuild,
              let saved = savedAssociations.first(where: { $0.deviceID == deviceID }) else { return }
        do {
            _ = try ManagedResidentBinding(association: saved, firmwareBuild: firmwareBuild)
            association = saved
            status = "Saved device evidence restored. Review the exact firmware association before Run."
        } catch { report(error) }
    }
    /// Saves reviewed evidence through a compare-and-replace gate; it never installs firmware or grants future trust.
    func saveAssociation() {
        guard !isBusy, associationsLoaded, trustedAssociation, let association,
              association.firmwareBuildID == firmwareBuild?.id else { return }
        updateAssociations(removing: false, association: association)
    }
    /// Explicitly forgets the selected saved device; upload reconciliation journals remain untouched.
    func forgetAssociation(deviceID: String? = nil) {
        guard !isBusy, associationsLoaded, let id = deviceID ?? association?.deviceID,
              let saved = savedAssociations.first(where: { $0.deviceID == id }) else { return }
        updateAssociations(removing: true, association: saved)
    }
    /// Captures reviewed context before actor suspension and refreshes conflicts without replaying the requested mutation.
    private func updateAssociations(removing: Bool, association: ManagedDeviceAssociation) {
        let expected = savedAssociations, token = generation
        associationContextGeneration = UUID(); isBusy = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let saved: [ManagedDeviceAssociation]
                if removing { saved = try await records.removeAssociation(deviceID: association.deviceID, expected: expected) }
                else { saved = try await records.saveAssociation(association, expected: expected) }
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                savedAssociations = saved; associationsLoaded = true
                if removing {
                    if self.association?.deviceID == association.deviceID { self.association = nil }
                    trustedAssociation = false
                }
                status = removing ? "Device association forgotten. Upload journals are retained." :
                    "Device association saved. Restoring it after restart will require renewed review."
            } catch {
                trustedAssociation = false
                await restoreAssociations()
                status = error is CancellationError ? "Association action cancelled; reload saved evidence before retrying." : error.localizedDescription
            }
            isBusy = false; task = nil
        }
    }

    /// Invalidates old output and physical review on mode/metadata changes, including programmatic changes during work.
    private func compilerSelectionChanged() {
        generation = UUID(); result = nil; offlineResult = nil; trustedResident = false; trustedAssociation = false
        task?.cancel()
        if !isBusy { status = "Build selection changed. Select exact firmware metadata; review device evidence separately for Run." }
    }
    /// Selects only an ID present in SDK-filtered entries and clears previous device evidence; empty means no selection.
    func selectFirmwareBuild(_ id: String) {
        guard !isBusy, id != selectedFirmwareBuildID else { return }
        guard id.isEmpty || firmwareBuilds.contains(where: { $0.id == id }) else {
            selectedFirmwareBuildID = ""; association = nil; compilerSelectionChanged()
            report(ManagedCatalogueError.missingBuild)
            return
        }
        selectedFirmwareBuildID = id; association = nil; compilerSelectionChanged()
    }
    /// Imports exact manifest bytes against the captured independently supplied anchor; failure discards old metadata.
    func selectCatalogue(_ url: URL) {
        guard !isBusy, selectionMode == .catalogue else { return }
        catalogueSource = .development
        catalogue = nil; selectedFirmwareBuildID = ""; association = nil; compilerSelectionChanged()
        let hash = expectedCatalogueSHA256, token = generation
        isBusy = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let bytes = try await CompilerRecordReader.read(url, maximumBytes: 128 * 1024)
                let loaded = try await ManagedCompilerCatalogue.load(manifestJSON: bytes, expectedSHA256: hash)
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                catalogue = loaded
                status = "Catalogue verified. Choose an exact firmware build; no device association is needed for offline Build."
            } catch { status = error is CancellationError ? "Catalogue import cancelled." : error.localizedDescription }
            isBusy = false; task = nil
        }
    }
    /// Restores bounded SDK evidence only for the exact selected build; import never grants physical review or permission.
    func selectAssociation(_ url: URL) {
        guard !isBusy, selectionMode == .catalogue, let firmwareBuild else { return }
        association = nil; trustedAssociation = false
        let token = generation
        isBusy = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let bytes = try await CompilerRecordReader.read(url, maximumBytes: 2048)
                let loaded = try ManagedDeviceAssociation(recordJSON: bytes)
                _ = try ManagedResidentBinding(association: loaded, firmwareBuild: firmwareBuild)
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                association = loaded
                status = "Device association loaded. Review its evidence and installed-image limits before Run."
            } catch { status = error is CancellationError ? "Association import cancelled." : error.localizedDescription }
            isBusy = false; task = nil
        }
    }
    /// Loads saved context for review only; opening a window never reconnects or writes a board.
    func restoreContext() async {
        let token = contextGeneration
        do {
            let saved = try await records.loadManaged()
            try Task.checkCancellation()
            guard token == contextGeneration else { return }
            pendingRecord = saved; contextLoaded = true
        } catch {
            guard token == contextGeneration else { return }
            contextLoaded = false
            status = "Saved run context could not be read: \(error.localizedDescription)"
        }
        if pendingRecord != nil { status = "A saved managed transaction requires review. Check its outcome before requesting another Run." }
    }
    /// Selects a read-only compiler capability; verification occurs in the SDK during each actual build.
    func selectService(_ url: URL) {
        guard !isBusy else { return }
        compilerSource = .development
        compilerSelectionChanged()
        if serviceScope, let serviceURL { serviceURL.stopAccessingSecurityScopedResource() }
        serviceScope = url.startAccessingSecurityScopedResource()
        serviceURL = url; serviceName = url.lastPathComponent; result = nil; offlineResult = nil
    }
    /// Imports at most 2048 bytes and validates them through the SDK; no identity is guessed from an endpoint.
    func selectResident(_ url: URL) {
        guard !isBusy else { return }
        selectionMode = .legacy
        generation = UUID(); let token = generation
        result = nil; offlineResult = nil; resident = nil; trustedResident = false; isBusy = true
        task = Task { [weak self] in
            do {
                let binding = try await Self.readResident(url)
                guard let self else { return }
                guard generation == token else { throw CancellationError() }
                resident = binding; isBusy = false; task = nil
                status = "Resident record loaded. Confirm its trusted source and installed-image association before building."
            } catch {
                guard let self else { return }
                status = error.localizedDescription; isBusy = false; task = nil
            }
        }
    }
    /// Uses the same bounded read-only importer and SDK schema validation as catalogue metadata.
    @concurrent private static func readResident(_ url: URL) async throws -> ManagedResidentBinding {
        try await ManagedResidentBinding(recordJSON: CompilerRecordReader.read(url, maximumBytes: 2048))
    }
    /// Starts a real SDK compile of an immutable current document snapshot; Build never touches a board.
    func build(_ snapshot: SketchSourceSnapshot) {
        start(snapshot, workbench: nil)
    }
    /// Run explicitly builds this document revision before connecting, staging, saving context and committing once.
    func run(_ snapshot: SketchSourceSnapshot, workbench: WorkbenchModel) {
        guard canRun(on: workbench) else { return }
        start(snapshot, workbench: workbench)
    }
    /// Captures all source/target inputs before suspension and keeps stale completions away from the editor.
    private func start(_ snapshot: SketchSourceSnapshot, workbench: WorkbenchModel?) {
        guard canBuild else { return }
        let compiler: ManagedSketchCompiler
        if compilerSource == .bundled { compiler = ManagedSketchCompiler() }
        else if let serviceURL { compiler = ManagedSketchCompiler(serviceURL: serviceURL) }
        else { return }
        let endpoint: FirmingoEndpoint?
        let offlineRequest: ManagedOfflineBuildRequest?
        let deviceBinding: ManagedResidentBinding?
        let selectedAssociation = association
        do {
            if selectionMode == .catalogue {
                guard let catalogue, let firmwareBuild else { throw ManagedCatalogueError.missingBuild }
                offlineRequest = try ManagedOfflineBuildRequest(snapshot: snapshot, catalogue: catalogue, firmwareBuildID: firmwareBuild.id)
                if workbench != nil {
                    guard deviceAssociationReviewed, let selectedAssociation else { throw ManagedCatalogueError.invalidAssociation }
                    deviceBinding = try ManagedResidentBinding(association: selectedAssociation, firmwareBuild: firmwareBuild)
                } else { deviceBinding = nil }
            } else {
                guard let resident else { throw ManagedCatalogueError.invalidAssociation }
                offlineRequest = nil; deviceBinding = resident
            }
            if let workbench {
                guard let port = UInt16(workbench.port), port != 0 else { throw FirmingoError.invalidState }
                endpoint = try FirmingoEndpoint(address: workbench.address, port: port)
            } else { endpoint = nil }
        } catch { status = error.localizedDescription; return }
        generation = UUID(); let token = generation; revision = snapshot.revision
        workbench?.isManagedOperation = true
        isBusy = true; isRunning = workbench != nil; result = nil; offlineResult = nil; diagnostics = []; status = "Verifying compiler resources…"
        task = Task { [weak self] in
            guard let self else { return }
            var openConsole = false
            var operation: UUID?
            do {
                if workbench != nil { operation = try await records.beginManagedRun(association: offlineRequest == nil ? nil : selectedAssociation) }
                try Task.checkCancellation()
                let progress: @Sendable (ManagedCompilationPhase) -> Void = { [weak self] phase in
                    Task { @MainActor in
                        guard let self, self.generation == token, self.isBusy, self.result == nil, self.offlineResult == nil else { return }
                        self.status = "\(phase.rawValue.capitalized)…"
                    }
                }
                let capsule: ManagedCapsule?
                if let offlineRequest {
                    let built = try await compiler.build(offlineRequest, progress: progress)
                    try Task.checkCancellation()
                    guard generation == token, revision == snapshot.revision,
                          workbench == nil || deviceAssociationReviewed else { throw CancellationError() }
                    offlineResult = built; diagnostics = built.diagnostics
                    status = "Build complete: \(built.artifact.bytes.count)-byte offline managed capsule. Device execution is unconfirmed."
                    if workbench != nil, let selectedAssociation { capsule = try built.artifact.bind(to: selectedAssociation) }
                    else { capsule = nil }
                } else {
                    guard let deviceBinding else { throw ManagedCatalogueError.invalidAssociation }
                    let request = try ManagedSketchBuildRequest(snapshot: snapshot, board: .nanoRP2040Connect,
                        profile: .nanoManagedV1, resident: deviceBinding)
                    let built = try await compiler.build(request, progress: progress)
                    try Task.checkCancellation()
                    guard generation == token, revision == snapshot.revision, trustedResident else { throw CancellationError() }
                    result = built; diagnostics = built.diagnostics; capsule = built.artifact.capsule
                    status = "Build complete: \(built.artifact.capsule.bytes.count)-byte managed capsule. Device execution is unconfirmed."
                }
                if let endpoint, let workbench, let operation, let deviceBinding, let capsule {
                    await workbench.disconnectConsole()
                    try Task.checkCancellation()
                    let connection = try await FirmingoSession.connect(to: endpoint, expectedBoard: .nanoRP2040Connect,
                        expectedBackend: .application, expectedDeviceID: deviceBinding.deviceID)
                    runSession = connection
                    guard generation == token, revision == snapshot.revision, deviceAssociationReviewed else { throw CancellationError() }
                    status = "Staging managed capsule…"
                    let record = try await connection.stageManagedUpload(capsule)
                    contextGeneration = UUID()
                    pendingRecord = record
                    // Durably save reconciliation context before the SDK is allowed its one commit attempt.
                    try await records.saveManaged(record, operation: operation)
                    try Task.checkCancellation()
                    guard generation == token, revision == snapshot.revision, deviceAssociationReviewed else { throw CancellationError() }
                    status = "Requesting installation once…"
                    let committed = try await connection.commitManagedUpload(record)
                    await connection.disconnect(); runSession = nil
                    status = "Managed transaction: \(committed.state.rawValue) (\(committed.errorCode)). Check its outcome on a fresh connection."
                    // A known accepted commit authorizes one read-only status sample; uncertainty requires a new user action.
                    if committed.state == .committing { openConsole = try await query(record, endpoint: endpoint) }
                }
            } catch let error as ManagedCompilerResourceError {
                if compilerSource == .bundled {
                    bundledCompilerReady = false; bundledCompilerReason = error.localizedDescription
                }
                status = error.localizedDescription
            } catch ManagedCompilerError.compilationFailed(let messages) {
                diagnostics = messages; status = "Compilation failed. Review diagnostics."
            } catch SketchBuildError.unsupportedSource(let messages) {
                diagnostics = messages; status = "Source preparation failed. Review diagnostics."
            } catch ManagedUploadError.uncertainCommit(let record, let cause) {
                contextGeneration = UUID()
                pendingRecord = record
                status = "Installation outcome unknown: \(cause.localizedDescription). Check the saved transaction; commit will not be resent."
            } catch {
                if error is CancellationError { result = nil; offlineResult = nil }
                if workbench != nil, offlineRequest != nil, operation == nil {
                    // The reservation was rejected before compilation; revoking review must not cancel this refresh.
                    isRunning = false
                    await restoreAssociations()
                }
                status = error is CancellationError ? (pendingRecord == nil ? "Build cancelled; no artifact returned." : "Run cancelled; saved transaction requires review.") : error.localizedDescription
                if error is DemoOperationError { await refreshContextAfterConflict() }
            }
            if let connection = runSession { await connection.disconnect(); runSession = nil }
            if let operation { await records.finishDeviceOperation(operation) }
            isBusy = false; isRunning = false; task = nil; workbench?.isManagedOperation = false
            if openConsole, !Task.isCancelled, let workbench, let deviceBinding { workbench.connectConsole(expectedDeviceID: deviceBinding.deviceID) }
        }
    }
    /// An edit cancels pending compile/stage work; commit cancellation preserves its saved uncertain record.
    func sourceChanged(revision: UInt64) {
        self.revision = revision; result = nil; offlineResult = nil
        if isBusy { task?.cancel() }
        else { status = "Source changed. Build the current document revision before deployment." }
    }
    /// Target/endpoint changes invalidate the build and cancel a run without authorizing any replay.
    func selectionChanged() {
        generation = UUID(); result = nil; offlineResult = nil; trustedResident = false; trustedAssociation = false; task?.cancel()
        if !isBusy { status = "Device selection changed. Review device evidence before Run; catalogue Build stays offline." }
    }
    /// Revoking record trust invalidates output and active builds without canceling a newly started record import.
    func trustChanged() {
        if selectionMode == .legacy {
            result = nil
            if resident != nil { task?.cancel() }
        }
    }
    /// Explicitly cancels the current operation; post-commit uncertainty remains visible and journaled.
    func cancel() { task?.cancel() }
    /// Queries saved context only on an explicit action; confirmed startup then opens the separate console.
    func checkOutcome(workbench: WorkbenchModel) {
        guard !isBusy, workbench.board == .nanoRP2040Connect, workbench.backend == .application,
              !workbench.isProgrammingFirmware, !workbench.isInspecting, !workbench.isConnecting, let record = pendingRecord,
              let port = UInt16(workbench.port), port != 0 else { return }
        let endpoint: FirmingoEndpoint
        do { endpoint = try FirmingoEndpoint(address: workbench.address, port: port) }
        catch { status = error.localizedDescription; return }
        isBusy = true; workbench.isManagedOperation = true
        task = Task { [weak self] in
            guard let self else { return }
            var openConsole = false
            var operation: UUID?
            do {
                operation = try await records.beginManagedReview(record)
                try Task.checkCancellation()
                await workbench.disconnectConsole()
                openConsole = try await query(record, endpoint: endpoint)
            } catch {
                status = error.localizedDescription
                if error is DemoOperationError { await refreshContextAfterConflict() }
            }
            if let connection = runSession { await connection.disconnect(); runSession = nil }
            if let operation { await records.finishDeviceOperation(operation) }
            isBusy = false; task = nil; workbench.isManagedOperation = false
            if openConsole, !Task.isCancelled { workbench.connectConsole(expectedDeviceID: record.deviceID) }
        }
    }
    /// Samples one transaction; no retries, polling, new upload, commit or sketch-consumption claim is made.
    private func query(_ record: ManagedUploadRecord, endpoint: FirmingoEndpoint) async throws -> Bool {
        let connection = try await FirmingoSession.connect(to: endpoint, expectedBoard: .nanoRP2040Connect,
            expectedBackend: .application, expectedDeviceID: record.deviceID)
        runSession = connection
        let outcome = try await connection.reconcileManagedUpload(record)
        await connection.disconnect(); runSession = nil
        switch outcome {
        case .snapshot(let snapshot):
            status = snapshot.state == .bootConfirmed
                ? "Startup confirmed: setup and one loop returned. Useful sketch behavior remains unverified."
                : "Managed transaction: \(snapshot.state.rawValue) (\(snapshot.errorCode)); slot touched: \(snapshot.slotTouched)."
            return snapshot.state == .bootConfirmed
        case .unknown(let reason): status = "Managed installation outcome unknown: \(String(describing: reason)). Request a new action after reviewing the saved context."
            return false
        }
    }
    /// Explicit user decision clears the latest blocker while retaining journal history; never initiates another Run.
    func clearContext() {
        guard !isBusy else { return }
        let expected = pendingRecord
        contextGeneration = UUID()
        isBusy = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await records.clearManaged(expected: expected)
                self.pendingRecord = nil; self.contextLoaded = true; self.status = "Saved run context cleared. A new Run requires a new explicit action."
            } catch {
                self.status = error.localizedDescription
                if error is DemoOperationError { await self.refreshContextAfterConflict() }
            }
            self.isBusy = false; self.task = nil
        }
    }
    /// Refreshes a stale window after a rejected action, without clearing context, reconnecting or replaying.
    private func refreshContextAfterConflict() async {
        contextGeneration = UUID()
        do {
            pendingRecord = try await records.loadManaged()
            contextLoaded = true
        } catch {
            contextLoaded = false
            status += " Saved run context could not be read: \(error.localizedDescription)"
        }
    }
    /// Releases window-owned compiler capability and cancels work; durable commit context remains available.
    func stop() {
        generation = UUID(); task?.cancel()
        if serviceScope, let serviceURL { serviceURL.stopAccessingSecurityScopedResource() }
        serviceScope = false
    }
}
