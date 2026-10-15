import Foundation

/// Bounded nonsymlink local asset reads; callers verify exact bytes before making runtime capabilities.
enum ManagedCompilerResourceReader {
    /// Reserves the bounded snapshot once and drains Foundation chunk temporaries before reading another chunk.
    /// Cancellation and read/cleanup errors keep their original meaning; the snapshot is independent of later file edits.
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
            data.reserveCapacity(size)
            while true {
                try Task.checkCancellation()
                let count = try autoreleasepool {
                    guard let chunk = try handle.read(upToCount: min(1024 * 1024, maximum - data.count + 1)), !chunk.isEmpty else {
                        return 0
                    }
                    guard chunk.count <= maximum - data.count else {
                        throw ManagedCompilerResourceError.invalidFile(role)
                    }
                    data.append(chunk)
                    return chunk.count
                }
                if count == 0 { break }
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
