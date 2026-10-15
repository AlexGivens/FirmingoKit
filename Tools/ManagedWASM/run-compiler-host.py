"""Verify and run an already signed macOS compiler qualification app; export only its own test journal."""
import argparse
import base64
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import plistlib
import re
import subprocess
import time
import uuid


DEADLINE_ARTIFACTS = {
    "before-deadline-gpio.fms": (316, "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"),
    "fresh-after-deadline-console.fms": (392, "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0")}


def signature(app, team, *, identifier="com.firmingokit.compilerqualification"):
    """Require the expected signed identifier, team, hardened runtime and finite sandbox entitlements before launch."""
    if app.is_symlink() or not app.is_dir() or not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("select a real signed app and expected Apple development team")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, capture_output=True, timeout=30)
    result = subprocess.run(["codesign", "-dvvv", str(app)], check=True, capture_output=True, text=True, timeout=15)
    details = result.stderr
    if ("Identifier=" + identifier + "\n" not in details or "TeamIdentifier=" + team + "\n" not in details
            or "flags=0x10000(runtime)" not in details or "Authority=Apple Development:" not in details):
        raise ValueError("app signature does not match the selected development/sandbox host")
    result = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(app)], check=True, capture_output=True, timeout=15)
    entitlements = plistlib.loads(result.stdout)
    if entitlements != {"com.apple.security.app-sandbox": True, "com.apple.security.network.client": True}:
        raise ValueError("unexpected qualification app entitlements")
    return details, entitlements


def report_envelope(data):
    """Extract exactly one bounded journal from the app's inherited stdout."""
    if len(data) > 1024**2: raise ValueError("excessive app output")
    prefix = b"FIRMINGO_COMPILER_REPORT:"
    envelopes = [line[len(prefix):] for line in data.splitlines() if line.startswith(prefix)]
    if len(envelopes) != 1: raise ValueError("missing or ambiguous qualification journal")
    decoded = base64.b64decode(envelopes[0], validate=True)
    if len(decoded) > 65536: raise ValueError("excessive qualification journal")
    return decoded


def decode_report(data, run_id):
    """Correlate the original schema-one run and require all six actual completed checks."""
    decoded = report_envelope(data)
    report = json.loads(decoded)
    if (report["schema"] != 1 or report["runID"] != run_id or report["status"] != "passed" or report["stage"] != "complete"
            or report["deviceOperations"] is not False
            or [step["name"] for step in report["steps"]] != ["resources", "cold-gpio", "warm-console", "frontend-error", "busy-cancellation", "fresh-after-cancellation"]):
        raise ValueError("qualification journal is incomplete, stale or failed")
    context = report["context"]
    if (report["firmwareBuildID"] != "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f"
            or context["consumerManifestSHA256"] != "1bbc0cc19d80490914799fbec5cb4bbc0a942a73fd3bbf6e09fff2c3856e660a"
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


def decode_artifacts(data, run_id, expected):
    """Check a closed caller-selected test manifest, unique run-bound envelopes and actual bytes before writing files."""
    if len(data) > 1024**2: raise ValueError("excessive app output")
    prefix = b"FIRMINGO_COMPILER_ARTIFACT:"
    envelopes = [line[len(prefix):] for line in data.splitlines() if line.startswith(prefix)]
    if len(envelopes) != len(expected): raise ValueError("missing or ambiguous exported capsules")
    result = {}
    for envelope in envelopes:
        if len(envelope) > 4096: raise ValueError("excessive artifact envelope")
        value = json.loads(base64.b64decode(envelope, validate=True))
        if (set(value) != {"runID", "path", "base64"} or value["runID"] != run_id
                or not isinstance(value["path"], str) or value["path"] not in expected or value["path"] in result
                or not isinstance(value["base64"], str)):
            raise ValueError("stale, duplicate or unexpected exported capsule")
        raw = base64.b64decode(value["base64"], validate=True)
        size, digest = expected[value["path"]]
        if len(raw) != size or hashlib.sha256(raw).hexdigest() != digest:
            raise ValueError("exported capsule bytes do not match the independent vector")
        result[value["path"]] = raw
    return result


def run(app, team, output, *, deadline=False, host_inputs=None):
    """Launch one verified app with a fresh UUID and bounded time; no private-container or native-UI inspection occurs."""
    details, entitlements = signature(app, team)
    expected_context = None
    if deadline:
        if host_inputs is None: raise ValueError("deadline mode requires independently selected host-inputs.json")
        with host_inputs.open("rb") as source: inputs = source.read(262145)
        if len(inputs) > 262144: raise ValueError("excessive host inputs")
        expected_context = json.loads(inputs)["context"]
    elif host_inputs is not None:
        raise ValueError("host inputs are selected only with --deadline")
    output.mkdir()
    run_id = str(uuid.uuid4()).upper()
    started = time.monotonic()
    try:
        (output / "signature.txt").write_text(details)
        with (output / "stdout.log").open("xb") as stdout, (output / "stderr.log").open("xb") as stderr:
            arguments = [str(app / "Contents/MacOS/CompilerQualification"), "--qualification-run", run_id, "--qualification-quit"]
            if deadline: arguments.append("--qualification-deadline")
            process = subprocess.Popen(arguments, stdout=stdout, stderr=stderr)
            try:
                (output / "launch.json").write_text(json.dumps({"runID": run_id, "processID": process.pid, "mode": "deadline" if deadline else "original-six"}) + "\n")
                returncode = process.wait(timeout=180)
            except BaseException:
                if process.poll() is None: process.kill()
                process.wait(timeout=10)
                raise
        if returncode: raise ValueError("qualification app exited unsuccessfully")
        stdout = output / "stdout.log"
        if stdout.stat().st_size > 1024**2: raise ValueError("excessive app output")
        raw = stdout.read_bytes()
        artifacts = None
        if deadline:
            data = report_envelope(raw)
            spec = importlib.util.spec_from_file_location("compiler_deadline", Path(__file__).with_name("check-compiler-deadline.py"))
            checker = importlib.util.module_from_spec(spec); spec.loader.exec_module(checker)
            report = checker.check(data, run_id, process.pid, expected_context)
            artifacts = decode_artifacts(raw, run_id, DEADLINE_ARTIFACTS)
        else: data, report = decode_report(raw, run_id)
        (output / "report.json").write_bytes(data)
        summary = {"schema": 1, "status": "passed_signed_sandbox_compiler_host", "runID": run_id,
                   "teamIdentifier": team, "entitlements": entitlements, "hardenedRuntime": True,
                   "seconds": time.monotonic() - started, "reportSHA256": hashlib.sha256(data).hexdigest(),
                   "context": report["context"], "deviceOperations": False}
        if deadline:
            summary["status"] = "passed_signed_sandbox_deadline_host"
            summary["hostInputsSHA256"] = hashlib.sha256(inputs).hexdigest()
            summary["deadline"] = report
            summary["artifacts"] = []
            for name, contents in artifacts.items():
                (output / name).write_bytes(contents)
                summary["artifacts"].append({"path": name, "bytes": len(contents), "sha256": hashlib.sha256(contents).hexdigest()})
        (output / "operation.json").write_text(json.dumps(summary, indent=2) + "\n")
        return summary
    except BaseException as error:
        (output / "failure.json").write_text(json.dumps({"status": "failed_compiler_host", "runID": run_id, "detail": str(error)[:2048]}) + "\n")
        raise


def main():
    """Keep signing separate and require a new local results directory; hardware/deployment remain explicit workflows."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deadline", action="store_true", help="run the real public 60-second deadline and validate exported known capsule bytes")
    parser.add_argument("--host-inputs", type=Path, help="independently selected generated provenance, required with --deadline")
    parser.add_argument("app", type=Path); parser.add_argument("team"); parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(run(args.app.absolute(), args.team, args.output.absolute(), deadline=args.deadline, host_inputs=args.host_inputs), sort_keys=True))


if __name__ == "__main__":
    try: main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error
