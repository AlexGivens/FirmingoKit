import Foundation

/// Persistable observations for one full-image operation; it is never authority to resume or repeat a write.
/// Save each awaited installer record update durably, especially writeStarted before allowing transfer.
public struct FirmwareInstallationRecord: Codable, Equatable, Sendable {
    /// Local persistence schema, independent of the release and FMGO schemas.
    public let version: UInt32
    /// Opaque operation identity, unique for each newly prepared user action.
    public let operationID: UUID
    /// Host-confirmed board model, not an assertion inferred from the generic ROM volume.
    public let boardID: String
    /// Exact selected application/UART profile.
    public let profile: String
    /// Reviewed release version, currently 0.1.0.
    public let firmwareVersion: String
    /// Source retained for acquisition/recovery context, not authentication.
    public let releaseSource: URL
    /// Exact index digest from acquisition.
    public let manifestSHA256: String
    /// Complete UF2 digest; hello cannot attest it.
    public let imageSHA256: String
    /// Build-report provenance digest, retained without claiming verification of its contents.
    public let buildReportSHA256: String
    /// Complete image size including UF2 headers and padding.
    public let imageBytes: Int
    /// Backend namespace; restoring it does not recreate a backend or select a device.
    public let backendID: String
    /// Attachment observed before execution, invalid for restored/new programming authority.
    public let targetInstanceID: String
    /// Last selected mount, retained only as context and never automatically reused.
    public let targetMountURL: URL
    /// Last known operation boundary, deliberately separate from installed-image success.
    public let state: State
    /// Bytes known accepted by the host filesystem, not bytes verified on flash.
    public let transferredBytes: Int
    /// Optional hello-observed identity, self-reported rather than cryptographic attestation.
    public let observedDeviceID: String?
    /// Optional hello-observed boot, which does not by itself prove a post-transfer reboot.
    public let observedBootID: String?
    /// Bounded persisted error context; thrown errors retain the original underlying cause too.
    public let failureSummary: String?

    /// Saved board-specific next action; it never authorizes replay, resume, or automatic rollback.
    public var recoveryInstructions: String {
        guard let board = FirmingoBoard(rawValue: boardID) else {
            return "Review the saved operation and select a supported physical board before a new action."
        }
        return "Keep the saved artifact hashes and source. \(FirmingoInstallationPlan.romInstruction(for: board)) Select the physical target again, reacquire and validate the exact Firmingo image, and explicitly request a new full reinstall; never resume at a byte offset or automatically repeat this operation."
    }

    /// Observable lifecycle boundaries; no state claims exact-image attestation or useful behavior.
    public enum State: String, Codable, Sendable {
        /// Reviewable target-bound preparation; no write has been permitted.
        case prepared
        /// Persisted before the first device-changing action; restart means an uncertain outcome.
        case writeStarted
        /// Host transfer/synchronization/close completed; installation remains unverified.
        case transferComplete
        /// Transfer completed and a later hello matched the selected contract; exact image is unverified.
        case helloMatched
        /// Write was never permitted; a new preparation/action is required to attempt again.
        case failedBeforeWrite
        /// Flash may have changed; do not retry or resume automatically.
        case outcomeUnknown
    }

    /// Stable local persistence fields, never the firmware's wire schema.
    private enum CodingKeys: String, CodingKey {
        /// Schema and operation provenance keys.
        case version, operationID, boardID, profile, firmwareVersion, releaseSource, manifestSHA256
        /// Exact artifact and attachment context keys.
        case imageSHA256, buildReportSHA256, imageBytes, backendID, targetInstanceID, targetMountURL
        /// Observable outcome and optional diagnostic keys.
        case state, transferredBytes, observedDeviceID, observedBootID, failureSummary
    }

    /// Issues prepared context from immutable validated image metadata and an inspected selection.
    init(image: FirmingoFirmwareImage, volume: FirmwareBootloaderVolume) {
        version = 1
        operationID = UUID()
        boardID = image.entry.board.rawValue
        profile = image.entry.profile.rawValue
        firmwareVersion = image.entry.firmwareVersion
        releaseSource = image.releaseSource
        manifestSHA256 = image.manifestSHA256
        imageSHA256 = image.entry.sha256
        buildReportSHA256 = image.entry.buildReportSHA256
        imageBytes = image.bytes.count
        backendID = volume.backendID
        targetInstanceID = volume.instanceID
        targetMountURL = volume.mountURL
        state = .prepared
        transferredBytes = 0
        observedDeviceID = nil
        observedBootID = nil
        failureSummary = nil
    }
    /// Restores bounded context with strict known values; decoded records cannot recreate execution tokens.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        version = try fields.decode(UInt32.self, forKey: .version)
        operationID = try fields.decode(UUID.self, forKey: .operationID)
        boardID = try fields.decode(String.self, forKey: .boardID)
        profile = try fields.decode(String.self, forKey: .profile)
        firmwareVersion = try fields.decode(String.self, forKey: .firmwareVersion)
        releaseSource = try fields.decode(URL.self, forKey: .releaseSource)
        manifestSHA256 = try fields.decode(String.self, forKey: .manifestSHA256)
        imageSHA256 = try fields.decode(String.self, forKey: .imageSHA256)
        buildReportSHA256 = try fields.decode(String.self, forKey: .buildReportSHA256)
        imageBytes = try fields.decode(Int.self, forKey: .imageBytes)
        backendID = try fields.decode(String.self, forKey: .backendID)
        targetInstanceID = try fields.decode(String.self, forKey: .targetInstanceID)
        targetMountURL = try fields.decode(URL.self, forKey: .targetMountURL)
        state = try fields.decode(State.self, forKey: .state)
        transferredBytes = try fields.decode(Int.self, forKey: .transferredBytes)
        observedDeviceID = try fields.decodeIfPresent(String.self, forKey: .observedDeviceID)
        observedBootID = try fields.decodeIfPresent(String.self, forKey: .observedBootID)
        failureSummary = try fields.decodeIfPresent(String.self, forKey: .failureSummary)
        try validate()
    }
    /// Validates bounded persistence without treating source text or an attachment token as authorization.
    private func validate() throws {
        guard version == 1, FirmingoBoard(rawValue: boardID) != nil,
              FirmingoDevice.Backend(rawValue: profile) != nil, firmwareVersion == "0.1.0",
              FirmwareReleaseContract.isDigest(manifestSHA256), FirmwareReleaseContract.isDigest(imageSHA256),
              FirmwareReleaseContract.isDigest(buildReportSHA256),
              imageBytes >= 512, imageBytes <= FirmwareReleaseContract.maximumImageBytes, imageBytes % 512 == 0,
              (0...imageBytes).contains(transferredBytes),
              FirmwareBootloaderVolume.validToken(backendID, limit: 64),
              FirmwareBootloaderVolume.validToken(targetInstanceID, limit: 128),
              releaseSource.absoluteString.utf8.count <= 2048, releaseSource.user == nil, releaseSource.password == nil,
              releaseSource.query == nil, releaseSource.fragment == nil,
              (releaseSource.scheme == "https" && releaseSource.host?.isEmpty == false) ||
                  (releaseSource.isFileURL && [nil, "", "localhost"].contains(releaseSource.host) && !releaseSource.path.utf8.contains(0)),
              targetMountURL.isFileURL, targetMountURL.path.utf8.count <= 2048, !targetMountURL.path.utf8.contains(0),
              targetMountURL.user == nil, targetMountURL.password == nil,
              targetMountURL.host == nil || targetMountURL.host == "" || targetMountURL.host == "localhost",
              targetMountURL.query == nil, targetMountURL.fragment == nil,
              (state != .prepared && state != .failedBeforeWrite) || transferredBytes == 0,
              (state != .transferComplete && state != .helloMatched) || transferredBytes == imageBytes,
              (observedDeviceID == nil) == (observedBootID == nil),
              state != .helloMatched || observedDeviceID != nil,
              failureSummary.map({ $0.utf8.count <= 1024 && !$0.utf8.contains(0) }) ?? true else {
            throw FirmwareInstallationError.invalidRequest("invalid saved installation context")
        }
        if let observedDeviceID, let observedBootID {
            guard FirmwareReleaseContract.isIdentity(observedDeviceID),
                  FirmwareReleaseContract.isIdentity(observedBootID),
                  state == .helloMatched || state == .outcomeUnknown || state == .writeStarted else {
                throw FirmwareInstallationError.invalidRequest("invalid saved hello observation")
            }
        }
    }
    /// Copies bounded runtime observations while preserving immutable artifact/target provenance.
    func updated(state: State, transferredBytes: Int? = nil,
                 device: FirmingoDevice? = nil, failure: (any Error)? = nil) throws -> Self {
        let value = Self(original: self, state: state, transferredBytes: transferredBytes ?? self.transferredBytes,
                         device: device, failureSummary: failure.map { Self.boundedFailure($0.localizedDescription) })
        try value.validate()
        return value
    }
    /// Bounds persisted errors by UTF-8 bytes without splitting scalars or retaining NUL; grapheme clusters
    /// can contain arbitrarily many combining scalars, so a character-count prefix is insufficient.
    private static func boundedFailure(_ text: String) -> String {
        var result = ""
        var bytes = 0
        for scalar in text.unicodeScalars where scalar.value != 0 {
            let size = String(scalar).utf8.count
            guard bytes + size <= 1024 else { break }
            result.unicodeScalars.append(scalar)
            bytes += size
        }
        return result
    }
    /// Internal immutable copying initializer; updates always pass validation before publication.
    private init(original: Self, state: State, transferredBytes: Int, device: FirmingoDevice?, failureSummary: String?) {
        version = original.version
        operationID = original.operationID
        boardID = original.boardID
        profile = original.profile
        firmwareVersion = original.firmwareVersion
        releaseSource = original.releaseSource
        manifestSHA256 = original.manifestSHA256
        imageSHA256 = original.imageSHA256
        buildReportSHA256 = original.buildReportSHA256
        imageBytes = original.imageBytes
        backendID = original.backendID
        targetInstanceID = original.targetInstanceID
        targetMountURL = original.targetMountURL
        self.state = state
        self.transferredBytes = transferredBytes
        observedDeviceID = device?.deviceID ?? original.observedDeviceID
        observedBootID = device?.bootID ?? original.observedBootID
        self.failureSummary = failureSummary
    }
}
