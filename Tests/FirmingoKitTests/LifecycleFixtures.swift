import Foundation
import Testing
@testable import FirmingoKit

/// Local synthetic UF2/parser resources and an observed unsigned release index, never board inputs.
enum LifecycleFixtures {
    /// Loads checked-in bytes without a network, external tool, or sibling checkout dependency.
    static func data(_ name: String) throws -> Data {
        let root = try #require(Bundle.module.resourceURL)
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/lifecycle/\(name)"))
    }
    /// Decodes the literal independent UF2 headers with non-executable zero payloads.
    static func bytes() throws -> Data {
        let text = String(decoding: try data("synthetic.uf2.hex"), as: UTF8.self)
        return Data(try text.split(whereSeparator: \.isWhitespace).map { try #require(UInt8($0, radix: 16)) })
    }
    /// Supplies a benign declared source; tests never contact it or infer its authenticity.
    static func source() throws -> URL {
        try #require(URL(string: "https://example.invalid/firmingo-0.1.0/manifest.json"))
    }
    /// Loads a mutable schema dictionary solely for deliberate negative test cases.
    static func object() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data("synthetic-manifest.json")) as? [String: Any])
    }
    /// Encodes a deliberate test variation without invoking the SDK's parser or UF2 writer.
    static func manifest(_ object: [String: Any]? = nil) throws -> FirmingoReleaseManifest {
        let data = try object.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
            ?? self.data("synthetic-manifest.json")
        return try FirmingoReleaseManifest(data: data, trustedSource: source())
    }
    /// Updates only the image digest/size so malformed UF2 reaches layout validation after integrity.
    static func manifest(for bytes: Data) throws -> FirmingoReleaseManifest {
        var object = try object()
        var files = try #require(object["files"] as? [[String: Any]])
        files[0]["bytes"] = bytes.count
        files[0]["sha256"] = FirmwareReleaseContract.digest(bytes)
        object["files"] = files
        return try manifest(object)
    }
    /// Validates synthetic bytes through the public complete-firmware boundary.
    static func image(_ bytes: Data? = nil) throws -> FirmingoFirmwareImage {
        let bytes = try bytes ?? self.bytes()
        return try FirmingoFirmwareImage(bytes: bytes, manifest: manifest(for: bytes),
                                         board: .nanoRP2040Connect, profile: .application)
    }
    /// Replaces a single block field with a literal little-endian test value after fixture bounds checks.
    static func replacing(_ offset: Int, with value: UInt32) throws -> Data {
        var data = try bytes()
        for index in 0..<4 { data[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
        return data
    }
}
