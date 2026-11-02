import Foundation

/// Correlated version-one response from the actual app; stdout export never needs private-container access.
public struct WorkbenchCommandResult: Codable, Sendable {
    /// Protocol schema shared with the CLI validator.
    public let schema: Int
    /// Original validated request; no automatic retry or rebinding.
    public let request: WorkbenchRequest
    /// Actual app PID independently checked by the launching controller.
    public let processID: Int32
    /// Same static registry shown in the manual Test Lab.
    public let scenarios: [WorkbenchScenario]
    /// Verified metadata when available, never installed-image evidence.
    public let catalogue: WorkbenchCatalogue?
    /// Terminal report for run, absent for discovery or rejected commands.
    public let report: WorkbenchReport?
    /// Bounded orchestration failure; no failed command is represented as a passed run.
    public let error: String?
    /// Creates a response after explicit discovery/execution, keeping actual process identity.
    public init(request: WorkbenchRequest, catalogue: WorkbenchCatalogue?, report: WorkbenchReport?, error: String? = nil) {
        schema = 1; self.request = request; processID = ProcessInfo.processInfo.processIdentifier
        scenarios = WorkbenchScenario.all; self.catalogue = catalogue; self.report = report
        self.error = error.map { String($0.prefix(512)) }
    }
    /// Bounded app-owned envelope; only a terminal response is exported.
    public func stdoutEnvelope() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(self)
        guard bytes.count <= 65536 else { throw WorkbenchFailure("Automation response exceeds 64 KiB.") }
        return Data(("FIRMINGO_WORKBENCH_RESULT:" + bytes.base64EncodedString() + "\n").utf8)
    }
}
