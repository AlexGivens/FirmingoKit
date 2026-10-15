"""Generate an Apple compiler qualification app from an independently anchored prepared SDK; no installation or signing."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat

ROOT = Path(__file__).resolve().parents[2]
MAXIMUM = 400 * 1024**2


def identity(path, maximum=MAXIMUM):
    """Stream an ordinary bounded file without blocking on special files or following its final symlink."""
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= maximum:
            raise ValueError("select bounded regular prepared-package files")
        digest = hashlib.sha256(); count = 0
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            while data := stream.read(1024**2):
                count += len(data)
                if count > before.st_size: raise ValueError("prepared input grew")
                digest.update(data)
        after = os.fstat(descriptor)
        if count != before.st_size or (before.st_mtime_ns, before.st_size) != (after.st_mtime_ns, after.st_size):
            raise ValueError("prepared input changed during read")
        return {"bytes": count, "sha256": digest.hexdigest()}
    finally:
        os.close(descriptor)


def prepared_sdk(root, expected):
    """Verify the explicit source snapshot and compiler/source delivery before creating a host project."""
    if root.is_symlink() or not root.is_dir() or not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("select a real prepared SDK and an independently trusted SHA-256")
    path = root / "prepared-package.json"
    if identity(path, 262144)["sha256"] != expected: raise ValueError("prepared SDK anchor mismatch")
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected: raise ValueError("prepared SDK inventory changed")
    value = json.loads(data)
    if (value["schema"] != 1 or value["operation"] != "prepared_experimental_sdk_package"
            or value["qualification"] != "experimental-unqualified" or value["published"] is not False
            or value["consumerManifestSHA256"] != "d042dc7d3869949d8e311fff28c5d66327ba090ba2ec8ff149e3a12019d8ea8c"
            or not re.fullmatch(r"[0-9a-f]{40}", value["sdkCommit"]) or not 1 <= len(value["files"]) <= 1024):
        raise ValueError("unsupported prepared SDK snapshot")
    names = set(); total = 0
    for record in value["files"]:
        name = record["path"]
        if (not isinstance(name, str) or not re.fullmatch(r"[a-zA-Z0-9_./+-]+", name)
                or any(part in ("", ".", "..", ".git") for part in name.split("/")) or name in names
                or type(record["bytes"]) is not int or not 0 < record["bytes"] <= MAXIMUM):
            raise ValueError("unsafe prepared SDK inventory")
        names.add(name); total += record["bytes"]
        if total > 512 * 1024**2: raise ValueError("excessive prepared SDK")
        source = root / name
        if any(parent.is_symlink() for parent in source.parents if parent != root and root in parent.parents):
            raise ValueError("symlinked prepared SDK directory")
        if identity(source, record["bytes"]) != {key: record[key] for key in ("bytes", "sha256")}:
            raise ValueError("prepared SDK payload mismatch: " + name)
    if identity(path, 262144)["sha256"] != expected: raise ValueError("prepared SDK inventory changed during verification")
    records = {record["path"]: record for record in value["files"]}
    resource = "Sources/FirmingoKit/Resources/ManagedCompiler/"
    for name, pin in ((resource + "compiler.wasm", "a7648688ae9e349304c576804367b66b68b22185060a847a2e292675329ca493"),
                      (resource + "inventory.json", "e3c6080b78d2014cf82ca54f4605647f5e3b3967a8acb23c0daff2812475acf2"),
                      (resource + "consumer-package.json", value["consumerManifestSHA256"]),
                      ("CompilerDelivery/compiler-source.tar.gz", "dcdbe2d1fc2135dc726f06aa7b4fa4be9d81ac61f5fba2969d464f21b86089ef")):
        if records.get(name, {}).get("sha256") != pin: raise ValueError("prepared SDK omits reviewed compiler/source roles")
    return value


def generate(sdk, expected, output):
    """Generate only a new project, embedding static provenance and no device/transport capabilities."""
    value = prepared_sdk(sdk, expected)
    source = ROOT / "Validation/CompilerHost"
    output.mkdir()
    try:
        sources = output / "Sources"; sources.mkdir()
        for name in ("QualificationApp.swift", "QualificationChecks.swift", "QualificationStress.swift"):
            shutil.copyfile(source / name, sources / name)
        context = {"preparedManifestSHA256": expected, "sdkCommit": value["sdkCommit"], "consumerManifestSHA256": value["consumerManifestSHA256"]}
        (sources / "qualification-context.json").write_text(json.dumps(context, indent=2) + "\n")
        project = output / "CompilerQualification.xcodeproj"; project.mkdir()
        template = (source / "project.pbxproj.template").read_text()
        if template.count("SDK_RELATIVE_PATH") != 1: raise ValueError("unsupported host project template")
        (project / "project.pbxproj").write_text(template.replace("SDK_RELATIVE_PATH", json.dumps(os.path.relpath(sdk, output))))
        scheme = project / "xcshareddata/xcschemes"; scheme.mkdir(parents=True)
        shutil.copyfile(source / "scheme.xcscheme", scheme / "CompilerQualification.xcscheme")
        info = {"CFBundleDevelopmentRegion": "en", "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "$(PRODUCT_NAME)", "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False}, "UILaunchScreen": {},
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
                "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]}
        (output / "Info.plist").write_bytes(plistlib.dumps(info))
        (output / "CompilerQualification.entitlements").write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True,
                                                                                 "com.apple.security.network.client": True}))
        files = [{"path": path.relative_to(output).as_posix(), **identity(path)} for path in sorted(output.rglob("*")) if path.is_file()]
        receipt = {"schema": 1, "operation": "generated_compiler_qualification_host", "context": context, "files": files,
                   "signed": False, "installed": False, "deviceOperations": False}
        (output / "host-inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
        return receipt
    except BaseException:
        shutil.rmtree(output)
        raise


def main():
    """Require explicit prepared bytes/anchor and a new output directory; device facilitation remains separate."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sdk", type=Path); parser.add_argument("prepared_sha256"); parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = generate(args.sdk.absolute(), args.prepared_sha256, args.output.absolute())
    print(json.dumps({"status": result["operation"], "files": len(result["files"]), "signed": False, "installed": False}))


if __name__ == "__main__":
    try: main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        raise SystemExit(str(error)) from error
