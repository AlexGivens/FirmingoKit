/// One source-addressable build message; positions are one-based and columns count UTF-8 bytes.
public struct SketchDiagnostic: Equatable, Sendable {
    /// Message category independent of UI styling.
    public let severity: Severity
    /// Concise actionable text, not an executable compiler command.
    public let message: String
    /// Original snapshot filename for a source message; nil denotes a build-level message.
    public let filename: String?
    /// One-based original source line, if available.
    public let line: Int?
    /// One-based UTF-8 byte column, if available.
    public let column: Int?

    /// Build-message severity shared by preparation and later compiler diagnostics.
    public enum Severity: String, Sendable {
        /// Informational context for another diagnostic.
        case note
        /// A nonfatal build warning.
        case warning
        /// A condition preventing a valid build.
        case error
    }
    /// SDK-controlled construction keeps source coordinates tied to validated input.
    init(severity: Severity, message: String, filename: String? = nil, line: Int? = nil, column: Int? = nil) {
        self.severity = severity
        self.message = message
        self.filename = filename
        self.line = line
        self.column = column
    }
}
