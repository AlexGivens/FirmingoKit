#if os(iOS)
import FirmingoKit
import SwiftUI
import UniformTypeIdentifiers

/// Presents the iPhone/iPad ROM workflow and records each explicit user action.
@MainActor struct FilesFirmwareView: View {
    /// Current window's connections are closed before the user enters ROM mode.
    let workbench: WorkbenchModel
    /// Reloads the editor's saved associations after a user-reviewed installation.
    let onAssociated: () -> Void
    /// Completes only the sheet dismissal.
    @Environment(\.dismiss) private var dismiss
    /// App-private journal shared by editor and Test Lab.
    private let records = InstallationRecordStore.shared
    /// Pending or completed attempt across launches.
    @State private var record: ManagedROMInstall.Record?
    /// Validated local image, retained until Files has taken its copy.
    @State private var image: ManagedROMInstall?
    /// Fresh functional observation awaiting the user's review.
    @State private var observation: ManagedROMInstall.Observation?
    /// Explicit optional input when recovering a known board.
    @State private var deviceID = ""
    /// Workbench's current explicit endpoint, editable for this verification only.
    @State private var address = "192.168.77.1"
    /// User-visible status including unresolved handoffs and errors.
    @State private var status = "Loading the reviewed Nano image…"
    /// Prevents conflicting actions while a bounded operation is active.
    @State private var busy = false
    /// Prevents creating an attempt before the saved context has been read.
    @State private var loaded = false
    /// Shows the system picker for the same reviewed image when no image was bundled.
    @State private var importing = false
    /// Presents system Files export only for a saved pending operation.
    @State private var exporting = false
    /// Confirms replacement before any handoff.
    @State private var confirming = false
    /// Stores whether the confirmation is for a new recovery attempt.
    @State private var recovery = false

    /// One guided workflow for the initial image and recovery.
    var body: some View {
        NavigationStack {
            Form {
                Section("Nano RP2040 Connect") {
                    LabeledContent("Firmware", value: ManagedROMInstall.firmwareVersion)
                    Text("This image replaces the Firmingo resident and the managed sketch. Connect only the Nano you intend to program.")
                    Text(status).accessibilityIdentifier("workbench.files-install-status")
                    if image == nil {
                        Button("Choose Reviewed UF2", systemImage: "folder") { importing = true }
                    }
                }
                if record?.observedDeviceID == nil, let record {
                    Section("Pending Installation") {
                        if !record.copyReported {
                            Text("On the unlocked iPad or iPhone, save the UF2 locally in Files. Connect the Nano, bridge REC to GND, then press RESET. Remove REC–GND when RPI-RP2 appears. Leave D2 disconnected.")
                            Text("In Files, copy the saved UF2 to the root of RPI-RP2. The Nano may reboot and the drive may disappear. Return here to report the copy.")
                            Button("Save UF2 to Files", systemImage: "square.and.arrow.up") { exporting = true }
                                .disabled(image == nil)
                            Button("I Copied the UF2") { perform {
                                self.record = try await records.reportFilesCopy(record)
                                status = "Copy reported. Check the Nano after it restarts."
                            } }
                        } else {
                            Text("After the Nano restarts in normal mode, keep it connected and allow local-network access if asked.")
                            TextField("Nano IP address", text: $address)
                                .keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Check Installed Firmware") { verify(record) }
                            if let observation {
                                LabeledContent("Device", value: observation.device.deviceID)
                                LabeledContent("Functional check", value: "Exact 256-byte console reply")
                                Text("Confirm this is the Nano you copied the image to. The running check records device-reported evidence.")
                                Button("Associate This Nano") { associate(record, observation: observation) }
                            }
                        }
                    }
                }
                Section("Start an Attempt") {
                    if record == nil || record?.observedDeviceID != nil {
                        TextField("Existing Nano device ID (optional)", text: $deviceID)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Install Firmingo…") { recovery = false; confirming = true }
                            .disabled(image == nil || !loaded)
                    }
                    Button("Recover Firmingo…") { recovery = true; confirming = true }
                        .disabled(image == nil || !loaded)
                }
            }
            .disabled(busy)
            .navigationTitle("Install or Recover")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy) } }
        }
        .interactiveDismissDisabled(busy)
        .task { await restore() }
        .onChange(of: address) { observation = nil }
        .fileImporter(isPresented: $importing, allowedContentTypes: [FirmwareExport.type, .data]) { result in
            perform {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                image = try await ManagedROMInstall.load(from: url)
                status = "Reviewed image verified. Ready for the next explicit action."
            }
        }
        .fileExporter(isPresented: $exporting, document: image.map { FirmwareExport(bytes: $0.bytes) },
                      contentType: FirmwareExport.type, defaultFilename: String(ManagedROMInstall.filename.dropLast(4))) { result in
            switch result {
            case .success: status = "UF2 exported. Report the copy after you copy it to RPI-RP2."
            case .failure(let error): status = "Files export failed: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(recovery ? "Start a New ROM Recovery?" : "Install Firmingo on the Selected Nano?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(recovery ? "Prepare Recovery" : "Prepare Installation", role: .destructive) { begin() }
        } message: {
            Text("The following Files copy replaces the resident and managed sketch. It requires a separate action in Files.")
        }
    }

    /// Restores the journal and validates a cached or deliberately bundled candidate image.
    private func restore() async {
        busy = true
        defer { busy = false }
        do {
            record = try await records.loadFilesInstallation()
            loaded = true
            let cached = try await records.filesImageURL()
            if FileManager.default.fileExists(atPath: cached.path) {
                image = try await ManagedROMInstall.load(from: cached)
            } else if let url = Bundle.main.url(forResource: String(ManagedROMInstall.filename.dropLast(4)), withExtension: "uf2") {
                image = try await ManagedROMInstall.load(from: url)
            }
            status = if let associated = record?.observedDeviceID { "Device \(associated) is associated with the reviewed FMS2 build." }
                else if record != nil { "Pending attempt restored. Continue from the last recorded step." }
                else if image != nil { "Reviewed image verified and ready." }
                else { "This build needs the reviewed Nano UF2 from Files." }
        } catch { status = error.localizedDescription }
        deviceID = record?.expectedDeviceID ?? ""
        address = workbench.address
    }

    /// Saves the attempt before enabling a user-directed export.
    private func begin() {
        guard let image, !workbench.isManagedOperation else { return }
        perform {
            let previous = record
            let pending = previous?.observedDeviceID == nil ? previous : nil
            let expected = pending?.expectedDeviceID ?? (deviceID.isEmpty ? nil : deviceID)
            let boot = if let expected, workbench.device?.deviceID == expected { workbench.device?.bootID }
                else { pending?.previousBootID }
            let next = try ManagedROMInstall.Record(recovery: recovery, expectedDeviceID: expected, previousBootID: boot)
            _ = workbench.beginFirmwareOperation()
            await workbench.finishFirmwareOperation()
            try await records.beginFilesHandoff(next, image: image, replacing: previous)
            record = next; observation = nil
            status = "Attempt saved. Follow the ROM and Files instructions below."
        }
    }

    /// Requests one fresh verification after the operator reports the external copy.
    private func verify(_ record: ManagedROMInstall.Record) {
        observation = nil
        perform {
            let endpoint = try FirmingoEndpoint(address: address)
            let lease = try await records.beginFilesVerification(record)
            do {
                observation = try await ManagedROMInstall.observe(at: endpoint, expectedDeviceID: record.expectedDeviceID,
                                                                 previousBootID: record.previousBootID)
                status = "Firmware and console checks passed. Review the device before associating."
            } catch {
                await records.finishDeviceOperation(lease)
                throw error
            }
            await records.finishDeviceOperation(lease)
        }
    }

    /// Saves only the selected observed device after a separate explicit review.
    private func associate(_ record: ManagedROMInstall.Record, observation: ManagedROMInstall.Observation) {
        perform {
            self.record = try await records.associateFilesInstallation(record, observation: observation)
            self.observation = nil
            status = "Device associated with the reviewed FMS2 build."
            onAssociated()
        }
    }

    /// Isolates pending UI operations and presents any error without replaying a copy or probe.
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await operation() }
            catch { status = error.localizedDescription }
        }
    }

    /// A write-only native export backed by immutable previously verified bytes.
    private struct FirmwareExport: FileDocument {
        /// Registers the actual UF2 extension for the Files handoff.
        static let type = UTType(exportedAs: "com.firmingokit.demo.firmingo-uf2", conformingTo: .data)
        /// FileDocument requires the readable type even though this document is only exported.
        static let readableContentTypes = [type]
        /// One immutable reviewed image.
        let bytes: Data
        /// Captures owned checked bytes before presenting Files.
        init(bytes: Data) { self.bytes = bytes }
        /// Loading is confined to SDK preflight.
        init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }
        /// Returns exact UF2 bytes with no conversion.
        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
    }
}
#endif
