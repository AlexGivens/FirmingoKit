import SwiftUI
import FirmingoWorkbenchCore
import FirmingoKit
import UniformTypeIdentifiers

/// Manual presentation of the same registry, request engine and reports used by the CLI.
@MainActor struct WorkbenchLabView: View {
    /// App-wide model prevents one Test Lab window from hiding another's active run.
    @Bindable var model: WorkbenchLabModel
    /// Finite scenario controls and retained observations; no UI action bypasses the shared runner.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Compiler and device scenarios use public FirmingoKit APIs. Compiler checks are offline. Device checks connect to the explicitly selected board; the binary check sends its selected fixed probe. Lifecycle checks require iOS/iPadOS.")
                    #if os(iOS)
                    Text("The screen stays awake during foreground test runs. Going Home still pauses the controller and exercises real lifecycle behavior.").font(.caption)
                    #endif
                    GroupBox("Paired controller") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.pairing.status).textSelection(.enabled)
                            if let error = model.pairing.diagnosticError { Text(error).foregroundStyle(.red) }
                            if let id = model.pairing.sessionID { Text("Session: " + id.uuidString).font(.caption.monospaced()) }
                            SecureField("One-time pairing invitation (base64)", text: $model.pairingText)
                                .accessibilityIdentifier("workbench.pairing.invitation")
                            HStack {
                                Button("Connect controller") { model.connectPairing() }
                                    .disabled(model.pairingText.isEmpty || model.engine.isRunning)
                                Button("Disconnect controller") { model.pairing.disconnect() }
                                    .disabled(model.pairing.sessionID == nil)
                            }
                            Text("Explicit developer session; controller can run selected scenarios and export reports. Real scene transitions remain device actions. Pair again after app/controller restart.").font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Selected device test") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Inspection reads hello only. Binary testing sends a fixed probe to an already running compatible application; it does not install a sketch.").font(.caption)
                            TextField("Private IPv4 address · FMGO port 7420", text: $model.deviceAddress)
                            TextField("Expected device ID · 16 lowercase hex digits", text: $model.deviceID)
                            Picker("Expected board", selection: $model.deviceBoard) {
                                ForEach(FirmingoBoard.allCases) { board in Text(board.displayName).tag(board.rawValue) }
                            }
                            TextField("Expected boot ID · inspect first", text: $model.deviceBootID)
                                .onChange(of: model.deviceBootID) { _, _ in model.allowConsoleProbe = false; model.allowManagedStage = false; model.allowManagedCommit = false }
                            Picker("Existing application's binary protocol", selection: $model.consoleProbe) {
                                Text("Raw 256-byte echo").tag("raw-256-v1")
                                Text("FMS2 qualification command 2").tag("fms2-command-2-v1")
                            }.onChange(of: model.consoleProbe) { _, _ in model.allowConsoleProbe = false }
                            Toggle("Authorize this fixed binary probe", isOn: $model.allowConsoleProbe)
                            Text("Leave REC and upload-arm jumpers disconnected. Hello is self-reported identity; it does not attest installed firmware bytes.").font(.caption)
                        }.disabled(model.engine.isRunning)
                    }
                    GroupBox("Managed FMS2 upload and recovery") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Requires the separately installed reviewed FMS2 resident. RAM staging, flash commit and read-only startup reconciliation are separate actions. A restarted app can query saved context but cannot commit it.").font(.caption)
                            Picker("Fixed test sketch", selection: $model.managedSketch) {
                                Text("State A · seed 7 / D13 low").tag("state-a")
                                Text("State B · seed 23 / D13 high").tag("state-b")
                            }
                            TextField("Reviewed installed resident-only UF2 SHA-256", text: $model.managedResidentImage)
                            TextField("How the installed resident was established", text: $model.managedEvidenceNote)
                            Toggle("Authorize RAM stage with D2 connected to GND", isOn: $model.allowManagedStage)
                            TextField("Original stage operation UUID", text: $model.managedOperationID)
                                .onChange(of: model.managedOperationID) { _, _ in model.allowManagedCommit = false }
                            TextField("Exact saved SDK record SHA-256", text: $model.managedRecordSHA256)
                                .onChange(of: model.managedRecordSHA256) { _, _ in model.allowManagedCommit = false }
                            Toggle("Authorize one flash commit of this live stage", isOn: $model.allowManagedCommit)
                            Text("Commit replaces the managed sketch. Keep REC disconnected. After upload testing, remove D2-to-GND. A missing commit reply remains uncertain; query the saved transaction without retrying commit.").font(.caption)
                        }.disabled(model.engine.isRunning)
                        .onChange(of: model.managedSketch) { _, _ in model.allowManagedStage = false }
                        .onChange(of: model.managedResidentImage) { _, _ in model.allowManagedStage = false }
                        .onChange(of: model.managedEvidenceNote) { _, _ in model.allowManagedStage = false }
                    }
                    HStack {
                        Button("Load SDK Catalogue") { model.inspectCatalogue() }
                            .accessibilityIdentifier("workbench.lab.catalogue")
                        Button("Load Run History") { model.refreshHistory() }
                    }.disabled(model.engine.isRunning)
                    Picker("Exact firmware build", selection: $model.selectedBuildID) {
                        Text("Select explicitly for compilation").tag("")
                        ForEach(model.engine.catalogue?.builds ?? []) { build in
                            Text(build.profile + " · " + String(build.id.prefix(12))).tag(build.id)
                        }
                    }.disabled(model.engine.isRunning)
                    if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    ForEach(WorkbenchScenario.all) { scenario in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(scenario.title).font(.headline)
                                Text(scenario.category + " · " + scenario.id).font(.caption.monospaced())
                                Text(scenario.detail)
                                if let reason = scenario.unavailableReason { Text("Blocked: " + reason).foregroundStyle(.secondary) }
                                if scenario.requiresSceneTransitions && !model.engine.supportsSceneTransitions {
                                    Text("Requires interactive iOS/iPadOS scene delivery; unavailable in this host.").foregroundStyle(.secondary)
                                }
                                if scenario.requiresBuild && model.selectedBuildID.isEmpty {
                                    Text("Prerequisite: load the catalogue and select the exact supported descriptor.").foregroundStyle(.secondary)
                                }
                                if scenario.requiresDevice { Text(scenario.id.hasPrefix("managed.") ? "Prerequisite: select the original Nano boot and action-specific managed fields above; stage and commit have separate authorizations." : "Prerequisite: select exact device fields; console also requires its observed boot and fixed-probe authorization.").font(.caption) }
                                Button("Run " + scenario.title) { model.run(scenario) }
                                    .disabled(!model.canRun(scenario))
                                    .accessibilityIdentifier("workbench.lab.run." + scenario.id)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let report = model.engine.report {
                        Divider()
                        Text("Current run: " + report.status.rawValue).font(.headline)
                        Text(report.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                        if model.engine.awaitingLifecycleStart {
                            Button("Start lifecycle interruption") { model.beginLifecycleInterruption() }
                                .accessibilityIdentifier("workbench.lab.lifecycle.start")
                        }
                        if let device = report.deviceEvidence {
                            Text("Device: \(device.selection.deviceID) · \(device.selection.address)").font(.caption.monospaced())
                            if let observed = device.snapshot {
                                Text("Observed board: \(observed.boardID) · firmware: \(observed.firmwareVersion) · boot: \(observed.bootID)").font(.caption.monospaced())
                                Text("Channels: \(observed.channels.count) · advertised upload targets: \(observed.targets.count)").font(.caption)
                            }
                            Text("Probe attempted: \(device.probeAttempted ? "yes" : "no") · sent: \(device.sentBytes) · received: \(device.received.count) bytes").font(.caption)
                            Text("Console close acknowledged: \(device.consoleClosed ? "yes" : "no") · disconnected: \(device.disconnected ? "yes" : "no")").font(.caption)
                        }
                        if let managed = report.managedEvidence {
                            Text("Managed action: " + managed.outcome).font(.headline)
                            Text("Operation: " + managed.selection.operationID.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                            if let checkpoint = managed.checkpoint {
                                Text("Commit intent saved: \(checkpoint.commitIntent ? "yes" : "no") · pending guard released: \(checkpoint.released ? "yes" : "no")").font(.caption)
                                if let snapshot = checkpoint.snapshot { Text("Transaction: " + snapshot.state + " · " + snapshot.errorCode + " · slot touched: " + String(snapshot.slotTouched)) }
                                if let reason = checkpoint.unknownReason { Text("Saved context reason: " + reason) }
                                Button("Select saved managed context") { model.selectManagedContext(report) }.disabled(model.engine.isRunning)
                            }
                        }
                        if let exercise = report.exercise {
                            Text("Completed builds: \(exercise.builds.count) · footprint samples: \(exercise.samples.count) · omitted: \(exercise.droppedSamples)")
                            Text(exercise.sceneObservationScope).font(.caption)
                            if let phase = exercise.progress.last { Text("Current SDK phase: " + phase.phase) }
                            if let outcome = exercise.outcome { Text("Interrupted request: " + outcome) }
                            if let peak = exercise.samples.map(\.bytes).max() {
                                Text("Sampled self-process footprint maximum: \(peak) bytes; excludes WebKit children and missed peaks.").font(.caption)
                            }
                        }
                        if model.engine.isRunning { Button("Cancel current scenario") { model.cancel() } }
                        ForEach(report.events, id: \.sequence) { event in
                            VStack(alignment: .leading) {
                                Text(String(format: "%.3f s · %@", event.seconds, event.phase)).font(.caption.monospaced())
                                Text(event.detail).textSelection(.enabled)
                            }
                        }
                        ForEach(Array((report.diagnostics ?? []).enumerated()), id: \.offset) { _, diagnostic in
                            let location = diagnostic.filename ?? "build"
                            let line = diagnostic.line.map { ":\($0)" } ?? ""
                            Text("\(diagnostic.severity): \(location)\(line) — \(diagnostic.message)")
                                .font(.caption.monospaced()).textSelection(.enabled)
                        }
                        if let omitted = report.diagnosticsOmitted, omitted > 0 {
                            Text("Additional messages omitted from display: \(omitted)")
                        }
                        if !model.engine.isRunning {
                            ShareLink("Export run report", item: model.store.directory.appendingPathComponent(report.id.uuidString + "/report.json"))
                        }
                    }
                    if !model.history.isEmpty {
                        Divider()
                        Text("Saved context — no automatic replay").font(.headline)
                        ForEach(model.history) { report in
                            if report.managedEvidence?.checkpoint != nil { Button("Select context · " + String(report.id.uuidString.prefix(8))) { model.selectManagedContext(report) }.disabled(model.engine.isRunning) }
                            Text(report.scenarioID + " · " + report.status.rawValue + " · " + String(report.id.uuidString.prefix(8)))
                                .font(.caption.monospaced())
                        }
                    }
                }.padding()
            }
            .navigationTitle("Firmingo Workbench · Test Lab")
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 500)
            #endif
        }
    }
}
