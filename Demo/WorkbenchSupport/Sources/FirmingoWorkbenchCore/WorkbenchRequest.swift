import Foundation

/// Version-one, bounded, device-free command admitted identically by the UI and app automation.
public struct WorkbenchRequest: Codable, Sendable, Equatable {
    /// Command schema; independent of SDK, compiler and firmware versions.
    public let schema: Int
    /// Correlation and no-replay identity; every new action requires a fresh UUID.
    public let requestID: UUID
    /// Closed operation vocabulary; hardware authority is limited to explicit schema-two selection.
    public let operation: Operation
    /// Explicit stable scenario identity, required only for run commands.
    public let scenarioID: String?
    /// Exact static descriptor; never a physical-device identity or automatic latest selection.
    public let firmwareBuildID: String?
    /// Explicit hardware selection is present only in schema two device scenarios.
    public let device: WorkbenchDeviceSelection?
    /// Operations in the initial app/CLI protocol.
    public enum Operation: String, Codable, Sendable {
        /// Discover scenarios without running a test or touching hardware.
        case list
        /// Run one finite selected scenario through the shared engine.
        case run
    }
    /// Builds a checked command; neither construction nor decoding invokes the SDK.
    public init(requestID: UUID = UUID(), operation: Operation, scenarioID: String? = nil, firmwareBuildID: String? = nil, device: WorkbenchDeviceSelection? = nil) throws {
        schema = device == nil ? 1 : 2; self.device = device; self.requestID = requestID; self.operation = operation
        self.scenarioID = scenarioID; self.firmwareBuildID = firmwareBuildID
        try validate()
    }
    /// Rejects unsupported schema/options before journal creation or SDK work.
    public func validate() throws {
        guard (schema == 1 && device == nil) || (schema == 2 && device != nil), scenarioID == nil || (scenarioID?.utf8.count ?? 0) <= 96,
              firmwareBuildID == nil || Self.isDigest(firmwareBuildID ?? "") else { throw WorkbenchFailure("Invalid command schema or selection.") }
        switch operation {
        case .list:
            guard scenarioID == nil, firmwareBuildID == nil, device == nil else { throw WorkbenchFailure("List accepts no scenario or build selection.") }
        case .run:
            guard let scenarioID, let scenario = WorkbenchScenario.all.first(where: { $0.id == scenarioID }) else { throw WorkbenchFailure("Unknown scenario.") }
            guard scenario.requiresDevice == (device != nil) else { throw WorkbenchFailure("Device selection is required only for device scenarios.") }
            if let device {
                try device.validate()
                guard firmwareBuildID == nil else { throw WorkbenchFailure("Hardware checks do not require a compiler descriptor.") }
                if scenarioID == "device.inspect" {
                    guard device.bootID == nil, device.consoleProbe == nil else { throw WorkbenchFailure("Inspection accepts no console probe or boot assumption.") }
                } else {
                    guard device.bootID != nil, device.consoleProbe != nil else { throw WorkbenchFailure("Inspect first and explicitly select the boot and binary probe.") }
                }
            }
        }
    }
    /// Decodes one small closed object, refusing paths, flags and extra commands.
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 4096, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["schema", "requestID", "operation", "scenarioID", "firmwareBuildID", "device"]),
              Set(["schema", "requestID", "operation"]).isSubset(of: Set(object.keys)) else { throw WorkbenchFailure("Invalid command object.") }
        if let device = object["device"] {
            guard object["firmwareBuildID"] == nil else { throw WorkbenchFailure("Hardware requests accept no compiler descriptor field.") }
            _ = try WorkbenchDeviceSelection.decode(JSONSerialization.data(withJSONObject: device))
        }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate(); return value
    }
    /// Recognizes only lowercase SHA-256 identifiers, without claiming their provenance.
    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
