import Foundation

/// Closed paired-controller actions. No path, source, service URL, scene injection, device write or shell operation exists.
public struct WorkbenchControlCommand: Codable, Sendable {
    /// Transport command schema, independent of the embedded run request schema.
    public let schema: Int
    /// Correlation identity; transport sequences prevent repeated execution in a session.
    public let commandID: UUID
    /// Explicit supported operation.
    public let action: Action
    /// Selected run for status/cancel/start/report; cannot silently target a newer UI operation.
    public let runID: UUID?
    /// Existing checked Workbench request, present only for run admission.
    public let request: WorkbenchRequest?
    /// Scope remains offline compiler scenarios and read-only evidence.
    public enum Action: String, Codable, Sendable {
        /// Return the registry and current SDK catalogue.
        case list
        /// Admit one fresh durable request and acknowledge admission separately from completion.
        case run
        /// Return live state for one explicit run.
        case status
        /// Request cancellation of that exact active run.
        case cancel
        /// Explicit second lifecycle start after calibration; does not fake a scene change.
        case beginLifecycle
        /// Export one current or saved bounded report, without replaying it.
        case report
    }
    /// Validates before journal/SDK work and rejects nested request extensions.
    public static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count <= 4096, let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(object.keys).isSubset(of: ["schema", "commandID", "action", "runID", "request"]) else {
            throw WorkbenchFailure("Invalid controller command.")
        }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard value.schema == 1 else { throw WorkbenchFailure("Unsupported controller schema.") }
        switch value.action {
        case .list:
            guard value.runID == nil, value.request == nil else { throw WorkbenchFailure("List accepts no run selection.") }
        case .run:
            guard let request = value.request, request.operation == .run, value.runID == nil,
                  let raw = object["request"] else { throw WorkbenchFailure("Select exactly one checked run request.") }
            _ = try WorkbenchRequest.decode(JSONSerialization.data(withJSONObject: raw))
        case .status, .cancel, .beginLifecycle, .report:
            guard value.runID != nil, value.request == nil else { throw WorkbenchFailure("Select the exact run UUID.") }
        }
        return value
    }
}
