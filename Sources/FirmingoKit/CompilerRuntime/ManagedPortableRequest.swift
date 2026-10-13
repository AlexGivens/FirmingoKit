import Foundation

/// Immutable portable input; physical associations and UInt64 revision arithmetic stay in Swift.
struct ManagedPortableRequest: Sendable {
    /// Unique runtime correlation, never a device identity or current address.
    let buildID: String
    /// Lossless ASCII token for document/revision, including UInt64.max.
    let revisionToken: String
    /// Exact original source snapshot for independent output checks.
    let snapshot: SketchSourceSnapshot
    /// Canonical closed compiler request bytes, supplied as a JavaScript argument.
    let json: Data
    /// Hash of the exact portable input, independently compared to the execution receipt.
    let requestSHA256: String
    /// Exact descriptor or minimal static binding identity, never fabricated firmware facts.
    let targetIdentity: String
    /// Selects the distinct identity field in the execution receipt.
    let targetIdentityKey: String
    /// Explicit static API binding used by independent capsule checks.
    let apiAddress: UInt32
    /// Exact declared resident ELF hash; it is not installed-image attestation.
    let residentELFSHA256: String
    /// Present only for supplied-ELF packaging; declarations never become pinned compile provenance.
    let packagingProvenance: ManagedELFProvenance?

    /// Converts legacy static requirements while keeping its device ID exclusively in Swift.
    init(_ request: ManagedSketchBuildRequest, provenance: ManagedELFProvenance? = nil) throws {
        let binding: [String: Any] = ["schema": 1, "board": request.board.rawValue, "profile": request.profile.rawValue,
            "residentELFSHA256": request.resident.residentELFSHA256, "firmwareImageSHA256": request.resident.firmwareImageSHA256,
            "apiAddress": request.resident.apiAddress, "residentABI": 1, "targetID": 1, "maximumCapsuleBytes": 4096]
        try self.init(snapshot: request.snapshot, target: binding, key: "residentBinding", apiAddress: request.resident.apiAddress,
                      residentELFSHA256: request.resident.residentELFSHA256, provenance: provenance)
    }
    /// Converts only the exact selected descriptor; no device placeholder reaches the compiler.
    init(_ request: ManagedOfflineBuildRequest, provenance: ManagedELFProvenance? = nil) throws {
        let firmware = request.firmwareBuild
        if let provenance {
            guard provenance.recipeIdentifier == firmware.recipeIdentifier, provenance.recipeSHA256 == firmware.recipeSHA256 else {
                throw SketchBuildError.invalidProvenance
            }
        }
        let descriptor: [String: Any] = ["schema": 1, "board": firmware.board.rawValue, "profile": firmware.profile.rawValue,
            "backend": "application", "firmwareVersion": firmware.firmwareVersion, "firmwareCommit": firmware.firmwareCommit,
            "residentELFSHA256": firmware.residentELFSHA256, "firmwareImageSHA256": firmware.firmwareImageSHA256,
            "buildReportSHA256": firmware.buildReportSHA256, "apiAddress": firmware.apiAddress, "residentABI": 1,
            "targetID": 1, "maximumCapsuleBytes": 4096, "recipeIdentifier": firmware.recipeIdentifier,
            "recipeSHA256": firmware.recipeSHA256, "qualification": firmware.qualification]
        try self.init(snapshot: request.snapshot, target: descriptor, key: "firmwareBuild", apiAddress: firmware.apiAddress,
                      residentELFSHA256: firmware.residentELFSHA256, provenance: provenance)
        guard targetIdentity == firmware.id else { throw SketchBuildError.invalidProvenance }
    }
    /// Serializes safe integers and source tokens; request identity includes explicit correlation/deadline.
    private init(snapshot: SketchSourceSnapshot, target: [String: Any], key: String, apiAddress: UInt32,
                 residentELFSHA256: String, provenance: ManagedELFProvenance?) throws {
        self.snapshot = snapshot; self.apiAddress = apiAddress; self.residentELFSHA256 = residentELFSHA256
        packagingProvenance = provenance
        buildID = UUID().uuidString; revisionToken = snapshot.documentID.uuidString + ":" + String(snapshot.revision)
        targetIdentityKey = key == "firmwareBuild" ? "firmwareBuildID" : "residentBindingID"
        targetIdentity = NanoManagedContract.digest(try Self.canonical(target))
        var input: [String: Any] = ["interfaceVersion": 1, "kind": provenance == nil ? "build" : "package_elf", "buildID": buildID,
            "source": ["filename": snapshot.filename, "revision": revisionToken, "text": snapshot.source],
            "target": ["board": FirmingoBoard.nanoRP2040Connect.rawValue, "profile": "nano-managed-v1",
                "recipeIdentifier": provenance?.recipeIdentifier ?? ManagedCompilerResourceInventory.recipeIdentifier,
                "recipeSHA256": provenance?.recipeSHA256 ?? ManagedCompilerResourceInventory.recipeSHA256, key: target],
            "options": ["deadlineMilliseconds": 60000]]
        if let provenance {
            input["provenance"] = ["compiler": provenance.compiler, "recipeIdentifier": provenance.recipeIdentifier,
                "recipeSHA256": provenance.recipeSHA256, "toolchainSHA256": provenance.toolchainSHA256]
        }
        json = try Self.canonical(input)
        requestSHA256 = NanoManagedContract.digest(json)
    }
    /// Compact sorted UTF-8 JSON matches the compiler's canonical identity for this closed data.
    static func canonical(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
