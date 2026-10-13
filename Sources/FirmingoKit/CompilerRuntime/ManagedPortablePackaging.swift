import Foundation

/// Native correlation, provenance and deployment-format checks for shared supplied-ELF packaging.
/// It accepts no compile receipt and never parses ELF or creates capsule bytes.
struct ManagedPortablePackaging: Sendable {
    /// Shared compiler-produced capsule, independently checked against static resident requirements.
    let payload: ManagedCapsulePayload
    /// Unchanged canonical packaging report, used by legacy and offline Swift artifacts.
    let reportJSON: Data
    /// Exact caller-supplied ELF identity, independently hashed before accepting its receipt.
    let linkedELFSHA256: String

    /// Requires closed fields, captured input/provenance, original/generated hashes and exact output identities.
    @concurrent static func decode(_ json: String, request: ManagedPortableRequest, elf: Data,
                                  sourceSHA256: String, translationUnitSHA256: String) async throws -> Self {
        try Task.checkCancellation()
        guard let provenance = request.packagingProvenance else { throw WireJSON.invalid }
        let root = try WireJSON.parse(Data(json.utf8), maximumBytes: 128 * 1024, maximumTokens: 4096)
        guard try root.required("schema").uint32() == 1,
              try root.required("operation").string() == "package_elf",
              try root.required("buildID").string() == request.buildID,
              try root.required("requestSHA256").string() == request.requestSHA256 else { throw WireJSON.invalid }
        let outcome = try root.required("outcome").string()
        if outcome != "succeeded" {
            try fields(root, ["schema", "operation", "buildID", "requestSHA256", "outcome", "error", "diagnostics"])
            let error = try root.required("error"); try fields(error, ["code", "stage", "message"])
            let code = try error.required("code").string(), message = try error.required("message").string()
            guard ["preprocessing", "validating", "packaging"].contains(try error.required("stage").string()),
                  message.utf8.count <= 4096, !message.contains("\0"), !code.isEmpty, code.utf8.count <= 64,
                  code.utf8.allSatisfy({ $0 == 95 || (97...122).contains($0) }),
                  outcome == (code == "cancelled" ? "cancelled" : code == "timed_out" ? "timed_out" : "failed") else { throw WireJSON.invalid }
            let diagnostics = try ManagedPortableOutput.diagnosticRecords(root.required("diagnostics"))
            switch code {
            case "invalid_elf": throw SketchBuildError.invalidELF(message)
            case "invalid_provenance": throw SketchBuildError.invalidProvenance
            case "unsupported_source": throw SketchBuildError.unsupportedSource(diagnostics)
            case "invalid_source": throw SketchBuildError.invalidInput(message)
            case "cancelled": throw CancellationError()
            case "timed_out": throw ManagedCompilerError.timedOut
            default: throw ManagedCompilerError.runtime("ELF packaging failed: " + code)
            }
        }
        try fields(root, ["schema", "operation", "buildID", "requestSHA256", "outcome", "artifact"])
        let artifact = try root.required("artifact"); try fields(artifact, ["format", "filename", "bytes", "sha256", "reportJSON", "receipt"])
        guard try artifact.required("format").string() == "nano-managed-v1",
              try artifact.required("filename").string() == String(request.snapshot.filename.dropLast(4)) + ".fms" else { throw WireJSON.invalid }
        let encoded = try artifact.required("bytes").string()
        guard encoded.utf8.count <= 5464, let bytes = Data(base64Encoded: encoded),
              (260...4096).contains(bytes.count), bytes.base64EncodedString() == encoded else { throw WireJSON.invalid }
        let report = try artifact.required("reportJSON").string()
        guard report.utf8.count <= 16_384 else { throw WireJSON.invalid }
        let reportJSON = Data(report.utf8)
        let receipt = try artifact.required("receipt")
        try fields(receipt, ["receiptSchema", "operation", "provenanceStatus", "requestSHA256", "buildID", "sourceRevision", "sourceFilename",
            "sourceSHA256", "translationUnitSHA256", request.targetIdentityKey, "board", "profile", "provenance", "buildInputSHA256",
            "linkedELFSHA256", "capsuleSHA256", "capsuleBytes"])
        let linkedHash = NanoManagedContract.digest(elf), capsuleHash = NanoManagedContract.digest(bytes)
        guard sourceSHA256 == NanoManagedContract.digest(Data(request.snapshot.source.utf8)),
              try receipt.required("receiptSchema").string() == "firmingo-compiler-declared-packaging-v1",
              try receipt.required("operation").string() == "independent_elf_packaging",
              try receipt.required("provenanceStatus").string() == "declared",
              try receipt.required("requestSHA256").string() == request.requestSHA256,
              try receipt.required("buildID").string() == request.buildID,
              try receipt.required("sourceRevision").string() == request.revisionToken,
              try receipt.required("sourceFilename").string() == request.snapshot.filename,
              try receipt.required("sourceSHA256").string() == sourceSHA256,
              try receipt.required("translationUnitSHA256").string() == translationUnitSHA256,
              try receipt.required(request.targetIdentityKey).string() == request.targetIdentity,
              try receipt.required("board").string() == "nano_rp2040_connect",
              try receipt.required("profile").string() == "nano-managed-v1",
              try receipt.required("linkedELFSHA256").string() == linkedHash,
              try receipt.required("capsuleSHA256").string() == capsuleHash,
              try artifact.required("sha256").string() == capsuleHash,
              try receipt.required("capsuleBytes").uint32() == bytes.count else { throw WireJSON.invalid }
        let declared = try receipt.required("provenance"); try fields(declared, ["compiler", "recipeIdentifier", "recipeSHA256", "toolchainSHA256"])
        guard try declared.required("compiler").string() == provenance.compiler,
              try declared.required("recipeIdentifier").string() == provenance.recipeIdentifier,
              try declared.required("recipeSHA256").string() == provenance.recipeSHA256,
              try declared.required("toolchainSHA256").string() == provenance.toolchainSHA256 else { throw WireJSON.invalid }
        var inputs = try ManagedPortableOutput.dictionary(receipt)
        for key in ["buildInputSHA256", "linkedELFSHA256", "capsuleSHA256", "capsuleBytes"] { inputs.removeValue(forKey: key) }
        guard try receipt.required("buildInputSHA256").string() == NanoManagedContract.digest(ManagedPortableRequest.canonical(inputs)) else { throw WireJSON.invalid }
        let payload = try ManagedCapsulePayload(bytes: bytes, reportJSON: reportJSON, apiAddress: request.apiAddress,
            residentELFSHA256: request.residentELFSHA256)
        let parsedReport = try WireJSON.parse(reportJSON, maximumBytes: 16_384, maximumTokens: 1024)
        try fields(parsedReport, ["status", "board", "image_format", "target_id", "max_install_bytes", "api_address", "resident_elf_sha256",
            "setup_address", "loop_address", "code_bytes", "code_sha256", "capsule_bytes", "capsule_sha256", "source_sha256", "compiler", "recipe_id", "linked_elf_sha256"])
        guard payload.compiler == provenance.compiler,
              payload.sourceSHA256 == ["sketch/\(request.snapshot.filename)": sourceSHA256, "generated/Sketch.cpp": translationUnitSHA256,
                "recipe/manifest.json": provenance.recipeSHA256, "toolchain/manifest.json": provenance.toolchainSHA256],
              try parsedReport.required("status").string() == "structurally validated packaging; compiler/source association is host supplied; no hardware proof",
              try parsedReport.required("recipe_id").string() == provenance.recipeIdentifier,
              try parsedReport.required("linked_elf_sha256").string() == linkedHash,
              try parsedReport.required("max_install_bytes").uint32() == 4096 else { throw WireJSON.invalid }
        try Task.checkCancellation()
        return Self(payload: payload, reportJSON: reportJSON, linkedELFSHA256: linkedHash)
    }

    /// Rejects unknown fields at each native packaging boundary without accepting additive metadata.
    private static func fields(_ value: WireJSON.Value, _ names: [String]) throws {
        guard Set(try value.object().keys) == Set(names.map { Data($0.utf8) }) else { throw WireJSON.invalid }
    }
}
