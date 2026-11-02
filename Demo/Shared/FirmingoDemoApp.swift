import SwiftUI

/// One document-based Workbench app; all test phases use runtime requests and one stable bundle identity.
@main
struct FirmingoDemoApp: App {
    /// App-lifetime scenario ownership shared by manual windows and explicit automation.
    @State private var lab: WorkbenchLabModel
    /// Starts no scenario on normal launch; explicit CLI requests are handled once by the same app binary.
    init() {
        let model = WorkbenchLabModel()
        _lab = State(initialValue: model)
        model.startAutomationIfRequested()
    }
    /// Preserves native documents while exposing the same shared Test Lab on each platform.
    var body: some Scene {
        DocumentGroup(newDocument: SketchDocument()) { file in
            WorkbenchView(document: file.$document, lab: lab, filename: file.fileURL?.lastPathComponent ?? "Sketch.ino")
        }
        #if os(macOS)
        Window("Firmingo Workbench Test Lab", id: "workbench-lab") { WorkbenchLabView(model: lab) }
        #endif
    }
}
