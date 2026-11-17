import Foundation

/// One reviewed Nano FMS2 initial/recovery image and its post-boot verification contract.
public struct ManagedROMInstall: Sendable {
    /// Filename of the reviewed distributable and app-cache image.
    public static let filename = "Firmingo-Nano-FMS2-1.0.0-rc.1.uf2"
    /// Reviewed composite digest. The resident-only UF2 has a different identity.
    public static let imageSHA256 = "5fdb0ed35ed5f68b357a01351f32ed11480679cb868ad593af3d05d00c7e90af"
    /// Exact bundled SDK descriptor associated with the reviewed resident within the composite.
    public static let firmwareBuildID = "33a0e866c2873b20aaf9303dc10c7af4d6920e99bb1ba2eee6b0c009034523b5"
    /// Expected version reported by the running resident.
    public static let firmwareVersion = "1.0.0-rc.1"
    /// Bound on a complete image read.
    public static let imageBytes = 316_416
    /// Validated composite bytes for the selected ROM volume.
    public let bytes: Data

    /// Verifies the independently pinned bytes and the disjoint resident/managed-sector layout before handoff.
    public init(bytes: Data) throws {
        guard bytes.count == Self.imageBytes, FirmwareReleaseContract.digest(bytes) == Self.imageSHA256 else {
            throw FirmwareLifecycleError.invalidImage("select the reviewed Nano FMS2 initial image")
        }
        try UF2ImageLayout.validateManagedInitial(bytes: bytes, residentBlocks: 602)
        self.bytes = bytes
    }

    /// Reads only a bounded, explicitly selected local image. The host owns security-scoped access.
    @concurrent public static func load(from url: URL) async throws -> Self {
        try Task.checkCancellation()
        guard url.isFileURL else { throw FirmwareLifecycleError.missingArtifact }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == imageBytes else {
            throw FirmwareLifecycleError.invalidImage("expected one regular reviewed Nano UF2")
        }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var bytes = Data()
        while bytes.count <= imageBytes {
            try Task.checkCancellation()
            guard let chunk = try input.read(upToCount: min(32 * 1024, imageBytes + 1 - bytes.count)),
                  !chunk.isEmpty else { break }
            bytes.append(chunk)
        }
        return try Self(bytes: bytes)
    }

    /// Observed functional evidence from a fresh session. It does not attest physical flash bytes.
    public struct Observation: Sendable {
        /// Device and boot reporting the expected resident and responding to its installation sketch probe.
        public let device: FirmingoDevice
    }

    /// Durable context for an explicit ROM install. Restoring a dispatched attempt grants no write authority.
    public struct Record: Codable, Equatable, Sendable {
        /// Local record format, independent of the firmware release version.
        public let schema: UInt32
        /// Correlates one user-directed attempt to the reviewed association.
        public let operationID: UUID
        /// Pins the complete composite selected for this attempt.
        public let imageSHA256: String
        /// Pins the resident descriptor within the image.
        public let firmwareBuildID: String
        /// Optional identity the operator explicitly selected for an existing device.
        public let expectedDeviceID: String?
        /// Previous boot, when observed for that same device before the handoff.
        public let previousBootID: String?
        /// True when the user starts a new attempt to recover Firmingo.
        public let recovery: Bool
        /// Operator's report of the external copy. It does not establish that a write succeeded.
        public private(set) var copyReported: Bool
        /// Presence records durable authorization immediately before the one filesystem write attempt.
        public private(set) var writeDispatched: Bool?
        /// Recorded functional observation after the user reviewed and associated the device.
        public private(set) var observedDeviceID: String?
        /// Running boot accepted when the user reviewed and associated the device.
        public private(set) var observedBootID: String?
        /// This operation may be checked without issuing another write.
        public var mayVerify: Bool { copyReported || writeDispatched == true }

        /// Captures exact candidate selection with no automatic file or device activity.
        public init(recovery: Bool, expectedDeviceID: String? = nil, previousBootID: String? = nil) throws {
            schema = 2; operationID = UUID()
            imageSHA256 = ManagedROMInstall.imageSHA256; firmwareBuildID = ManagedROMInstall.firmwareBuildID
            self.recovery = recovery; self.expectedDeviceID = expectedDeviceID; self.previousBootID = previousBootID
            copyReported = false
            try validate()
        }
        /// Bounds the shape and exact reviewed candidate before any restored operation can be acted upon.
        public func validate() throws {
            guard [1, 2].contains(schema), imageSHA256 == ManagedROMInstall.imageSHA256,
                  firmwareBuildID == ManagedROMInstall.firmwareBuildID,
                  (observedBootID == nil) == (observedDeviceID == nil),
                  observedDeviceID == nil || mayVerify,
                  writeDispatched == nil || (writeDispatched == true && !copyReported),
                  previousBootID == nil || expectedDeviceID != nil,
                  previousBootID == nil || observedBootID == nil || previousBootID != observedBootID,
                  expectedDeviceID == nil || observedDeviceID == nil || expectedDeviceID == observedDeviceID,
                  [expectedDeviceID, previousBootID, observedDeviceID, observedBootID].compactMap({ $0 })
                    .allSatisfy({ NanoManagedContract.isHex($0, bytes: 8) }) else {
                throw FirmingoError.protocolViolation("Invalid or incompatible Files installation record")
            }
        }
        /// Records the user's copy report without granting a managed device association.
        public mutating func reportCopy() throws {
            try validate()
            guard !mayVerify else { throw FirmingoError.protocolViolation("An installation attempt was already recorded") }
            copyReported = true
        }
        /// Consumes the write opportunity for this attempt before any possible flash change.
        mutating func dispatchWrite() throws {
            try validate()
            guard !mayVerify else { throw FirmingoError.protocolViolation("An installation attempt was already recorded") }
            writeDispatched = true
        }
        /// Records a reviewed post-copy observation and derives its exact SDK association.
        public mutating func associate(_ observation: Observation) throws -> ManagedDeviceAssociation {
            try validate()
            let device = observation.device
            guard mayVerify, observedDeviceID == nil, expectedDeviceID == nil || expectedDeviceID == device.deviceID else {
                throw FirmingoError.protocolViolation("Files installation evidence is missing or selects a different Nano")
            }
            try ManagedROMInstall.check(device, previousBootID: previousBootID)
            let association = try ManagedDeviceAssociation(deviceID: device.deviceID, firmwareBuildID: firmwareBuildID,
                evidence: .reviewedInstallationRecord, installationOperationID: operationID)
            observedDeviceID = device.deviceID; observedBootID = device.bootID
            return association
        }
    }

    /// Verifies an explicitly selected Nano after a user-directed copy. The physical model and copy
    /// are user-confirmed. A matching hello and live echo establish observed functionality.
    public static func observe(at endpoint: FirmingoEndpoint, expectedDeviceID: String? = nil,
                               previousBootID: String? = nil) async throws -> Observation {
        let session = try await FirmingoSession.connect(to: endpoint, expectedBoard: .nanoRP2040Connect,
                                                        expectedBackend: .application, expectedDeviceID: expectedDeviceID)
        return try await observe(on: session, previousBootID: previousBootID)
    }

    /// Uses the same checked session for hello and all functional observations.
    static func observe(on session: FirmingoSession, previousBootID: String?) async throws -> Observation {
        do {
            let device = session.device
            try check(device, previousBootID: previousBootID)
            try await session.openConsole()
            let nonce = UInt8.random(in: .min ... .max)
            let state = try await exchange(Data([1, nonce]), count: 24, on: session)
            try checkStarter(state, nonce: nonce)
            let challenge = Data((UInt8.min...UInt8.max).shuffled())
            let reply = try await exchange(Data([2]) + challenge, count: challenge.count, on: session)
            guard reply == challenge else { throw FirmingoError.protocolViolation("The installation sketch did not return the exact challenge") }
            try await session.closeConsole()
            await session.disconnect()
            return Observation(device: device)
        } catch {
            await session.disconnect()
            throw error
        }
    }

    /// Sends a single bounded probe and consumes the exact reply within a finite deadline.
    private static func exchange(_ request: Data, count: Int, on session: FirmingoSession) async throws -> Data {
        try await session.sendSerial(request)
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                var bytes = Data()
                for try await part in session.serialBytes {
                    guard !part.isEmpty, part.count <= count - bytes.count else {
                        throw FirmingoError.protocolViolation("Invalid installation probe length")
                    }
                    bytes.append(part)
                    if bytes.count == count { return bytes }
                }
                throw FirmingoError.disconnected
            }
            group.addTask { try await Task.sleep(for: .seconds(5)); throw FirmingoError.timedOut }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw FirmingoError.disconnected }
            return value
        }
    }

    /// Confirms the starter's identity and initial state before using the binary echo command.
    static func checkStarter(_ bytes: Data, nonce: UInt8) throws {
        guard bytes.count == 24, bytes.prefix(4) == Data("FQ2A".utf8) else {
            throw FirmingoError.protocolViolation("The installed starter is unavailable or differs from the reviewed image")
        }
        let data = Array(bytes)
        let words = stride(from: 4, to: 24, by: 4).map { offset in
            data[offset..<offset + 4].reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        guard words[0] == UInt32(nonce), words[1] == 7, words[2] == 0,
              words[3] == 7 &+ words[4] else {
            throw FirmingoError.protocolViolation("The installed starter returned an invalid challenge or state")
        }
    }

    /// Checks candidate capabilities before opening the console; a known prior boot must have changed.
    static func check(_ device: FirmingoDevice, previousBootID: String?) throws {
        guard device.boardID == FirmingoBoard.nanoRP2040Connect.rawValue,
              device.firmwareVersion == firmwareVersion,
              device.bootID != previousBootID,
              device.targets.contains(where: {
                  $0.id == 2 && $0.format == "nano-managed-v2" && $0.maximumSize == 4096 &&
                  $0.maximumChunk == 1024 && $0.authorization == "physical-d2-gnd"
              }) else {
            throw FirmingoError.protocolViolation("Expected the reviewed Nano FMS2 resident on a fresh boot")
        }
    }
}
