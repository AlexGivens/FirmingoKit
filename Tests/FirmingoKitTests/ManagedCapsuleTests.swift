import Foundation
import Testing
@testable import FirmingoKit

/// Local validation of independent non-executable firmware parser vectors, never physical uploads.
struct ManagedCapsuleTests {
    /// Golden whole/code hashes and binding validate independently supplied FMS1 bytes.
    @Test func goldenCapsule() throws {
        let capsule = try ManagedUploadFixtures.capsule()
        #expect(capsule.bytes.count == 264)
        #expect(capsule.sha256 == ManagedUploadFixtures.capsuleDigest)
        #expect(capsule.resident.apiAddress == 0x1002154c)
        #expect(capsule.setupAddress == 0x10200101)
        #expect(capsule.loopAddress == 0x10200105)
        #expect(capsule.compiler == "parser-fixture-not-executable")
    }
    /// Each independently constrained header/digest/padding region fails before any connection exists.
    @Test(arguments: [0, 4, 6, 8, 12, 16, 20, 24, 28, 32, 64, 263])
    func corruptBytes(offset: Int) throws {
        var bytes = try ManagedUploadFixtures.bytes()
        bytes[offset] ^= 1
        #expect(throws: ManagedUploadError.self) {
            try ManagedCapsule(bytes: bytes, reportJSON: ManagedUploadFixtures.reportJSON(), resident: ManagedUploadFixtures.resident())
        }
    }
    /// Missing/mismatched required report metadata cannot qualify a capsule for another resident.
    @Test(arguments: ["board", "image_format", "target_id", "api_address", "resident_elf_sha256",
                      "setup_address", "loop_address", "capsule_bytes", "code_bytes", "code_sha256", "capsule_sha256", "compiler", "source_sha256"])
    func incompleteReport(field: String) throws {
        var report = try ManagedUploadFixtures.report()
        report.removeValue(forKey: field)
        #expect(throws: ManagedUploadError.self) {
            try ManagedCapsule(bytes: ManagedUploadFixtures.bytes(), reportJSON: ManagedUploadFixtures.reportJSON(report),
                               resident: ManagedUploadFixtures.resident())
        }
    }
    /// Trailing bytes, oversized input, UF2-shaped bytes, and invalid source paths are rejected locally.
    @Test func invalidSizesAndPaths() throws {
        for bytes in [Data(repeating: 0, count: 256), Data(repeating: 0, count: 4097),
                      try ManagedUploadFixtures.bytes() + Data([0])] {
            #expect(throws: ManagedUploadError.self) {
                try ManagedCapsule(bytes: bytes, reportJSON: ManagedUploadFixtures.reportJSON(), resident: ManagedUploadFixtures.resident())
            }
        }
        for path in ["../escape.ino", "/absolute.ino", "a//b.ino", "a\\b.ino", "C:/absolute.ino"] {
            var report = try ManagedUploadFixtures.report()
            report["source_sha256"] = [path: String(repeating: "1", count: 64)]
            #expect(throws: ManagedUploadError.self) {
                try ManagedCapsule(bytes: ManagedUploadFixtures.bytes(), reportJSON: ManagedUploadFixtures.reportJSON(report),
                                   resident: ManagedUploadFixtures.resident())
            }
        }
    }
    /// Resident metadata needs explicit lowercase identities/hashes and a resident-range aligned API address.
    @Test func invalidResidentBinding() throws {
        for address: UInt32 in [0, 0x1002154d, 0x10200100] {
            #expect(throws: ManagedUploadError.self) {
                try ManagedResidentBinding(deviceID: "a1b2c3d4e5f60718", residentELFSHA256: String(repeating: "2", count: 64),
                                           firmwareImageSHA256: String(repeating: "3", count: 64), apiAddress: address)
            }
        }
        #expect(throws: ManagedUploadError.self) { try ManagedUploadFixtures.resident(deviceID: "localhost") }
    }

    /// Present but mismatched resident/target/digest metadata cannot pass as an independently built capsule.
    @Test(arguments: ["board", "target_id", "api_address", "resident_elf_sha256", "capsule_sha256", "max_install_bytes"])
    func mismatchedReport(field: String) throws {
        var report = try ManagedUploadFixtures.report()
        switch field {
        case "board": report[field] = "raspberry_pi_pico"
        case "target_id": report[field] = 2
        case "api_address": report[field] = "0x10021550"
        case "max_install_bytes": report[field] = 4_194_304
        default: report[field] = String(repeating: "0", count: 64)
        }
        #expect(throws: ManagedUploadError.self) {
            try ManagedCapsule(bytes: ManagedUploadFixtures.bytes(), reportJSON: ManagedUploadFixtures.reportJSON(report),
                               resident: ManagedUploadFixtures.resident())
        }
    }
}
