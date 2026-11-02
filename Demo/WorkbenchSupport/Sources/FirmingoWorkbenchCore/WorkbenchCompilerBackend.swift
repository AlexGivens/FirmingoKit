import Foundation

/// Testable app orchestration boundary; the production implementation invokes only public SDK compiler APIs.
@MainActor public protocol WorkbenchCompilerBackend {
    /// Loads independently verified SDK metadata without contacting a device.
    func catalogue() async throws -> WorkbenchCatalogue
    /// Checks actual compiler resource integrity; absent bytes are not simulated.
    func verifyResources() async throws
    /// Compiles one pinned input through the same compiler instance, or returns real typed diagnostics.
    func compile(_ input: WorkbenchCompilerInput, buildID: String) async throws -> WorkbenchReport.Artifact
}
