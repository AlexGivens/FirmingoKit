import Foundation
#if os(macOS)
import Darwin
import DiskArbitration
import IOKit
#endif

/// Experimental macOS transfer to an explicitly selected RP2040 USB ROM mount, never model discovery.
/// Requires user-selected filesystem access and Disk Arbitration/IOKit inspection. No board/host pair
/// is hardware-qualified yet. iOS/iPadOS returns unsupportedPlatform before any programming action.
public actor MacOSUF2ProgrammingBackend: FirmwareProgrammingBackend {
    /// Namespace for this pinned RP2040 ROM mounted-volume backend.
    public nonisolated let identifier = "macos-rp2040-rom-uf2-v1"
    /// Rejects overlapping direct calls while callbacks suspend; installer leases also span instances.
    private var writing = false

    /// Constructs the backend without scanning volumes, resetting devices, or creating files.
    public init() {}

    /// Reads an explicit mount root and verifies USB VID/PID, attachment registry IDs, and ROM info.
    /// A generic RP2040 ROM observation still requires host confirmation of the physical board model.
    public func inspect(volumeURL: URL) async throws -> FirmwareBootloaderVolume {
        #if os(macOS)
        try Task.checkCancellation()
        let scoped = volumeURL.startAccessingSecurityScopedResource()
        defer { if scoped { volumeURL.stopAccessingSecurityScopedResource() } }
        return try Self.inspectSelected(volumeURL, backendID: identifier)
        #else
        throw FirmwareInstallationError.unsupportedPlatform
        #endif
    }

    /// Rechecks attachment before and after the awaited durable write gate, then creates FIRMINGO.UF2
    /// exclusively in a pinned directory descriptor. No overwrite, shell, reset, replay, or cleanup
    /// deletion of partial images occurs. Cancellation is checked between writes; fsync/close errors
    /// propagate. Local filesystem completion is distinct from board reboot/install verification.
    public func write(image: FirmingoFirmwareImage, to volume: FirmwareBootloaderVolume,
                      willWrite: @escaping @Sendable () async throws -> Void,
                      progress: @escaping @Sendable (Int) async throws -> Void) async throws {
        #if os(macOS)
        guard !writing else { throw FirmwareInstallationError.busy }
        guard volume.backendID == identifier else { throw FirmwareInstallationError.targetChanged }
        writing = true
        defer { writing = false }
        try Task.checkCancellation()
        let scoped = volume.mountURL.startAccessingSecurityScopedResource()
        defer { if scoped { volume.mountURL.stopAccessingSecurityScopedResource() } }
        let root = try Self.openDirectory(volume.mountURL)
        do {
            try Self.revalidate(volume, root: root)
            try await willWrite()
            try Task.checkCancellation()
            try Self.revalidate(volume, root: root)
            let file = openat(root, "FIRMINGO.UF2", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard file >= 0 else { throw Self.posixError() }
            do {
                try await UF2FileTransfer.transfer(image.bytes) { chunk in
                    while true {
                        try Task.checkCancellation()
                        let count = chunk.withUnsafeBytes { Darwin.write(file, $0.baseAddress, $0.count) }
                        if count < 0, errno == EINTR { continue }
                        guard count >= 0 else { throw Self.posixError() }
                        return count
                    }
                } synchronize: {
                    guard fsync(file) == 0 else { throw Self.posixError() }
                } progress: { try await progress($0) }
            } catch {
                try Self.closeDescriptor(file, preserving: error)
                throw error
            }
            try Self.closeDescriptor(file)
        } catch {
            try Self.closeDescriptor(root, preserving: error)
            throw error
        }
        try Self.closeDescriptor(root)
        #else
        throw FirmwareInstallationError.unsupportedPlatform
        #endif
    }

    /// Parses bounded ASCII ROM metadata with unique expected fields; it never identifies Nano/Pico.
    static func validateROMInfo(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 4096, data.allSatisfy({ $0 != 0 && $0 < 128 }) else {
            throw FirmwareInstallationError.invalidRequest("invalid RP2040 ROM metadata")
        }
        let lines = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.first?.hasPrefix("UF2 Bootloader ") == true,
              lines.filter({ $0.hasPrefix("Board-ID:") }) == ["Board-ID: RPI-RP2"],
              lines.filter({ $0.hasPrefix("Model:") }) == ["Model: Raspberry Pi RP2"] else {
            throw FirmwareInstallationError.invalidRequest("selected volume is not the pinned RP2040 ROM interface")
        }
    }

    #if os(macOS)
    /// Combines mounted IOMedia and USB attachment IDs with ROM info integrity, without writing.
    private static func inspectSelected(_ url: URL, backendID: String) throws -> FirmwareBootloaderVolume {
        guard url.isFileURL, url.path.utf8.count <= 2048, !url.path.utf8.contains(0),
              url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL,
              let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let description = DADiskCopyDescription(disk) else {
            throw FirmwareInstallationError.invalidRequest("select an accessible mounted USB ROM volume root")
        }
        let fields = description as NSDictionary
        guard let mount = fields[kDADiskDescriptionVolumePathKey] as? URL,
              mount.standardizedFileURL == url.standardizedFileURL,
              fields[kDADiskDescriptionDeviceProtocolKey] as? String == "USB" else {
            throw FirmwareInstallationError.invalidRequest("selection is not a mounted USB volume root")
        }
        let media = DADiskCopyIOMedia(disk)
        guard media != 0 else { throw FirmwareInstallationError.targetChanged }
        defer { releaseRegistryObject(media) }
        var mediaID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(media, &mediaID) == KERN_SUCCESS else {
            throw FirmwareInstallationError.targetChanged
        }
        let usbID = try usbAttachmentID(media: media)
        let root = try openDirectory(url)
        let info: Data
        do { info = try readInfo(root: root) }
        catch { try closeDescriptor(root, preserving: error); throw error }
        try closeDescriptor(root)
        try validateROMInfo(info)
        return try FirmwareBootloaderVolume(backendID: backendID, instanceID: "usb:\(usbID)-media:\(mediaID)",
                                            mountURL: url, infoSHA256: FirmwareReleaseContract.digest(info))
    }
    /// Finds the actual USB device ancestor and accepts only RP2040 ROM VID 2e8a / PID 0003.
    private static func usbAttachmentID(media: io_registry_entry_t) throws -> UInt64 {
        var current: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(media, kIOServicePlane, &current) == KERN_SUCCESS else {
            throw FirmwareInstallationError.targetChanged
        }
        for _ in 0..<32 {
            let vendor = IORegistryEntryCreateCFProperty(current, "idVendor" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
            let product = IORegistryEntryCreateCFProperty(current, "idProduct" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
            if let vendor, let product {
                defer { releaseRegistryObject(current) }
                guard vendor.uint32Value == 0x2e8a, product.uint32Value == 0x0003 else {
                    throw FirmwareInstallationError.invalidRequest("USB device is not the RP2040 ROM bootloader")
                }
                var value: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(current, &value) == KERN_SUCCESS else {
                    throw FirmwareInstallationError.targetChanged
                }
                return value
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            releaseRegistryObject(current)
            guard status == KERN_SUCCESS else { throw FirmwareInstallationError.targetChanged }
            current = parent
        }
        releaseRegistryObject(current)
        throw FirmwareInstallationError.invalidRequest("USB ancestor exceeds inspection bounds")
    }
    /// Releases a retained kernel handle; failure indicates an SDK ownership bug, not device input.
    private static func releaseRegistryObject(_ object: io_object_t) {
        let status = IOObjectRelease(object)
        assert(status == KERN_SUCCESS, "Invalid owned IOKit object")
    }
    /// Pins the explicit mount root rather than reopening a path for every write.
    private static func openDirectory(_ url: URL) throws -> Int32 {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        return descriptor
    }
    /// Rechecks attachment and that the pinned descriptor still denotes the currently selected root.
    private static func revalidate(_ volume: FirmwareBootloaderVolume, root: Int32) throws {
        guard try inspectSelected(volume.mountURL, backendID: volume.backendID) == volume else {
            throw FirmwareInstallationError.targetChanged
        }
        var pinned = stat()
        var selected = stat()
        guard fstat(root, &pinned) == 0, lstat(volume.mountURL.path, &selected) == 0 else { throw posixError() }
        guard pinned.st_dev == selected.st_dev, pinned.st_ino == selected.st_ino else {
            throw FirmwareInstallationError.targetChanged
        }
    }
    /// Reads INFO_UF2.TXT through the pinned directory, excluding symlinks and excess data.
    private static func readInfo(root: Int32) throws -> Data {
        let file = openat(root, "INFO_UF2.TXT", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw posixError() }
        let result: Data
        do {
            var metadata = stat()
            guard fstat(file, &metadata) == 0 else { throw posixError() }
            guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), metadata.st_size <= 4096 else {
                throw FirmwareInstallationError.invalidRequest("invalid ROM info file type or size")
            }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4097)
            while data.count <= 4096 {
                let count = Darwin.read(file, &buffer, 4097 - data.count)
                if count < 0, errno == EINTR { continue }
                guard count >= 0 else { throw posixError() }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            guard data.count <= 4096 else { throw FirmwareInstallationError.invalidRequest("ROM info exceeds 4096 bytes") }
            result = data
        } catch { try closeDescriptor(file, preserving: error); throw error }
        try closeDescriptor(file)
        return result
    }
    /// Closes exactly once; when operation and close both fail their causes are preserved together.
    private static func closeDescriptor(_ descriptor: Int32, preserving underlying: (any Error)? = nil) throws {
        guard Darwin.close(descriptor) == 0 else {
            let failure = posixError()
            if let underlying { throw FirmwareInstallationError.cleanupFailed(underlying: underlying, cleanup: failure) }
            throw failure
        }
    }
    /// Captures errno immediately before another syscall can overwrite its cause.
    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    #endif
}
