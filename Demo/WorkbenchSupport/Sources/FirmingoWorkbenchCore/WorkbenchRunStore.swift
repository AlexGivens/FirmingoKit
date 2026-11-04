import Foundation
import Darwin

/// App-owned journal boundary; a failed durable gate prevents the next scenario operation.
@MainActor public protocol WorkbenchRunStore {
    /// Reserves a new request identity; an existing directory must reject replay.
    func begin(_ report: WorkbenchReport) throws
    /// Durably saves bounded progress before execution continues.
    func save(_ report: WorkbenchReport) throws
}

/// Local per-run journals; reopening context does not reconstruct tasks or write authority.
@MainActor public final class WorkbenchFileRunStore: WorkbenchRunStore {
    /// Explicit app-owned result root; the CLI never reaches into a private container.
    public let directory: URL
    /// Captures a local root without creating files or touching hardware.
    public init(directory: URL) { self.directory = directory }
    /// Exclusive directory creation is the no-replay gate across app launches.
    public func begin(_ report: WorkbenchReport) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let run = directory.appendingPathComponent(report.id.uuidString, isDirectory: true)
        guard Darwin.mkdir(run.path, 0o700) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        try save(report)
    }
    /// Synchronizes contents and directory metadata; any error prevents a later passed report.
    public func save(_ report: WorkbenchReport) throws {
        try report.validateScope()
        guard report.events.count <= 64, report.artifacts.count <= 3 else { throw WorkbenchFailure("Run evidence bound exceeded.") }
        if let exercise = report.exercise {
            guard exercise.builds.count <= 40, exercise.progress.count <= 8, exercise.scenes.count <= 32,
                  exercise.samples.count <= 128, exercise.droppedSamples >= 0 else { throw WorkbenchFailure("Compiler exercise evidence bound exceeded.") }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(report)
        guard bytes.count <= 65536 else { throw WorkbenchFailure("Run report exceeds 64 KiB.") }
        let run = directory.appendingPathComponent(report.id.uuidString, isDirectory: true)
        let url = run.appendingPathComponent("report.json")
        try bytes.write(to: url, options: .atomic)
        let file = try FileHandle(forWritingTo: url)
        do { try file.synchronize() }
        catch {
            do { try file.close() }
            catch let cleanup { throw WorkbenchFailure("Journal synchronization and close failed: \(error); \(cleanup)") }
            throw error
        }
        try file.close()
        let fd = Darwin.open(run.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let result = fsync(fd), failure = errno
        guard Darwin.close(fd) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure)) }
    }
    /// Loads one explicitly selected saved report without executing or rewriting it; interrupted context remains unknown.
    public func load(id: UUID) throws -> WorkbenchReport {
        let run = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        let meta = try run.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard meta.isDirectory == true, meta.isSymbolicLink != true else { throw WorkbenchFailure("Invalid saved run directory.") }
        let file = run.appendingPathComponent("report.json")
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size <= 65536 else {
            throw WorkbenchFailure("Invalid saved run.")
        }
        let bytes = try Data(contentsOf: file)
        guard bytes.count <= 65536 else { throw WorkbenchFailure("Saved run exceeds its bound.") }
        var result = try JSONDecoder().decode(WorkbenchReport.self, from: bytes)
        guard (1...3).contains(result.schema), result.id == id, result.deviceOperations == (result.schema >= 2), result.events.count <= 64, result.artifacts.count <= 3 else {
            throw WorkbenchFailure("Invalid saved run identity.")
        }
        try result.validateScope()
        if result.status == .running { result.status = .outcomeUnknown }
        return result
    }
    /// Reads at most 32 recent snapshots; stale running reports are returned unknown without modifying originals.
    public func history() throws -> [WorkbenchReport] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
        guard urls.count <= 4096 else { throw WorkbenchFailure("Run history exceeds its scan bound; archive older results explicitly.") }
        let dated = try urls.map { url in
            (url, try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast)
        }
        var records: [WorkbenchReport] = []
        for (run, _) in dated.sorted(by: { $0.1 > $1.1 }).prefix(32) {
            let meta = try run.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard UUID(uuidString: run.lastPathComponent) != nil, meta.isDirectory == true, meta.isSymbolicLink != true else { continue }
            let file = run.appendingPathComponent("report.json")
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size <= 65536 else { throw WorkbenchFailure("Invalid saved run.") }
            let bytes = try Data(contentsOf: file)
            guard bytes.count <= 65536 else { throw WorkbenchFailure("Invalid saved run size.") }
            var record = try JSONDecoder().decode(WorkbenchReport.self, from: bytes)
            guard (1...3).contains(record.schema), record.deviceOperations == (record.schema >= 2), record.events.count <= 64, record.artifacts.count <= 3, record.id.uuidString == run.lastPathComponent else { throw WorkbenchFailure("Invalid saved run identity.") }
            try record.validateScope()
            if record.status == .running { record.status = .outcomeUnknown }
            records.append(record)
        }
        return records
    }
}
