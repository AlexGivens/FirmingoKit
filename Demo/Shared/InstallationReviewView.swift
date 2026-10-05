import FirmingoKit
import SwiftUI
import UniformTypeIdentifiers

/// Native local-file selection and SDK plan review, accessible while Firmingo is disconnected.
@MainActor
struct InstallationReviewView: View {
    /// Window-owned communication presentation passed to the SDK's installation close boundary.
    let workbench: WorkbenchModel
    /// Dismissal belongs to the presenting document window.
    @Environment(\.dismiss) private var dismiss
    /// Sheet-scoped artifact selections and cancellable SDK validation.
    @State private var model = InstallationReviewModel()
    /// Opens the native JSON manifest picker only after user action.
    @State private var choosingManifest = false
    /// Opens the native UF2 picker only after user action.
    @State private var choosingImage = false
    /// Explicit mounted-ROM folder selection; the SDK verifies USB/attachment metadata.
    @State private var choosingVolume = false
    /// Final destructive user decision is separate from file review and target preparation.
    @State private var confirmingInstallation = false

    /// Scrollable native form with explicit trust acknowledgement, progress, and honest execution status.
    var body: some View {
        NavigationStack {
            Form {
                Section("Release image") {
                    Picker("Board", selection: $model.board) {
                        ForEach(FirmingoBoard.allCases) { board in Text(board.displayName).tag(board) }
                    }
                    Picker("Profile", selection: $model.profile) {
                        Text("Application").tag(FirmingoDevice.Backend.application)
                        Text("UART").tag(FirmingoDevice.Backend.uart)
                    }
                    Button("Choose Release Manifest…") { choosingManifest = true }
                    Text(model.manifestURL?.lastPathComponent ?? "No manifest selected").foregroundStyle(.secondary)
                    Button("Choose Firmingo UF2…") { choosingImage = true }
                    Text(model.imageURL?.lastPathComponent ?? "No image selected").foregroundStyle(.secondary)
                    Toggle("I trust the source of this release", isOn: $model.trustsReleaseSource)
                    Text("The release index is unsigned. A matching checksum verifies file integrity; you must establish trust in its publisher.")
                        .font(.caption)
                    Button("Review Installation Plan") { model.review() }.disabled(!model.canReview)
                }
                .disabled(model.isValidating)
                Section("Review status") {
                    if model.isValidating {
                        ProgressView("Operation in progress")
                        Button("Cancel operation", role: .cancel) { model.cancel() }
                    }
                    Text(model.status)
                    Text("Programming is experimental and has no hardware qualification. Reviewing files performs no device operation.")
                        .foregroundStyle(.secondary)
                }
                if let plan = model.plan {
                    planSections(plan)
                    #if os(macOS)
                    Section("Selected physical target") {
                        Button("Choose ROM Volume…") { choosingVolume = true }
                        Text(model.volumeURL?.path ?? "No ROM volume selected")
                        Toggle("This ROM volume belongs to my physical \(plan.board.displayName)", isOn: $model.confirmsPhysicalBoard)
                        Text("The RP2040 ROM interface cannot distinguish Nano from Pico. Identify the physical board and resolve multiple attached boards before confirming.")
                            .font(.caption)
                        Button("Prepare Selected Target") { model.prepareInstallation() }.disabled(!model.canPrepare)
                        Button("Install Firmingo…", role: .destructive) { confirmingInstallation = true }.disabled(!model.canInstall || workbench.isManagedOperation)
                    }
                    .disabled(model.isValidating)
                    #endif
                }
                if let record = model.record { recordSection(record) }
            }
            .formStyle(.grouped)
            .navigationTitle("Prepare Firmingo Installation")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(model.isValidating) }
            }
        }
        .fileImporter(isPresented: $choosingManifest, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): model.manifestURL = url
            case .failure(let error): model.presentImportError(error)
            }
        }
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [UTType(filenameExtension: "uf2") ?? .data]) { result in
            switch result {
            case .success(let url): model.imageURL = url
            case .failure(let error): model.presentImportError(error)
            }
        }
        .fileImporter(isPresented: $choosingVolume, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): model.volumeURL = url
            case .failure(let error): model.presentImportError(error)
            }
        }
        .confirmationDialog("Install Firmingo on the confirmed physical board?", isPresented: $confirmingInstallation, titleVisibility: .visible) {
            Button("Install Firmingo", role: .destructive) { model.install(workbench: workbench) }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let plan = model.plan {
                Text("\(plan.board.displayName) · Firmingo \(plan.image.entry.firmwareVersion) · \(plan.image.entry.profile.rawValue)\n\(model.volumeURL?.path ?? "")\n\(plan.dataEffect)")
            }
        }
        .interactiveDismissDisabled(model.isValidating)
        .task { await model.restoreLatest() }
        .onChange(of: model.board) { model.invalidate() }
        .onChange(of: model.profile) { model.invalidate() }
        .onChange(of: model.manifestURL) { model.trustsReleaseSource = false; model.invalidate() }
        .onChange(of: model.imageURL) { model.invalidate() }
        .onChange(of: model.trustsReleaseSource) { model.invalidate() }
        .onChange(of: model.volumeURL) { model.confirmsPhysicalBoard = false; model.invalidateTarget() }
        .onChange(of: model.confirmsPhysicalBoard) { model.invalidateTarget() }
        .onDisappear { model.invalidate() }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 620, minHeight: 480, idealHeight: 680)
        #endif
    }

    /// Presents persisted SDK observations and a separately requested fresh hello, with no write authority.
    @ViewBuilder private func recordSection(_ record: FirmwareInstallationRecord) -> some View {
        Section("Saved operation") {
            Text("\(record.boardID) · Firmingo \(record.firmwareVersion) · \(record.profile)")
            Text("Operation \(record.operationID.uuidString)").font(.caption.monospaced())
            Text(stateDescription(record.state))
            Text("\(record.transferredBytes) of \(record.imageBytes) bytes accepted by the host filesystem")
            if model.isValidating, record.state == .writeStarted {
                ProgressView(value: Double(record.transferredBytes), total: Double(record.imageBytes))
                    .accessibilityLabel("Host transfer progress")
            }
            LabeledContent("Saved image SHA-256") { Text(record.imageSHA256).font(.caption.monospaced()) }
            Text("Previous selection: \(record.targetMountURL.path)").font(.caption)
            if let failure = record.failureSummary { Text(failure) }
            if let deviceID = record.observedDeviceID, let bootID = record.observedBootID {
                Text("Observed device \(deviceID) · boot \(bootID)").font(.caption.monospaced())
            }
            if let url = model.recordURL { ShareLink("Share Operation Record", item: url) }
            Text(record.recoveryInstructions)
            TextField("Verification IP address", text: $model.verificationAddress).autocorrectionDisabled().disabled(model.isValidating)
            TextField("Verification TCP port", text: $model.verificationPort).disabled(model.isValidating)
            Text("Select the physical board's endpoint. Without a previously recorded device identity, a matching hello cannot establish that this is the board selected over USB.")
                .font(.caption)
            Button("Verify with Fresh Hello") { model.verify() }.disabled(!model.canVerify)
        }
    }

    /// Uses textual state cues; restored write permission is deliberately described as uncertain.
    private func stateDescription(_ state: FirmwareInstallationRecord.State) -> String {
        switch state {
        case .prepared: "Prepared; programming has not been requested."
        case .writeStarted: "Write permitted. A saved interrupted operation has an unknown outcome."
        case .transferComplete: "Host transfer completed; installation remains unverified."
        case .helloMatched: "Hello matched; exact image and useful behavior remain unverified."
        case .failedBeforeWrite: "Programming did not start. A new preparation is required."
        case .outcomeUnknown: "Unknown programming outcome. No automatic retry or resume."
        }
    }

    /// Presents SDK facts and ordered guidance without simulating a writer or verification result.
    @ViewBuilder private func planSections(_ plan: FirmingoInstallationPlan) -> some View {
        Section("Selected artifact") {
            Text("\(plan.board.displayName) · Firmingo \(plan.image.entry.firmwareVersion) · \(plan.image.entry.profile.rawValue)")
            Text("\(plan.image.bytes.count) UF2 bytes · \(plan.image.blockCount) blocks · \(plan.image.entry.qualification)")
            LabeledContent("Image SHA-256") { Text(plan.image.entry.sha256).font(.caption.monospaced()) }
            LabeledContent("Manifest SHA-256") { Text(plan.image.manifestSHA256).font(.caption.monospaced()) }
            LabeledContent("Build report SHA-256") { Text(plan.image.entry.buildReportSHA256).font(.caption.monospaced()) }
            Text("Manifest source: \(plan.image.releaseSource.path)")
            Text(String(format: "Affected flash sectors: 0x%08x through 0x%08x (end excluded)",
                        plan.image.affectedFlashRange.lowerBound, plan.image.affectedFlashRange.upperBound))
                .font(.caption.monospaced())
        }
        Section("Effect on existing data") { Text(plan.dataEffect) }
        Section("Physical and host steps") {
            ForEach(plan.steps) { step in Text(step.instruction) }
        }
        Section("Interrupted transfer") { Text(plan.recoveryInstructions) }
        Section("Verification limits") { Text(plan.verificationLimitations) }
    }
}
