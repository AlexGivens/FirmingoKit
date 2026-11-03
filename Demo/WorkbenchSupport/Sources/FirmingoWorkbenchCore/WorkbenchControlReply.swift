import Foundation

/// Correlated bounded response; accepted transport/run admission never means a scenario passed.
public struct WorkbenchControlReply: Encodable, Sendable {
    /// Protocol schema.
    public let schema = 1
    /// Original explicit command, retained for independent controller validation.
    public let command: WorkbenchControlCommand
    /// Exact app instance assigned before pairing; changes after relaunch.
    public let instanceID: UUID
    /// Actual runtime process, independent of controller/OS device identifiers.
    public let processID = ProcessInfo.processInfo.processIdentifier
    /// Actual app bundle identity.
    public let appIdentifier = Bundle.main.bundleIdentifier ?? "command-line-host"
    /// Actual build version.
    public let appVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unbundled"
    /// Admission/query succeeded; report.status remains the scenario outcome.
    public let accepted: Bool
    /// Bounded rejection description; never credentials or a source payload.
    public let error: String?
    /// Current shared engine state for human and agent coordination.
    public let state: State
    /// Registry only on explicit list.
    public let scenarios: [WorkbenchScenario]?
    /// Verified metadata only on explicit list.
    public let catalogue: WorkbenchCatalogue?
    /// Full bounded report only on explicit export.
    public let report: WorkbenchReport?
    /// Live read-only projection; no restored task or write permission.
    public struct State: Codable, Sendable {
        /// One shared engine admission gate.
        public let isRunning: Bool
        /// Latest report identity, which may be a completed run.
        public let runID: UUID?
        /// Last durable scenario status.
        public let status: WorkbenchReport.Status?
        /// Last durable phase; lets an agent wait for real user-action boundaries.
        public let phase: String?
        /// Whether explicit lifecycle start is currently admissible.
        public let awaitingLifecycleStart: Bool
    }
}
