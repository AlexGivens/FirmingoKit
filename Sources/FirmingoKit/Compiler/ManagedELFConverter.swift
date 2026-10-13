import Foundation

/// Packages independently linked Nano stateless ELF code as FMS1; it never compiles, connects or uploads.
/// Hosts must establish that the ELF was built from this prepared revision, recipe and resident API address.
/// ELF metadata and a self-supplied receipt cannot prove that association or instruction/ABI compatibility.
public enum ManagedELFConverter {
    /// Validates the pinned module.ld layout and defined Thumb wrappers, serializes FMS1, and checks its
    /// report through the independent capsule validator. Rejects conventional UF2/full-firmware ELF,
    /// globals/runtime initialization, unresolved symbols, relocations and unsupported layout.
    /// Input ELF is limited to 2 MiB; code is 4–3840 bytes. Work runs off the main actor with cancellation
    /// checks. A result establishes structural packaging only; trusted code/hardware qualification is separate.
    /// Parsing/packaging runs in the verified shared compiler's private WebKit worker with no WASM service.
    /// A missing/corrupt source package or unavailable web host fails explicitly; there is no native fallback.
    @concurrent public static func convert(_ elfData: Data, prepared: PreparedManagedSketch,
                                          provenance: ManagedELFProvenance) async throws -> ManagedSketchArtifact {
        try Task.checkCancellation()
        let resident = prepared.request.resident
        let package = try await packageELF(elfData, request: ManagedPortableRequest(prepared.request, provenance: provenance),
            sourceSHA256: prepared.sourceSHA256, translationUnitSHA256: prepared.translationUnitSHA256)
        let validated = try ManagedCapsule(bytes: package.payload.bytes, reportJSON: package.reportJSON, resident: resident)
        let capsuleHash = package.payload.sha256
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let identity = InputIdentity(prepared: prepared, provenance: provenance)
        let receipt = ManagedSketchArtifact.Receipt(prepared: prepared, provenance: provenance,
            buildInputSHA256: NanoManagedContract.digest(try encoder.encode(identity)),
            linkedELFSHA256: NanoManagedContract.digest(elfData), capsuleSHA256: capsuleHash)
        try Task.checkCancellation()
        return ManagedSketchArtifact(capsule: validated, filename: String(prepared.request.snapshot.filename.dropLast(4)) + ".fms",
                                     reportJSON: package.reportJSON, receipt: receipt)
    }

    /// Packages independently linked source for an exact catalogue firmware build without a device ID.
    /// Requires matching descriptor/recipe identity; throws invalidProvenance otherwise. ELF, FMS1 and report
    /// validation match the legacy overload; conversion is off-main-actor and cancellable. Declared provenance
    /// does not prove assets or source association; the real compiler overload establishes its runtime inputs.
    @concurrent public static func convert(_ elfData: Data, prepared: PreparedManagedOfflineSketch,
                                          provenance: ManagedELFProvenance) async throws -> ManagedOfflineSketchArtifact {
        try Task.checkCancellation()
        let firmware = prepared.request.firmwareBuild
        guard provenance.recipeIdentifier == firmware.recipeIdentifier, provenance.recipeSHA256 == firmware.recipeSHA256 else {
            throw SketchBuildError.invalidProvenance
        }
        let package = try await packageELF(elfData, request: ManagedPortableRequest(prepared.request, provenance: provenance),
            sourceSHA256: prepared.sourceSHA256, translationUnitSHA256: prepared.translationUnitSHA256)
        let artifact = try ManagedOfflineSketchArtifact(bytes: package.payload.bytes, sha256: package.payload.sha256,
            reportJSON: package.reportJSON, prepared: prepared, provenance: provenance, linkedELFSHA256: package.linkedELFSHA256)
        try Task.checkCancellation()
        return artifact
    }

    /// Loads verified compiler sources and delegates ELF parsing/packaging to its isolated service-free worker.
    private static func packageELF(_ elf: Data, request: ManagedPortableRequest, sourceSHA256: String,
                                   translationUnitSHA256: String) async throws -> ManagedPortablePackaging {
        try Task.checkCancellation()
        guard (52...2 * 1024 * 1024).contains(elf.count) else { throw SketchBuildError.invalidELF("Expected bounded independently linked ELF bytes") }
        let resources = try await VerifiedManagedResources.load()
        let host = await ManagedWebKitHost()
        let json = try await host.package(elf: elf, request: request, page: resources.page)
        return try await ManagedPortablePackaging.decode(json, request: request, elf: elf,
            sourceSHA256: sourceSHA256, translationUnitSHA256: translationUnitSHA256)
    }

    /// Reuses the unchanged legacy receipt identity for already independently validated compiler output.
    static func receiptInputSHA256(prepared: PreparedManagedSketch, provenance: ManagedELFProvenance) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return NanoManagedContract.digest(try encoder.encode(InputIdentity(prepared: prepared, provenance: provenance)))
    }
    /// Serializes all current build-affecting inputs deterministically; no cache or stale artifact reuse exists.
    private struct InputIdentity: Encodable {
        /// Original document identity/revision/name, preventing silent reuse for another edit.
        let documentID: UUID
        /// Original revision, even when normalized generated text is equal.
        let revision: UInt64
        /// Original filename influencing diagnostics and preprocessing.
        let filename: String
        /// Exact original source digest.
        let sourceSHA256: String
        /// Exact compiler-input digest.
        let translationUnitSHA256: String
        /// Explicit board ID.
        let boardID: String
        /// Artifact and ABI profile.
        let profile: String
        /// Host-associated resident identity and hashes.
        let deviceID: String
        /// Exact resident ELF, covering ABI table contents.
        let residentELFSHA256: String
        /// Host-known complete firmware image.
        let firmwareImageSHA256: String
        /// Address used by the declared module recipe.
        let apiAddress: UInt32
        /// Compiler, recipe and verified asset manifest identity.
        let provenance: ManagedELFProvenance
        /// Captures only validated immutable inputs; future recipe/options must extend this schema.
        init(prepared: PreparedManagedSketch, provenance: ManagedELFProvenance) {
            documentID = prepared.request.snapshot.documentID; revision = prepared.request.snapshot.revision
            filename = prepared.request.snapshot.filename; sourceSHA256 = prepared.sourceSHA256
            translationUnitSHA256 = prepared.translationUnitSHA256; boardID = prepared.request.board.rawValue
            profile = prepared.request.profile.rawValue; deviceID = prepared.request.resident.deviceID
            residentELFSHA256 = prepared.request.resident.residentELFSHA256
            firmwareImageSHA256 = prepared.request.resident.firmwareImageSHA256
            apiAddress = prepared.request.resident.apiAddress; self.provenance = provenance
        }
    }
}
