import Foundation

/// Local experimental Nano compiler using an internal isolated WebKit/WASI worker, with no board side effect.
/// Default loading uses verified SDK resources; an explicitly prepared SDK includes the reviewed service. No shell/native
/// compiler fallback exists. A valid artifact establishes compile/link/structural packaging, not hardware behavior.
public actor ManagedSketchCompiler {
    /// Optional explicit development service; nil uses only the SDK-pinned package resource inventory.
    private let serviceURL: URL?
    /// Reserves this actor across suspension so two document revisions cannot share mutable runtime state.
    private var building = false
    /// Selects a reviewed local service; actual byte/hash verification occurs off the main actor for every build.
    /// Callers retain security-scoped access for the full build when their sandbox requires it.
    public init(serviceURL: URL) { self.serviceURL = serviceURL }
    /// Selects SDK-owned bundled resources without a picker, environment override or external toolchain.
    /// Construction performs no I/O. Build verifies the inventory and assets off UI execution. The source checkout
    /// reports missing `compiler.wasm`; an explicitly prepared SDK supplies the reviewed binary.
    public init() { serviceURL = nil }

    /// Verifies the selected resources off UI execution without preparing source, starting WebKit or contacting a board.
    /// Useful for host setup/availability checks. Success confirms asset integrity only, not recipe/hardware behavior;
    /// builds verify again and no bytes are cached. Missing or corrupt packaged assets fail explicitly.
    /// Shares the build reservation: overlapping verification/build requests throw busy; cancellation releases it.
    public func verifyResources() async throws {
        guard !building else { throw ManagedCompilerError.busy }
        building = true
        defer { building = false }
        try Task.checkCancellation()
        _ = try await loadToolchain()
        try Task.checkCancellation()
    }

    /// Keeps resource selection identical across legacy and offline builds; no automatic fallback occurs.
    private func loadToolchain(profile: ManagedSketchBuildRequest.Profile = .nanoManagedV1) async throws -> VerifiedManagedToolchain {
        if let serviceURL { return try await VerifiedManagedToolchain.load(serviceURL: serviceURL, profile: profile) }
        return try await VerifiedManagedResources.load().toolchain(profile: profile)
    }

    /// Compiles one immutable single-file revision through verify, preprocess, compile, link and package.
    /// Progress is a finite synchronous observer (at most eight notifications, including two source/wrapper
    /// compile notifications), invoked from compiler or WebKit isolation; it must not block. Cancellation
    /// discards the page/worker and never returns an earlier artifact. Runtime execution has a 60-second
    /// deadline. Builds run offline, require explicit resident metadata, and never connect or upload.
    public func build(_ request: ManagedSketchBuildRequest,
                      progress: @escaping @Sendable (ManagedCompilationPhase) -> Void = { _ in }) async throws -> ManagedCompilationResult {
        guard !building else { throw ManagedCompilerError.busy }
        building = true
        defer { building = false }
        try Task.checkCancellation()
        progress(.verifying)
        let toolchain = try await loadToolchain(profile: request.profile)
        let portable = try ManagedPortableRequest(request)
        let host = await ManagedWebKitHost()
        let json = try await host.run(request: portable, toolchain: toolchain, progress: progress)
        let output = try await ManagedPortableOutput.decode(json, request: portable)
        let prepared = PreparedManagedSketch(request: request, sourceSHA256: output.sourceSHA256, translationUnit: output.translationUnit,
            translationUnitSHA256: output.translationUnitSHA256, sourceLineCount: output.sourceLineCount)
        let provenance = try ManagedELFProvenance(compiler: "Clang/LLD 22.1.8 ABI-two WASI service, isolated WebKit worker",
            recipeIdentifier: request.profile.recipeIdentifier, recipeSHA256: toolchain.recipeSHA256, toolchainSHA256: toolchain.toolchainSHA256)
        let report = try output.sdkReport(provenance: provenance)
        let capsule = try ManagedCapsule(bytes: output.bytes, reportJSON: report, resident: request.resident)
        let receipt = ManagedSketchArtifact.Receipt(prepared: prepared, provenance: provenance,
            buildInputSHA256: try ManagedELFConverter.receiptInputSHA256(prepared: prepared, provenance: provenance),
            linkedELFSHA256: output.linkedELFSHA256, capsuleSHA256: capsule.sha256)
        let artifact = ManagedSketchArtifact(capsule: capsule, filename: String(request.snapshot.filename.dropLast(4)) + ".fms",
            reportJSON: report, receipt: receipt, compilerReceiptJSON: output.executionReceiptJSON)
        try Task.checkCancellation()
        return ManagedCompilationResult(artifact: artifact, diagnostics: output.diagnostics, linearMemoryBytes: output.memoryBytes)
    }

    /// Compiles an exact verified catalogue selection without connecting or creating any physical-device identity.
    /// Uses the same verified service, source restrictions, eight bounded progress notifications, 60-second
    /// runtime deadline and cancellation cleanup as the legacy overload. Both overloads share one busy gate;
    /// a failed/cancelled build cannot return stale bytes. The receipt records source/catalogue/descriptor/
    /// recipe/toolchain identity. Bind its artifact explicitly before upload; build success is not hardware proof.
    public func build(_ request: ManagedOfflineBuildRequest,
                      progress: @escaping @Sendable (ManagedCompilationPhase) -> Void = { _ in }) async throws -> ManagedOfflineCompilationResult {
        guard !building else { throw ManagedCompilerError.busy }
        building = true
        defer { building = false }
        try Task.checkCancellation()
        progress(.verifying)
        let toolchain = try await loadToolchain(profile: request.firmwareBuild.profile)
        guard toolchain.recipeSHA256 == request.firmwareBuild.recipeSHA256 else {
            throw SketchBuildError.invalidProvenance
        }
        let portable = try ManagedPortableRequest(request)
        let host = await ManagedWebKitHost()
        let json = try await host.run(request: portable, toolchain: toolchain, progress: progress)
        let output = try await ManagedPortableOutput.decode(json, request: portable)
        let prepared = PreparedManagedOfflineSketch(request: request, source: ManagedSketchPreprocessor.Source(sourceSHA256: output.sourceSHA256,
            translationUnit: output.translationUnit, translationUnitSHA256: output.translationUnitSHA256, sourceLineCount: output.sourceLineCount))
        let provenance = try ManagedELFProvenance(compiler: "Clang/LLD 22.1.8 ABI-two WASI service, isolated WebKit worker",
            recipeIdentifier: request.firmwareBuild.recipeIdentifier, recipeSHA256: toolchain.recipeSHA256, toolchainSHA256: toolchain.toolchainSHA256)
        let report = try output.sdkReport(provenance: provenance)
        let artifact = try ManagedOfflineSketchArtifact(bytes: output.bytes, sha256: NanoManagedContract.digest(output.bytes), reportJSON: report,
            prepared: prepared, provenance: provenance, linkedELFSHA256: output.linkedELFSHA256, compilerReceiptJSON: output.executionReceiptJSON)
        try Task.checkCancellation()
        return ManagedOfflineCompilationResult(artifact: artifact, diagnostics: output.diagnostics, linearMemoryBytes: output.memoryBytes)
    }
}
