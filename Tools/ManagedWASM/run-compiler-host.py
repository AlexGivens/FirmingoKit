"""Verify and run an already signed macOS compiler qualification app; export only its own test journal."""
import argparse
import base64
import hashlib
import json
import math
from pathlib import Path
import plistlib
import re
import subprocess
import time
import uuid


def signature(app, team):
    """Require the expected signed identifier, team, hardened runtime and finite sandbox entitlements before launch."""
    if app.is_symlink() or not app.is_dir() or not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("select a real signed app and expected Apple development team")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, capture_output=True, timeout=30)
    result = subprocess.run(["codesign", "-dvvv", str(app)], check=True, capture_output=True, text=True, timeout=15)
    details = result.stderr
    if ("Identifier=com.firmingokit.compilerqualification\n" not in details or "TeamIdentifier=" + team + "\n" not in details
            or "flags=0x10000(runtime)" not in details or "Authority=Apple Development:" not in details):
        raise ValueError("app signature does not match the selected development/sandbox host")
    result = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(app)], check=True, capture_output=True, timeout=15)
    entitlements = plistlib.loads(result.stdout)
    if entitlements != {"com.apple.security.app-sandbox": True, "com.apple.security.network.client": True}:
        raise ValueError("unexpected qualification app entitlements")
    return details, entitlements


def decode_report(data, run_id):
    """Bound the explicit stdout envelope, correlate the run and require all six actual completed checks."""
    if len(data) > 1024**2: raise ValueError("excessive app output")
    prefix = b"FIRMINGO_COMPILER_REPORT:"
    envelopes = [line[len(prefix):] for line in data.splitlines() if line.startswith(prefix)]
    if len(envelopes) != 1: raise ValueError("missing or ambiguous qualification journal")
    decoded = base64.b64decode(envelopes[0], validate=True)
    if len(decoded) > 65536: raise ValueError("excessive qualification journal")
    report = json.loads(decoded)
    if (report["schema"] != 1 or report["runID"] != run_id or report["status"] != "passed" or report["stage"] != "complete"
            or report["deviceOperations"] is not False
            or [step["name"] for step in report["steps"]] != ["resources", "cold-gpio", "warm-console", "frontend-error", "busy-cancellation", "fresh-after-cancellation"]):
        raise ValueError("qualification journal is incomplete, stale or failed")
    context = report["context"]
    if (report["firmwareBuildID"] != "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f"
            or context["consumerManifestSHA256"] != "d042dc7d3869949d8e311fff28c5d66327ba090ba2ec8ff149e3a12019d8ea8c"
            or not re.fullmatch(r"[0-9a-f]{64}", context["preparedManifestSHA256"])
            or not re.fullmatch(r"[0-9a-f]{40}", context["sdkCommit"])):
        raise ValueError("unexpected qualification context")
    pins = {"cold-gpio": "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d",
            "warm-console": "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0",
            "fresh-after-cancellation": "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"}
    for step in report["steps"]:
        if type(step["seconds"]) not in (int, float) or not math.isfinite(step["seconds"]) or not 0 <= step["seconds"] <= 180:
            raise ValueError("invalid qualification measurement")
        if step["name"] in pins and (step.get("capsuleSHA256") != pins[step["name"]]
                or type(step.get("wasmLinearMemoryBytes")) is not int or not 0 < step["wasmLinearMemoryBytes"] <= 256 * 1024**2):
            raise ValueError("qualification artifact or memory mismatch")
    return decoded, report


def run(app, team, output):
    """Launch one verified app with a fresh UUID and bounded time; no private-container or native-UI inspection occurs."""
    details, entitlements = signature(app, team)
    output.mkdir()
    run_id = str(uuid.uuid4()).upper()
    started = time.monotonic()
    try:
        (output / "signature.txt").write_text(details)
        with (output / "stdout.log").open("xb") as stdout, (output / "stderr.log").open("xb") as stderr:
            result = subprocess.run([str(app / "Contents/MacOS/CompilerQualification"), "--qualification-run", run_id, "--qualification-quit"],
                                    stdout=stdout, stderr=stderr, timeout=180)
        if result.returncode: raise ValueError("qualification app exited unsuccessfully")
        stdout = output / "stdout.log"
        if stdout.stat().st_size > 1024**2: raise ValueError("excessive app output")
        data, report = decode_report(stdout.read_bytes(), run_id)
        (output / "report.json").write_bytes(data)
        summary = {"schema": 1, "status": "passed_signed_sandbox_compiler_host", "runID": run_id,
                   "teamIdentifier": team, "entitlements": entitlements, "hardenedRuntime": True,
                   "seconds": time.monotonic() - started, "reportSHA256": hashlib.sha256(data).hexdigest(),
                   "context": report["context"], "deviceOperations": False}
        (output / "operation.json").write_text(json.dumps(summary, indent=2) + "\n")
        return summary
    except BaseException as error:
        (output / "failure.json").write_text(json.dumps({"status": "failed_compiler_host", "runID": run_id, "detail": str(error)[:2048]}) + "\n")
        raise


def main():
    """Keep signing separate and require a new local results directory; hardware/deployment remain explicit workflows."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path); parser.add_argument("team"); parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(run(args.app.absolute(), args.team, args.output.absolute()), sort_keys=True))


if __name__ == "__main__":
    try: main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error
