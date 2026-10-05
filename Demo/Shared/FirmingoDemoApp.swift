import SwiftUI

/// Native document-based demonstration host, separate from the reusable package.
@main
struct FirmingoDemoApp: App {
    /// Uses platform-native document creation, opening, saving, and window ownership.
    var body: some Scene {
        DocumentGroup(newDocument: SketchDocument()) { file in
            WorkbenchView(document: file.$document, filename: file.fileURL?.lastPathComponent ?? "Sketch.ino")
        }
    }
}
