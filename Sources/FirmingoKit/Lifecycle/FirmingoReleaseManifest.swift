import Foundation

/// A bounded, locally parsed unsigned schema-one release index, supplied by a trusted host source.
/// The SDK checks consistency, not publisher authenticity. The host must establish trust before
/// passing bytes; a HTTPS URL or matching checksum alone does not authenticate the publisher.
public struct FirmingoReleaseManifest: Sendable {
    /// Host-declared manifest location for provenance; parsing never fetches it.
    public let source: URL
    /// Digest of the exact manifest bytes, including whitespace, for acquisition receipts.
    public let sha256: String
    /// Reviewed release version; currently only 0.1.0 is accepted.
    public let version: String
    /// Reviewed distribution channel, currently beta.
    public let releaseChannel: String
    /// Immutable exact board/profile entries. No image bytes are bundled or downloaded.
    public let files: [Entry]

    /// Manifest metadata identifying one complete Firmingo image, distinct from a managed capsule.
    public struct Entry: Sendable {
        /// Validated package-relative ASCII path; never a filesystem authorization.
        public let path: String
        /// Manifest board identity checked against its explicit recipe.
        public let board: FirmingoBoard
        /// Application or UART firmware profile; also the expected hello backend.
        public let profile: FirmingoDevice.Backend
        /// Exact reviewed firmware version from this release.
        public let firmwareVersion: String
        /// Complete UF2 file size, including block headers and padding.
        public let byteCount: Int
        /// Whole-file SHA-256 required before format validation.
        public let sha256: String
        /// Exact board/core/options build selection from the selected baseline.
        public let fqbn: String
        /// Build-reported flash usage, distinct from the UF2 payload address extent.
        public let flashBytes: UInt32
        /// Build-reported static RAM usage; this does not measure runtime heap/stack use.
        public let staticRAMBytes: UInt32
        /// Upstream evidence level, currently compile-tested, never SDK hardware qualification.
        public let qualification: String
        /// Digest of the upstream build report; that report is not present or authenticated here.
        public let buildReportSHA256: String

        /// Checks the pinned release generator's exact fields and board mapping.
        fileprivate init(_ value: WireJSON.Value, version: String) throws {
            guard Set(try value.object().keys) == Set([
                "path", "board_id", "profile", "firmware_version", "bytes", "sha256", "fqbn",
                "flash_bytes", "static_ram_bytes", "qualification", "build_report_sha256"
            ].map { Data($0.utf8) }),
                  let board = FirmingoBoard(rawValue: try value.required("board_id").string()),
                  let profile = FirmingoDevice.Backend(rawValue: try value.required("profile").string()) else {
                throw FirmwareLifecycleError.invalidManifest("unsupported file fields, board, or profile")
            }
            let path = try value.required("path").string()
            let size = try value.required("bytes").uint32()
            let digest = try value.required("sha256").string()
            let reportDigest = try value.required("build_report_sha256").string()
            let fqbn = try value.required("fqbn").string()
            let flash = try value.required("flash_bytes").uint32()
            let ram = try value.required("static_ram_bytes").uint32()
            let qualification = try value.required("qualification").string()
            let expectedPath = "\(board.rawValue)/\(profile.rawValue)/firmingo-\(version)-\(board.rawValue)-\(profile.rawValue).uf2"
            guard path == expectedPath, try value.required("firmware_version").string() == version,
                  size >= 512, size <= FirmwareReleaseContract.maximumImageBytes, size % 512 == 0,
                  FirmwareReleaseContract.isDigest(digest), FirmwareReleaseContract.isDigest(reportDigest),
                  fqbn == FirmwareReleaseContract.fqbn(for: board),
                  flash > 0, flash <= FirmwareReleaseContract.maximumFlash,
                  ram > 0, ram <= FirmwareReleaseContract.maximumStaticRAM,
                  qualification == "compile-tested" else {
                throw FirmwareLifecycleError.invalidManifest("incompatible file metadata or board recipe")
            }
            self.path = path
            self.board = board
            self.profile = profile
            firmwareVersion = version
            byteCount = Int(size)
            sha256 = digest
            self.fqbn = fqbn
            flashBytes = flash
            staticRAMBytes = ram
            self.qualification = qualification
            buildReportSHA256 = reportDigest
        }
    }

    /// Parses at most 16 KiB / 1024 JSON tokens with unique decoded keys and at most four entries.
    /// Only reviewed 0.1.0 beta schema-one metadata is accepted. Unknown fields, including signature
    /// metadata, require a reviewed verifier/schema update and are rejected rather than ignored.
    /// The source must be HTTPS or a local file URL without credentials, query, or fragment.
    /// Throws ``FirmwareLifecycleError``; this method performs no I/O or device operation.
    public init(data: Data, trustedSource source: URL) throws {
        guard source.absoluteString.utf8.count <= 2048,
              source.user == nil, source.password == nil, source.query == nil, source.fragment == nil,
              (source.scheme == "https" && source.host?.isEmpty == false) ||
              (source.isFileURL && (source.host == nil || source.host == "" || source.host == "localhost")) else {
            throw FirmwareLifecycleError.invalidManifest("a trusted HTTPS or local file source is required")
        }
        do {
            let root = try WireJSON.parse(data, maximumBytes: 16384, maximumTokens: 1024)
            guard Set(try root.object().keys) == Set([
                "schema_version", "product", "version", "release_channel", "artifact_format", "files"
            ].map { Data($0.utf8) }),
                  try root.required("schema_version").uint32() == 1,
                  try root.required("product").string() == "Firmingo",
                  try root.required("version").string() == "0.1.0",
                  try root.required("release_channel").string() == "beta",
                  try root.required("artifact_format").string() == "UF2" else {
                throw FirmwareLifecycleError.invalidManifest("unsupported release schema or version")
            }
            let values = try root.required("files").array()
            guard (1...4).contains(values.count) else {
                throw FirmwareLifecycleError.invalidManifest("one through four files are required")
            }
            let files = try values.map { try Entry($0, version: "0.1.0") }
            guard Set(files.map(\.path)).count == files.count else {
                throw FirmwareLifecycleError.invalidManifest("duplicate board/profile entries")
            }
            self.source = source
            sha256 = FirmwareReleaseContract.digest(data)
            version = "0.1.0"
            releaseChannel = "beta"
            self.files = files
        } catch let error as FirmwareLifecycleError {
            throw error
        } catch {
            throw FirmwareLifecycleError.invalidManifest("malformed or incomplete JSON")
        }
    }

    /// Finds an exact board/profile selection, never falling back to another board or firmware.
    public func entry(for board: FirmingoBoard, profile: FirmingoDevice.Backend) throws -> Entry {
        guard let entry = files.first(where: { $0.board == board && $0.profile == profile }) else {
            throw FirmwareLifecycleError.missingArtifact
        }
        return entry
    }
}
