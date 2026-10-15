"""Type-check the source-only Apple qualification host against the locally built SDK; never launch UI or provision assets."""
from pathlib import Path
import subprocess


def main():
    """Use SwiftPM's actual product path so both maintained module layouts work on Apple CI."""
    root = Path(__file__).resolve().parents[2]
    products = subprocess.run(["swift", "build", "--show-bin-path"], cwd=root, capture_output=True, text=True, timeout=30)
    if products.returncode: raise SystemExit(products.stderr)
    path = Path(products.stdout.strip())
    if not path.is_absolute() or not path.is_dir(): raise SystemExit("Build SDK products before type-checking the host")
    # The maintained Apple workflow declares ARM64. A translated Python process's
    # machine string does not identify the architecture of the built Swift module.
    architecture = "arm64"
    cache = root / ".build/compiler-host-typecheck/cache"; cache.mkdir(parents=True, exist_ok=True)
    command = ["xcrun", "swiftc", "-typecheck", "-parse-as-library", "-swift-version", "6", "-warnings-as-errors",
               "-enable-upcoming-feature", "ApproachableConcurrency", "-target", architecture + "-apple-macos14.0",
               "-module-cache-path", str(cache), "-I", str(path), "-I", str(path / "Modules"),
               str(root / "Validation/CompilerHost/QualificationChecks.swift"), str(root / "Validation/CompilerHost/QualificationApp.swift")]
    subprocess.run(command, cwd=root, check=True, timeout=90)
    print("Source-only compiler qualification host type-check passed; no signed/runtime/device claim")


if __name__ == "__main__":
    main()
