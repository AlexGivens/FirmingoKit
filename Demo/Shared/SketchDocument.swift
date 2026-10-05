import SwiftUI
import UniformTypeIdentifiers

/// A UTF-8 Arduino-style source document owned by the demo, without build or device side effects.
struct SketchDocument: FileDocument {
    /// Native document identity whose filename extension is ino.
    static let sketchType = UTType(exportedAs: "com.firmingokit.demo.sketch", conformingTo: .plainText)
    /// Accept ino and plain-text sources for opening; newly saved documents use ino.
    static var readableContentTypes: [UTType] { [sketchType, .plainText] }
    /// Newly created documents retain the ino extension.
    static var writableContentTypes: [UTType] { [sketchType] }
    /// Editable source; compilation will consume an immutable copy when its SDK implementation exists.
    var source: String

    /// Creates a new source document with a minimal template.
    init(source: String = "void setup() {\n}\n\nvoid loop() {\n}\n") { self.source = source }

    /// Rejects non-UTF-8 sources and files above 4 MiB instead of loading unbounded editor content.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 4 * 1024 * 1024,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        source = text
    }

    /// Serializes exact UTF-8 source without changing line endings.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(source.utf8))
    }
}
