import Foundation

/// Durable run snapshot; local compiler evidence never implies hardware qualification.
public struct WorkbenchReport: Codable, Sendable, Identifiable {
    /// Report schema, separate from command and firmware schemas.
    public var schema = 1
    /// Same UUID as the admitted request and its exclusive journal directory.
    public var id: UUID
    /// Exact scenario selected before execution.
    public var scenarioID: String
    /// Last observed state; unfinished runs remain distinguishable from completed tests.
    public var status: Status
    /// Explicit build selection; nil is meaningful for metadata/resource-only cases.
    public var firmwareBuildID: String?
    /// Actual verified catalogue identity when available.
    public var catalogueSHA256: String?
    /// Runtime environment recorded by this process, not an OS support claim.
    public var operatingSystem: String
    /// Process owning the run; used to identify incomplete historical context.
    public var processID: Int32
    /// Product identity from the actual host bundle.
    public var appIdentifier: String
    /// Actual host bundle version, or an explicit command-line-host label.
    public var appVersion: String
    /// Bounded ordered timeline; earlier observations are never replaced by a final status string.
    public var events: [Event]
    /// Actual bounded capsule exports, with SDK provenance; never permission to deploy.
    public var artifacts: [Artifact]
    /// Bounded source diagnostics when a compiler rejection occurs; absent in earlier schema-one snapshots.
    public var diagnostics: [Diagnostic]?
    /// Number of additional compiler messages beyond the report's sixteen-message presentation bound.
    public var diagnosticsOmitted: Int?
    /// Optional bounded compiler exercise extension; absent in earlier schema-one reports.
    public var exercise: WorkbenchExerciseEvidence?
    /// Bounded selected device/console observations, present only in report schema two.
    public var deviceEvidence: WorkbenchDeviceEvidence?
    /// Managed action observations belong only to schema three.
    public var managedEvidence: WorkbenchManagedEvidence?
    /// Whether this report describes an explicitly selected hardware operation; not flash authority.
    public var deviceOperations = false
    /// Closed statuses; blocked/cancelled/incomplete can never be counted as passed.
    public enum Status: String, Codable, Sendable {
        /// Explicit request admitted; work not complete.
        case running
        /// Every assertion in this case completed successfully.
        case passed
        /// An assertion or SDK operation failed.
        case failed
        /// Required resources/selection or an unmigrated feature prevents this case.
        case blocked
        /// Actual cancellation settled; no earlier artifact is substituted.
        case cancelled
        /// A prior process left incomplete context; no automatic execution is restored.
        case outcomeUnknown
    }
    /// One bounded progress or assertion observation with monotonic elapsed time.
    public struct Event: Codable, Sendable {
        /// Stable ordinal for ordering without wall-clock assumptions.
        public var sequence: Int
        /// Seconds since run admission, not chip/electrical timing.
        public var seconds: Double
        /// Stable phase name used by both presentation and automation.
        public var phase: String
        /// Expected/observed outcome or actionable error, bounded to 1024 UTF-8 bytes.
        public var detail: String
    }
    /// A real SDK-produced capsule and receipt, exported only after its expected hash matches.
    public struct Artifact: Codable, Sendable {
        /// Fixed safe filename assigned by the scenario.
        public var name: String
        /// Exact whole-capsule digest.
        public var sha256: String
        /// Complete capsule bytes, bounded by the selected SDK profile.
        public var bytes: Data
        /// Original SDK offline receipt, including source, recipe, service and resident identities.
        public var receiptJSON: Data
        /// Post-build WASM linear bytes; not aggregate app/WebKit peak memory.
        public var wasmLinearMemoryBytes: Int
    }
    /// Codable projection of a real SDK source diagnostic, without adding a compiler parser.
    public struct Diagnostic: Codable, Sendable {
        /// SDK message severity, retained independently of UI colors.
        public var severity: String
        /// Original bounded source message.
        public var message: String
        /// Original source filename when supplied by the SDK.
        public var filename: String?
        /// One-based source line when supplied.
        public var line: Int?
        /// One-based UTF-8 byte column when supplied.
        public var column: Int?
    }
    /// Rejects ambiguous history/export scope while preserving partial failed observations.
    func validateScope() throws {
        guard (1...3).contains(schema), deviceOperations == (schema >= 2) else { throw WorkbenchFailure("Invalid report scope.") }
        if schema == 3 {
            guard let managedEvidence, deviceEvidence == nil, WorkbenchManagedSelection.scenarios.contains(scenarioID),
                  firmwareBuildID == nil, catalogueSHA256 == nil, artifacts.isEmpty, exercise == nil else { throw WorkbenchFailure("Invalid managed report scope.") }
            try managedEvidence.validate(scenario: scenarioID, runID: id, passed: status == .passed)
            return
        }
        guard managedEvidence == nil else { throw WorkbenchFailure("Managed evidence requires schema three.") }
        if schema == 1 {
            guard deviceEvidence == nil else { throw WorkbenchFailure("Offline report contains hardware evidence.") }
        } else {
            guard let deviceEvidence, ["device.inspect", "device.console-binary"].contains(scenarioID),
                  firmwareBuildID == nil, catalogueSHA256 == nil, artifacts.isEmpty, exercise == nil,
                  deviceEvidence.received.count <= 257, (0...257).contains(deviceEvidence.sentBytes) else {
                throw WorkbenchFailure("Invalid hardware report scope.")
            }
            _ = try WorkbenchRequest(operation: .run, scenarioID: scenarioID, device: deviceEvidence.selection)
            if status == .passed { try deviceEvidence.validate(console: scenarioID == "device.console-binary") }
        }
    }
    /// Creates only a running snapshot, before the journal gate or SDK operation.
    public init(request: WorkbenchRequest) {
        schema = request.schema; deviceOperations = request.device != nil
        deviceEvidence = request.managed == nil ? request.device.map { .init(selection: $0) } : nil
        managedEvidence = request.managed.map {
            var value = WorkbenchManagedEvidence(selection: $0)
            if request.scenarioID == "managed.stage" {
                value.checkpoint = .init(request: request)
                value.recordSHA256 = WorkbenchManagedCheckpoint.digest(Data("null".utf8))
            }
            return value
        }
        id = request.requestID; scenarioID = request.scenarioID ?? ""
        status = .running; firmwareBuildID = request.firmwareBuildID
        operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        processID = ProcessInfo.processInfo.processIdentifier
        appIdentifier = Bundle.main.bundleIdentifier ?? "command-line-host"
        appVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unbundled"
        events = []; artifacts = []
    }
}
