import Darwin
import Foundation

extension ManagedROMInstall {
    /// Progress after validating the selected drive and durably recording the attempt.
    public enum InstallPhase: Sendable {
        /// The reviewed image is being written to the selected volume.
        case writing
        /// The host accepted the image; the ROM must detach and the starter must respond.
        case waitingForReboot
    }

    /// Writes the reviewed Nano image once to a directory selected in place by the system picker,
    /// then waits for ROM detachment and checks the running firmware and starter over USB Ethernet.
    /// The host must have the user select their single connected Nano in ROM mode. RP2040 ROM
    /// metadata identifies the chip family but exposes neither the board model nor its Firmingo ID.
    /// The host must atomically save the new record against the supplied record in saveWriteIntent.
    /// If an error follows that callback, the saved attempt can be verified or explicitly recovered.
    @concurrent public func install(in selectedFolder: URL, record: Record, at endpoint: FirmingoEndpoint,
                                   saveWriteIntent: @Sendable (Record) async throws -> Void,
                                   progress: @Sendable (InstallPhase) async -> Void = { _ in }) async throws -> Observation {
        try Task.checkCancellation()
        var dispatched = record
        try dispatched.dispatchWrite()
        let scoped = selectedFolder.startAccessingSecurityScopedResource()
        defer { if scoped { selectedFolder.stopAccessingSecurityScopedResource() } }
        let writeRecord = dispatched
        let attachment = try await ManagedROMVolume.program(bytes, in: selectedFolder) {
            try await saveWriteIntent(writeRecord)
            await progress(.writing)
        }
        await progress(.waitingForReboot)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(25))
        while try ManagedROMVolume.isMounted(selectedFolder, attachment: attachment) {
            guard clock.now < deadline else {
                throw FirmwareInstallationError.invalidRequest("the ROM drive did not detach after the transfer")
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        // Retry only hello while USB Ethernet is coming up. A console probe is sent on one checked session.
        while clock.now < deadline {
            let session: FirmingoSession
            do {
                session = try await FirmingoSession.connect(to: endpoint, expectedBoard: .nanoRP2040Connect,
                    expectedBackend: .application, expectedDeviceID: record.expectedDeviceID)
            } catch FirmingoError.transport {
                try await Task.sleep(for: .milliseconds(350))
                continue
            } catch FirmingoError.timedOut {
                continue
            } catch FirmingoError.disconnected {
                try await Task.sleep(for: .milliseconds(350))
                continue
            }
            return try await Self.observe(on: session, previousBootID: record.previousBootID)
        }
        throw FirmingoError.timedOut
    }
}

/// A system-mounted RP2040 ROM root, pinned for the duration of a single picker grant.
struct ManagedROMVolume: Equatable {
    /// Mount and directory identifiers measured through the opened descriptor.
    let device: dev_t
    /// Root inode on the selected mount.
    let inode: ino_t
    /// ROM information pinned at selection and checked again immediately before writing.
    let infoDigest: String

    /// Keeps the original directory descriptor open across admission and writes only through it.
    static func program(_ bytes: Data, in url: URL, admit: () async throws -> Void) async throws -> Self {
        let root = try openRoot(url)
        defer { _ = Darwin.close(root) }
        let attachment = try inspect(url, root: root)
        try await admit()
        try Task.checkCancellation()
        try write(bytes, to: url, root: root, attachment: attachment)
        return attachment
    }

    /// Verifies local mount type, volume root/name, and ROM markers on the same attachment.
    private static func inspect(_ url: URL, root: Int32) throws -> Self {
        var directory = stat()
        var mount = statfs()
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fstat(root, &directory) == 0, fstatfs(root, &mount) == 0,
              fcntl(root, F_GETPATH, &path) == 0 else { throw posixError() }
        let type = withUnsafeBytes(of: mount.f_fstypename) { decodeSystemString($0) }
        let mountPath = withUnsafeBytes(of: mount.f_mntonname) { decodeSystemString($0) }
        let realPath = path.withUnsafeBytes { decodeSystemString($0) }
        let values = try url.resourceValues(forKeys: [.volumeNameKey, .volumeIsInternalKey])
        guard realPath == mountPath, (mount.f_flags & UInt32(MNT_LOCAL)) != 0,
              type == "msdos" || type == "lifs", values.volumeName == "RPI-RP2", values.volumeIsInternal != true else {
            throw FirmwareInstallationError.invalidRequest("choose the root of the connected RPI-RP2 boot drive under Locations")
        }
        let info = try MacOSUF2ProgrammingBackend.readInfo(root: root)
        try MacOSUF2ProgrammingBackend.validateROMInfo(info)
        return Self(device: directory.st_dev, inode: directory.st_ino, infoDigest: FirmwareReleaseContract.digest(info))
    }

    /// Decodes a NUL-terminated filesystem field.
    private static func decodeSystemString(_ bytes: UnsafeRawBufferPointer) -> String {
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// Opens only the selected directory without following a final-component symlink.
    private static func openRoot(_ url: URL) throws -> Int32 {
        let path = url.path
        guard url.isFileURL, !path.utf8.contains(0) else { throw FirmwareInstallationError.targetChanged }
        let root = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw posixError() }
        return root
    }

    /// Writes one fixed name directly as ROM blocks. Coordination covers creation, flush and close.
    private static func write(_ bytes: Data, to url: URL, root: Int32, attachment: Self) throws {
        var coordinationError: NSError?
        var outcome: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            outcome = Result {
                guard try isMounted(coordinatedURL, attachment: attachment),
                      try inspect(coordinatedURL, root: root) == attachment else {
                    throw FirmwareInstallationError.targetChanged
                }
                try Task.checkCancellation()
                let file = openat(root, "FIRMINGO.UF2", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
                guard file >= 0 else { throw posixError() }
                do {
                    try bytes.withUnsafeBytes { source in
                        var offset = 0
                        while offset < source.count {
                            try Task.checkCancellation()
                            let count = Darwin.write(file, source.baseAddress?.advanced(by: offset),
                                                     min(65_536, source.count - offset))
                            if count < 0, errno == EINTR { continue }
                            if count < 0 { throw posixError() }
                            guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
                            offset += count
                        }
                    }
                } catch {
                    _ = Darwin.close(file)
                    throw error
                }
                // At this point the host accepted every byte. A ROM reboot can end flush/close.
                // Acceptance alone never proves an install; the caller must see detach and a fresh live probe.
                let syncError = fsync(file) == 0 ? nil : posixError()
                let closeError = Darwin.close(file) == 0 ? nil : posixError()
                for error in [syncError, closeError].compactMap({ $0 }) where
                    ![EIO, ENODEV, ENXIO, ENOENT].contains(Int32(error.code)) {
                    throw error
                }
            }
        }
        if let outcome { return try outcome.get() }
        if let coordinationError { throw coordinationError }
        throw FirmwareInstallationError.targetChanged
    }

    /// Confirms detach or a changed mount without treating access denial as detach.
    static func isMounted(_ url: URL, attachment: Self) throws -> Bool {
        var directory = stat()
        if lstat(url.path, &directory) == 0 {
            return directory.st_dev == attachment.device && directory.st_ino == attachment.inode
        }
        if [ENOENT, ENODEV, ENXIO].contains(errno) { return false }
        throw posixError()
    }

    /// Captures syscall errors before cleanup can change errno.
    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
