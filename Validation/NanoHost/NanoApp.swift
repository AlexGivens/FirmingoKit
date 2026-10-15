import SwiftUI
import Foundation

/// Separate explicit hardware-qualification host; compiler-only hosts retain their no-device behavior.
@main @MainActor struct NanoQualificationApp: App {
    /// One owner for all device and compiler commands in this single-window test app.
    @StateObject private var model: NanoModel
    /// Actual inactivity cancels owned work and invalidates any RAM-stage capability.
    @Environment(\.scenePhase) private var phase

    /// Starts explicit offline automation from the app lifetime, independent of whether a view task appears.
    init() {
        let model = NanoModel(); _model = StateObject(wrappedValue: model)
        if ProcessInfo.processInfo.arguments.contains("--nano-offline") {
            Task { @MainActor in model.prepare() }
        }
    }

    /// Exposes distinct prepare, inspect, associate, stage, commit, status and behavior actions.
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Nano SDK qualification").font(.title)
                    Text("Status").font(.headline)
                    Text(model.status)
                    Button("Prepare offline test sketches") { model.prepare() }.disabled(model.busy || model.gate.state != .empty)
                    Group {
                        Text("Numeric board address").font(.headline)
                        TextField("Numeric board address", text: $model.address)
                            .textFieldStyle(.roundedBorder)
                        Text("Selected Nano device ID").font(.headline)
                        TextField("Selected Nano device ID (16 hex digits)", text: $model.deviceID)
                            .textFieldStyle(.roundedBorder)
                    }.disabled(model.busy || [.associated, .staged].contains(model.gate.state))
                    Button("Inspect selected Nano") { model.inspect() }
                        .disabled(model.busy || ![.prepared, .inspected, .associated].contains(model.gate.state))
                    Text("Resident-only UF2 SHA-256: " + NanoGate.imageSHA).font(.caption).textSelection(.enabled)
                    Text("Hello does not identify installed image bytes. Review the selected Nano's exact installation/readback evidence.")
                    Group {
                        Text("Installed resident-only UF2 SHA-256").font(.headline)
                        TextField("Installed resident-only UF2 SHA-256", text: $model.imageSHA)
                            .textFieldStyle(.roundedBorder)
                        Text("Installation/readback evidence").font(.headline)
                        TextField("How the exact installed resident was established", text: $model.evidenceNote)
                            .textFieldStyle(.roundedBorder)
                    }.disabled(model.busy || model.gate.state != .inspected)
                    Button("Record reviewed resident association") { model.associate() }.disabled(model.busy || model.gate.state != .inspected)
                    Text("Test sketch").font(.headline)
                    Picker("Test sketch", selection: $model.sketch) {
                        Text("GPIO6 high / delay").tag("gpio")
                        Text("Binary console echo").tag("console")
                    }.disabled(model.busy || [.staged, .commitAttempted].contains(model.gate.state))
                    Text("Staging requires D2/GPIO25 connected to GND. Keep the arm present through installation; REC/GND is the separate ROM recovery path.")
                    Button("Stage selected sketch in RAM") { model.stage() }.disabled(model.busy || model.gate.state != .associated)
                    if model.gate.state == .staged {
                        Text("Installation erases/replaces the managed sketch slot. Commit is attempted once; a lost reply must be reconciled.")
                        Button("Install staged sketch once", role: .destructive) { model.commit() }.disabled(model.busy)
                        Button("Abort RAM stage") { model.abort() }.disabled(model.busy)
                    }
                    Button("Check installation and startup status") { model.reconcile() }.disabled(model.busy || model.gate.state != .commitAttempted)
                    Button("Check exact 256-byte console echo") { model.echo() }.disabled(model.busy || model.gate.state != .confirmed)
                    Text("GPIO6 / D13 observation").font(.headline)
                    TextField("Actual measurement or board-correct LED interpretation", text: $model.observation)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.busy || model.gate.state != .confirmed)
                    Button("Record GPIO observation") { model.recordGPIO() }.disabled(model.busy || model.gate.state != .confirmed)
                    Button("Start another explicit test operation") { model.next() }.disabled(model.busy || ![.confirmed, .aborted].contains(model.gate.state))
                    Button("Cancel active work") { model.inactive() }.disabled(!model.busy)
                    if let journal = model.journal { ShareLink("Share qualification journal", item: journal) }
                }.padding().frame(minWidth: 300)
            }.frame(minWidth: 300, minHeight: 220)
             .onChange(of: phase) { _, value in if value != .active { model.inactive() } }
        }
    }
}
