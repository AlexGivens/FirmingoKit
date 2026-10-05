import Foundation

/// Prepares a bounded single `.ino` as C++17 input without a compiler, dependency discovery, or board access.
/// It adds the local facade and source mapping; helper functions require explicit forward declarations.
public enum ManagedSketchPreprocessor {
    /// Normalizes CRLF/CR, removes an initial UTF-8 BOM from compiler input, and adds Arduino.h/#line.
    /// Only literal Arduino.h includes are allowed: macros, conditional includes, pragmas and user #line
    /// directives and escaped physical newlines are rejected with original positions. Comments/literals
    /// are scanned before directive validation. C++ syntax errors still belong to the compiler.
    /// This is preprocessing, not C++ type checking or proof of statelessness; the linker/output gate owns that.
    /// Hashing/scanning runs off the main actor. Cancellation is checked during the bounded scan.
    @concurrent public static func prepare(_ request: ManagedSketchBuildRequest) async throws -> PreparedManagedSketch {
        let source = try prepareSource(request.snapshot)
        return PreparedManagedSketch(request: request, sourceSHA256: source.sourceSHA256,
            translationUnit: source.translationUnit, translationUnitSHA256: source.translationUnitSHA256,
            sourceLineCount: source.sourceLineCount)
    }

    /// Prepares the same constrained source layout for an exact catalogue selection, with no device binding.
    /// Cancellation, diagnostics and source mapping match the legacy overload; this does not compile source.
    @concurrent public static func prepare(_ request: ManagedOfflineBuildRequest) async throws -> PreparedManagedOfflineSketch {
        let source = try prepareSource(request.snapshot)
        return PreparedManagedOfflineSketch(request: request, source: source)
    }

    /// Bounded immutable preprocessing output shared by both public request forms.
    struct Source: Sendable {
        /// Original source digest before normalization.
        let sourceSHA256: String
        /// Complete generated compiler input.
        let translationUnit: String
        /// Exact generated-input digest.
        let translationUnitSHA256: String
        /// Normalized original source line count.
        let sourceLineCount: Int
    }

    /// Scans one immutable source snapshot without knowledge of any device or catalogue.
    private static func prepareSource(_ snapshot: SketchSourceSnapshot) throws -> Source {
        try Task.checkCancellation()
        var normalized = snapshot.source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasPrefix("\u{feff}") { normalized.removeFirst() }
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SketchBuildError.invalidInput("Source contains no code after removing the initial BOM")
        }
        if let continuation = normalized.range(of: "\\\n") {
            let prefix = normalized[..<continuation.lowerBound]
            let line = prefix.utf8.filter { $0 == 10 }.count + 1
            let column = prefix.split(separator: "\n", omittingEmptySubsequences: false).last?.utf8.count ?? 0
            throw SketchBuildError.unsupportedSource([SketchDiagnostic(severity: .error,
                message: "Escaped physical newlines are unavailable; write each directive or statement without line splicing.",
                filename: snapshot.filename, line: line, column: column + 1)])
        }
        let masks = try maskedSource(Array(normalized.utf8))
        let codeLines = String(decoding: masks.code, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        let textLines = String(decoding: masks.comments, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        var diagnostics: [SketchDiagnostic] = []
        for (index, code) in codeLines.enumerated() {
            let trimmed = code.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else {
                continue
            }
            let text = String(textLines[index])
            guard text.range(of: #"^[ \t]*#[ \t]*include[ \t]*(<Arduino\.h>|"Arduino\.h")[ \t]*$"#,
                             options: .regularExpression) == nil else {
                continue
            }
            let column = code.utf8.firstIndex(of: 35).map { code.utf8.distance(from: code.utf8.startIndex, to: $0) + 1 } ?? 1
            diagnostics.append(SketchDiagnostic(severity: .error,
                message: "Use only a literal Arduino.h include; libraries, macros and source-location overrides are unavailable.",
                filename: snapshot.filename, line: index + 1, column: column))
            if diagnostics.count == 64 { break }
        }
        guard diagnostics.isEmpty else {
            throw SketchBuildError.unsupportedSource(diagnostics)
        }
        var translation = "#include <Arduino.h>\n#line 1 \"\(snapshot.filename)\"\n" + normalized
        if !translation.hasSuffix("\n") { translation.append("\n") }
        try Task.checkCancellation()
        return Source(sourceSHA256: NanoManagedContract.digest(Data(snapshot.source.utf8)),
                                     translationUnit: translation, translationUnitSHA256: NanoManagedContract.digest(Data(translation.utf8)),
                                     sourceLineCount: codeLines.count)
    }

    /// Produces equal-byte-position masks: comments are removed in both; literals only in code.
    /// C++ raw strings use their actual bounded delimiter, preventing fake directives inside multiline text.
    private static func maskedSource(_ bytes: [UInt8]) throws -> (code: [UInt8], comments: [UInt8]) {
        var code = bytes
        var comments = bytes
        var index = 0
        while index < bytes.count {
            if index % 4096 == 0 { try Task.checkCancellation() }
            let next = index + 1 < bytes.count ? bytes[index + 1] : 0
            if bytes[index] == 47 && (next == 47 || next == 42) {
                let start = index
                index += 2
                if next == 47 {
                    while index < bytes.count, bytes[index] != 10 { index += 1 }
                } else {
                    while index + 1 < bytes.count, !(bytes[index] == 42 && bytes[index + 1] == 47) { index += 1 }
                    index = min(index + 2, bytes.count)
                }
                blank(start..<index, in: &code)
                blank(start..<index, in: &comments)
                continue
            }
            if bytes[index] == 82, next == 34, let end = rawLiteralEnd(bytes, at: index) {
                blank(index..<end, in: &code)
                index = end
                continue
            }
            if bytes[index] == 34 || bytes[index] == 39 {
                let start = index
                let quote = bytes[index]
                // Numeric digit separators are tokens, not the start of a character literal.
                if quote == 39, numericSeparator(bytes, at: index) { index += 1; continue }
                index += 1
                while index < bytes.count {
                    if bytes[index] == 92 { index = min(index + 2, bytes.count); continue }
                    let end = bytes[index] == quote
                    index += 1
                    if end { break }
                }
                blank(start..<index, in: &code)
                continue
            }
            index += 1
        }
        return (code, comments)
    }
    /// Distinguishes decimal/hex/binary digit separators from ordinary character literals and prefixes.
    private static func numericSeparator(_ bytes: [UInt8], at index: Int) -> Bool {
        guard index > 0, index + 1 < bytes.count else {
            return false
        }
        let digit: (UInt8) -> Bool = { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
        guard digit(bytes[index - 1]), digit(bytes[index + 1]) else {
            return false
        }
        var start = index - 1
        while start > 0, digit(bytes[start - 1]) || [88, 120, 39].contains(bytes[start - 1]) { start -= 1 }
        return (48...57).contains(bytes[start])
    }
    /// Finds a raw string's closing delimiter, or masks to EOF when its delimiter never closes.
    private static func rawLiteralEnd(_ bytes: [UInt8], at start: Int) -> Int? {
        var opening = start + 2
        while opening < bytes.count, opening - start - 2 <= 16, bytes[opening] != 40 {
            guard bytes[opening] > 32, ![41, 92, 127].contains(bytes[opening]) else {
                return nil
            }
            opening += 1
        }
        guard opening < bytes.count, bytes[opening] == 40, opening - start - 2 <= 16 else {
            return nil
        }
        let suffix = [UInt8(41)] + bytes[(start + 2)..<opening] + [UInt8(34)]
        var index = opening + 1
        while index + suffix.count <= bytes.count {
            if bytes[index] == 41, bytes[index..<(index + suffix.count)].elementsEqual(suffix) { return index + suffix.count }
            index += 1
        }
        return bytes.count
    }
    /// Replaces a lexical region with spaces while retaining newlines and byte coordinates.
    private static func blank(_ range: Range<Int>, in bytes: inout [UInt8]) {
        for index in range where bytes[index] != 10 { bytes[index] = 32 }
    }
}
