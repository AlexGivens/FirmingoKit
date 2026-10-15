import Foundation

/// Offline ELF packaging result, distinct from source compilation, managed upload or firmware installation.
/// Its report carries host-supplied build provenance; validation does not authenticate that association.
public struct ManagedSketchArtifact: Sendable {
    /// Validated FMS1 capsule suitable for the separate capability/binding-gated upload API.
    public let capsule: ManagedCapsule
    /// Safe `.fms` leaf derived from the immutable source filename.
    public let filename: String
    /// Deterministic bounded report matching the capsule, source and declared build identity.
    public let reportJSON: Data
    /// Typed receipt for revision checks and retained provenance; it is never upload authorization.
    public let receipt: Receipt

    /// Distinct verified portable execution receipt when built through the shared compiler; nil for independent ELF packaging.
    public let compilerReceiptJSON: Data?

    /// SDK-only construction after complete linked-output and capsule/report validation.
    init(capsule: ManagedCapsule, filename: String, reportJSON: Data, receipt: Receipt, compilerReceiptJSON: Data? = nil) {
        self.capsule = capsule
        self.filename = filename
        self.reportJSON = reportJSON
        self.receipt = receipt
        self.compilerReceiptJSON = compilerReceiptJSON
    }

    /// Schema-one immutable input/output evidence; the receipt alone cannot authenticate source association or hardware execution.
    public struct Receipt: Encodable, Equatable, Sendable {
        /// Local receipt schema, independent of firmware protocol/ABI version.
        public let version: UInt32
        /// Original host document identity.
        public let documentID: UUID
        /// Exact source revision; a newer revision must never reuse this result implicitly.
        public let sourceRevision: UInt64
        /// Original diagnostic source filename.
        public let sourceFilename: String
        /// Original UTF-8 source hash.
        public let sourceSHA256: String
        /// Exact generated translation-unit hash.
        public let translationUnitSHA256: String
        /// Complete input identity: source/revision/target/resident, generated unit and build provenance.
        public let buildInputSHA256: String
        /// Selected managed board ID.
        public let boardID: String
        /// Explicit versioned managed profile.
        public let profile: String
        /// Host-associated resident device identity, not remote attestation.
        public let deviceID: String
        /// Exact resident ELF association declared by the host.
        public let residentELFSHA256: String
        /// Host-known installed complete image association.
        public let firmwareImageSHA256: String
        /// Resident API table address from verified installation metadata.
        public let apiAddress: UInt32
        /// Compiler/recipe/toolchain identity supplied with the independently linked ELF.
        public let provenance: ManagedELFProvenance
        /// Digest of the complete linked ELF including nonloaded metadata.
        public let linkedELFSHA256: String
        /// Complete FMS1/FMS2 digest, distinct from ELF and code digests.
        public let capsuleSHA256: String

        /// Issues a receipt only for an already validated package.
        init(prepared: PreparedManagedSketch, provenance: ManagedELFProvenance,
             buildInputSHA256: String, linkedELFSHA256: String, capsuleSHA256: String) {
            version = 1
            documentID = prepared.request.snapshot.documentID
            sourceRevision = prepared.request.snapshot.revision
            sourceFilename = prepared.request.snapshot.filename
            sourceSHA256 = prepared.sourceSHA256
            translationUnitSHA256 = prepared.translationUnitSHA256
            self.buildInputSHA256 = buildInputSHA256
            boardID = prepared.request.board.rawValue
            profile = prepared.request.profile.rawValue
            deviceID = prepared.request.resident.deviceID
            residentELFSHA256 = prepared.request.resident.residentELFSHA256
            firmwareImageSHA256 = prepared.request.resident.firmwareImageSHA256
            apiAddress = prepared.request.resident.apiAddress
            self.provenance = provenance
            self.linkedELFSHA256 = linkedELFSHA256
            self.capsuleSHA256 = capsuleSHA256
        }
    }
}
