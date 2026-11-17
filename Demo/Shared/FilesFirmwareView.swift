#if os(iOS)
import FirmingoKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Installs or recovers Firmingo from one in-place document-picker selection.
@MainActor struct FilesFirmwareView: View {
    /// The window's device sessions are closed before entering ROM mode.
    let workbench: WorkbenchModel
    /// Reloads the editor's associations after a verified installation.
    let onAssociated: () -> Void
    /// Dismisses the installation sheet.
    @Environment(\.dismiss) private var dismiss
    /// Journal and deployment gate shared by all Workbench windows.
    private let records = InstallationRecordStore.shared
    /// Current attempt as recorded in the app's durable journal.
    @State private var record: ManagedROMInstall.Record?
    /// Independently verified bundled or explicitly chosen image.
    @State private var image: ManagedROMInstall?
    /// Fresh manual check requiring review when the automatic check was interrupted.
    @State private var observation: ManagedROMInstall.Observation?
    /// Optional identity for a known board.
    @State private var deviceID = ""
    /// Numeric address used to check the rebooted Nano.
    @State private var address = "192.168.77.1"
    /// Transfer, verification, or recovery guidance.
    @State private var status = "Loading the reviewed Nano image…"
    /// Prevents conflicting actions while the app owns the operation.
    @State private var busy = false
    /// Prevents replacing an unreadable or unrestored context.
    @State private var loaded = false
    /// Presents the reviewed-image importer if a development build omitted the bundled image.
    @State private var importing = false
    /// Presents the native in-place directory picker.
    @State private var pickingVolume = false
    /// The explicitly imported UF2 type declared in the app plist.
    private static let uf2 = UTType(exportedAs: "com.firmingokit.demo.firmingo-uf2", conformingTo: .data)

    /// Guides the Nano from entry into ROM mode through verified startup.
    var body: some View {
        NavigationStack {
            Form {
                Section("Arduino Nano RP2040 Connect") {
                    Text(status).accessibilityIdentifier("workbench.files-install-status")
                    LabeledContent("Firmingo", value: ManagedROMInstall.firmwareVersion)
                    if let installed = record?.observedDeviceID {
                        LabeledContent("Device", value: installed)
                        LabeledContent("Starter console", value: "Exact 256-byte reply verified")
                    }
                    if busy { ProgressView() }
                    if image == nil && loaded {
                        Button("Choose Reviewed UF2…", systemImage: "folder") { importing = true }
                    }
                }
                if let record, record.observedDeviceID == nil {
                    if record.mayVerify {
                        Section("Check Installed Firmware") {
                            Text("Keep the Nano connected in normal mode and allow local-network access if asked.")
                            Button("Verify Again") { verify(record) }
                            if let observation {
                                LabeledContent("Device", value: observation.device.deviceID)
                                Text("Confirm this is the Nano you installed Firmingo on.")
                                Button("Use This Nano") { associate(record, observation: observation) }
                            }
                        }
                    } else {
                        Section("Select the Boot Drive") {
                            if let expected = record.expectedDeviceID {
                                LabeledContent("Expected device", value: expected)
                            }
                            Text("Connect only the Nano you intend to program. Leave D2 disconnected. Bridge REC to GND and press RESET, then remove the REC jumper when RPI-RP2 appears.")
                            Text("Choose the RPI-RP2 drive under Locations. Selecting it starts installation and replaces the firmware and managed sketch. Keep the Nano connected while it restarts.")
                            Button("Choose Boot Drive…", systemImage: "externaldrive") { pickingVolume = true }
                                .disabled(image == nil)
                        }
                    }
                }
                if record == nil || record?.observedDeviceID != nil {
                    Section {
                        Button("Install Firmingo", systemImage: "arrow.down.to.line") { begin(recovery: false) }
                            .disabled(image == nil || !loaded)
                    }
                }
                if record == nil || record?.mayVerify == true {
                    Section {
                        Button("Recover Firmingo", systemImage: "arrow.clockwise") { begin(recovery: true) }
                            .disabled(image == nil || !loaded)
                    }
                }
                DisclosureGroup("Connection Options") {
                    if record == nil || record?.observedDeviceID != nil {
                        TextField("Existing device ID (optional)", text: $deviceID)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    TextField("Nano IP address", text: $address)
                        .keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .disabled(busy)
            .navigationTitle("Install or Recover")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy) } }
        }
        .interactiveDismissDisabled(busy)
        .task { await restore() }
        .onChange(of: address) { observation = nil }
        .sheet(isPresented: $pickingVolume) {
            BootDrivePicker { url in
                pickingVolume = false
                if let url { install(in: url) }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [Self.uf2, .data]) { result in
            perform {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                image = try await ManagedROMInstall.load(from: url)
                status = "Reviewed image verified and ready."
            }
        }
    }

    /// Restores the journal and validates the app's preferred image or its cached copy.
    private func restore() async {
        busy = true
        defer { busy = false }
        do {
            record = try await records.loadFilesInstallation()
            loaded = true
            let cached = try await records.filesImageURL()
            if let url = Bundle.main.url(forResource: String(ManagedROMInstall.filename.dropLast(4)), withExtension: "uf2") {
                image = try await ManagedROMInstall.load(from: url)
            } else if FileManager.default.fileExists(atPath: cached.path) {
                image = try await ManagedROMInstall.load(from: cached)
            }
            status = if record?.observedDeviceID != nil { "Firmingo is ready. You can start coding." }
                else if record?.mayVerify == true { "An earlier installation needs verification. Choose Verify Again or start a new recovery." }
                else if record != nil { "Select the connected Nano’s boot drive to continue." }
                else if image != nil { "Ready to install Firmingo." }
                else { "This build needs the reviewed Nano UF2." }
        } catch { status = error.localizedDescription }
        deviceID = record?.expectedDeviceID ?? ""
        address = workbench.address
    }

    /// Saves an attempt with any available board identity before offering the ROM picker.
    private func begin(recovery: Bool) {
        guard let image else { return }
        perform {
            guard !workbench.isManagedOperation else { throw FirmwareInstallationError.busy }
            let previous = record
            let pending = previous?.observedDeviceID == nil ? previous : nil
            let knownNano = workbench.device.flatMap { device in
                device.boardID == FirmingoBoard.nanoRP2040Connect.rawValue ? device : nil
            }
            let recoveryTarget = recovery ? (knownNano?.deviceID ?? previous?.observedDeviceID) : nil
            let expected = pending?.expectedDeviceID ?? (deviceID.isEmpty ? recoveryTarget : deviceID)
            let boot = if let expected, knownNano?.deviceID == expected { knownNano?.bootID }
                else if let expected, previous?.observedDeviceID == expected { previous?.observedBootID }
                else { pending?.previousBootID }
            let next = try ManagedROMInstall.Record(recovery: recovery, expectedDeviceID: expected, previousBootID: boot)
            _ = workbench.beginFirmwareOperation()
            await workbench.finishFirmwareOperation()
            try await records.prepareFilesInstallation(next, image: image, replacing: previous)
            record = next
            observation = nil
            status = "Put the Nano in ROM mode to select its boot drive."
        }
    }

    /// Holds the shared gate from preflight until verified association or a recorded interruption.
    private func install(in url: URL) {
        guard let image, let selected = record, !selected.mayVerify else { return }
        perform {
            let endpoint = try FirmingoEndpoint(address: address)
            let lease = try await records.beginFilesProgramming(selected)
            let store = records
            status = "Checking the selected boot drive…"
            do {
                let verified = try await image.install(in: url, record: selected, at: endpoint) { dispatched in
                    try await store.saveFilesWriteIntent(dispatched, replacing: selected, lease: lease)
                } progress: { phase in
                    await showProgress(phase)
                }
                guard let dispatched = try await records.loadFilesInstallation() else {
                    throw DemoOperationError.contextChanged
                }
                record = try await records.associateFilesInstallation(dispatched, observation: verified, lease: lease)
                status = "Firmingo is ready. You can start coding."
                onAssociated()
            } catch {
                await records.finishDeviceOperation(lease)
                record = (try? await records.loadFilesInstallation()) ?? record
                if record?.mayVerify == true {
                    status = "Installation could not be confirmed. \(error.localizedDescription) Choose Verify Again to check the Nano or start a new recovery."
                    return
                }
                throw error
            }
            await records.finishDeviceOperation(lease)
        }
    }

    /// Shows the current automatic installation phase.
    private func showProgress(_ phase: ManagedROMInstall.InstallPhase) {
        switch phase {
        case .writing: status = "Installing Firmingo. Keep the Nano connected."
        case .waitingForReboot: status = "Waiting for the Nano to restart and checking its starter sketch…"
        }
    }

    /// Performs a new read-only check of an interrupted or earlier installation.
    private func verify(_ record: ManagedROMInstall.Record) {
        observation = nil
        perform {
            let endpoint = try FirmingoEndpoint(address: address)
            let lease = try await records.beginFilesVerification(record)
            do {
                observation = try await ManagedROMInstall.observe(at: endpoint, expectedDeviceID: record.expectedDeviceID,
                                                                 previousBootID: record.previousBootID)
                status = "Firmware and starter checks passed. Confirm the connected Nano."
            } catch {
                await records.finishDeviceOperation(lease)
                throw error
            }
            await records.finishDeviceOperation(lease)
        }
    }

    /// Associates the manually reviewed device when the automatic install could not finish.
    private func associate(_ record: ManagedROMInstall.Record, observation: ManagedROMInstall.Observation) {
        perform {
            self.record = try await records.associateFilesInstallation(record, observation: observation)
            self.observation = nil
            status = "Firmingo is ready. You can start coding."
            onAssociated()
        }
    }

    /// Runs one selected action and surfaces failures without repeating the action.
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await operation() }
            catch { status = error.localizedDescription }
        }
    }
}

/// Presents Apple's directory picker with access to the original volume.
private struct BootDrivePicker: UIViewControllerRepresentable {
    /// Completes with a transient access grant or a cancelled selection.
    let completion: (URL?) -> Void

    /// Opens one directory in place so the SDK can validate and write to that mount.
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        return picker
    }

    /// The system picker owns updates to its directory contents.
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    /// Holds the callback for the picker delegate.
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    /// Bridges picker actions to the SwiftUI owner.
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        /// Selection or cancellation callback.
        let completion: (URL?) -> Void

        /// Captures one picker presentation's callback.
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }

        /// Passes only the single directory selected by the user.
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls.count == 1 ? urls.first : nil)
        }

        /// Ends the picker without starting an install.
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}
#endif
