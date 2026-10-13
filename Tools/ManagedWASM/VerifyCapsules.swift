import Foundation
import FirmingoKit

/// Read-only independent SDK deployment validation of explicitly selected capsule/report/binding files.
@main struct VerifyCapsules {
    /// Verifies bytes and declared binding without compilation, packaging, connection or device writes.
    static func main() {
        do { try validate() }
        catch { print("SDK capsule validation failed:", error); exit(1) }
    }
    /// Keeps validation failures at a readable nonzero CLI outcome rather than an unhandled Swift error.
    private static func validate() throws {
        guard CommandLine.arguments.count == 4 else {
            print("Usage: verify-capsules <capsule.fms> <report.json> <resident-binding.json>")
            throw CocoaError(.fileReadInvalidFileName)
        }
        let resident = try ManagedResidentBinding(recordJSON: read(CommandLine.arguments[3], maximum: 16_384))
        let capsule = try ManagedCapsule(bytes: read(CommandLine.arguments[1], maximum: 4096),
            reportJSON: read(CommandLine.arguments[2], maximum: 16_384), resident: resident)
        print("SDK capsule/report/binding validation passed:", capsule.sha256)
        print("Declared metadata is not installed-image attestation or permission to upload.")
    }
    /// Bounds regular-file reads before allocating data; symlinks and oversized inputs fail explicitly.
    private static func read(_ path: String, maximum: Int) throws -> Data {
        let url = URL(fileURLWithPath: path)
        let facts = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard facts.isRegularFile == true, facts.isSymbolicLink != true,
              let size = facts.fileSize, size <= maximum else { throw CocoaError(.fileReadCorruptFile) }
        let handle = try FileHandle(forReadingFrom: url)
        let data: Data
        do {
            data = try handle.read(upToCount: maximum + 1) ?? Data()
        } catch {
            try handle.close()
            throw error
        }
        try handle.close()
        guard data.count == size, data.count <= maximum else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
}
