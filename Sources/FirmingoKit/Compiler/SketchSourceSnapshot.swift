import Foundation

/// Immutable single-file source revision; constructing a snapshot never compiles or contacts a board.
public struct SketchSourceSnapshot: Equatable, Sendable {
    /// Host document identity, preserved even when the filename changes.
    public let documentID: UUID
    /// Host revision captured before preparation; a later edit must create a new snapshot.
    public let revision: UInt64
    /// Bounded portable ASCII `.ino` leaf used in source diagnostics and build provenance.
    public let filename: String
    /// Original source, retaining line endings for provenance; preparation normalizes compiler input.
    public let source: String

    /// Accepts one nonempty UTF-8 source file up to 256 KiB, without NUL or an unsafe filename.
    /// Multi-file sketches, user libraries and arbitrary compiler options are not supported by this boundary.
    public init(documentID: UUID, revision: UInt64, filename: String, source: String) throws {
        guard Self.validFilename(filename) else {
            throw SketchBuildError.invalidInput("Use a portable .ino leaf filename up to 96 bytes")
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source.utf8.count <= 256 * 1024, !source.utf8.contains(0) else {
            throw SketchBuildError.invalidInput("Source must be nonempty, at most 256 KiB, and contain no NUL")
        }
        self.documentID = documentID
        self.revision = revision
        self.filename = filename
        self.source = source
    }

    /// Restricts diagnostic names to one non-hidden ASCII component; paths and line-directive escapes fail.
    static func validFilename(_ filename: String) -> Bool {
        filename.utf8.count <= 96 && filename.count > 4 && filename.hasSuffix(".ino") &&
            !filename.hasPrefix(".") && !filename.contains("..") && filename.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [32, 45, 46, 95].contains($0)
            } && filename.utf8.first.map({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 }) == true
    }
}
