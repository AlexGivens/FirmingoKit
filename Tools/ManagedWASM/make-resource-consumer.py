"""Create a separate SDK-local minimal SwiftPM consumer for package resource discovery checks."""
from pathlib import Path
import argparse
import base64
import re


def main():
    """Keep all generated consumer inputs/outputs under FirmingoKit .build; use only the local package dependency."""
    sdk = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fresh", help="new simple directory name beneath SDK .build; refuse an existing destination")
    args = parser.parse_args()
    if args.fresh and not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", args.fresh):
        raise SystemExit("Use a bounded simple fresh consumer directory name")
    root = sdk / ".build" / (args.fresh or "compiler-resource-consumer")
    if args.fresh and root.exists():
        raise SystemExit("Select a new fresh consumer directory")
    source = root / "Sources/ResourceConsumer"
    source.mkdir(parents=True, exist_ok=True)
    # Embed only the unchanged non-executable parser fixture in this developer consumer.
    elf = bytes.fromhex((sdk / "Tests/FirmingoKitTests/Fixtures/compiler/stateless.elf.hex").read_text())
    (root / "Package.swift").write_text('''// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "ResourceConsumer", platforms: [.macOS(.v14)],
 dependencies: [.package(name: "FirmingoKit", path: "../..")],
 targets: [.executableTarget(name: "ResourceConsumer", dependencies: [.product(name: "FirmingoKit", package: "FirmingoKit")],
 swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")])])
''')
    (source / "main.swift").write_text('''import Foundation
import FirmingoKit

/// A separate local consumer checks SDK metadata discovery without developer paths or a service import.
@main struct ResourceConsumer {
    /// Construction/loading has no device or compiler-execution side effect.
    static func main() async throws {
        let catalogue = try await ManagedCompilerCatalogue.loadBundled()
        let compiler = ManagedSketchCompiler()
        guard catalogue.firmwareBuilds.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        print("Verified bundled catalogue:", catalogue.manifestSHA256)
        print(catalogue.unavailableReason(for: .nanoRP2040Connect) ?? "Unexpected available metadata")
        if CommandLine.arguments.count == 2 {
            // Synthetic local compiler evidence only: never deploy this test capsule.
            let resident = try ManagedResidentBinding(deviceID: "0102030405060708",
                residentELFSHA256: String(repeating: "0", count: 64), firmwareImageSHA256: String(repeating: "1", count: 64),
                apiAddress: 0x10022ca0)
            let snapshot = try SketchSourceSnapshot(documentID: UUID(), revision: .max, filename: "Blink.ino",
                source: "void setup() { pinMode(LED_BUILTIN, OUTPUT); } void loop() { digitalWrite(LED_BUILTIN, HIGH); delay(100); digitalWrite(LED_BUILTIN, LOW); delay(100); }")
            let request = try ManagedSketchBuildRequest(snapshot: snapshot, board: .nanoRP2040Connect, profile: .nanoManagedV1, resident: resident)
            let result = try await ManagedSketchCompiler(serviceURL: URL(fileURLWithPath: CommandLine.arguments[1])).build(request)
            guard result.artifact.compilerReceiptJSON != nil, result.artifact.receipt.sourceRevision == .max,
                  result.artifact.capsule.sha256 == "018c94a4a49b71880d6f04aecbe08e809c8ecf49e4278261c45dad3ead205720" else { throw CocoaError(.fileReadCorruptFile) }
            print("Synthetic packaged-consumer WASM compilation verified:", result.artifact.capsule.sha256)
        } else if CommandLine.arguments.count != 1 { throw CocoaError(.fileReadInvalidFileName) }
        let resident = try ManagedResidentBinding(deviceID: "0102030405060708", residentELFSHA256: String(repeating: "0", count: 64),
            firmwareImageSHA256: String(repeating: "1", count: 64), apiAddress: 0x1002154c)
        let snapshot = try SketchSourceSnapshot(documentID: UUID(), revision: .max, filename: "Prepare.ino", source: "void setup() {} void loop() {}")
        let selected = try ManagedSketchBuildRequest(snapshot: snapshot, board: .nanoRP2040Connect, profile: .nanoManagedV1, resident: resident)
        let prepared = try await ManagedSketchPreprocessor.prepare(selected)
        guard prepared.request.snapshot.revision == .max, prepared.translationUnit.hasSuffix(snapshot.source + "\\n") else { throw CocoaError(.fileReadCorruptFile) }
        print("Packaged service-free preparation verified:", prepared.translationUnitSHA256)
        guard let elf = Data(base64Encoded: "SYNTHETIC_PARSER_ELF_BASE64") else { throw CocoaError(.fileReadCorruptFile) }
        let provenance = try ManagedELFProvenance(compiler: "independent non-executable parser fixture",
            recipeIdentifier: "consumer-declared-v1", recipeSHA256: String(repeating: "4", count: 64),
            toolchainSHA256: String(repeating: "5", count: 64))
        let artifact = try await ManagedELFConverter.convert(elf, prepared: prepared, provenance: provenance)
        guard artifact.capsule.sha256 == "ef8bff817d9b80026f6eaeac33d1c40fac2f41b046865de967d3c0cf2539d52a",
              artifact.compilerReceiptJSON == nil, artifact.receipt.provenance == provenance,
              artifact.receipt.sourceRevision == .max else { throw CocoaError(.fileReadCorruptFile) }
        print("Packaged service-free ELF conversion verified:", artifact.capsule.sha256)
        _ = compiler
    }
}
'''.replace("SYNTHETIC_PARSER_ELF_BASE64", base64.b64encode(elf).decode("ascii")))
    print("Created", root.relative_to(sdk), "; run swift run --package-path", root.relative_to(sdk), "ResourceConsumer")


if __name__ == "__main__":
    main()
