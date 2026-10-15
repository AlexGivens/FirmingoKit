#!/usr/bin/env python3
"""Verify SDK-local firmware/parser/metadata fixtures against their independent provenance manifests."""
import hashlib
import json
from pathlib import Path


def verify_files(root, manifest, fixture_root):
    """Check safe paths, digests, and independent FMGO or synthetic UF2 hex structure."""
    for entry in manifest["files"]:
        path = (root / entry["path"]).resolve()
        if not path.is_relative_to(fixture_root):
            raise ValueError(f"Unsafe fixture path: {entry['path']}")
        data = path.read_bytes()
        if len(data) != entry["bytes"] or hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise ValueError(f"Fixture integrity mismatch: {entry['path']}")
        if path.name.endswith(".uf2.hex"):
            image = bytes.fromhex(data.decode("ascii"))
            if len(image) != manifest["synthetic_decoded_bytes"] or hashlib.sha256(image).hexdigest() != manifest["synthetic_decoded_sha256"]:
                raise ValueError(f"Synthetic UF2 integrity mismatch: {entry['path']}")
            if not image or len(image) % 512 or image[:4] != b"UF2\n":
                raise ValueError(f"Invalid synthetic UF2 structure: {entry['path']}")
        elif "compiler-stateful" in path.parts and path.suffix == ".hex":
            image = bytes.fromhex(data.decode("ascii"))
            if not image or image[:4] not in (b"\x7fELF", b"FMS2"):
                raise ValueError("Invalid compiler stateful fixture")
        elif path.name.endswith(".elf.hex"):
            image = bytes.fromhex(data.decode("ascii"))
            if len(image) != manifest["synthetic_decoded_bytes"] or hashlib.sha256(image).hexdigest() != manifest["synthetic_decoded_sha256"]:
                raise ValueError(f"Synthetic ELF integrity mismatch: {entry['path']}")
            if len(image) < 52 or image[:7] != b"\x7fELF\x01\x01\x01":
                raise ValueError(f"Invalid synthetic ELF structure: {entry['path']}")
        elif path.suffix == ".hex":
            frame = bytes.fromhex(data.decode("ascii"))
            if len(frame) < 16 or frame[:4] != b"FMGO" or len(frame) != 16 + int.from_bytes(frame[12:16], "big"):
                raise ValueError(f"Invalid golden frame: {entry['path']}")
    origin = manifest.get("commit", "independently authored SDK metadata parser inputs")
    print(f"Verified {len(manifest['files'])} fixtures from {origin}.")


def main():
    """Verify SDK-local provenance sets without reading a reference checkout."""
    root = Path(__file__).resolve().parents[1]
    fixture_root = (root / "Tests/FirmingoKitTests/Fixtures").resolve()
    for name in ["provenance.json", "lifecycle/provenance.json", "compiler/provenance.json", "compiler-catalogue/provenance.json", "compiler-offline/provenance.json", "compiler-stateful/sdk-provenance.json"]:
        manifest = json.loads((fixture_root / name).read_text())
        verify_files(root, manifest, fixture_root)
        if name == "compiler-catalogue/provenance.json":
            descriptor = json.loads((fixture_root / "compiler-catalogue/descriptor.json").read_text())
            canonical = json.dumps(descriptor, sort_keys=True, separators=(",", ":")).encode()
            if hashlib.sha256(canonical).hexdigest() != manifest["descriptorID"]:
                raise ValueError("Synthetic catalogue descriptor identity mismatch")


if __name__ == "__main__":
    main()
