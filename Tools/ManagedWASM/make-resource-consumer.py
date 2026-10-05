"""Create a separate SDK-local minimal SwiftPM consumer for package resource discovery checks."""
from pathlib import Path


def main():
    """Keep all generated consumer inputs/outputs under FirmingoKit .build; use only the local package dependency."""
    sdk = Path(__file__).resolve().parents[2]
    root = sdk / ".build/compiler-resource-consumer"
    source = root / "Sources/ResourceConsumer"
    source.mkdir(parents=True, exist_ok=True)
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
        _ = compiler
    }
}
''')
    print("Created .build/compiler-resource-consumer; run swift run --package-path .build/compiler-resource-consumer ResourceConsumer")


if __name__ == "__main__":
    main()
