import Foundation

extension FirmingoFirmwareImage {
    /// Acquires two explicitly selected trusted local files with bounded reads on a concurrent executor.
    /// The manifest is limited to 16 KiB and the image to its validated entry size (at most two MiB).
    /// File selection is host-owned; neither the filename nor its location establishes authenticity.
    /// Security-scoped URL access is held only during each read. Cancellation is checked between
    /// bounded 64-KiB reads and before validation; this method never discovers or writes a device.
    /// Throws underlying file/stream errors, ``FirmwareLifecycleError``, or `CancellationError`.
    @concurrent
    public static func load(trustedManifestURL: URL, imageURL: URL,
                            board: FirmingoBoard, profile: FirmingoDevice.Backend) async throws -> Self {
        guard trustedManifestURL.isFileURL, imageURL.isFileURL else {
            throw FirmwareLifecycleError.invalidManifest("explicit local file URLs are required")
        }
        let data = try readLocalFile(trustedManifestURL, maximumBytes: 16384, isManifest: true)
        let manifest = try FirmingoReleaseManifest(data: data, trustedSource: trustedManifestURL)
        let entry = try manifest.entry(for: board, profile: profile)
        let image = try readLocalFile(imageURL, maximumBytes: entry.byteCount, isManifest: false)
        try Task.checkCancellation()
        return try Self(bytes: image, manifest: manifest, board: board, profile: profile)
    }

    /// Reads only regular local-file streams through a bounded allocation; scope/stream close on every exit.
    private static func readLocalFile(_ url: URL, maximumBytes: Int, isManifest: Bool) throws -> Data {
        try Task.checkCancellation()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard let stream = InputStream(url: url) else {
            throw CocoaError(.fileReadUnknown)
        }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var chunk = [UInt8](repeating: 0, count: min(maximumBytes + 1, 65536))
        while true {
            try Task.checkCancellation()
            let count = stream.read(&chunk, maxLength: min(chunk.count, maximumBytes + 1 - result.count))
            if count < 0 {
                if let error = stream.streamError { throw error }
                throw CocoaError(.fileReadUnknown)
            }
            if count == 0 { return result }
            result.append(contentsOf: chunk.prefix(count))
            guard result.count <= maximumBytes else {
                if isManifest { throw FirmwareLifecycleError.invalidManifest("local manifest exceeds 16 KiB") }
                throw FirmwareLifecycleError.invalidImage("local image exceeds its manifest byte count")
            }
        }
    }
}
