/// SDK-issued, device-independent C++ source for an exact catalogue/firmware-build selection.
/// External callers cannot replace compiler input or claim preprocessing occurred for another revision.
public struct PreparedManagedOfflineSketch: Sendable {
    /// Original source, catalogue byte identity and immutable resident descriptor.
    public let request: ManagedOfflineBuildRequest
    /// Original UTF-8 source digest before normalization.
    public let sourceSHA256: String
    /// Generated single-file C++ input with Arduino facade and original source mapping.
    public let translationUnit: String
    /// Exact generated-input digest.
    public let translationUnitSHA256: String
    /// Original normalized line count, including any trailing empty line.
    public let sourceLineCount: Int

    /// Constructs only from the shared bounded SDK preprocessor output.
    init(request: ManagedOfflineBuildRequest, source: ManagedSketchPreprocessor.Source) {
        self.request = request; sourceSHA256 = source.sourceSHA256
        translationUnit = source.translationUnit; translationUnitSHA256 = source.translationUnitSHA256
        sourceLineCount = source.sourceLineCount
    }

    /// Maps physical generated lines; diagnostics that honor #line already use original coordinates.
    public func sourceLine(forGeneratedLine line: Int) -> Int? {
        guard line >= 3, line - 2 <= sourceLineCount else {
            return nil
        }
        return line - 2
    }
}
