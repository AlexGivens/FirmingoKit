import Foundation

/// Native trust-boundary validation of the portable compiler's bytes, correlation and execution receipt.
struct ManagedPortableOutput: Sendable {
    /// FMS1 produced and independently validated by the compiler; Swift never repackages it here.
    let bytes: Data
    /// Complete portable report before SDK provenance translation.
    let reportJSON: Data
    /// Original source identity, checked independently against the captured Swift snapshot.
    let sourceSHA256: String
    /// Exact compiler-produced unit and its independently verified hash.
    let translationUnit: String
    /// Generated-input identity used by the unchanged SDK receipt schemas.
    let translationUnitSHA256: String
    /// Source line count returned by portable preprocessing, bounded to source bytes.
    let sourceLineCount: Int
    /// Original BOM extent reported by portable preparation.
    let sourceBOMBytes: Int
    /// Complete bounded diagnostics with mapped original byte positions.
    let diagnostics: [SketchDiagnostic]
    /// Actual final WASM linear-memory observation, not total process peak memory.
    let memoryBytes: Int
    /// Complete linked ELF identity, checked against its transferred bytes.
    let linkedELFSHA256: String
    /// Exact portable execution receipt retained for native boundary checks.
    let executionReceiptJSON: Data

    /// Parses closed output fields and verifies hashes/selection before returning any artifact.
    @concurrent static func decode(_ json: String, request: ManagedPortableRequest) async throws -> Self {
        try Task.checkCancellation()
        let root = try WireJSON.parse(Data(json.utf8), maximumBytes: 3_500_000, maximumTokens: 4096)
        let event = try root.required("event")
        guard try root.required("schema").uint32() == 1,
              try event.required("interfaceVersion").uint32() == 1,
              try event.required("kind").string() == "result",
              try event.required("buildID").string() == request.buildID else { throw WireJSON.invalid }
        _ = try integer(event.required("sequence"), minimum: 1, maximum: 136)
        let outcome = try event.required("outcome").string()
        let diagnostics = try diagnosticRecords(root.required("diagnostics"))
        if outcome != "succeeded" {
            guard ["failed", "cancelled", "timed_out"].contains(outcome) else { throw WireJSON.invalid }
            try fields(root, ["schema", "event", "diagnostics"])
            try fields(event, ["interfaceVersion", "kind", "buildID", "sequence", "outcome", "error"])
            let error = try event.required("error"); try fields(error, ["code", "stage", "message"])
            let code = try error.required("code").string()
            let stage = try error.required("stage").string()
            let message = try error.required("message").string()
            guard validCode(code), ["verifying", "preprocessing", "compiling", "linking", "validating", "packaging"].contains(stage),
                  message.utf8.count <= 4096, !message.contains("\0"),
                  outcome == (code == "cancelled" ? "cancelled" : code == "timed_out" ? "timed_out" : "failed") else { throw WireJSON.invalid }
            switch code {
            case "compile_failed", "link_failed":
                guard stage == (code == "compile_failed" ? "compiling" : "linking"),
                      diagnostics.contains(where: { $0.severity == .error }) else { throw WireJSON.invalid }
                throw ManagedCompilerError.compilationFailed(diagnostics)
            case "unsupported_source": throw SketchBuildError.unsupportedSource(diagnostics)
            case "cancelled": throw CancellationError()
            case "timed_out": throw ManagedCompilerError.timedOut
            case "invalid_elf": throw SketchBuildError.invalidELF(try error.required("message").string())
            default: throw ManagedCompilerError.runtime("portable compiler rejected build: " + code)
            }
        }
        try fields(root, ["schema", "event", "diagnostics", "preparation", "memoryBytes", "linkedELFBase64"])
        try fields(event, ["interfaceVersion", "kind", "buildID", "sequence", "outcome", "artifact"])
        guard !diagnostics.contains(where: { $0.severity == .error }) else { throw WireJSON.invalid }
        guard try integer(event.required("sequence"), minimum: 1, maximum: 136) == 8 + diagnostics.count else { throw WireJSON.invalid }
        let artifact = try event.required("artifact")
        try fields(artifact, ["format", "filename", "bytes", "sha256", "reportJSON", "receipt"])
        guard try artifact.required("format").string() == "nano-managed-v1",
              try artifact.required("filename").string() == String(request.snapshot.filename.dropLast(4)) + ".fms" else { throw WireJSON.invalid }
        let bytes = try binary(artifact.required("bytes"), minimum: 260, maximum: 4096)
        let receipt = try artifact.required("receipt")
        let names = ["receiptSchema", "operation", "provenanceStatus", "requestSHA256", "buildID", "sourceRevision", "sourceFilename",
            "sourceSHA256", "translationUnitSHA256", request.targetIdentityKey, "board", "profile", "provenance", "interfaceVersion",
            "service", "wasiShim", "toolchainManifest", "recipeAssets", "buildInputSHA256", "linkedELFSHA256", "capsuleSHA256", "capsuleBytes"]
        try fields(receipt, names)
        guard try receipt.required("receiptSchema").string() == "firmingo-compiler-build-v1",
              try receipt.required("operation").string() == "wasm_compile_link_package",
              try receipt.required("provenanceStatus").string() == "pinned_assets_executed",
              try receipt.required("interfaceVersion").uint32() == 1,
              try receipt.required("buildID").string() == request.buildID,
              try receipt.required("sourceRevision").string() == request.revisionToken,
              try receipt.required("sourceFilename").string() == request.snapshot.filename,
              try receipt.required("requestSHA256").string() == request.requestSHA256,
              try receipt.required(request.targetIdentityKey).string() == request.targetIdentity,
              try receipt.required("board").string() == "nano_rp2040_connect",
              try receipt.required("profile").string() == "nano-managed-v1" else { throw WireJSON.invalid }
        let service = try receipt.required("service")
        try fields(service, ["bytes", "sha256", "serviceABI", "compiler", "maximumMemoryBytes"])
        guard try service.required("bytes").uint32() == VerifiedManagedToolchain.serviceBytes,
              try service.required("sha256").string() == VerifiedManagedToolchain.serviceSHA256,
              try service.required("serviceABI").uint32() == 2,
              try service.required("compiler").string() == "Clang/LLD 22.1.8 ABI-two WASI service",
              try service.required("maximumMemoryBytes").uint32() == 268435456 else { throw WireJSON.invalid }
        let toolchain = try receipt.required("toolchainManifest"); try fields(toolchain, ["schema", "service"])
        guard try toolchain.required("schema").uint32() == 1,
              try ManagedPortableRequest.canonical(dictionary(toolchain.required("service"))) == ManagedPortableRequest.canonical(dictionary(service)) else { throw WireJSON.invalid }
        let shim = try receipt.required("wasiShim"); try fields(shim, ["package", "version", "receiptSHA256"])
        guard try shim.required("package").string() == "@bjorn3/browser_wasi_shim", try shim.required("version").string() == "0.4.2",
              try shim.required("receiptSHA256").string() == "1ad1971d3617837d1bc858a31c488d112b20ec6f8df9eecfccb361af2303087d" else { throw WireJSON.invalid }
        let provenance = try receipt.required("provenance"); try fields(provenance, ["compiler", "recipeIdentifier", "recipeSHA256", "toolchainSHA256"])
        guard try provenance.required("compiler").string() == service.required("compiler").string(),
              try provenance.required("recipeIdentifier").string() == ManagedCompilerResourceInventory.recipeIdentifier,
              try provenance.required("recipeSHA256").string() == ManagedCompilerResourceInventory.recipeSHA256,
              try provenance.required("toolchainSHA256").string() == NanoManagedContract.digest(ManagedPortableRequest.canonical(dictionary(toolchain))) else { throw WireJSON.invalid }
        let assets = try receipt.required("recipeAssets").array()
        let expectedAssets: [(String, UInt32, String)] = [
            ("Recipe/Arduino.h", 5022, "46e2ecc7ac653b12c6f63ab616e4a49c347c6ece360e203011337733987d60da"),
            ("Recipe/Entry.cpp", 572, "80e5f48e6512d61f247d61e6637c40abeb25a2b9c84093e81390ee8aeed6d88d"),
            ("Recipe/Module.ld", 1078, "a8ded6a674337881bd650ed38b39cdba1299cd469f5e238317989e1e96de0da8"),
            ("Sources/ManagedRecipe.js", 3496, "e30c8f523d7938cb92127f4bb430ebb88d59f7b32dd3c430665409477e4a058e")]
        guard assets.count == expectedAssets.count else { throw WireJSON.invalid }
        for (asset, expected) in zip(assets, expectedAssets) {
            try fields(asset, ["path", "bytes", "sha256"])
            guard try asset.required("path").string() == expected.0, try asset.required("bytes").uint32() == expected.1,
                  try asset.required("sha256").string() == expected.2 else { throw WireJSON.invalid }
        }
        let sourceSHA256 = NanoManagedContract.digest(Data(request.snapshot.source.utf8))
        guard try receipt.required("sourceSHA256").string() == sourceSHA256 else { throw WireJSON.invalid }
        let preparation = try root.required("preparation"); try fields(preparation, ["translationUnit", "sourceLineCount", "sourceBOMBytes"])
        let unit = try preparation.required("translationUnit").string()
        guard unit.utf8.count <= 262400, unit.hasPrefix("#include <Arduino.h>\n#line 1 \"" + request.snapshot.filename + "\"\n") else { throw WireJSON.invalid }
        let unitSHA256 = NanoManagedContract.digest(Data(unit.utf8))
        guard try receipt.required("translationUnitSHA256").string() == unitSHA256 else { throw WireJSON.invalid }
        let lineCount = try integer(preparation.required("sourceLineCount"), minimum: 1, maximum: 262145)
        let bom = try integer(preparation.required("sourceBOMBytes"), minimum: 0, maximum: 3)
        guard bom == (request.snapshot.source.hasPrefix("\u{feff}") ? 3 : 0) else { throw WireJSON.invalid }
        let elf = try binary(root.required("linkedELFBase64"), minimum: 52, maximum: 2097152)
        let linkedHash = NanoManagedContract.digest(elf), capsuleHash = NanoManagedContract.digest(bytes)
        guard try receipt.required("linkedELFSHA256").string() == linkedHash,
              try receipt.required("capsuleSHA256").string() == capsuleHash,
              try artifact.required("sha256").string() == capsuleHash,
              try receipt.required("capsuleBytes").uint32() == bytes.count else { throw WireJSON.invalid }
        let memory = try integer(root.required("memoryBytes"), minimum: 65536, maximum: 268435456)
        let report = Data(try artifact.required("reportJSON").string().utf8)
        guard report.count <= 16384 else { throw WireJSON.invalid }
        let reportValue = try WireJSON.parse(report)
        guard try reportValue.required("linked_elf_sha256").string() == linkedHash,
              try reportValue.required("source_sha256").required("sketch/" + request.snapshot.filename).string() == sourceSHA256,
              try reportValue.required("source_sha256").required("generated/Sketch.cpp").string() == unitSHA256 else { throw WireJSON.invalid }
        _ = try ManagedCapsulePayload(bytes: bytes, reportJSON: report, apiAddress: request.apiAddress, residentELFSHA256: request.residentELFSHA256)
        // Recompute receipt identity from parsed closed data rather than trusting its declared digest.
        var receiptObject = try dictionary(receipt)
        for key in ["buildInputSHA256", "linkedELFSHA256", "capsuleSHA256", "capsuleBytes"] { receiptObject.removeValue(forKey: key) }
        guard try receipt.required("buildInputSHA256").string() == NanoManagedContract.digest(ManagedPortableRequest.canonical(receiptObject)) else { throw WireJSON.invalid }
        try Task.checkCancellation()
        return Self(bytes: bytes, reportJSON: report, sourceSHA256: sourceSHA256, translationUnit: unit, translationUnitSHA256: unitSHA256,
            sourceLineCount: lineCount, sourceBOMBytes: bom, diagnostics: diagnostics, memoryBytes: memory, linkedELFSHA256: linkedHash,
            executionReceiptJSON: try ManagedPortableRequest.canonical(dictionary(receipt)))
    }
    /// Translates native host provenance without altering compiler-produced capsule bytes or source/output hashes.
    func sdkReport(provenance: ManagedELFProvenance) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: reportJSON) as? [String: Any],
              var hashes = object["source_sha256"] as? [String: String] else { throw WireJSON.invalid }
        object["compiler"] = provenance.compiler; object["recipe_id"] = provenance.recipeIdentifier
        hashes["recipe/manifest.json"] = provenance.recipeSHA256; hashes["toolchain/manifest.json"] = provenance.toolchainSHA256
        object["source_sha256"] = hashes
        return try ManagedPortableRequest.canonical(object)
    }
    /// Converts exact parsed JSON scalars for canonical hashing; no coercion or unknown data is introduced.
    static func dictionary(_ value: WireJSON.Value) throws -> [String: Any] {
        try value.object().reduce(into: [:]) { result, item in result[String(decoding: item.key, as: UTF8.self)] = try scalar(item.value) }
    }
    /// Recursively preserves parsed decimal integers, arrays and strings used by the receipt schema.
    private static func scalar(_ value: WireJSON.Value) throws -> Any {
        switch value {
        case .object: try dictionary(value)
        case .array: try value.array().map(scalar)
        case .string: try value.string()
        case .number: try integer(value, minimum: 0, maximum: 9_007_199_254_740_991)
        case .boolean: try value.bool()
        case .null: NSNull()
        }
    }
    /// Requires every bounded diagnostic's portable stage/code while preserving the public Swift diagnostic shape.
    static func diagnosticRecords(_ value: WireJSON.Value) throws -> [SketchDiagnostic] {
        let values = try value.array(); guard values.count <= 128 else { throw WireJSON.invalid }
        return try values.map { item in
            try fields(item, ["severity", "stage", "code", "message", "filename", "line", "column"])
            guard let severity = SketchDiagnostic.Severity(rawValue: try item.required("severity").string()) else { throw WireJSON.invalid }
            guard ["verifying", "preprocessing", "compiling", "linking", "validating", "packaging"].contains(try item.required("stage").string()),
                  validCode(try item.required("code").string()) else { throw WireJSON.invalid }
            let message = try item.required("message").string(); guard message.utf8.count <= 4096, !message.contains("\0") else { throw WireJSON.invalid }
            let name = try item.required("filename"), line = try item.required("line"), column = try item.required("column")
            let filename: String? = if case .null = name { nil } else { try name.string() }
            guard filename?.utf8.count ?? 0 <= 256, !(filename?.contains("\0") ?? false) else { throw WireJSON.invalid }
            if case .null = line, case .null = column { return SketchDiagnostic(severity: severity, message: message, filename: filename) }
            guard filename != nil else { throw WireJSON.invalid }
            return SketchDiagnostic(severity: severity, message: message, filename: filename,
                line: try integer(line, minimum: 1, maximum: 9_007_199_254_740_991), column: try integer(column, minimum: 1, maximum: 9_007_199_254_740_991))
        }
    }
    /// Portable stable codes contain lowercase ASCII letters/underscores and stay bounded.
    private static func validCode(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64 && value.utf8.allSatisfy { $0 == 95 || (97...122).contains($0) }
    }
    /// Enforces canonical padded base64 and bounds before publishing exact binary bytes.
    private static func binary(_ value: WireJSON.Value, minimum: Int, maximum: Int) throws -> Data {
        let text = try value.string(); guard text.utf8.count <= ((maximum + 2) / 3) * 4,
            let data = Data(base64Encoded: text), data.count >= minimum, data.count <= maximum, data.base64EncodedString() == text else { throw WireJSON.invalid }
        return data
    }
    /// Uses exact parsed decimal integer literals, excluding bool/fraction/exponent coercion.
    private static func integer(_ value: WireJSON.Value, minimum: Int, maximum: Int) throws -> Int {
        guard case .number(let text) = value, let integer = Int(text), integer >= minimum, integer <= maximum else { throw WireJSON.invalid }
        return integer
    }
    /// Unknown/additive fields never cross the native boundary.
    private static func fields(_ value: WireJSON.Value, _ names: [String]) throws {
        guard Set(try value.object().keys) == Set(names.map { Data($0.utf8) }) else { throw WireJSON.invalid }
    }
}
