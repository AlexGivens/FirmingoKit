"""Validate real public-deadline expiry and same-process foreground recovery; never launch an app or contact a board."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import uuid


def number(value, maximum=180):
    """Reject booleans and nonfinite, negative or unbounded elapsed observations."""
    return type(value) in (int, float) and math.isfinite(value) and 0 <= value <= maximum


def check(data, run_id, process_id, expected_context):
    """Require exact independent launch context, typed 60-second timeout, source-phase progress and known fresh output."""
    if len(data) > 65536 or str(uuid.UUID(run_id)).upper() != run_id or type(process_id) is not int or process_id <= 0:
        raise ValueError("select bounded evidence and an exact launch UUID/PID")
    r = json.loads(data)
    if (type(r["schema"]) is not int or r["schema"] != 6 or r["kind"] != "production-deadline-fresh-recovery"
            or r["runID"] != run_id or r["status"] != "passed" or r["stage"] != "complete" or r.get("error") is not None
            or type(r["hostProcessID"]) is not int or r["hostProcessID"] != process_id or r["deviceOperations"] is not False
            or r["firmwareBuildID"] != "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f"
            or type(r["runtimeDeadlineSeconds"]) is not int or r["runtimeDeadlineSeconds"] != 60
            or type(r["observationLimitSeconds"]) is not int or r["observationLimitSeconds"] != 180
            or r["workloadSHA256"] != "bde5df426deb79fd8277abfd5b406cf1288b28b307646b62bc5ee1028cce26eb"
            or type(r["workloadBytes"]) is not int or r["workloadBytes"] != 227646
            or r["outcome"] != "timedOut" or r["artifactReturned"] is not False):
        raise ValueError("deadline journal is failed, incomplete, stale or mismatched")
    context = r["context"]
    if (context != expected_context
            or context["consumerManifestSHA256"] != "d042dc7d3869949d8e311fff28c5d66327ba090ba2ec8ff149e3a12019d8ea8c"
            or not re.fullmatch(r"[0-9a-f]{40}", context["sdkCommit"])
            or not re.fullmatch(r"[0-9a-f]{64}", context["preparedManifestSHA256"])):
        raise ValueError("unexpected deadline context")
    began, settled, fresh = (r[key] for key in ("deadlineStartedSeconds", "deadlineSettledSeconds", "freshStartedSeconds"))
    if (not all(number(t) for t in (began, settled, fresh)) or not 60 <= settled - began <= 75 or fresh < settled):
        raise ValueError("missing production-duration settlement before fresh admission")
    progress = r["progress"]
    if [p["phase"] for p in progress] != ["verifying", "verifying", "preparing", "compiling"]:
        raise ValueError("deadline did not expire in the first observed source-compilation interval")
    previous = began
    for p in progress:
        if not number(p["seconds"]) or not previous <= p["seconds"] <= settled:
            raise ValueError("invalid deadline progress timing")
        previous = p["seconds"]
    events = r["events"]
    if not 1 <= len(events) <= 64: raise ValueError("missing bounded actual foreground observations")
    previous = -1
    for e in events:
        if (not number(e["seconds"]) or e["seconds"] < previous or e["seconds"] > fresh + r["steps"][-1]["seconds"]
                or e["phase"] not in ("active", "inactive", "background")
                or e["stage"] not in ("waiting-for-active", "before-deadline-gpio", "deadline", "after-timeout", "fresh-after-deadline-console")
                or (e["phase"] != "active" and e["stage"] != "waiting-for-active")
                or (e["stage"] == "waiting-for-active" and e["seconds"] > began)):
            raise ValueError("foreground was lost or deadline scene observations are invalid")
        previous = e["seconds"]
    if not any(e["phase"] == "active" and e["seconds"] <= began for e in events):
        raise ValueError("missing actual active admission")
    expected = [("before-deadline-gpio", "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"),
                ("fresh-after-deadline-console", "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0")]
    if len(r["steps"]) != 2: raise ValueError("missing known baseline or fresh build")
    for step, (name, digest) in zip(r["steps"], expected):
        if (step["name"] != name or step["capsuleSHA256"] != digest or not number(step["seconds"], 75)
                or type(step["wasmLinearMemoryBytes"]) is not int or not 0 < step["wasmLinearMemoryBytes"] <= 256 * 1024**2):
            raise ValueError("invalid deadline recovery artifact or runtime measurement")
    if r["steps"][0]["seconds"] > began or fresh + r["steps"][1]["seconds"] > 180:
        raise ValueError("known builds exceed bounded ordered run")
    return {"status": "passed_production_deadline_checks", "runID": run_id, "hostProcessID": process_id,
            "reportSHA256": hashlib.sha256(data).hexdigest(), "context": context,
            "runtimeDeadlineSeconds": 60, "deadlineElapsedSeconds": settled - began,
            "deadlineStartedSeconds": began, "deadlineSettledSeconds": settled, "freshStartedSeconds": fresh,
            "outcome": r["outcome"], "artifactReturned": r["artifactReturned"], "progress": progress,
            "events": events, "steps": r["steps"], "workloadSHA256": r["workloadSHA256"], "workloadBytes": r["workloadBytes"],
            "scope": "Actual public 60-second runtime deadline and same-instance foreground recovery; no injected timer, OS suspension, aggregate memory or board claim"}


def main():
    """Read only explicit bounded local evidence and independently selected generated provenance."""
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("report", type=Path); p.add_argument("run_id"); p.add_argument("process_id", type=int); p.add_argument("host_inputs", type=Path)
    a = p.parse_args()
    with a.report.open("rb") as source: data = source.read(65537)
    with a.host_inputs.open("rb") as source: inputs = source.read(262145)
    if len(inputs) > 262144: raise ValueError("excessive host inputs")
    print(json.dumps(check(data, a.run_id, a.process_id, json.loads(inputs)["context"]), sort_keys=True))


if __name__ == "__main__":
    try: main()
    except (ValueError, OSError, KeyError, TypeError, IndexError) as error: raise SystemExit(str(error)) from error
