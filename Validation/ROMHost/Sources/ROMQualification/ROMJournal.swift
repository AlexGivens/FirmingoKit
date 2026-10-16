import Foundation
import Darwin
import FirmingoKit

/// App-owned durable observations; a fresh output directory prevents overwriting previous experiments.
actor ROMJournal {
    /// New explicit result directory, never a bootloader mount.
    private let directory: URL
    /// Bounded event and record inventory written after every callback.
    private var report: [String: String]
    /// Ordered public SDK records, retained separately as immutable files.
    private var records = 0
    /// Creates only a new local result directory; initialization never inspects a device.
    init(directory: URL, command: String) throws {
        guard !directory.standardizedFileURL.path.hasPrefix("/Volumes/"), !FileManager.default.fileExists(atPath: directory.path) else {
            throw ROMFailure("Select a new local output directory outside /Volumes.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        self.directory = directory
        report = ["schema": "1", "kind": "sdk-rom-qualification", "runID": UUID().uuidString,
            "pid": String(ProcessInfo.processInfo.processIdentifier), "command": command,
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "sandboxQualified": "false", "hardwareQualified": "false", "automaticReplay": "false"]
    }
    /// Bounded acquisition of an explicitly selected regular file, with checked close on success/error.
    static func read(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ROMFailure("Select a regular nonsymlink file.") }
        let file = try FileHandle(forReadingFrom: url)
        let bytes: Data
        do {
            bytes = try file.read(upToCount: maximum + 1) ?? Data()
            guard bytes.count <= maximum else { throw ROMFailure("Input exceeds its bound.") }
        } catch {
            do { try file.close() }
            catch let cleanup { throw FirmwareInstallationError.cleanupFailed(underlying: error, cleanup: cleanup) }
            throw error
        }
        try file.close(); return bytes
    }
    /// Synchronizes both file contents and the directory entry before the callback can permit a write.
    private func write(_ bytes: Data, name: String, immutable: Bool = false) throws {
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url, options: immutable ? .withoutOverwriting : .atomic)
        let file = try FileHandle(forWritingTo: url)
        do { try file.synchronize() }
        catch {
            do { try file.close() }
            catch let cleanup { throw FirmwareInstallationError.cleanupFailed(underlying: error, cleanup: cleanup) }
            throw error
        }
        try file.close()
        let root = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if fsync(root) != 0 {
            let failure = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            if Darwin.close(root) != 0 { throw FirmwareInstallationError.cleanupFailed(underlying: failure, cleanup: NSError(domain: NSPOSIXErrorDomain, code: Int(errno))) }
            throw failure
        }
        guard Darwin.close(root) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    /// Durably records each public SDK transition and progress sample before returning to the executor.
    func save(_ record: FirmwareInstallationRecord) throws {
        guard records < 256 else { throw ROMFailure("Record bound exceeded; stopping the transfer.") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let bytes = try encoder.encode(record)
        try write(bytes, name: String(format: "record-%03d.json", records), immutable: true)
        try write(bytes, name: "record.json")
        records += 1; report["records"] = String(records); report["state"] = record.state.rawValue
        report["acceptedBytes"] = String(record.transferredBytes)
        try event("latestRecordSHA256", ROMCandidate.digest(bytes))
    }
    /// Saves one bounded named observation and prints only its bounded value; no user stream logging.
    func event(_ key: String, _ value: String) throws {
        guard report.count < 64, key.utf8.count <= 64, value.utf8.count <= 4096 else { throw ROMFailure("Report bound exceeded.") }
        report[key] = value
        try write(JSONEncoder().encode(report), name: "report.json")
        try FileHandle.standardOutput.write(contentsOf: Data((key + ": " + value + "\n").utf8))
    }
    /// Pauses only after a known accepted prefix, then fails rather than automatically continuing the transfer.
    func pauseAfterPrefix(_ record: FirmwareInstallationRecord) async throws {
        guard record.transferredBytes >= 65536, record.transferredBytes < record.imageBytes else {
            throw ROMFailure("The selected partial-transfer checkpoint was not reached.")
        }
        try event("pausedAfterAcceptedPrefix", String(record.transferredBytes))
        try event("pauseMeaning", "Host filesystem acceptance only; flash contents require independent readback. No automatic continuation.")
        try await Task.sleep(for: .seconds(120))
        throw ROMFailure("Partial-transfer checkpoint expired; a new explicit recovery action is required.")
    }
}
