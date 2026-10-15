import Foundation

/// Device-independent structurally validated FMS1/FMS2 packaging and immutable source/build evidence.
/// Binding to a reviewed device association is explicit and does not authorize upload or attest installed bytes.
public struct ManagedOfflineSketchArtifact: Sendable {
    /// Complete FMS1/FMS2 bytes; these are not a conventional UF2 or complete resident image.
    public let bytes: Data
    /// Exact whole-capsule digest, independent of document revision and physical-device selection.
    public let sha256: String
    /// Safe .fms filename derived from the source leaf.
    public let filename: String
    /// Matching bounded build report with exact source, recipe and toolchain provenance.
    public let reportJSON: Data
    /// Exact static firmware requirements; no physical device ID exists in this value.
    public let firmwareBuild: ManagedFirmwareBuildDescriptor
    /// Immutable offline input/output identity for revision and target checks; never execution permission.
    public let receipt: Receipt

    /// Distinct portable execution receipt for actual shared-compiler builds; nil for independently supplied ELF.
    public let compilerReceiptJSON: Data?

    /// Issues a result after shared ELF/capsule/report validation and recipe identity checks.
    init(bytes: Data, sha256: String, reportJSON: Data, prepared: PreparedManagedOfflineSketch,
         provenance: ManagedELFProvenance, linkedELFSHA256: String, compilerReceiptJSON: Data? = nil) throws {
        self.bytes = bytes; self.sha256 = sha256; self.reportJSON = reportJSON; self.compilerReceiptJSON = compilerReceiptJSON
        firmwareBuild = prepared.request.firmwareBuild
        filename = String(prepared.request.snapshot.filename.dropLast(4)) + ".fms"
        receipt = try Receipt(prepared: prepared, provenance: provenance,
                              linkedELFSHA256: linkedELFSHA256, capsuleSHA256: sha256)
    }

    /// Requires matching exact descriptor evidence and validates bytes again against that device binding.
    /// Throws associationMismatch for another build. The caller must review the evidence and current source
    /// revision, then use fresh device/backend/advertised-target checks before staging through the upload API.
    /// This local operation does not connect, stage, commit, replace firmware or resume a journal.
    public func bind(to association: ManagedDeviceAssociation) throws -> ManagedCapsule {
        let resident = try ManagedResidentBinding(association: association, firmwareBuild: firmwareBuild)
        return try ManagedCapsule(bytes: bytes, reportJSON: reportJSON, resident: resident)
    }

    /// Schema-one offline receipt, distinct from the legacy device-bound artifact receipt schema.
    public struct Receipt: Encodable, Equatable, Sendable {
        /// Local offline receipt version, independent of protocol/ABI and legacy receipt schemas.
        public let version: UInt32
        /// Original document identity.
        public let documentID: UUID
        /// Exact original revision; identical source at a newer revision still has different input identity.
        public let sourceRevision: UInt64
        /// Original diagnostic source leaf.
        public let sourceFilename: String
        /// Original UTF-8 source digest.
        public let sourceSHA256: String
        /// Complete generated compiler-input digest.
        public let translationUnitSHA256: String
        /// Exact verified catalogue bytes.
        public let catalogueSHA256: String
        /// Content identity covering all selected resident-build and recipe requirements.
        public let firmwareBuildID: String
        /// Explicit board identity.
        public let boardID: String
        /// Explicit managed artifact/ABI profile.
        public let profile: String
        /// Compiler, recipe and exact verified runtime/service identity.
        public let provenance: ManagedELFProvenance
        /// Sorted compact JSON digest covering every input above including version, excluding output hashes.
        public let buildInputSHA256: String
        /// Complete linked ELF digest, including nonloaded metadata.
        public let linkedELFSHA256: String
        /// Complete FMS1/FMS2 digest, distinct from linked ELF and code digests.
        public let capsuleSHA256: String

        /// Records exact validated input/output fields, without inserting a device placeholder.
        init(prepared: PreparedManagedOfflineSketch, provenance: ManagedELFProvenance,
             linkedELFSHA256: String, capsuleSHA256: String) throws {
            let request = prepared.request
            version = 1; documentID = request.snapshot.documentID; sourceRevision = request.snapshot.revision
            sourceFilename = request.snapshot.filename; sourceSHA256 = prepared.sourceSHA256
            translationUnitSHA256 = prepared.translationUnitSHA256; catalogueSHA256 = request.catalogueSHA256
            firmwareBuildID = request.firmwareBuild.id; boardID = request.firmwareBuild.board.rawValue
            profile = request.firmwareBuild.profile.rawValue; self.provenance = provenance
            self.linkedELFSHA256 = linkedELFSHA256; self.capsuleSHA256 = capsuleSHA256
            let inputs: [String: Any] = ["version": version, "documentID": documentID.uuidString,
                "sourceRevision": sourceRevision, "sourceFilename": sourceFilename, "sourceSHA256": sourceSHA256,
                "translationUnitSHA256": translationUnitSHA256, "catalogueSHA256": catalogueSHA256,
                "firmwareBuildID": firmwareBuildID, "boardID": boardID, "profile": profile,
                "provenance": ["compiler": provenance.compiler, "recipeIdentifier": provenance.recipeIdentifier,
                    "recipeSHA256": provenance.recipeSHA256, "toolchainSHA256": provenance.toolchainSHA256]]
            buildInputSHA256 = NanoManagedContract.digest(try JSONSerialization.data(withJSONObject: inputs,
                options: [.sortedKeys, .withoutEscapingSlashes]))
        }
    }
}
