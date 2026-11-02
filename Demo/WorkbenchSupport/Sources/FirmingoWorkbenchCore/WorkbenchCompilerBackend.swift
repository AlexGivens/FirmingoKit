import Foundation

/// Testable app orchestration boundary; the production implementation invokes only public SDK compiler APIs.
@MainActor public protocol WorkbenchCompilerBackend {
    /// Loads independently verified SDK metadata without contacting a device.
    func catalogue() async throws -> WorkbenchCatalogue
    /// Checks actual compiler resource integrity; absent bytes are not simulated.
    func verifyResources() async throws
    /// Compiles one pinned input through the same compiler instance, or returns real typed diagnostics.
    func compile(_ input: WorkbenchCompilerInput, buildID: String, probe: WorkbenchCompilerProbe) async throws -> WorkbenchReport.Artifact
}

/// Convenience for scenarios that do not assert callback timing; still bounded by the same SDK observer.
public extension WorkbenchCompilerBackend {
    /// Executes the identical compiler path with an owned bounded probe.
    func compile(_ input: WorkbenchCompilerInput, buildID: String) async throws -> WorkbenchReport.Artifact {
        try await compile(input, buildID: buildID, probe: WorkbenchCompilerProbe())
    }
}
