import Foundation

/// Prepares a bounded single `.ino` through the shared compiler source package, without a WASM service or board access.
/// It adds the local facade and source mapping; helper functions require explicit forward declarations.
public enum ManagedSketchPreprocessor {
    /// Normalizes CRLF/CR, removes an initial UTF-8 BOM from compiler input, and adds Arduino.h/#line.
    /// Only literal Arduino.h includes are allowed: macros, conditional includes, pragmas and user #line
    /// directives and escaped physical newlines are rejected with original positions. Comments/literals
    /// are scanned before directive validation. C++ syntax errors still belong to the compiler.
    /// This is preprocessing, not C++ type checking or proof of statelessness; the linker/output gate owns that.
    /// Lexical scanning runs in the shared compiler worker, with verified package loading and cancellation.
    /// No WASM service or service approval is required; missing/corrupt resources or host failure throw explicitly.
    @concurrent public static func prepare(_ request: ManagedSketchBuildRequest) async throws -> PreparedManagedSketch {
        let source = try await prepareSource(ManagedPortableRequest(request))
        return PreparedManagedSketch(request: request, sourceSHA256: source.sourceSHA256,
            translationUnit: source.translationUnit, translationUnitSHA256: source.translationUnitSHA256,
            sourceLineCount: source.sourceLineCount)
    }

    /// Prepares the same constrained source layout for an exact catalogue selection, with no device binding.
    /// Cancellation, diagnostics and source mapping match the legacy overload; this does not compile source.
    @concurrent public static func prepare(_ request: ManagedOfflineBuildRequest) async throws -> PreparedManagedOfflineSketch {
        let source = try await prepareSource(ManagedPortableRequest(request))
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

    /// Loads the verified source package and delegates lexical preparation to its isolated service-free worker.
    private static func prepareSource(_ request: ManagedPortableRequest) async throws -> Source {
        try Task.checkCancellation()
        let resources = try await VerifiedManagedResources.load()
        let host = await ManagedWebKitHost()
        let json = try await host.prepare(request: request, page: resources.page)
        return try await ManagedPortablePreparation.decode(json, request: request).source
    }
}
