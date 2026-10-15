"""Check a correlated completed repeated-build journal; footprint summaries exclude WebKit children and missed peaks."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re


def number(value, maximum):
    """Reject booleans, nonfinite values and impossible negative/out-of-run measurements."""
    return type(value) in (int, float) and math.isfinite(value) and 0 <= value <= maximum


def check(data, run_id, iterations):
    """Require fresh complete exact artifacts, bounded monotonic samples and the selected experimental context."""
    if len(data) > 2 * 1024**2 or type(iterations) is not int or not 2 <= iterations <= 40:
        raise ValueError("select a bounded stress report and two through forty builds")
    report = json.loads(data)
    if (type(report["schema"]) is not int or report["schema"] != 2 or report["kind"] != "repeated-builds"
            or report["runID"] != run_id or report["status"] != "passed" or report["stage"] != "complete"
            or type(report["iterations"]) is not int or report["iterations"] != iterations
            or report["deviceOperations"] is not False or type(report["hostProcessID"]) is not int or report["hostProcessID"] <= 0
            or report["firmwareBuildID"] != "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f"
            or len(report["steps"]) != iterations or report.get("error") is not None):
        raise ValueError("stress journal is failed, incomplete, stale or mismatched")
    context = report["context"]
    if (context["consumerManifestSHA256"] != "d042dc7d3869949d8e311fff28c5d66327ba090ba2ec8ff149e3a12019d8ea8c"
            or not re.fullmatch(r"[0-9a-f]{40}", context["sdkCommit"])
            or not re.fullmatch(r"[0-9a-f]{64}", context["preparedManifestSHA256"])):
        raise ValueError("unexpected stress compiler context")
    for index, step in enumerate(report["steps"], 1):
        gpio = index % 2 == 1
        expected = "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d" if gpio else "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0"
        if (step["name"] != f"build-{index}-" + ("gpio" if gpio else "console") or step["capsuleSHA256"] != expected
                or not number(step["seconds"], 180) or type(step["wasmLinearMemoryBytes"]) is not int
                or not 0 < step["wasmLinearMemoryBytes"] <= 256 * 1024**2):
            raise ValueError("unexpected repeated artifact, duration or worker memory")
    samples = report["hostFootprintSamples"]
    if not 2 <= len(samples) <= 4096 or type(report["droppedSamples"]) is not int or report["droppedSamples"] < 0:
        raise ValueError("missing or unbounded footprint samples")
    previous = 0
    for sample in samples:
        if (not number(sample["seconds"], 180) or sample["seconds"] < previous
                or type(sample["bytes"]) is not int or not 0 < sample["bytes"] < 2**50
                or not isinstance(sample["stage"], str) or len(sample["stage"]) > 64):
            raise ValueError("invalid footprint observation")
        previous = sample["seconds"]
    return {"status": "passed_repeated_build_checks", "runID": run_id, "iterations": iterations,
            "reportSHA256": hashlib.sha256(data).hexdigest(), "context": context,
            "hostFootprintSampleCount": len(samples), "hostFootprintFirstBytes": samples[0]["bytes"],
            "hostFootprintLastBytes": samples[-1]["bytes"], "hostFootprintSampledPeakBytes": max(s["bytes"] for s in samples),
            "droppedSamples": report["droppedSamples"], "memoryScope": "Host process samples only; excludes WebKit children and missed peaks; no leak-free claim"}


def main():
    """Read only a bounded explicitly selected local report; perform no app launch, signing or device action."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path); parser.add_argument("run_id"); parser.add_argument("iterations", type=int)
    args = parser.parse_args()
    if not args.report.is_file(): raise ValueError("select a regular journal file")
    with args.report.open("rb") as source: data = source.read(2 * 1024**2 + 1)
    print(json.dumps(check(data, args.run_id, args.iterations), sort_keys=True))


if __name__ == "__main__":
    try: main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        raise SystemExit(str(error)) from error
