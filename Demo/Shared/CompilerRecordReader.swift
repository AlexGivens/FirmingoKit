import Foundation
import FirmingoKit

/// Bounded read-only importer for SDK metadata, balancing document-picker scope off the UI actor.
enum CompilerRecordReader {
    /// Reads a regular nonsymlink file with an exact byte cap; cancellation preserves its original error.
    /// The SDK owns schema/hash/identity validation. This helper performs no compiler or device operation.
    @concurrent static func read(_ url: URL, maximumBytes: Int, allowsEmpty: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, (allowsEmpty || size > 0), size <= maximumBytes else {
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

    /// Captures up to eight regular helper files from one explicitly selected folder, retaining relative paths.
    @concurrent static func readHelpers(in root: URL) async throws -> [SketchSourceSnapshot.File] {
        let scope = root.startAccessingSecurityScopedResource()
        defer { if scope { root.stopAccessingSecurityScopedResource() } }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let folder = try root.resourceValues(forKeys: keys)
        guard root.isFileURL, folder.isDirectory == true, folder.isSymbolicLink != true else {
            throw SketchBuildError.invalidInput("Choose a folder containing only C++ helpers and headers")
        }
        var listingError: (any Error)?
        guard let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles], errorHandler: { _, error in
                    listingError = error
                    return false
                }) else { throw CocoaError(.fileReadCorruptFile) }
        var files: [SketchSourceSnapshot.File] = []
        var total = 0, count = 0
        let rootParts = root.standardizedFileURL.pathComponents
        while let item = items.nextObject() as? URL {
            try Task.checkCancellation()
            count += 1
            let parts = item.standardizedFileURL.pathComponents
            let relative = parts.dropFirst(rootParts.count)
            let values = try item.resourceValues(forKeys: keys)
            guard count <= 24, parts.starts(with: rootParts), (1...3).contains(relative.count),
                  values.isSymbolicLink != true else {
                throw SketchBuildError.invalidInput("Helper folder exceeds portable path limits or contains a link")
            }
            if values.isDirectory == true { continue }
            guard files.count < 8, ["cpp", "h"].contains(item.pathExtension) else {
                throw SketchBuildError.invalidInput("Choose a folder containing only up to eight .cpp and .h files")
            }
            let data = try await read(item, maximumBytes: 256 * 1024 - total, allowsEmpty: true)
            let source = String(decoding: data, as: UTF8.self)
            guard source.utf8.elementsEqual(data) else {
                throw SketchBuildError.invalidInput("Helper files must contain UTF-8 source")
            }
            total += data.count
            files.append(try SketchSourceSnapshot.File(path: relative.joined(separator: "/"), source: source))
        }
        if let listingError { throw listingError }
        guard !files.isEmpty else { throw SketchBuildError.invalidInput("No .cpp or .h helpers were found") }
        return files.sorted { $0.path < $1.path }
    }
}
