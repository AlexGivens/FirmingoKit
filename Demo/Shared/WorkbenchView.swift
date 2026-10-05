import SwiftUI
import FirmingoKit
import UniformTypeIdentifiers

/// Document editing and honest SDK capability presentation; no protocol or compiler logic lives here.
@MainActor
struct WorkbenchView: View {
    /// Native document binding, preserving platform open/save/undo behavior.
    @Binding var document: SketchDocument
    /// Inspection state scoped to this document window.
    @State private var model = WorkbenchModel()
    /// Owns cancellable source compilation and managed deployment separately from complete-firmware installation.
    @State private var builds = WorkbenchBuildModel()
    /// Explicit Run reviews replacement of the managed slot and required physical authorization.
    @State private var confirmingRun = false
    /// Requires a new explicit action before discarding unresolved reconciliation context.
    @State private var confirmingClear = false
    /// Stable document identity ties receipts to this window's source revisions.
    @State private var documentID = UUID()
    /// Original document filename used by source diagnostics.
    var filename: String = "Sketch.ino"
    /// Presents explicit endpoint selection.
    @State private var showingInspection = false
    /// Presents SDK artifact preflight independently of a working device connection.
    @State private var showingInstallationReview = false
    /// Source revision incremented on every source/filename mutation and captured in immutable build receipts.
    @State private var revision: UInt64 = 0
    /// Scales monospaced editing text with accessibility text settings.
    @ScaledMetric private var editorSize = 14

    /// Starts near a two-thirds editor/one-third status layout; macOS exposes a draggable divider.
    var body: some View {
        GeometryReader { geometry in
            #if os(macOS)
            VSplitView {
                editor.frame(minHeight: 180, idealHeight: geometry.size.height * 0.67)
                statusPane.frame(minHeight: 120, idealHeight: geometry.size.height * 0.33)
            }
            #else
            VStack(spacing: 0) {
                editor.frame(maxHeight: .infinity)
                Divider()
                statusPane.frame(height: geometry.size.height * 0.33)
            }
            #endif
        }
        .toolbar {
            ToolbarItem {
                Button("Inspect Device", systemImage: "network") { showingInspection = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            ToolbarItem {
                Button("Prepare Firmingo Installation", systemImage: "shippingbox") { showingInstallationReview = true }
            }
            ToolbarItemGroup {
                Button("Build", systemImage: "hammer") { startBuild(run: false) }
                    .disabled(!builds.canBuild || (builds.selectionMode == .legacy && model.board != .nanoRP2040Connect) || model.isProgrammingFirmware)
                    .keyboardShortcut("b", modifiers: [.command])
                Button("Run", systemImage: "play") { confirmingRun = true }
                    .disabled(!builds.canRun(on: model))
                    .keyboardShortcut("r", modifiers: [.command])
                if builds.isBusy { Button("Cancel Build/Run") { builds.cancel() } }
            }
        }
        .sheet(isPresented: $showingInspection) { DeviceInspectionView(model: model) }
        .sheet(isPresented: $showingInstallationReview) { InstallationReviewView(workbench: model) }
        .onChange(of: document.source) { revision &+= 1; builds.sourceChanged(revision: revision) }
        .onChange(of: filename) { revision &+= 1; builds.sourceChanged(revision: revision) }
        .onChange(of: model.board) { builds.selectionChanged() }
        .onChange(of: model.address) { builds.selectionChanged() }
        .onChange(of: model.port) { builds.selectionChanged() }
        .onChange(of: model.isProgrammingFirmware) { builds.selectionChanged() }
        .onChange(of: model.backend) { builds.selectionChanged() }
        .onChange(of: builds.trustedResident) { if !builds.trustedResident { builds.trustChanged() } }
        .task { await builds.restoreContext(); await builds.restoreAssociations(); builds.loadSDKResources() }
        .onDisappear { builds.stop(); model.stopForWindowClose() }
        .alert("Run this document on the selected Nano?", isPresented: $confirmingRun) {
            Button("Build and Run", role: .destructive) { startBuild(run: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces the managed sketch slot. The reviewed device association must match the exact selected Firmingo build. Hold D2/GPIO25 to GND for authorization. Startup confirmation does not prove useful sketch behavior; interrupted commit may have an unknown outcome.")
        }
        .alert("Clear saved run context?", isPresented: $confirmingClear) {
            Button("Clear Context", role: .destructive) { builds.clearContext() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The board may already contain this sketch. Clearing context does not cancel or reverse installation; journal history remains available. A new Run needs a new explicit action.") }
        #if os(macOS)
        .frame(minWidth: 650, minHeight: 480)
        #endif
    }

    /// Creates an immutable exact editor snapshot before invoking SDK compilation or explicit deployment.
    private func startBuild(run: Bool) {
        do {
            let snapshot = try SketchSourceSnapshot(documentID: documentID, revision: revision, filename: filename, source: document.source)
            if run { builds.run(snapshot, workbench: model) } else { builds.build(snapshot) }
        } catch { builds.report(error) }
    }

    /// Source-only editing with native undo and scalable monospaced text.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sketch").font(.headline)
                Spacer()
                Text("Revision \(revision)").font(.caption).foregroundStyle(.secondary)
            }
            TextEditor(text: $document.source)
                .font(.system(size: editorSize, design: .monospaced))
                .autocorrectionDisabled()
                .accessibilityLabel("Sketch source")
        }
        .padding()
    }

    /// Bounded presentation of inspected identity and a live SDK-backed serial console.
    private var statusPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Device & Console").font(.headline)
                Text("Selected: \(model.board.displayName)")
                Text(model.status)
                if let device = model.device {
                    Text("Device \(device.deviceID) · Boot \(device.bootID)").font(.caption.monospaced())
                    Text("Firmware \(device.firmwareVersion) · \(device.channels[0].backend.rawValue) backend")
                    Text("Advertised upload targets: \(device.targets.count)")
                }
                if model.session != nil {
                    Picker("Display", selection: $model.displayMode) {
                        ForEach(WorkbenchModel.ConsoleDisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(model.displayedTranscript.isEmpty ? "No serial bytes received yet." : model.displayedTranscript)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityLabel("Received serial bytes")
                    if model.truncatedBytes > 0 {
                        Text("Display truncated \(model.truncatedBytes) older bytes.")
                    }
                    HStack {
                        TextField("Send UTF-8 bytes", text: $model.consoleInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Send") { model.sendInput() }
                            .disabled(model.consoleInput.isEmpty)
                    }
                }
                Text(model.consoleStatus)
                Group {
                    Text("Build & Run").font(.headline)
                    Text(builds.status)
                    CompilerSelectionView(builds: builds, isProgrammingFirmware: model.isProgrammingFirmware)
                    if model.backend != .application || model.board != .nanoRP2040Connect {
                        Text("Run requires a matching Nano application device selection. Catalogue Build remains independent of device settings.").foregroundStyle(.secondary)
                    }
                    if let record = builds.pendingRecord {
                        Text("Saved device \(record.deviceID), transaction \(record.uploadID)").font(.caption.monospaced())
                        HStack {
                            Button("Check Outcome / Open Console") { builds.checkOutcome(workbench: model) }
                                .disabled(model.board != .nanoRP2040Connect || model.backend != .application)
                            Button("Clear Saved Context…") { confirmingClear = true }
                        }.disabled(builds.isBusy || model.isProgrammingFirmware)
                    }
                    if !builds.contextLoaded {
                        Button("Clear Unreadable Saved Context…") { confirmingClear = true }.disabled(builds.isBusy)
                    }
                    ForEach(Array(builds.diagnostics.enumerated()), id: \.offset) { _, message in
                        Text("\(message.filename ?? "Build")\(message.line.map { ":\($0)" } ?? ""): \(message.severity.rawValue): \(message.message)")
                            .font(.caption.monospaced())
                    }
                }
                Text("Experimental Nano managed builds use a constrained Arduino API. Hardware, sandbox and physical iPad execution remain unqualified.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
    }
}
