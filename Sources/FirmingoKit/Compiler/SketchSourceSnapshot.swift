import Foundation

/// Immutable source revision; constructing a snapshot never compiles or contacts a board.
public struct SketchSourceSnapshot: Equatable, Sendable {
    /// Host document identity, preserved even when the filename changes.
    public let documentID: UUID
    /// Host revision captured before preparation; a later edit must create a new snapshot.
    public let revision: UInt64
    /// Bounded portable ASCII `.ino` leaf used in source diagnostics and build provenance.
    public let filename: String
    /// Original source, retaining line endings for provenance; preparation normalizes compiler input.
    public let source: String
    /// Explicit helper translation units and headers, sorted by their ASCII paths.
    public let files: [File]

    /// Accepts the original single-file input and preserves its interface-one build identity.
    public init(documentID: UUID, revision: UInt64, filename: String, source: String) throws {
        try self.init(documentID: documentID, revision: revision, filename: filename, source: source, files: [])
    }

    /// Accepts up to eight explicit helpers with at most 256 KiB of original UTF-8 across the snapshot.
    /// Bundle helpers use portable relative paths; no compiler library or filesystem discovery is performed.
    public init(documentID: UUID, revision: UInt64, filename: String, source: String, files: [File]) throws {
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
        guard files.count <= 8, files.isEmpty || !Self.reserved(filename) else {
            throw SketchBuildError.invalidInput("Use at most eight helpers and a portable sketch name")
        }
        var filesByPath = Set([filename.lowercased()])
        var directories: [String: String] = [:]
        var total = source.utf8.count
        for file in files {
            let path = file.path.lowercased()
            guard directories[path] == nil, filesByPath.insert(path).inserted else {
                throw SketchBuildError.invalidInput("Bundle paths conflict")
            }
            let parts = file.path.split(separator: "/")
            for depth in 1..<parts.count {
                let directory = parts.prefix(depth).joined(separator: "/"), key = directory.lowercased()
                guard !filesByPath.contains(key), directories[key] == nil || directories[key] == directory else {
                    throw SketchBuildError.invalidInput("Bundle directories conflict")
                }
                directories[key] = directory
            }
            total += file.source.utf8.count
            guard total <= 256 * 1024 else { throw SketchBuildError.invalidInput("Combined source exceeds 256 KiB") }
        }
        self.files = files.sorted { $0.path < $1.path }
    }

    /// One explicit local C++ source file or header in a bundle.
    public struct File: Equatable, Sendable {
        /// Portable relative path with up to three components and 96 ASCII bytes.
        public let path: String
        /// Original helper text, including line endings and any UTF-8 BOM.
        public let source: String

        /// Validates the path and individual size; the snapshot additionally rejects conflicts and aggregate overflow.
        public init(path: String, source: String) throws {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard path.utf8.count <= 96, components.count <= 3, path.hasSuffix(".cpp") || path.hasSuffix(".h"),
                  components.last?.lowercased() != "arduino.h",
                  components.allSatisfy({ part in
                      guard let first = part.utf8.first, SketchSourceSnapshot.nameStart(first),
                            !part.hasSuffix("."), !SketchSourceSnapshot.reserved(String(part)) else { return false }
                      return part.utf8.allSatisfy { SketchSourceSnapshot.nameStart($0) || $0 == 45 || $0 == 46 }
                  }),
                  source.utf8.count <= 256 * 1024, !source.utf8.contains(0) else {
                throw SketchBuildError.invalidInput("Use a bounded relative .cpp or .h helper path with valid UTF-8 source")
            }
            self.path = path
            self.source = source
        }
    }

    /// ASCII alphanumeric or underscore, accepted at the start of each portable component.
    private static func nameStart(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 95
    }

    /// Matches platform-reserved filename stems excluded by the portable compiler.
    private static func reserved(_ component: String) -> Bool {
        let stem = component.prefix(while: { $0 != "." }).trimmingCharacters(in: .whitespaces).lowercased()
        return ["con", "prn", "aux", "nul"].contains(stem) ||
            (stem.utf8.count == 4 && (stem.hasPrefix("com") || stem.hasPrefix("lpt")) &&
                stem.utf8.last.map { (49...57).contains($0) } == true)
    }

    /// Restricts diagnostic names to one non-hidden ASCII component; paths and line-directive escapes fail.
    static func validFilename(_ filename: String) -> Bool {
        filename.utf8.count <= 96 && filename.count > 4 && filename.hasSuffix(".ino") &&
            !filename.hasPrefix(".") && !filename.contains("..") && filename.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [32, 45, 46, 95].contains($0)
            } && filename.utf8.first.map({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 }) == true
    }
}
