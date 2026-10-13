"""Read-only integrity check for an unsigned demo archive's SDK compiler resources."""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    """Require the exact current SDK inventory/roles, empty catalogue and absent unapproved service."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    sdk = Path(__file__).resolve().parents[2]
    expected_root = sdk / "Sources/FirmingoKit/Resources/ManagedCompiler"
    matches = list(args.archive.glob("Products/Applications/*.app/Contents/Resources/FirmingoKit_FirmingoKit.bundle/Contents/Resources/ManagedCompiler/inventory.json"))
    if len(matches) != 1:
        raise SystemExit("Expected exactly one macOS app SDK resource inventory")
    root = matches[0].parent
    roles = {"manifest.json", "host.html", "LICENSE-MIT", "LICENSE-APACHE", "catalogue.json",
             "Firmingo-Compiler-LICENSE", "compiler-package.json", "compiler-sources.json"}
    allowed = roles | {"inventory.json"}
    if root.is_symlink() or any(p.name not in allowed or p.is_symlink() or not p.is_file() for p in root.iterdir()):
        raise SystemExit("Unexpected or unsafe archived compiler resource")
    data = matches[0].read_bytes()
    if data != (expected_root / "inventory.json").read_bytes():
        raise SystemExit("Archived inventory differs from the current SDK resource set")
    inventory = json.loads(data)
    if inventory["service"]["distributionReview"] != "pending" or (root / "compiler.wasm").exists():
        raise SystemExit("This SDK resource set must remain pending and service-free")
    for file in inventory["files"]:
        if file["path"] not in roles:
            raise SystemExit("Unexpected resource role")
        resource = root / file["path"]
        if resource.is_symlink():
            raise SystemExit("Symlinked archived resource")
        content = resource.read_bytes()
        if len(content) != file["bytes"] or hashlib.sha256(content).hexdigest() != file["sha256"]:
            raise SystemExit("Archived resource integrity mismatch: " + file["path"])
    if json.loads((root / "catalogue.json").read_bytes())["firmwareBuilds"]:
        raise SystemExit("No reviewed production descriptors are staged in this SDK")
    print("Unsigned archive: inventory, eight roles, empty catalogue and absent service verified")
    print("ManagedCompiler directory bytes:", sum(p.stat().st_size for p in root.rglob("*") if p.is_file()))


if __name__ == "__main__":
    main()
