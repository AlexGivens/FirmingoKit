import Foundation
import FirmingoKit

/// Bounded read-only importer for SDK metadata, balancing document-picker scope off the UI actor.
enum CompilerRecordReader {
    /// Reads a regular nonsymlink file with an exact byte cap; cancellation preserves its original error.
    /// The SDK owns schema/hash/identity validation. This helper performs no compiler or device operation.
    @concurrent static func read(_ url: URL, maximumBytes: Int) async throws -> Data {
        try Task.checkCancellation()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumBytes else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let handle = try FileHandle(forReadingFrom: url)
        let bytes: Data
        do {
            var data = Data()
            while true {
                try Task.checkCancellation()
                guard let chunk = try handle.read(upToCount: min(64 * 1024, maximumBytes - data.count + 1)), !chunk.isEmpty else { break }
                guard chunk.count <= maximumBytes - data.count else { throw CocoaError(.fileReadCorruptFile) }
                data.append(chunk)
            }
            bytes = data
        } catch {
            do { try handle.close() }
            catch let cleanup { throw FirmwareInstallationError.cleanupFailed(underlying: error, cleanup: cleanup) }
            throw error
        }
        try handle.close(); try Task.checkCancellation()
        return bytes
    }
}
