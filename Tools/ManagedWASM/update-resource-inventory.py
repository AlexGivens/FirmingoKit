"""Maintain SDK-local pending resource inventory; never copy or approve a compiler service."""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    """Write deterministic resource metadata or verify checked-in bytes without changing them."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2] / "Sources/FirmingoKit/Resources/ManagedCompiler"
    if (root / "compiler.wasm").exists():
        raise SystemExit("Unapproved service must not be staged in the package")
    allowed = {"manifest.json", "host.html", "LICENSE-MIT", "LICENSE-APACHE", "catalogue.json", "inventory.json"}
    if any(p.name not in allowed or p.is_symlink() or not p.is_file() for p in root.iterdir()):
        raise SystemExit("Unexpected or unsafe staged compiler resource")
    catalogue = b'{"schema":1,"firmwareBuilds":[]}\n'
    if args.check:
        if (root / "catalogue.json").read_bytes() != catalogue:
            raise SystemExit("No reviewed production descriptors are staged; catalogue must remain empty")
    else:
        (root / "catalogue.json").write_bytes(catalogue)
    runtime = json.loads((root / "manifest.json").read_bytes())
    inventory = {
        "schema": 1,
        "recipe": {
            "identifier": runtime["recipe"], "sha256": runtime["recipeSHA256"],
            "board": "nano_rp2040_connect", "profile": "nano-managed-v1",
            "sourceContract": "nano-stateless-facade-v1", "qualification": "experimental-unqualified",
        },
        "service": {
            "path": "compiler.wasm", "bytes": 101196044,
            "sha256": "3e2544acf7f88f6f1d5fbce34648df8eb96dfff47afa242a3e008bc8f86e2f33",
            "abi": 2, "distributionReview": "pending",
        },
        "files": [],
    }
    for name in ["manifest.json", "host.html", "LICENSE-MIT", "LICENSE-APACHE", "catalogue.json"]:
        data = (root / name).read_bytes()
        inventory["files"].append({"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    data = (json.dumps(inventory, indent=2) + "\n").encode()
    if args.check:
        if (root / "inventory.json").read_bytes() != data:
            raise SystemExit("Resource inventory differs from deterministic pending metadata")
    else:
        (root / "inventory.json").write_bytes(data)
    print("Pending inventory SHA-256:", hashlib.sha256(data).hexdigest())


if __name__ == "__main__":
    main()
