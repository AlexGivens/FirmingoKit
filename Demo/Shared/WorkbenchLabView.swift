import SwiftUI
import FirmingoWorkbenchCore
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
                    Text("Compiler and device scenarios use public FirmingoKit APIs. Compiler checks are offline; lifecycle checks require this app on iOS/iPadOS.")
                    GroupBox("Paired controller") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.pairing.status).textSelection(.enabled)
                            if let id = model.pairing.sessionID { Text("Session: " + id.uuidString).font(.caption.monospaced()) }
                            SecureField("One-time pairing invitation (base64)", text: $model.pairingText)
                                .accessibilityIdentifier("workbench.pairing.invitation")
                            HStack {
                                Button("Connect controller") { model.connectPairing() }
                                    .disabled(model.pairingText.isEmpty || model.engine.isRunning)
                                Button("Disconnect controller") { model.pairing.disconnect() }
                                    .disabled(model.pairing.sessionID == nil)
                            }
                            Text("Explicit developer session; controller can run offline scenarios and export reports. Real scene transitions remain device actions. Pair again after app/controller restart.").font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading)
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
                                Button("Run " + scenario.title) { model.run(scenario) }
                                    .disabled(model.engine.isRunning || scenario.unavailableReason != nil || (scenario.requiresSceneTransitions && !model.engine.supportsSceneTransitions) || (scenario.requiresBuild && model.selectedBuildID.isEmpty))
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
