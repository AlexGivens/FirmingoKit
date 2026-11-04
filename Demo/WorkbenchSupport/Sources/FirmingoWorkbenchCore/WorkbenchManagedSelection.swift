import Foundation

/// Schema-three managed workflow selection; saved operation IDs never grant commit capability.
public struct WorkbenchManagedSelection: Codable, Equatable, Sendable {
    /// Original stage run UUID, retained by every subsequent explicit action.
    public let operationID: UUID
    /// Stage-only fixed source vector; arbitrary source and artifacts are not accepted.
    public let sketch: String?
    /// Stage-only reviewed resident-only image identity, independent of hello.
    public let residentImageSHA256: String?
    /// Stage-only explanation of how the operator established the installed resident.
    public let evidence: String?
    /// Exact canonical saved-record hash required for every follow-up action.
    public let recordSHA256: String?
    /// Explicit stage or commit authority; absent for read-only and disposal actions.
    public let authorization: String?
    /// Captures explicit selections without I/O or implied authority.
    public init(operationID: UUID, sketch: String? = nil, residentImageSHA256: String? = nil,
                evidence: String? = nil, recordSHA256: String? = nil, authorization: String? = nil) {
        self.operationID = operationID; self.sketch = sketch; self.residentImageSHA256 = residentImageSHA256
        self.evidence = evidence; self.recordSHA256 = recordSHA256; self.authorization = authorization
    }
    /// Accepts only the action's exact options; stage/commit are independently authorized.
    public func validate(scenario: String, runID: UUID) throws {
        guard Self.scenarios.contains(scenario) else { throw WorkbenchFailure("Unknown managed action.") }
        if scenario == "managed.restore" {
            guard sketch == nil, residentImageSHA256 == nil, evidence == nil, recordSHA256 == nil, authorization == nil else { throw WorkbenchFailure("Restore accepts only the original operation identity.") }; return
        }
        if scenario == "managed.stage" {
            guard operationID == runID, ["state-a", "state-b"].contains(sketch ?? ""),
                  residentImageSHA256 == Self.imageSHA256, (8...512).contains(evidence?.utf8.count ?? 0),
                  recordSHA256 == nil, authorization == "stage-d2-gnd" else {
                throw WorkbenchFailure("Stage requires a fresh operation, fixed sketch and reviewed resident evidence plus explicit D2 authorization.")
            }
        } else {
            guard sketch == nil, residentImageSHA256 == nil, evidence == nil,
                  WorkbenchRequest.isDigest(recordSHA256 ?? ""),
                  authorization == (scenario == "managed.commit" ? "commit-once-d2-gnd" : nil) else {
                throw WorkbenchFailure("Select the exact saved transaction; only commit accepts its separate one-shot authorization.")
            }
        }
    }
    /// Closed workflow vocabulary shared by request validation and the UI.
    public static let scenarios = ["managed.stage", "managed.commit", "managed.abort", "managed.disconnect", "managed.reconcile", "managed.retire", "managed.restore"]
    /// Existing reviewed FMS2 resident; this constant does not attest the board's installed image.
    public static let imageSHA256 = "1ef766226ce6a2c51c668562cd51a71ed0bfbe1634b76b54d704c7e710ca1b2f"
    /// Exact reviewed resident ELF binding, independent of image digest and hello.
    public static let residentELFSHA256 = "bf32639c7fc2181c9ff6f99aaf8c64e19bda4f83f9690321e2b098bc81e451a8"
    /// Independently pinned static descriptor accepted by the managed qualification driver.
    public static let buildID = "dacbf259b96de0e050514764253403f3ef1ef51d0f9efaf1f43a10d8654c0e18"
    /// Strict nested parsing rejects extra authority before journal admission.
    public static func decode(_ bytes: Data) throws -> Self {
        let keys: Set<String> = ["operationID", "sketch", "residentImageSHA256", "evidence", "recordSHA256", "authorization"]
        guard bytes.count <= 2048, let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(value.keys).isSubset(of: keys), !value.values.contains(where: { $0 is NSNull }) else {
            throw WorkbenchFailure("Invalid managed selection.")
        }
        return try JSONDecoder().decode(Self.self, from: bytes)
    }
}
