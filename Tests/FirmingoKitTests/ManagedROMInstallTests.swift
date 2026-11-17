import Foundation
import Testing
@testable import FirmingoKit

/// Covers exact review boundaries without contacting a real device or copying to a ROM volume.
struct ManagedROMInstallTests {
    /// Pending state survives encoding; a copy report alone never records a verified board.
    @Test func filesRecordDoesNotCreateAssociation() throws {
        var record = try ManagedROMInstall.Record(recovery: true, expectedDeviceID: "5031503337360009", previousBootID: "1122334455667788")
        #expect(!record.copyReported)
        let encoded = try JSONEncoder().encode(record)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy["schema"] = 1
        legacy.removeValue(forKey: "writeDispatched")
        var pending = try JSONDecoder().decode(ManagedROMInstall.Record.self, from: JSONSerialization.data(withJSONObject: legacy))
        try pending.validate()
        #expect(pending.writeDispatched == nil)
        #expect(!pending.mayVerify)
        try pending.dispatchWrite()
        #expect(pending.mayVerify)
        try record.reportCopy()
        #expect(record.copyReported)
        #expect(record.observedDeviceID == nil)
        let bytes = try JSONEncoder().encode(record)
        let loaded = try JSONDecoder().decode(ManagedROMInstall.Record.self, from: bytes)
        try loaded.validate()
        #expect(loaded == record)
        #expect(throws: FirmingoError.self) { try record.reportCopy() }
        #expect(throws: FirmingoError.self) { try ManagedROMInstall.Record(recovery: false, previousBootID: "1122334455667788") }
        #expect(throws: FirmwareLifecycleError.self) { try ManagedROMInstall(bytes: Data(repeating: 0, count: ManagedROMInstall.imageBytes)) }
    }

    /// A dispatched record remains consumed after an app restart even before a successful write.
    @Test func restoredWriteIntentCannotBeDispatchedAgain() throws {
        var record = try ManagedROMInstall.Record(recovery: false)
        try record.dispatchWrite()
        var restored = try JSONDecoder().decode(ManagedROMInstall.Record.self, from: JSONEncoder().encode(record))
        try restored.validate()
        #expect(restored.mayVerify)
        #expect(!restored.copyReported)
        #expect(restored.observedDeviceID == nil)
        #expect(throws: FirmingoError.self) { try restored.dispatchWrite() }
        #expect(throws: FirmingoError.self) { try restored.reportCopy() }
    }

    /// A correctly named ordinary directory and copied ROM metadata never reach write admission.
    @Test func ordinaryDirectoryWithROMMarkersIsRejectedBeforeAdmission() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = parent.appendingPathComponent("RPI-RP2", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let marker = Data("UF2 Bootloader v3.0\r\nModel: Raspberry Pi RP2\r\nBoard-ID: RPI-RP2\r\n".utf8)
        try marker.write(to: directory.appendingPathComponent("INFO_UF2.TXT"))
        await #expect(throws: FirmwareInstallationError.self) {
            try await ManagedROMVolume.program(Data([0]), in: directory) {
                Issue.record("The ordinary directory reached write admission")
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["INFO_UF2.TXT"])
    }

    /// Checks disjoint mapped payload ranges independently of the production image hash.
    @Test func managedInitialLayoutRejectsGapWrites() throws {
        var image = Data()
        for number in 0..<17 {
            let address = number == 0 ? 0x10000000 : 0x10200000 + (number - 1) * 256
            var page = Data(repeating: 0, count: 512)
            let words = [0x0a324655, 0x9e5d5157, 0x2000, address, 256, number, 17, 0xe48bff56]
            for (position, word) in words.enumerated() {
                page.replaceSubrange(position * 4..<position * 4 + 4, with: u32(UInt32(word)))
            }
            page.replaceSubrange(508..<512, with: u32(0x0ab16f30))
            image.append(page)
        }
        try UF2ImageLayout.validateManagedInitial(bytes: image, residentBlocks: 1)
        #expect(throws: FirmwareLifecycleError.self) { try UF2ImageLayout(bytes: image, board: .nanoRP2040Connect) }
        image.replaceSubrange(524..<528, with: u32(0x10100000))
        #expect(throws: FirmwareLifecycleError.self) { try UF2ImageLayout.validateManagedInitial(bytes: image, residentBlocks: 1) }
    }

    /// An echo-capable sketch with the wrong starter identity, nonce, or initialized state cannot qualify.
    @Test func starterProbeVerifiesVariantAndState() throws {
        let response = Data("FQ2A".utf8) + Data([49, 7, 0, 22, 15].flatMap { u32(UInt32($0)) })
        try ManagedROMInstall.checkStarter(response, nonce: 49)
        #expect(throws: FirmingoError.self) { try ManagedROMInstall.checkStarter(response, nonce: 50) }
        for offset in [3, 8, 12, 16] {
            var changed = response
            changed[offset] ^= 1
            #expect(throws: FirmingoError.self) { try ManagedROMInstall.checkStarter(changed, nonce: 49) }
        }
    }

    /// Encodes one UF2 fixture word without using production decoder logic.
    private func u32(_ value: UInt32) -> [UInt8] {
        [0,8,16,24].map { UInt8(truncatingIfNeeded: value >> $0) }
    }
}
