import Foundation

/// Immutable device-independent metadata for one experimental Nano resident build and compatible recipe.
/// Catalogue integrity validates these declarations, not the source build, installed bytes or executable ABI.
/// There is no physical device ID, default API address, compiler invocation or upload permission in this value.
public struct ManagedFirmwareBuildDescriptor: Equatable, Sendable, Identifiable {
    /// Content identity of every descriptor field, independent of JSON whitespace and key ordering.
    public let id: String
    /// Explicit board; currently only the experimental Nano managed contract is accepted.
    public let board: FirmingoBoard
    /// Capsule profile, distinct from the complete-image application/UART profile.
    public let profile: ManagedSketchBuildRequest.Profile
    /// Resident version label retained as provenance; never used to identify installed image bytes.
    public let firmwareVersion: String
    /// Declared firmware source commit, separate from complete compiled-image identity.
    public let firmwareCommit: String
    /// Exact resident ELF digest from trusted build evidence.
    public let residentELFSHA256: String
    /// Exact complete installed-image candidate; composite and resident-only images have different hashes.
    public let firmwareImageSHA256: String
    /// Digest of the independent resident build report; declaration alone does not validate that report.
    public let buildReportSHA256: String
    /// Four-byte-aligned API table address from this exact resident ELF.
    public let apiAddress: UInt32
    /// Exact compatible SDK recipe; it does not claim the resident was built using that recipe.
    public let recipeIdentifier: String
    /// Compatible recipe manifest digest, covering facade, arguments and linker policy.
    public let recipeSHA256: String
    /// Experimental status; catalogue input cannot promote this SDK recipe to hardware-qualified support.
    public let qualification = "experimental"

    /// Validates one closed schema-one descriptor of at most 4096 bytes. Required fields are documented in
    /// the catalogue guide. Only the current Nano ABI-one/application target and pinned Clang recipe pass;
    /// no metadata constructor authenticates a publisher, reads an ELF or attests installed firmware.
    public init(recordJSON: Data) throws {
        do { try self.init(value: WireJSON.parse(recordJSON, maximumBytes: 4096)) }
        catch { throw ManagedCatalogueError.invalidDescriptor }
    }

    /// Applies the same exact schema when a descriptor is nested in a verified catalogue.
    init(value: WireJSON.Value) throws {
        let names = ["schema", "board", "profile", "backend", "firmwareVersion", "firmwareCommit", "residentELFSHA256",
                     "firmwareImageSHA256", "buildReportSHA256", "apiAddress", "residentABI", "targetID", "maximumCapsuleBytes",
                     "recipeIdentifier", "recipeSHA256", "qualification"]
        guard Set(try value.object().keys) == Set(names.map { Data($0.utf8) }),
              try value.required("schema").uint32() == 1,
              try value.required("board").string() == FirmingoBoard.nanoRP2040Connect.rawValue,
              try value.required("profile").string() == ManagedSketchBuildRequest.Profile.nanoManagedV1.rawValue,
              try value.required("backend").string() == "application",
              try value.required("residentABI").uint32() == 1,
              try value.required("targetID").uint32() == NanoManagedContract.targetID,
              try value.required("maximumCapsuleBytes").uint32() == NanoManagedContract.maximumSize,
              try value.required("qualification").string() == "experimental" else {
            throw ManagedCatalogueError.invalidDescriptor
        }
        let version = try value.required("firmwareVersion").string()
        let commit = try value.required("firmwareCommit").string()
        let elf = try value.required("residentELFSHA256").string()
        let image = try value.required("firmwareImageSHA256").string()
        let report = try value.required("buildReportSHA256").string()
        let address = try value.required("apiAddress").uint32()
        let recipe = try value.required("recipeIdentifier").string()
        let recipeHash = try value.required("recipeSHA256").string()
        guard !version.isEmpty, version.utf8.count <= 64,
              version.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }),
              NanoManagedContract.isHex(commit, bytes: 20), NanoManagedContract.isHex(elf, bytes: 32),
              NanoManagedContract.isHex(image, bytes: 32), NanoManagedContract.isHex(report, bytes: 32),
              (0x10000000..<0x10200000).contains(address), address % 4 == 0,
              recipe == "nano-stateless-clang-22.1.8-v1-experimental",
              recipeHash == "b7869f6fc863e1905deb6974408c6e7dc63943a1fb3e342a357fdf757b1e23d9" else {
            throw ManagedCatalogueError.invalidDescriptor
        }
        board = .nanoRP2040Connect; profile = .nanoManagedV1
        firmwareVersion = version; firmwareCommit = commit; residentELFSHA256 = elf
        firmwareImageSHA256 = image; buildReportSHA256 = report; apiAddress = address
        recipeIdentifier = recipe; recipeSHA256 = recipeHash
        let fields: [String: Any] = ["schema": 1, "board": board.rawValue, "profile": profile.rawValue,
            "backend": "application", "firmwareVersion": version, "firmwareCommit": commit,
            "residentELFSHA256": elf, "firmwareImageSHA256": image, "buildReportSHA256": report,
            "apiAddress": address, "residentABI": 1, "targetID": NanoManagedContract.targetID,
            "maximumCapsuleBytes": NanoManagedContract.maximumSize, "recipeIdentifier": recipe,
            "recipeSHA256": recipeHash, "qualification": qualification]
        id = NanoManagedContract.digest(try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes]))
    }
}
