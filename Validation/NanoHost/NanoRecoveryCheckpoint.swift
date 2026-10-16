import Foundation
import FirmingoKit

/// App-owned persisted intent plus SDK record, used only by the separate recovery qualification bundle.
struct NanoRecoveryCheckpoint: Codable {
    /// Closed checkpoint format, independent of the SDK record's version.
    let schema: Int
    /// Validated SDK transaction, never a restored live session.
    let record: ManagedUploadRecord
    /// Host admission evidence; commit intent always remains conservative across restart.
    let intent: NanoRecoveryIntent
    /// Original app run for audit linkage across a real process restart.
    let originatingRunID: String
    /// Closed persistence fields.
    private enum CodingKeys: String, CodingKey { case schema, record, intent, originatingRunID }

    /// Binds only the exact FMS2 test resident and one of the two known executable capsules.
    init(record: ManagedUploadRecord, intent: NanoRecoveryIntent, originatingRunID: String) throws {
        guard NanoCandidate.stateful, record.targetID == 2, record.format == "nano-managed-v2",
              record.firmwareImageSHA256 == NanoCandidate.imageSHA,
              record.residentELFSHA256 == "bf32639c7fc2181c9ff6f99aaf8c64e19bda4f83f9690321e2b098bc81e451a8",
              NanoCandidate.pins.contains(where: { $0.3 == record.sha256 }), UUID(uuidString: originatingRunID) != nil else { throw NanoGate.Rejected() }
        schema = 1; self.record = record; self.intent = intent; self.originatingRunID = originatingRunID
    }
    /// Revalidates restored metadata instead of trusting synthesized field decoding.
    init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        guard try fields.decode(Int.self, forKey: .schema) == 1 else { throw NanoGate.Rejected() }
        try self.init(record: fields.decode(ManagedUploadRecord.self, forKey: .record),
                      intent: fields.decode(NanoRecoveryIntent.self, forKey: .intent),
                      originatingRunID: fields.decode(String.self, forKey: .originatingRunID))
    }
}
