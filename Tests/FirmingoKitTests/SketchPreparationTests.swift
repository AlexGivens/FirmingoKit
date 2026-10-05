import Foundation
import Testing
@testable import FirmingoKit

/// Exercises source limits, lexical preprocessing and revision preservation without compiler or board access.
struct SketchPreparationTests {
    /// Source paths cannot inject line directives or escape the per-build workspace.
    @Test(arguments: ["../Sketch.ino", "sub/Sketch.ino", "Sketch\\name.ino", ".hidden.ino", "Sketch..ino",
                      "Sketch.ino\n", "Sketch\".ino", "é.ino", "Sketch.cpp", " Sketch.ino", String(repeating: "a", count: 93) + ".ino"])
    func rejectsUnsafeFilename(_ filename: String) throws {
        #expect(throws: SketchBuildError.self) { try CompilerFixtures.request(filename: filename) }
    }
    /// Original source accepts the exact UTF-8 byte bound while rejecting empty/NUL/excessive input.
    @Test func sourceBounds() throws {
        let source = String(repeating: "a", count: 256 * 1024)
        #expect(try CompilerFixtures.request(source: source).snapshot.source == source)
        for invalid in ["", " \r\n\t", "void setup() {}\0", source + "a", String(repeating: "é", count: 131073)] {
            #expect(throws: SketchBuildError.self) { try CompilerFixtures.request(source: invalid) }
        }
        #expect(try CompilerFixtures.request(filename: String(repeating: "a", count: 92) + ".ino").snapshot.filename.utf8.count == 96)
    }
    /// BOM and all physical line endings normalize without mutating original source hashes or revision.
    @Test func normalizationAndMapping() async throws {
        let source = "\u{feff}void setup() {}\r\nvoid loop() {}\r"
        let prepared = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request(source: source))
        #expect(prepared.translationUnit == "#include <Arduino.h>\n#line 1 \"Sketch.ino\"\nvoid setup() {}\nvoid loop() {}\n")
        #expect(prepared.request.snapshot.source == source)
        #expect(prepared.request.snapshot.revision == 7)
        #expect(prepared.sourceSHA256 == NanoManagedContract.digest(Data(source.utf8)))
        // Independent Python hashlib vectors guard exact original/generated UTF-8 provenance.
        #expect(prepared.sourceSHA256 == "2f3bb57b502367f2d87bd53a1e6a2f98c61d22107b7c47ac85faab56b8e6a153")
        #expect(prepared.translationUnitSHA256 == "9a298b76d01802f89c360908c473933a9ff814b794ec40a07f49fdabe0e386f4")
        #expect(prepared.sourceSHA256 != prepared.translationUnitSHA256)
        #expect(prepared.sourceLineCount == 3)
        #expect(prepared.sourceLine(forGeneratedLine: 3) == 1)
        #expect(prepared.sourceLine(forGeneratedLine: 5) == 3)
        for line in [Int.min, -1, 0, 1, 2, 6, Int.max] { #expect(prepared.sourceLine(forGeneratedLine: line) == nil) }
        await #expect(throws: SketchBuildError.self) {
            try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request(source: "\u{feff}"))
        }
    }
    /// Literal facade includes survive comments, and helpers stay in source order without invented prototypes.
    @Test func facadeAndExplicitDeclarations() async throws {
        let source = "/* é */ # include \"Arduino.h\" // local\nvoid helper();\nvoid setup() { helper(); }\nvoid loop() {}\nvoid helper() {}"
        let prepared = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request(source: source))
        #expect(prepared.translationUnit.hasSuffix(source + "\n"))
        #expect(prepared.translationUnit.components(separatedBy: "void helper();").count == 2)
    }
    /// Directive-like text in comments/ordinary/raw literals cannot create false unsupported-source errors.
    @Test func lexicalMasks() async throws {
        let source = #"""
        // #include <Other.h>
        /*
        #define FAKE 1
        */
        const char *s = "#pragma once /* \" */";
        const char *r = u8R"token(
        #line 900 "wrong"
        // /* )wrong"
        )token";
        char quote = '\'';
        void setup() {} void loop() {}
        """#
        let prepared = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request(source: source))
        #expect(prepared.translationUnit.hasSuffix(source + "\n"))
    }
    /// Numeric C++ digit separators must not hide the following real directive as a character literal.
    @Test(arguments: ["1'000", "0xAB'CD", "0b10'01", "123'456'789"])
    func digitSeparators(_ number: String) async throws {
        do {
            _ = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request(source: "int n = \(number);\n  #define X 1"))
            Issue.record("Expected unsupported directive")
        } catch SketchBuildError.unsupportedSource(let diagnostics) {
            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].line == 2)
            #expect(diagnostics[0].column == 3)
        }
    }
    /// Macro/conditional/library/location overrides fail at their original one-based UTF-8 coordinates.
    @Test(arguments: ["#include <Wire.h>", "#include HEADER", "#include \"../Arduino.h\"", "#define X 1", "#if 1", "#pragma once", "#line 4", "#include <Arduino.h> garbage"])
    func unsupportedDirectives(_ directive: String) async throws {
        do {
            _ = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request(source: "void setup() {}\n/* é */ \(directive)\nvoid loop() {}"))
            Issue.record("Expected unsupported source")
        } catch SketchBuildError.unsupportedSource(let diagnostics) {
            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].filename == "Sketch.ino")
            #expect(diagnostics[0].line == 2)
            #expect(diagnostics[0].column == 10)
            #expect(diagnostics[0].severity == .error)
        }
    }
    /// Escaped newlines are rejected before lexical scanning, with bounded diagnostics for directive floods.
    @Test func lineSplicingAndDiagnosticBound() async throws {
        do {
            _ = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request(source: "// splice\\\r\n#define X 1"))
            Issue.record("Expected line-splicing rejection")
        } catch SketchBuildError.unsupportedSource(let diagnostics) {
            #expect(diagnostics[0].line == 1)
            #expect(diagnostics[0].column == 10)
        }
        do {
            _ = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request(source: String(repeating: "#define X 1\n", count: 100)))
            Issue.record("Expected diagnostic flood rejection")
        } catch SketchBuildError.unsupportedSource(let diagnostics) { #expect(diagnostics.count == 64) }
    }
    /// Pico cannot become a Nano build by retaining the same resident API or profile name.
    @Test func unsupportedBoard() throws {
        #expect(throws: SketchBuildError.self) {
            try ManagedSketchBuildRequest(snapshot: CompilerFixtures.request().snapshot, board: .raspberryPiPico,
                profile: .nanoManagedV1, resident: ManagedUploadFixtures.resident())
        }
    }
    /// A cancelled task cannot prepare even a valid input or leave an artifact behind.
    @Test func cancelledPreparation() async throws {
        let request = try CompilerFixtures.request()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ManagedSketchPreprocessor.prepare(request)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
