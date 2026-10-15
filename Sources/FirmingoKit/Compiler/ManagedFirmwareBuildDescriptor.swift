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
    /// Exact ABI-two volatile state contract; nil for the unchanged ABI-one descriptor schema.
    public let state: ManagedResidentState?
    /// Experimental status; catalogue input cannot promote this SDK recipe to hardware-qualified support.
    public let qualification = "experimental"

    /// Validates a closed schema-one (ABI one) or schema-two (ABI two) descriptor of at most 4096 bytes. Fields are documented in
    /// the catalogue guide. Only reviewed Nano application targets and their exact pinned Clang recipes pass;
    /// no metadata constructor authenticates a publisher, reads an ELF or attests installed firmware.
    public init(recordJSON: Data) throws {
        do { try self.init(value: WireJSON.parse(recordJSON, maximumBytes: 4096)) }
        catch { throw ManagedCatalogueError.invalidDescriptor }
    }

    /// Applies the same exact schema when a descriptor is nested in a verified catalogue.
    init(value: WireJSON.Value) throws {
        var names = ["schema", "board", "profile", "backend", "firmwareVersion", "firmwareCommit", "residentELFSHA256",
                     "firmwareImageSHA256", "buildReportSHA256", "apiAddress", "residentABI", "targetID", "maximumCapsuleBytes",
                     "recipeIdentifier", "recipeSHA256", "qualification"]
        guard let selectedProfile = ManagedSketchBuildRequest.Profile(rawValue: try value.required("profile").string()) else { throw ManagedCatalogueError.invalidDescriptor }
        let stateful = selectedProfile == .nanoManagedV2
        if stateful { names += ["stateAddress", "stateCapacityBytes", "compilerContractSHA256"] }
        guard Set(try value.object().keys) == Set(names.map { Data($0.utf8) }),
              try value.required("schema").uint32() == (stateful ? 2 : 1),
              try value.required("board").string() == FirmingoBoard.nanoRP2040Connect.rawValue,
              try value.required("profile").string() == selectedProfile.rawValue,
              try value.required("backend").string() == "application",
              try value.required("residentABI").uint32() == (stateful ? 2 : 1),
              try value.required("targetID").uint32() == selectedProfile.targetID,
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
              recipe == (stateful ? "nano-stateful-clang-22.1.8-v1-experimental" : "nano-stateless-clang-22.1.8-v1-experimental"),
              recipeHash == (stateful ? "25def36c701dd5e527ba128215deb3f87c158e1c6eb6eb2fa7fd106b5f543868" : "b7869f6fc863e1905deb6974408c6e7dc63943a1fb3e342a357fdf757b1e23d9") else {
            throw ManagedCatalogueError.invalidDescriptor
        }
        if stateful {
            guard try value.required("compilerContractSHA256").string() == ManagedResidentState.compilerContractSHA256 else { throw ManagedCatalogueError.invalidDescriptor }
            state = try ManagedResidentState(address: value.required("stateAddress").uint32(), capacityBytes: value.required("stateCapacityBytes").uint32())
        } else { state = nil }
        board = .nanoRP2040Connect; profile = selectedProfile
        firmwareVersion = version; firmwareCommit = commit; residentELFSHA256 = elf
        firmwareImageSHA256 = image; buildReportSHA256 = report; apiAddress = address
        recipeIdentifier = recipe; recipeSHA256 = recipeHash
        var fields: [String: Any] = ["schema": stateful ? 2 : 1, "board": board.rawValue, "profile": profile.rawValue,
            "backend": "application", "firmwareVersion": version, "firmwareCommit": commit,
            "residentELFSHA256": elf, "firmwareImageSHA256": image, "buildReportSHA256": report,
            "apiAddress": address, "residentABI": stateful ? 2 : 1, "targetID": selectedProfile.targetID,
            "maximumCapsuleBytes": NanoManagedContract.maximumSize, "recipeIdentifier": recipe,
            "recipeSHA256": recipeHash, "qualification": qualification]
        if let state {
            fields["stateAddress"] = state.address; fields["stateCapacityBytes"] = state.capacityBytes
            fields["compilerContractSHA256"] = ManagedResidentState.compilerContractSHA256
        }
        id = NanoManagedContract.digest(try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes]))
    }
}
