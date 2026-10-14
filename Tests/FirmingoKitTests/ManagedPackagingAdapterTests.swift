import Foundation
import Testing
@testable import FirmingoKit

/// Actual service-free WebKit packaging and native trust-boundary checks; synthetic capsules never reach devices.
@Suite(.serialized)
@MainActor struct ManagedPackagingAdapterTests {
    /// Valid output is accepted only for the captured source, declared recipe, ELF and static target.
    @Test func nativePackagingBoundary() async throws {
        let selected = try CompilerFixtures.request(revision: .max)
        let prepared = try await ManagedSketchPreprocessor.prepare(selected)
        let request = try ManagedPortableRequest(selected, provenance: CompilerFixtures.provenance())
        let resources = try await VerifiedManagedResources.load(), elf = try CompilerFixtures.elf()
        let json = try await ManagedWebKitHost().package(elf: elf, request: request, page: resources.page)
        let output = try await ManagedPortablePackaging.decode(json, request: request, elf: elf,
            sourceSHA256: prepared.sourceSHA256, translationUnitSHA256: prepared.translationUnitSHA256)
        #expect(output.payload.bytes == (try ManagedUploadFixtures.bytes()))
        let original = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        for mutation in ["buildID", "requestSHA256", "operation", "extra", "format", "filename", "bytes", "sha256", "receiptSchema",
                         "provenanceStatus", "sourceRevision", "sourceSHA256", "translationUnitSHA256", "residentBindingID",
                         "linkedELFSHA256", "capsuleSHA256", "capsuleBytes", "buildInputSHA256", "provenance", "service", "reportJSON"] {
            var root = original
            var artifact = try #require(root["artifact"] as? [String: Any])
            var receipt = try #require(artifact["receipt"] as? [String: Any])
            switch mutation {
            case "buildID": root[mutation] = "stale"
            case "requestSHA256": root[mutation] = String(repeating: "0", count: 64)
            case "operation": root[mutation] = "compile"
            case "extra": root[mutation] = true
            case "format", "filename", "sha256": artifact[mutation] = "altered"
            case "bytes": artifact[mutation] = "AAAA"
            case "reportJSON": artifact[mutation] = "{}"
            case "capsuleBytes": receipt[mutation] = true
            case "provenance":
                var provenance = try #require(receipt[mutation] as? [String: Any]); provenance["compiler"] = "changed"; receipt[mutation] = provenance
            case "service": receipt[mutation] = ["sha256": String(repeating: "0", count: 64)]
            default: receipt[mutation] = "altered"
            }
            artifact["receipt"] = receipt; root["artifact"] = artifact
            let changed = String(decoding: try ManagedPortableRequest.canonical(root), as: UTF8.self)
            if mutation == "reportJSON" {
                await #expect(throws: ManagedUploadError.self) {
                    _ = try await ManagedPortablePackaging.decode(changed, request: request, elf: elf,
                        sourceSHA256: prepared.sourceSHA256, translationUnitSHA256: prepared.translationUnitSHA256)
                }
            } else {
                await #expect(throws: FirmingoError.self) {
                    _ = try await ManagedPortablePackaging.decode(changed, request: request, elf: elf,
                        sourceSHA256: prepared.sourceSHA256, translationUnitSHA256: prepared.translationUnitSHA256)
                }
            }
        }
        #expect(!String(decoding: request.json, as: UTF8.self).contains("deviceID"))
        #expect(request.packagingProvenance?.recipeIdentifier == "nano-test-v1")
        #expect(request.revisionToken.hasSuffix("18446744073709551615"))
    }

    /// The shared parser rejects malformed/full-firmware bytes through the public API without any native ELF parser.
    @Test func malformedELFAndFreshPackaging() async throws {
        let prepared = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request())
        for input in [Data(), Data("UF2\n".utf8) + Data(repeating: 0, count: 508), try CompilerFixtures.elf().prefix(100)] {
            await #expect(throws: SketchBuildError.self) { try await ManagedELFConverter.convert(input, prepared: prepared, provenance: CompilerFixtures.provenance()) }
        }
        var fullFirmware = try CompilerFixtures.elf(); CompilerFixtures.word(0x10000100, at: 564, in: &fullFirmware)
        await #expect(throws: SketchBuildError.self) { try await ManagedELFConverter.convert(fullFirmware, prepared: prepared, provenance: CompilerFixtures.provenance()) }
        let fresh = try await ManagedELFConverter.convert(CompilerFixtures.elf(), prepared: prepared, provenance: CompilerFixtures.provenance())
        #expect(fresh.capsule.sha256 == ManagedUploadFixtures.capsuleDigest)
    }

    /// Native loading deadlines dispose the packaging page; a fresh service-free public conversion still succeeds.
    @Test func deadlineAndFreshPackaging() async throws {
        let selected = try CompilerFixtures.request(), elf = try CompilerFixtures.elf()
        let request = try ManagedPortableRequest(selected, provenance: CompilerFixtures.provenance())
        let resources = try await VerifiedManagedResources.load()
        do {
            _ = try await ManagedWebKitHost().package(elf: elf, request: request, page: resources.page, timeout: .milliseconds(1))
            Issue.record("One-millisecond loading deadline must fail")
        } catch ManagedCompilerError.timedOut { /* A timed-out operation must not publish a capsule. */ }
        let prepared = try await ManagedSketchPreprocessor.prepare(selected)
        #expect(try await ManagedELFConverter.convert(elf, prepared: prepared, provenance: CompilerFixtures.provenance()).capsule.sha256 == ManagedUploadFixtures.capsuleDigest)
    }
}
