import Foundation

/// Bounded nonsymlink local asset reads; callers verify exact bytes before making runtime capabilities.
enum ManagedCompilerResourceReader {
    /// Reads in fixed-size chunks with cancellation; read and cleanup failures retain both underlying causes.
    static func read(_ url: URL, maximum: Int, role: String) throws -> Data {
        try Task.checkCancellation()
        guard url.isFileURL, maximum > 0 else { throw ManagedCompilerResourceError.invalidFile(role) }
        let values: URLResourceValues
        do { values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw ManagedCompilerResourceError.invalidFile(role)
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximum else {
            throw ManagedCompilerResourceError.invalidFile(role)
        }
        let handle = try FileHandle(forReadingFrom: url)
        let bytes: Data
        do {
            var data = Data()
            while true {
                try Task.checkCancellation()
                guard let chunk = try handle.read(upToCount: min(1024 * 1024, maximum - data.count + 1)), !chunk.isEmpty else { break }
                guard chunk.count <= maximum - data.count else { throw ManagedCompilerResourceError.invalidFile(role) }
                data.append(chunk)
            }
            bytes = data
        } catch {
            do { try handle.close() }
            catch let cleanup { throw ManagedCompilerResourceReadFailure(underlying: error, cleanup: cleanup) }
            throw error
        }
        try handle.close()
        try Task.checkCancellation()
        return bytes
    }

    /// Keeps rare cleanup failure context without suppressing the original read/cancellation cause.
    private struct ManagedCompilerResourceReadFailure: Error {
        /// Original resource failure.
        let underlying: any Error
        /// Subsequent file-close failure.
        let cleanup: any Error
    }
}
