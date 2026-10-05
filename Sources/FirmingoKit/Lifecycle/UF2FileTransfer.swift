import Foundation

/// Lossless bounded host transfer loop, independently testable without a ROM volume or filesystem.
enum UF2FileTransfer {
    /// Retries only the unaccepted suffix of a known partial write; no ambiguous write is replayed.
    /// Awaited progress applies backpressure after each accepted prefix. Synchronization must finish
    /// before return; the caller owns close and classifies any failure after write permission as unknown.
    static func transfer(_ bytes: Data,
                         write: @Sendable (Data) async throws -> Int,
                         synchronize: @Sendable () async throws -> Void,
                         progress: @Sendable (Int) async throws -> Void) async throws {
        var offset = 0
        while offset < bytes.count {
            try Task.checkCancellation()
            let chunk = Data(bytes.dropFirst(offset).prefix(65536))
            let count = try await write(chunk)
            guard count > 0, count <= chunk.count else {
                throw FirmwareInstallationError.invalidRequest("invalid filesystem write count")
            }
            offset += count
            try await progress(offset)
        }
        try Task.checkCancellation()
        try await synchronize()
    }
}
