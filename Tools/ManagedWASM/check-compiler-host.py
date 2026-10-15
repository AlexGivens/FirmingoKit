"""Check source-only Apple qualification hosts against built SDK modules; never link/launch apps or provision assets."""
from pathlib import Path
import argparse
import subprocess


def main():
    """Type-check macOS sources and compile optimized iOS objects so SIL isolation diagnostics also run."""
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ios-products", type=Path, help="built iOS SDK products; optimized source object only, no signing/device access")
    args = parser.parse_args()
    if args.ios_products:
        path = args.ios_products.absolute()
    else:
        products = subprocess.run(["swift", "build", "--show-bin-path"], cwd=root, capture_output=True, text=True, timeout=30)
        if products.returncode: raise SystemExit(products.stderr)
        path = Path(products.stdout.strip())
    if not path.is_absolute() or not path.is_dir(): raise SystemExit("Build SDK products before type-checking the host")
    # The maintained Apple workflow declares ARM64. A translated Python process's
    # machine string does not identify the architecture of the built Swift module.
    architecture = "arm64"
    target = architecture + ("-apple-ios17.0" if args.ios_products else "-apple-macos14.0")
    cache = root / ".build/compiler-host-typecheck" / ("ios-cache" if args.ios_products else "cache"); cache.mkdir(parents=True, exist_ok=True)
    mode = ["-emit-object", "-whole-module-optimization", "-O"] if args.ios_products else ["-typecheck"]
    command = ["xcrun", "swiftc", *mode, "-parse-as-library", "-swift-version", "6", "-warnings-as-errors",
               "-enable-upcoming-feature", "ApproachableConcurrency", "-target", target,
               "-module-cache-path", str(cache), "-I", str(path), "-I", str(path / "Modules"),
               str(root / "Validation/CompilerHost/QualificationChecks.swift"), str(root / "Validation/CompilerHost/QualificationApp.swift"),
               str(root / "Validation/CompilerHost/QualificationStress.swift"),
               str(root / "Validation/CompilerHost/QualificationLifecycle.swift")]
    if args.ios_products:
        sdk = subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], check=True, capture_output=True, text=True, timeout=15)
        command.extend(["-sdk", sdk.stdout.strip(), "-o", str(cache / "qualification-host.o")])
    subprocess.run(command, cwd=root, check=True, timeout=90)
    print("Source-only compiler qualification host " + ("optimized iOS compilation" if args.ios_products else "macOS type-check")
          + " passed; no app linking/signing/runtime/device claim")


if __name__ == "__main__":
    main()
