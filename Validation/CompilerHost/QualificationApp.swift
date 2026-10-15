import SwiftUI
import Foundation

/// Small native platform host for explicit compiler checks; it contains no board, installation or upload workflow.
@main @MainActor struct CompilerQualificationApp: App {
    /// Window-owned test state; no saved selection or device capability is restored.
    @StateObject private var model = QualificationModel()
    /// Real scene events feed the opt-in lifecycle observer; no lifecycle event is synthesized.
    @Environment(\.scenePhase) private var scenePhase

    /// Uses native controls on macOS/iPad/iPhone with a shareable results journal.
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 16) {
                Text("Firmingo compiler checks").font(.title)
                Text("Compile bundled test sketches and check diagnostics, cancellation and recovery. No board is needed.")
                Text(model.status).accessibilityLabel("Compiler check status: " + model.status)
                if model.activeLifecycleReady {
                    Button("Start active compiler check") { model.beginActiveLifecycle() }
                }
                Button("Run compiler checks") { model.start() }.disabled(model.running)
                if let report = model.report { ShareLink("Share results", item: report) }
            }
            .padding().frame(minWidth: 280, minHeight: 220)
            .task { model.startIfRequested() }
            .onChange(of: scenePhase, initial: true) { _, phase in model.sceneChanged(phase) }
        }
    }
}

/// Main-actor presentation state for one finite check sequence; repeated starts cannot overlap.
@MainActor final class QualificationModel: ObservableObject {
    /// Bounded human-readable current phase or terminal outcome.
    @Published var status = "Ready"
    /// Disable duplicate commands while SDK work is active.
    @Published var running = false
    /// Last complete/failed journal available for explicit export.
    @Published var report: URL?
    /// Shows the explicit start button only after active-call preflight completes.
    @Published var activeLifecycleReady = false
    /// Consume launch automation only once per host process.
    private var launchConsumed = false
    /// Current view-delivered scene phase, independent of whether a lifecycle run is active.
    private var phase = "unknown"
    /// Owned only during an explicitly selected idle lifecycle check.
    private var lifecycle: QualificationLifecycle?
    /// Sole opt-in active-call lifecycle observer; it never changes SDK-wide policy.
    private var activeLifecycle: QualificationActiveLifecycle?

    /// User action starts the bounded series immediately before the requested Home transition.
    func beginActiveLifecycle() { activeLifecycle?.begin() }

    /// Forwards actual scene observations without introducing lifecycle policy into the SDK.
    func sceneChanged(_ value: ScenePhase) {
        switch value {
        case .active: phase = "active"
        case .inactive: phase = "inactive"
        case .background: phase = "background"
        @unknown default: phase = "unknown"
        }
        lifecycle?.record(phase: phase)
        activeLifecycle?.record(phase: phase)
    }

    /// Allows a source-driven launcher to request one exact UUID without inspecting native UI.
    func startIfRequested() {
        guard !launchConsumed else { return }; launchConsumed = true
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--qualification-run"), index + 1 < arguments.count,
           let id = UUID(uuidString: arguments[index + 1]) {
            let modes = ["--qualification-idle-lifecycle", "--qualification-active-lifecycle", "--qualification-stress-count"]
            guard modes.filter({ arguments.contains($0) }).count <= 1 else { status = "Select one compiler check mode"; return }
            if arguments.contains("--qualification-active-lifecycle") {
                start(id: id, activeLifecycle: true)
            } else if arguments.contains("--qualification-idle-lifecycle") {
                start(id: id, idleLifecycle: true)
            } else if let repeatIndex = arguments.firstIndex(of: "--qualification-stress-count") {
                guard repeatIndex + 1 < arguments.count, let count = Int(arguments[repeatIndex + 1]), (2...40).contains(count) else {
                    status = "Select 2 through 40 repeated builds"; return
                }
                start(id: id, iterations: count)
            } else { start(id: id) }
        }
    }

    /// Runs the public SDK asynchronously; results stay in this app's own Documents container.
    func start(id: UUID = UUID(), iterations: Int? = nil, idleLifecycle: Bool = false, activeLifecycle: Bool = false) {
        guard !running else { return }; running = true; report = nil
        Task { @MainActor in
            do {
                if activeLifecycle {
                    let observer = try QualificationActiveLifecycle(id: id, phase: phase); self.activeLifecycle = observer
                    report = try await observer.run(status: { status = $0 }, ready: { activeLifecycleReady = $0 })
                    self.activeLifecycle = nil
                } else if idleLifecycle {
                    let observer = try QualificationLifecycle(id: id, phase: phase); lifecycle = observer
                    report = try await observer.run { status = $0 }; lifecycle = nil
                } else if let iterations {
                    report = try await QualificationStress.run(id: id, iterations: iterations) { status = $0 }
                } else { report = try await QualificationChecks.run(id: id) { status = $0 } }
            } catch {
                lifecycle = nil
                self.activeLifecycle = nil; activeLifecycleReady = false
                status = "Could not record compiler checks: " + String(error.localizedDescription.prefix(2048))
            }
            running = false
            #if os(macOS)
            if ProcessInfo.processInfo.arguments.contains("--qualification-quit") {
                // Export our own test journal through the launcher's inherited pipe. macOS protects
                // app containers from external readers; no extra container/FDA access is needed.
                do {
                    if let report {
                        let data = try Data(contentsOf: report)
                        try FileHandle.standardOutput.write(contentsOf: Data(("FIRMINGO_COMPILER_REPORT:" + data.base64EncodedString() + "\n").utf8))
                    }
                } catch { status = "Could not export compiler results: " + error.localizedDescription }
                NSApplication.shared.terminate(nil)
            }
            #endif
        }
    }
}
