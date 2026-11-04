import Foundation
import FirmingoKit

/// Per-action observations, distinct from the longer-lived saved transaction.
public struct WorkbenchManagedEvidence: Codable, Sendable {
    /// Exact explicit action selection used for independent report validation.
    public let selection: WorkbenchManagedSelection
    /// Last synchronized checkpoint; restored values never carry executable capabilities.
    public var checkpoint: WorkbenchManagedCheckpoint?
    /// Canonical current SDK-record hash (including JSON null when no record was issued), never write authority.
    public var recordSHA256: String?
    /// Fixed real compiler output, present only in the stage report.
    public var artifact: WorkbenchReport.Artifact?
    /// Explicit outcome of this action; uncertainty remains an unknown report status.
    public var outcome = "not_observed"
    /// Creates no device claim before driver execution.
    public init(selection: WorkbenchManagedSelection) { self.selection = selection }
    /// A phase can pass only with its own durable assertions, never from transport admission.
    public func validate(scenario: String, runID: UUID, passed: Bool) throws {
        try selection.validate(scenario: scenario, runID: runID)
        if let checkpoint {
            try checkpoint.validate()
            guard checkpoint.request.managed?.operationID == selection.operationID else { throw WorkbenchFailure("Foreign managed operation evidence.") }
            guard try recordSHA256 == checkpoint.recordSHA256 else { throw WorkbenchFailure("Published record identity changed.") }
            if !["managed.stage", "managed.restore"].contains(scenario) {
                guard try checkpoint.recordSHA256 == selection.recordSHA256 else { throw WorkbenchFailure("Foreign managed record evidence.") }
            }
        }
        if let artifact {
            guard scenario == "managed.stage", let sketch = selection.sketch,
                  artifact.sha256 == WorkbenchManagedCheckpoint.capsuleSHA256(sketch),
                  WorkbenchManagedCheckpoint.digest(artifact.bytes) == artifact.sha256,
                  artifact.bytes.count <= 4096, artifact.receiptJSON.count <= 16384 else { throw WorkbenchFailure("Invalid fixed artifact evidence.") }
        }
        guard passed else { return }
        if scenario == "managed.restore", outcome == "context_restored", checkpoint != nil { return }
        if scenario == "managed.retire", outcome == "retired_unissued", let checkpoint,
           checkpoint.record == nil, !checkpoint.commitIntent, checkpoint.released, checkpoint.unknownReason == "stageFailedNoCommit" { return }
        guard let checkpoint, checkpoint.record != nil else { throw WorkbenchFailure("Managed pass lacks a saved SDK transaction.") }
        let expected: [String: String] = ["managed.stage": "ram_verified", "managed.commit": "commit_accepted",
            "managed.abort": "aborted", "managed.disconnect": "disconnected", "managed.reconcile": "boot_confirmed", "managed.retire": "retired_precommit"]
        guard outcome == expected[scenario] || (scenario == "managed.reconcile" && outcome == "aborted") else { throw WorkbenchFailure("Managed pass has the wrong phase outcome.") }
        switch scenario {
        case "managed.stage": guard checkpoint.stageIntent, !checkpoint.commitIntent, !checkpoint.released, artifact != nil else { throw WorkbenchFailure("Missing RAM-only stage evidence.") }
        case "managed.commit": guard checkpoint.commitIntent, checkpoint.snapshot?.state == "committing", checkpoint.snapshot?.slotTouched == false else { throw WorkbenchFailure("Commit acceptance is unconfirmed.") }
        case "managed.abort": guard !checkpoint.commitIntent, checkpoint.snapshot?.state == "aborted", checkpoint.snapshot?.errorCode == "none", checkpoint.released else { throw WorkbenchFailure("Abort is unconfirmed.") }
        case "managed.disconnect": guard !checkpoint.commitIntent else { throw WorkbenchFailure("Cannot claim pre-commit disconnect after commit intent.") }
        case "managed.reconcile": guard checkpoint.snapshot?.state == outcome, checkpoint.released else { throw WorkbenchFailure("Terminal reconciliation is unconfirmed.") }
        case "managed.retire": guard !checkpoint.commitIntent, checkpoint.unknownReason == "bootChanged", checkpoint.released else { throw WorkbenchFailure("Retirement prerequisites changed.") }
        default: throw WorkbenchFailure("Unsupported managed phase.")
        }
    }
}
