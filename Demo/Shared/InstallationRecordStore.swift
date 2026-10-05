import Darwin
import FirmingoKit
import Foundation

/// Host-owned atomic operation journals; no stored record authorizes programming or offset resume.
actor InstallationRecordStore {
    /// Serializes journal updates across document windows in this process.
    static let shared = InstallationRecordStore()
    /// Optional app-owned test storage; production uses Application Support in its sandbox container.
    private let selectedDirectory: URL?
    /// One process-local device action across all document windows; offline builds do not acquire it.
    private var activeOperation: (id: UUID, managedRun: Bool)?

    /// Allows deterministic journal checks inside this checkout without touching production context.
    init(directory: URL? = nil) { selectedDirectory = directory }

    /// Rechecks durable context and reserves a new Run before compilation or any device connection.
    func beginManagedRun(association: ManagedDeviceAssociation? = nil) throws -> UUID {
        if let association {
            guard try loadAssociations().contains(association) else { throw DemoOperationError.associationChanged }
        }
        return try beginDeployment(managedRun: true)
    }

    /// Versioned host envelope stores strict SDK record bytes; trust and device permission are never persisted.
    private struct AssociationArchive: Codable {
        /// Rejects future schemas instead of inferring a migration.
        let version: UInt32
        /// Base64-encoded SDK JSON preserves its schema and independent validation on every restore.
        let records: [Data]
    }

    /// Restores at most sixteen exact device associations without selecting or reviewing any of them.
    func loadAssociations() throws -> [ManagedDeviceAssociation] {
        try Task.checkCancellation()
        let url = try directory().appendingPathComponent("device-associations-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw DemoOperationError.invalidAssociationArchive
        }
        let bytes = try readBoundedRecord(url)
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(object.keys) == ["version", "records"] else { throw DemoOperationError.invalidAssociationArchive }
        let archive = try JSONDecoder().decode(AssociationArchive.self, from: bytes)
        guard archive.version == 1, archive.records.count <= 16 else { throw DemoOperationError.invalidAssociationArchive }
        let records = try archive.records.map { try ManagedDeviceAssociation(recordJSON: $0) }
        guard Set(records.map(\.deviceID)).count == records.count else { throw DemoOperationError.invalidAssociationArchive }
        return records.sorted { $0.deviceID < $1.deviceID }
    }

    /// Explicitly saves reviewed host evidence only if the complete roster still matches this window's snapshot.
    func saveAssociation(_ association: ManagedDeviceAssociation, expected: [ManagedDeviceAssociation]) throws -> [ManagedDeviceAssociation] {
        try Task.checkCancellation()
        guard activeOperation == nil else { throw DemoOperationError.busy }
        var records = try loadAssociations()
        guard records == expected else { throw DemoOperationError.associationChanged }
        records.removeAll { $0.deviceID == association.deviceID }
        records.append(association)
        return try writeAssociations(records)
    }

    /// Removes one explicitly selected saved association, preserving other devices and all upload journals.
    func removeAssociation(deviceID: String, expected: [ManagedDeviceAssociation]) throws -> [ManagedDeviceAssociation] {
        try Task.checkCancellation()
        guard activeOperation == nil else { throw DemoOperationError.busy }
        var records = try loadAssociations()
        guard records == expected, records.contains(where: { $0.deviceID == deviceID }) else {
            throw DemoOperationError.associationChanged
        }
        records.removeAll { $0.deviceID == deviceID }
        return try writeAssociations(records)
    }

    /// Bounds and synchronizes one atomic roster replacement; storage failures never acknowledge a save.
    private func writeAssociations(_ records: [ManagedDeviceAssociation]) throws -> [ManagedDeviceAssociation] {
        guard records.count <= 16 else { throw DemoOperationError.associationLimit }
        let sorted = records.sorted { $0.deviceID < $1.deviceID }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let archive = AssociationArchive(version: 1, records: try sorted.map { try $0.encodeRecord() })
        let bytes = try encoder.encode(archive)
        guard bytes.count <= 16384 else { throw CocoaError(.fileWriteOutOfSpace) }
        try durableWrite(bytes, to: directory().appendingPathComponent("device-associations-v1.json"))
        return sorted
    }

    /// Serializes firmware replacement against managed actions; ROM identity cannot safely distinguish targets.
    /// A pending or unreadable managed journal blocks replacement until a separate explicit review/clear.
    func beginFirmwareInstallation() throws -> UUID {
        try beginDeployment(managedRun: false)
    }

    /// Requires the currently saved transaction before an explicit fresh read-only status connection.
    func beginManagedReview(_ expected: ManagedUploadRecord) throws -> UUID {
        try Task.checkCancellation()
        guard activeOperation == nil else { throw DemoOperationError.busy }
        guard try loadManaged() == expected else { throw DemoOperationError.contextChanged }
        let id = UUID()
        activeOperation = (id, false)
        return id
    }

    /// Releases only the owning action; an old completion can never release a newer window's reservation.
    func finishDeviceOperation(_ id: UUID) {
        if activeOperation?.id == id { activeOperation = nil }
    }

    /// Grants no device permission when another action or an unresolved journal exists.
    private func beginDeployment(managedRun: Bool) throws -> UUID {
        try Task.checkCancellation()
        guard activeOperation == nil else { throw DemoOperationError.busy }
        guard try loadManaged() == nil else { throw DemoOperationError.pendingManagedTransaction }
        let id = UUID()
        activeOperation = (id, managedRun)
        return id
    }

    /// Saves operation and latest-context files, syncing data and directory entries before acknowledgement.
    /// Any storage failure propagates through the SDK write gate or progress callback.
    func save(_ record: FirmwareInstallationRecord) throws -> URL {
        let directory = try directory()
        let bytes = try JSONEncoder().encode(record)
        guard bytes.count <= 16384 else { throw CocoaError(.fileWriteOutOfSpace) }
        let journal = directory.appendingPathComponent("\(record.operationID.uuidString).json")
        try durableWrite(bytes, to: journal)
        try durableWrite(bytes, to: directory.appendingPathComponent("latest.json"))
        return journal
    }

    /// Saves managed-upload reconciliation context before the host may request its one-shot commit.
    func saveManaged(_ record: ManagedUploadRecord, operation: UUID) throws {
        guard activeOperation?.id == operation, activeOperation?.managedRun == true else {
            throw DemoOperationError.invalidReservation
        }
        let previous = try loadManaged()
        guard previous == nil || previous == record else { throw DemoOperationError.contextChanged }
        let folder = try directory()
        let bytes = try JSONEncoder().encode(record)
        guard bytes.count <= 16384 else { throw CocoaError(.fileWriteOutOfSpace) }
        try durableWrite(bytes, to: folder.appendingPathComponent("managed-\(record.deviceID)-\(record.bootID)-\(record.uploadID).json"))
        try durableWrite(bytes, to: folder.appendingPathComponent("managed-latest.json"))
    }

    /// Loads bounded saved context without reconnecting, retrying staging or replaying commit.
    func loadManaged() throws -> ManagedUploadRecord? {
        let url = try directory().appendingPathComponent("managed-latest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes = try readBoundedRecord(url)
        return try JSONDecoder().decode(ManagedUploadRecord.self, from: bytes)
    }

    /// Atomically rechecks the reviewed context before explicit removal, retaining transaction history.
    /// A window with unreadable context may clear corruption, but cannot discard a newer valid transaction.
    func clearManaged(expected: ManagedUploadRecord?) throws {
        try Task.checkCancellation()
        guard activeOperation == nil else { throw DemoOperationError.busy }
        let current: ManagedUploadRecord?
        do { current = try loadManaged() }
        catch is DecodingError {
            guard expected == nil else { throw DemoOperationError.contextChanged }
            current = nil
        } catch let error as CocoaError where error.code == .fileReadTooLarge {
            guard expected == nil else { throw DemoOperationError.contextChanged }
            current = nil
        }
        guard current == expected else { throw DemoOperationError.contextChanged }
        let folder = try directory()
        let url = folder.appendingPathComponent("managed-latest.json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try synchronizeDirectory(folder)
    }

    /// Loads bounded latest observations on sheet opening, without selecting a volume or preparing a writer.
    func loadLatest() throws -> FirmwareInstallationRecord? {
        let url = try directory().appendingPathComponent("latest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes = try readBoundedRecord(url)
        return try JSONDecoder().decode(FirmwareInstallationRecord.self, from: bytes)
    }

    /// Reads complete journal bytes with a hard bound, preserving read and cleanup causes on every failure.
    private func readBoundedRecord(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        let bytes: Data
        do {
            var data = Data()
            while data.count <= 16384 {
                guard let chunk = try handle.read(upToCount: 16385 - data.count), !chunk.isEmpty else { break }
                data.append(chunk)
            }
            guard data.count <= 16384 else { throw CocoaError(.fileReadTooLarge) }
            bytes = data
        } catch {
            do { try handle.close() }
            catch let cleanup { throw FirmwareInstallationError.cleanupFailed(underlying: error, cleanup: cleanup) }
            throw error
        }
        try handle.close()
        return bytes
    }

    /// Creates app-private journal storage and flushes its parent entry before acknowledging writes.
    private func directory() throws -> URL {
        if let selectedDirectory {
            try FileManager.default.createDirectory(at: selectedDirectory, withIntermediateDirectories: true)
            try synchronizeDirectory(selectedDirectory.deletingLastPathComponent())
            return selectedDirectory
        }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let folder = root.appendingPathComponent("FirmingoDemo-FirmwareOperations", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try synchronizeDirectory(root)
        return folder
    }

    /// Atomic replacement is followed by file and containing-directory synchronization; failures stop the SDK.
    private func durableWrite(_ bytes: Data, to url: URL) throws {
        try bytes.write(to: url, options: [.atomic])
        let handle = try FileHandle(forWritingTo: url)
        do { try handle.synchronize() }
        catch {
            do { try handle.close() }
            catch let cleanup { throw FirmwareInstallationError.cleanupFailed(underlying: error, cleanup: cleanup) }
            throw error
        }
        try handle.close()
        try synchronizeDirectory(url.deletingLastPathComponent())
    }

    /// Flushes directory entry changes without swallowing unsupported filesystem or permission failures.
    private func synchronizeDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let status = fsync(descriptor)
        let code = errno
        let closed = Darwin.close(descriptor)
        let closeCode = errno
        if status != 0 {
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
            if closed != 0 {
                throw FirmwareInstallationError.cleanupFailed(underlying: error, cleanup: NSError(domain: NSPOSIXErrorDomain, code: Int(closeCode)))
            }
            throw error
        }
        guard closed == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(closeCode)) }
    }
}
