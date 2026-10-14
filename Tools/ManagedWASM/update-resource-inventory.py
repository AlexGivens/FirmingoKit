"""Maintain the reviewed service-free SDK inventory; never copy a compiler binary."""
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
    allowed = {"manifest.json", "host.html", "LICENSE-MIT", "LICENSE-APACHE", "catalogue.json", "inventory.json", "Firmingo-Compiler-LICENSE", "compiler-package.json", "compiler-sources.json",
               "service-review.json", "service-source-notices.json", "service-LICENSES.txt", "service-FILE-NOTICES.txt"}
    if any(p.name not in allowed or p.is_symlink() or not p.is_file() for p in root.iterdir()):
        raise SystemExit("Unexpected or unsafe staged compiler resource")
    catalogue = b'{"schema":1,"firmwareBuilds":[]}\n'
    if args.check:
        if (root / "catalogue.json").read_bytes() != catalogue:
            raise SystemExit("No reviewed production descriptors are staged; catalogue must remain empty")
    else:
        (root / "catalogue.json").write_bytes(catalogue)
    runtime = json.loads((root / "manifest.json").read_bytes())
    if hashlib.sha256((root / "service-review.json").read_bytes()).hexdigest() != "2627a80ee5845929f030cfec6253f05e3cfc4f8c98bff69a0117b3d78114cb26":
        raise SystemExit("Service review differs from independently reviewed pair")
    review = json.loads((root / "service-review.json").read_bytes())
    notice_data = (root / "service-source-notices.json").read_bytes()
    if hashlib.sha256(notice_data).hexdigest() != review["noticeManifest"]["sha256"]:
        raise SystemExit("Service notice inventory differs from review")
    for record in json.loads(notice_data)["files"]:
        if record["path"] in ("LICENSES.txt", "FILE-NOTICES.txt"):
            data = (root / ("service-" + record["path"])).read_bytes()
            if len(data) != record["bytes"] or hashlib.sha256(data).hexdigest() != record["sha256"]:
                raise SystemExit("Service notice text differs from reviewed source excerpts")
    inventory = {
        "schema": 1,
        "recipe": {
            "identifier": runtime["recipe"], "sha256": runtime["recipeSHA256"],
            "board": "nano_rp2040_connect", "profile": "nano-managed-v1",
            "sourceContract": "nano-stateless-facade-v1", "qualification": "experimental-unqualified",
        },
        "service": {
            "path": "compiler.wasm", "bytes": 101194565,
            "sha256": "a7648688ae9e349304c576804367b66b68b22185060a847a2e292675329ca493",
            "abi": 2, "distributionReview": "approved",
        },
        "files": [],
    }
    for name in ["manifest.json", "host.html", "LICENSE-MIT", "LICENSE-APACHE", "catalogue.json", "Firmingo-Compiler-LICENSE", "compiler-package.json", "compiler-sources.json",
                 "service-review.json", "service-source-notices.json", "service-LICENSES.txt", "service-FILE-NOTICES.txt"]:
        data = (root / name).read_bytes()
        inventory["files"].append({"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    data = (json.dumps(inventory, indent=2) + "\n").encode()
    if args.check:
        if (root / "inventory.json").read_bytes() != data:
            raise SystemExit("Resource inventory differs from deterministic reviewed metadata")
    else:
        (root / "inventory.json").write_bytes(data)
    print("Reviewed service-free inventory SHA-256:", hashlib.sha256(data).hexdigest())


if __name__ == "__main__":
    main()
