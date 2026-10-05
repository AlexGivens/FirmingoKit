import SwiftUI
import FirmingoKit
import UniformTypeIdentifiers

/// Native SDK-driven offline selection and explicit device-evidence review; imported files remain a development capability.
@MainActor struct CompilerSelectionView: View {
    /// Window-owned build controller; the SDK owns metadata validation and recipe compatibility.
    @Bindable var builds: WorkbenchBuildModel
    /// Prevents reviewing device evidence while this window is replacing resident firmware.
    var isProgrammingFirmware: Bool
    /// Presents explicit service selection while redistribution/provenance review blocks packaging.
    @State private var selectingCompiler = false
    /// Imports a catalogue against independently reviewed provenance rather than hashing its own untrusted bytes.
    @State private var selectingCatalogue = false
    /// Restores separate SDK device evidence without implicitly confirming installed-image identity.
    @State private var selectingAssociation = false
    /// Retained compatibility path imports the legacy combined resident/device schema.
    @State private var selectingResident = false
    /// Forgetting evidence requires an explicit decision; it does not discard pending transaction records.
    @State private var confirmingForget = false
    /// Captures the reviewed removal target even if another selection changes while confirmation is presented.
    @State private var forgettingDeviceID: String?

    /// Uses finite SDK choices and clear unavailable reasons; no entry silently becomes the selected/latest build.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compiler: \(builds.compilerSource == .bundled ? "SDK package" : builds.serviceName)").font(.caption)
            if builds.compilerSource == .bundled, let reason = builds.bundledCompilerReason {
                Text(reason).foregroundStyle(.secondary)
            }
            Button("Reload SDK Resources") { builds.loadSDKResources() }
                .disabled(builds.isBusy || (builds.catalogueSource == .development && builds.compilerSource == .development))
            if builds.selectionMode == .catalogue {
                Text("Firmware catalogue: \(builds.catalogueSource.rawValue)").font(.caption)
                Picker("Build board", selection: $builds.buildBoard) {
                    ForEach(FirmingoBoard.allCases) { board in Text(board.displayName).tag(board) }
                }
                .disabled(builds.isBusy)
                if let reason = builds.catalogueUnavailableReason { Text(reason).foregroundStyle(.secondary) }
                if builds.catalogue != nil {
                    Picker("Firmware build", selection: Binding(get: { builds.selectedFirmwareBuildID }, set: { builds.selectFirmwareBuild($0) })) {
                        Text("Choose an exact build").tag("")
                        ForEach(builds.firmwareBuilds) { build in
                            Text("\(build.firmwareVersion) · \(build.id.prefix(12)) · \(build.qualification)").tag(build.id)
                        }
                    }
                    .disabled(builds.isBusy)
                }
                if let build = builds.firmwareBuild {
                    Text("Profile: \(build.profile.rawValue) · \(build.qualification)")
                    Text("Build identity: \(build.id)").font(.caption.monospaced())
                    Text("Resident ELF: \(build.residentELFSHA256)").font(.caption.monospaced())
                    Text("Firmware image: \(build.firmwareImageSHA256)").font(.caption.monospaced())
                    Text("Offline Build needs no device association. Run requires separate reviewed evidence and a fresh matching connection.")
                    Button("Import Device Association…") { selectingAssociation = true }.disabled(builds.isBusy || isProgrammingFirmware)
                }
                if let association = builds.association {
                    Text("Associated device: \(association.deviceID)").font(.caption.monospaced())
                    Text("Evidence: \(association.evidence.rawValue)").font(.caption)
                    if let operation = association.installationOperationID {
                        Text("Reviewed installation: \(operation.uuidString)").font(.caption.monospaced())
                    }
                    Toggle("I reviewed this device's exact firmware association and verification limits", isOn: $builds.trustedAssociation)
                        .disabled(builds.isBusy || isProgrammingFirmware)
                    Button("Save Reviewed Association") { builds.saveAssociation() }
                        .disabled(builds.isBusy || isProgrammingFirmware || !builds.associationsLoaded || !builds.trustedAssociation)
                    if builds.savedAssociations.contains(association) {
                        Button("Forget Saved Association…", role: .destructive) {
                            forgettingDeviceID = association.deviceID; confirmingForget = true
                        }
                            .disabled(builds.isBusy || isProgrammingFirmware)
                    }
                    Text("Imported evidence is a host assertion. Hello does not attest installed image bytes.").foregroundStyle(.secondary)
                }
                if let reason = builds.associationUnavailableReason { Text(reason).foregroundStyle(.secondary) }
                DisclosureGroup("Saved device associations") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved evidence never grants review after restart. Restore only after choosing its exact firmware build.").font(.caption)
                        Button("Reload Saved Associations") { builds.reloadAssociations() }
                            .disabled(builds.isBusy || isProgrammingFirmware)
                        if builds.associationsLoaded, builds.savedAssociations.isEmpty { Text("No device associations saved.") }
                        ForEach(builds.savedAssociations, id: \.deviceID) { saved in
                            Text("Device: \(saved.deviceID) · Build: \(saved.firmwareBuildID)").font(.caption.monospaced())
                            if saved.firmwareBuildID == builds.firmwareBuild?.id {
                                Button("Restore \(saved.deviceID)") { builds.selectSavedAssociation(saved.deviceID) }
                                    .disabled(builds.isBusy || isProgrammingFirmware)
                            } else { Text("This evidence requires a different exact firmware build.").font(.caption).foregroundStyle(.secondary) }
                            Button("Forget \(saved.deviceID)…", role: .destructive) {
                                forgettingDeviceID = saved.deviceID; confirmingForget = true
                            }
                            .disabled(builds.isBusy || isProgrammingFirmware)
                        }
                    }
                }
            } else {
                Button("Import Legacy Resident Record…") { selectingResident = true }.disabled(builds.isBusy || isProgrammingFirmware)
                if let resident = builds.resident {
                    Text("Resident device: \(resident.deviceID)").font(.caption.monospaced())
                    Toggle("I verified this trusted record matches the installed resident image", isOn: $builds.trustedResident)
                        .disabled(builds.isBusy || isProgrammingFirmware)
                }
            }
            DisclosureGroup("Development resources") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Development imports require independently reviewed provenance. SDK package resources are the normal path.")
                    Picker("Build selection", selection: $builds.selectionMode) {
                        ForEach(WorkbenchBuildModel.SelectionMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .disabled(builds.isBusy)
                    Picker("Compiler source", selection: Binding(get: { builds.compilerSource }, set: { builds.selectCompilerSource($0) })) {
                        ForEach(WorkbenchBuildModel.ResourceSource.allCases) { source in Text(source.rawValue).tag(source) }
                    }
                    .disabled(builds.isBusy)
                    if builds.compilerSource == .development {
                        Text(builds.serviceName).font(.caption)
                        Button("Select Compiler Service…") { selectingCompiler = true }.disabled(builds.isBusy)
                    }
                    if builds.selectionMode == .catalogue {
                        Picker("Catalogue source", selection: Binding(get: { builds.catalogueSource }, set: { builds.selectCatalogueSource($0) })) {
                            ForEach(WorkbenchBuildModel.ResourceSource.allCases) { source in Text(source.rawValue).tag(source) }
                        }
                        .disabled(builds.isBusy)
                        if builds.catalogueSource == .development {
                            TextField("Trusted catalogue SHA-256", text: $builds.expectedCatalogueSHA256)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .disabled(builds.isBusy)
                            Text("Use the SHA-256 from independently reviewed build or package provenance.").font(.caption)
                            Button("Import Reviewed Catalogue…") { selectingCatalogue = true }
                                .disabled(builds.isBusy || builds.expectedCatalogueSHA256.utf8.count != 64)
                        }
                    }
                }
            }
        }
        .alert("Forget this saved device association?", isPresented: $confirmingForget) {
            Button("Cancel", role: .cancel) {}
            Button("Forget", role: .destructive) {
                if let forgettingDeviceID { builds.forgetAssociation(deviceID: forgettingDeviceID) }
            }
        } message: { Text("This removes saved firmware evidence for device \(forgettingDeviceID ?? "unknown"). Upload journals and firmware are unchanged.") }
        .fileImporter(isPresented: $selectingCompiler, allowedContentTypes: [.data]) { result in
            switch result { case .success(let url): builds.selectService(url); case .failure(let error): builds.report(error) }
        }
        .fileImporter(isPresented: $selectingCatalogue, allowedContentTypes: [.json]) { result in
            switch result { case .success(let url): builds.selectCatalogue(url); case .failure(let error): builds.report(error) }
        }
        .fileImporter(isPresented: $selectingAssociation, allowedContentTypes: [.json]) { result in
            switch result { case .success(let url): builds.selectAssociation(url); case .failure(let error): builds.report(error) }
        }
        .fileImporter(isPresented: $selectingResident, allowedContentTypes: [.json]) { result in
            switch result { case .success(let url): builds.selectResident(url); case .failure(let error): builds.report(error) }
        }
    }
}
