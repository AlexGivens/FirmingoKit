/// App-owned device scenario boundary; production uses public SDK I/O, tests inject only observations.
@MainActor public protocol WorkbenchDeviceBackend {
    /// Executes the selected bounded operation and saves progress before side effects; never compiles or uploads.
    func run(_ selection: WorkbenchDeviceSelection, console: Bool,
             save: @escaping @MainActor (WorkbenchDeviceEvidence) throws -> Void) async throws
}
