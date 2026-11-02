import Foundation

/// Version-one, bounded, device-free command admitted identically by the UI and app automation.
public struct WorkbenchRequest: Codable, Sendable, Equatable {
    /// Command schema; independent of SDK, compiler and firmware versions.
    public let schema: Int
    /// Correlation and no-replay identity; every new action requires a fresh UUID.
    public let requestID: UUID
    /// Closed operation vocabulary; no shell, device or arbitrary-code command exists.
    public let operation: Operation
    /// Explicit stable scenario identity, required only for run commands.
    public let scenarioID: String?
    /// Exact static descriptor; never a physical-device identity or automatic latest selection.
    public let firmwareBuildID: String?
    /// Operations in the initial app/CLI protocol.
    public enum Operation: String, Codable, Sendable {
        /// Discover scenarios without running a test or touching hardware.
        case list
        /// Run one finite selected scenario through the shared engine.
        case run
    }
    /// Builds a checked command; neither construction nor decoding invokes the SDK.
    public init(requestID: UUID = UUID(), operation: Operation, scenarioID: String? = nil, firmwareBuildID: String? = nil) throws {
        schema = 1; self.requestID = requestID; self.operation = operation
        self.scenarioID = scenarioID; self.firmwareBuildID = firmwareBuildID
        try validate()
    }
    /// Rejects unsupported schema/options before journal creation or SDK work.
    public func validate() throws {
        guard schema == 1, scenarioID == nil || (scenarioID?.utf8.count ?? 0) <= 96,
              firmwareBuildID == nil || Self.isDigest(firmwareBuildID ?? "") else { throw WorkbenchFailure("Invalid command schema or selection.") }
        switch operation {
        case .list:
            guard scenarioID == nil, firmwareBuildID == nil else { throw WorkbenchFailure("List accepts no scenario or build selection.") }
        case .run:
            guard let scenarioID, WorkbenchScenario.all.contains(where: { $0.id == scenarioID }) else { throw WorkbenchFailure("Unknown scenario.") }
        }
    }
    /// Decodes one small closed object, refusing paths, flags and extra commands.
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 4096, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["schema", "requestID", "operation", "scenarioID", "firmwareBuildID"]),
              Set(["schema", "requestID", "operation"]).isSubset(of: Set(object.keys)) else { throw WorkbenchFailure("Invalid command object.") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate(); return value
    }
    /// Recognizes only lowercase SHA-256 identifiers, without claiming their provenance.
    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
