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

    /// Versioned offline receipt, including all original source identities for interface-two bundles.
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
        /// Digest over the primary and ordered helper path/hash records for a bundle.
        public let sourceBundleSHA256: String?
        /// Original helper path/hash records. This field is absent for single-file builds.
        public let sourceFiles: [SourceFile]?
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

        /// Original immutable helper identity retained in a build receipt.
        public struct SourceFile: Encodable, Equatable, Sendable {
            /// Portable path used by diagnostics and receipt metadata.
            public let path: String
            /// SHA-256 over exact original UTF-8 bytes.
            public let sha256: String

            /// Forms the canonical representation used by the portable request/receipt contract.
            var fields: [String: String] { ["path": path, "sha256": sha256] }
        }

        /// Hashes original helper bytes in the snapshot's portable order.
        static func identities(_ snapshot: SketchSourceSnapshot) -> [SourceFile] {
            snapshot.files.map { SourceFile(path: $0.path, sha256: NanoManagedContract.digest(Data($0.source.utf8))) }
        }

        /// Independently hashes the same path/hash array as the portable interface.
        static func bundleDigest(primary: SourceFile, helpers: [SourceFile]) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: ([primary] + helpers).map(\.fields),
                options: [.sortedKeys, .withoutEscapingSlashes])
            return NanoManagedContract.digest(data)
        }

        /// Records exact validated input/output fields, without inserting a device placeholder.
        init(prepared: PreparedManagedOfflineSketch, provenance: ManagedELFProvenance,
             linkedELFSHA256: String, capsuleSHA256: String) throws {
            let request = prepared.request
            let helpers = Self.identities(request.snapshot)
            version = helpers.isEmpty ? 1 : 2
            documentID = request.snapshot.documentID; sourceRevision = request.snapshot.revision
            sourceFilename = request.snapshot.filename; sourceSHA256 = prepared.sourceSHA256
            sourceFiles = helpers.isEmpty ? nil : helpers
            sourceBundleSHA256 = helpers.isEmpty ? nil :
                try Self.bundleDigest(primary: .init(path: sourceFilename, sha256: sourceSHA256), helpers: helpers)
            translationUnitSHA256 = prepared.translationUnitSHA256; catalogueSHA256 = request.catalogueSHA256
            firmwareBuildID = request.firmwareBuild.id; boardID = request.firmwareBuild.board.rawValue
            profile = request.firmwareBuild.profile.rawValue; self.provenance = provenance
            self.linkedELFSHA256 = linkedELFSHA256; self.capsuleSHA256 = capsuleSHA256
            var inputs: [String: Any] = ["version": version, "documentID": documentID.uuidString,
                "sourceRevision": sourceRevision, "sourceFilename": sourceFilename, "sourceSHA256": sourceSHA256,
                "translationUnitSHA256": translationUnitSHA256, "catalogueSHA256": catalogueSHA256,
                "firmwareBuildID": firmwareBuildID, "boardID": boardID, "profile": profile,
                "provenance": ["compiler": provenance.compiler, "recipeIdentifier": provenance.recipeIdentifier,
                    "recipeSHA256": provenance.recipeSHA256, "toolchainSHA256": provenance.toolchainSHA256]]
            if let sourceBundleSHA256, let sourceFiles {
                inputs["sourceBundleSHA256"] = sourceBundleSHA256
                inputs["sourceFiles"] = sourceFiles.map(\.fields)
            }
            buildInputSHA256 = NanoManagedContract.digest(try JSONSerialization.data(withJSONObject: inputs,
                options: [.sortedKeys, .withoutEscapingSlashes]))
        }
    }
}
