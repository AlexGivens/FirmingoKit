/// Validated, deterministic single-file C++ input; this value contains no compiled artifact.
public struct PreparedManagedSketch: Sendable {
    /// Immutable source revision and explicit offline target selection.
    public let request: ManagedSketchBuildRequest
    /// Original UTF-8 source digest, before line-ending normalization or generated text.
    public let sourceSHA256: String
    /// C++ translation unit with facade include and original-filename `#line` mapping.
    public let translationUnit: String
    /// Digest of exact generated compiler input, distinct from original source provenance.
    public let translationUnitSHA256: String
    /// Original normalized source line count, including a trailing empty line when present.
    public let sourceLineCount: Int

    /// SDK-issued preparation; external callers cannot substitute a translation unit into this value.
    init(request: ManagedSketchBuildRequest, sourceSHA256: String, translationUnit: String,
         translationUnitSHA256: String, sourceLineCount: Int) {
        self.request = request
        self.sourceSHA256 = sourceSHA256
        self.translationUnit = translationUnit
        self.translationUnitSHA256 = translationUnitSHA256
        self.sourceLineCount = sourceLineCount
    }

    /// Maps a physical generated line to the original source; the two generated prefix lines have no source.
    /// Compiler diagnostics honoring `#line` already use original coordinates and need no second mapping.
    public func sourceLine(forGeneratedLine line: Int) -> Int? {
        guard line >= 3, line - 2 <= sourceLineCount else {
            return nil
        }
        return line - 2
    }
}
