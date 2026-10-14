"""Create a fresh public-API SwiftPM consumer of an explicitly prepared self-contained SDK package."""
import argparse
import json
import os
from pathlib import Path


def main():
    """Generate only in a new directory; no binary lookup, network, compiler or device invocation occurs here."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sdk_package", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    sdk = args.sdk_package.resolve(strict=True)
    if not (sdk / "prepared-package.json").is_file():
        raise SystemExit("Select an explicitly prepared SDK source package")
    output = args.output.absolute()
    output.mkdir()
    relative = json.dumps(os.path.relpath(sdk, output))
    (output / "Package.swift").write_text('''// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "BundledConsumer", platforms: [.macOS(.v14)],
 dependencies: [.package(name: "FirmingoKit", path: SDK_RELATIVE_PATH)],
 targets: [.executableTarget(name: "BundledConsumer", dependencies: [.product(name: "FirmingoKit", package: "FirmingoKit")],
 swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")])])
'''.replace("SDK_RELATIVE_PATH", relative))
    source = output / "Sources/BundledConsumer"
    source.mkdir(parents=True)
    (source / "VerifyBundledCompiler.swift").write_bytes((Path(__file__).parent / "VerifyBundledCompiler.swift").read_bytes())
    print("Created", output, "; run swift run --package-path", output, "BundledConsumer NEW_RESULTS_DIRECTORY")


if __name__ == "__main__":
    main()
