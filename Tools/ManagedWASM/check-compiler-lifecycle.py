"""Check an opt-in idle scene transition journal; no app/device action or active-build interruption claim."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import uuid


def number(value, maximum):
    """Reject booleans, nonfinite values and negative/out-of-run observations."""
    return type(value) in (int, float) and math.isfinite(value) and 0 <= value <= maximum


def check(data, run_id, process_id, expected_context):
    """Require exact launch context/PID, two pinned artifacts and ordered real idle background/return observations."""
    if (len(data) > 65536 or str(uuid.UUID(run_id)).upper() != run_id
            or type(process_id) is not int or process_id <= 0):
        raise ValueError("select a bounded lifecycle report and exact launch UUID/PID")
    r = json.loads(data)
    if (type(r["schema"]) is not int or r["schema"] != 3 or r["kind"] != "idle-background-return"
            or r["runID"] != run_id or r["status"] != "passed" or r["stage"] != "complete"
            or r["deviceOperations"] is not False or r.get("error") is not None
            or type(r["hostProcessID"]) is not int or r["hostProcessID"] != process_id
            or r["firmwareBuildID"] != "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f"
            or type(r["observationLimitSeconds"]) is not int or r["observationLimitSeconds"] != 600
            or type(r["minimumBackgroundSeconds"]) is not int or r["minimumBackgroundSeconds"] != 3):
        raise ValueError("lifecycle journal is failed, incomplete, stale or mismatched")
    context = r["context"]
    if (context != expected_context
            or context["consumerManifestSHA256"] != "d042dc7d3869949d8e311fff28c5d66327ba090ba2ec8ff149e3a12019d8ea8c"
            or not re.fullmatch(r"[0-9a-f]{40}", context["sdkCommit"])
            or not re.fullmatch(r"[0-9a-f]{64}", context["preparedManifestSHA256"])):
        raise ValueError("lifecycle compiler context differs from the selected host")
    pins = [("before-background-gpio", "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"),
            ("after-foreground-console", "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0")]
    if len(r["steps"]) != 2: raise ValueError("both lifecycle builds must complete")
    for step, (name, digest) in zip(r["steps"], pins):
        if (step["name"] != name or step["capsuleSHA256"] != digest or not number(step["seconds"], 180)
                or type(step["wasmLinearMemoryBytes"]) is not int or not 0 < step["wasmLinearMemoryBytes"] <= 256 * 1024**2):
            raise ValueError("unexpected lifecycle artifact, duration or worker memory")
    events = r["events"]
    if not 3 <= len(events) <= 64:
        raise ValueError("missing bounded initial active/transition observations")
    previous = -1
    for event in events:
        if (not number(event["seconds"], 780) or event["seconds"] < previous
                or event["phase"] not in ("active", "inactive", "background")
                or event["stage"] not in ("waiting-for-active", "before-background-gpio", "waiting-for-background", "after-foreground-console")):
            raise ValueError("invalid lifecycle event")
        previous = event["seconds"]
    idle = [e for e in events if e["stage"] == "waiting-for-background"]
    background = next((i for i, e in enumerate(idle) if e["phase"] == "background"), None)
    active = next((e for e in idle[background + 1:] if e["phase"] == "active"), None) if background is not None else None
    if (active is None or active["seconds"] > 600 or active["seconds"] - idle[background]["seconds"] < 3
            or not any(e["phase"] == "active" and e["seconds"] < idle[background]["seconds"] for e in events)):
        raise ValueError("missing sufficiently separated idle background/foreground observations")
    return {"status": "passed_idle_background_return_checks", "runID": run_id, "hostProcessID": process_id,
            "reportSHA256": hashlib.sha256(data).hexdigest(), "context": context,
            "backgroundToActiveSeconds": active["seconds"] - idle[background]["seconds"], "events": events,
            "steps": r["steps"], "scope": "Idle scene transition in one process; no suspension, active-build interruption or memory-pressure claim"}


def main():
    """Read explicit bounded local evidence and the launcher's expected host context; never infer a device target."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path); parser.add_argument("run_id"); parser.add_argument("process_id", type=int)
    parser.add_argument("host_inputs", type=Path)
    args = parser.parse_args()
    with args.report.open("rb") as source: data = source.read(65537)
    with args.host_inputs.open("rb") as source: context_data = source.read(262145)
    if len(context_data) > 262144: raise ValueError("excessive host context")
    context = json.loads(context_data)["context"]
    print(json.dumps(check(data, args.run_id, args.process_id, context), sort_keys=True))


if __name__ == "__main__":
    try: main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        raise SystemExit(str(error)) from error
