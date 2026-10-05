import Foundation

/// Strict native validation after the independently validated JavaScript worker response.
struct ManagedWorkerOutput: Sendable {
    /// ARM output present only for a fully successful compile/link.
    let elf: Data
    /// Complete bounded diagnostic records without silent filtering.
    let diagnostics: [SketchDiagnostic]
    /// Actual worker linear-memory observation, never process peak memory.
    let memoryBytes: Int

    /// Parses closed fields, exact scalar types, phase order and bounded base64 off the main actor.
    @concurrent static func decode(_ json: String) async throws -> Self {
        try Task.checkCancellation()
        let value = try WireJSON.parse(Data(json.utf8), maximumBytes: 3_500_000, maximumTokens: 4096)
        let succeeded = try value.required("succeeded").bool()
        var keys = ["succeeded", "status", "canRunAgain", "diagnostics", "timings", "memoryBytes", "moduleMilliseconds", "instantiateMilliseconds"]
        if succeeded { keys.append("elfBase64") }
        try fields(value, keys)
        let status = try integer(value.required("status"), minimum: -2_147_483_648, maximum: 2_147_483_647)
        let canRunAgain = try value.required("canRunAgain").bool()
        let memory = try integer(value.required("memoryBytes"), minimum: 65536, maximum: 268435456)
        try duration(value.required("moduleMilliseconds"))
        try duration(value.required("instantiateMilliseconds"))
        let timings = try value.required("timings").array()
        guard (1...3).contains(timings.count) else { throw WireJSON.invalid }
        for (index, timing) in timings.enumerated() {
            try fields(timing, ["phase", "milliseconds"])
            guard try timing.required("phase").string() == (index < 2 ? "compiling" : "linking") else { throw WireJSON.invalid }
            try duration(timing.required("milliseconds"))
        }
        let records = try value.required("diagnostics").array()
        guard records.count <= 128 else { throw WireJSON.invalid }
        let diagnostics = try records.map { record -> SketchDiagnostic in
            try fields(record, ["severity", "message", "filename", "line", "column"])
            guard let severity = SketchDiagnostic.Severity(rawValue: try record.required("severity").string()) else { throw WireJSON.invalid }
            let message = try boundedText(record.required("message"), maximum: 4096)
            let filenameValue = try record.required("filename")
            let filename: String?
            if case .null = filenameValue { filename = nil } else { filename = try boundedText(filenameValue, maximum: 256) }
            let lineValue = try record.required("line"), columnValue = try record.required("column")
            if case .null = lineValue, case .null = columnValue {
                return SketchDiagnostic(severity: severity, message: message, filename: filename)
            }
            guard filename != nil else { throw WireJSON.invalid }
            return SketchDiagnostic(severity: severity, message: message, filename: filename,
                line: try integer(lineValue, minimum: 1, maximum: 9_007_199_254_740_991),
                column: try integer(columnValue, minimum: 1, maximum: 9_007_199_254_740_991))
        }
        let hasError = diagnostics.contains { $0.severity == .error }
        guard succeeded else {
            guard hasError else { throw WireJSON.invalid }
            throw ManagedCompilerError.compilationFailed(diagnostics)
        }
        guard status == 0, canRunAgain, !hasError, timings.count == 3 else { throw WireJSON.invalid }
        let encoded = try boundedText(value.required("elfBase64"), maximum: 2_796_204)
        guard let elf = Data(base64Encoded: encoded), (52...2_097_152).contains(elf.count), elf.base64EncodedString() == encoded else {
            throw WireJSON.invalid
        }
        try Task.checkCancellation()
        return Self(elf: elf, diagnostics: diagnostics, memoryBytes: memory)
    }
    /// Requires exact UTF-8 field names, rejecting additive fields and duplicate keys via WireJSON.
    private static func fields(_ value: WireJSON.Value, _ names: [String]) throws {
        guard Set(try value.object().keys) == Set(names.map { Data($0.utf8) }) else { throw WireJSON.invalid }
    }
    /// Extracts an exact bounded decimal integer; booleans, fractions and coercion fail.
    private static func integer(_ value: WireJSON.Value, minimum: Int, maximum: Int) throws -> Int {
        guard case .number(let text) = value, let integer = Int(text), integer >= minimum, integer <= maximum else { throw WireJSON.invalid }
        return integer
    }
    /// Extracts a finite duration in milliseconds; exponent notation is valid for this real-valued field only.
    private static func duration(_ value: WireJSON.Value) throws {
        guard case .number(let text) = value, let number = Double(text), number.isFinite, number >= 0, number <= 120_000 else { throw WireJSON.invalid }
    }
    /// Text bounds count UTF-8 bytes; NUL is already rejected by the strict parser.
    private static func boundedText(_ value: WireJSON.Value, maximum: Int) throws -> String {
        let text = try value.string()
        guard !text.isEmpty, text.utf8.count <= maximum else { throw WireJSON.invalid }
        return text
    }
}
