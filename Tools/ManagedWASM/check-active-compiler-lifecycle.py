"""Check explicit host cancellation of an active SDK call and fresh foreground recovery; no device action."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import uuid


def number(value, maximum=780):
    """Reject booleans and nonfinite, negative or unbounded observations."""
    return type(value) in (int, float) and math.isfinite(value) and 0 <= value <= maximum


def artifact(step, name, digest):
    """Validate independently pinned known outputs and finite runtime measurements."""
    if (step["name"] != name or step["capsuleSHA256"] != digest or not number(step["seconds"], 180)
            or type(step["wasmLinearMemoryBytes"]) is not int or not 0 < step["wasmLinearMemoryBytes"] <= 256 * 1024**2):
        raise ValueError("unexpected active lifecycle artifact or measurement")


def check(data, run_id, process_id, expected_context):
    """Require exact launch identity, typed no-artifact cancellation, real scene transitions and fresh known output."""
    if (len(data) > 65536 or str(uuid.UUID(run_id)).upper() != run_id or type(process_id) is not int or process_id <= 0):
        raise ValueError("select a bounded report and exact launch UUID/PID")
    r = json.loads(data)
    if (type(r["schema"]) is not int or r["schema"] != 4 or r["kind"] != "inactive-cancel-background-return"
            or r["runID"] != run_id or r["status"] != "passed" or r["stage"] != "complete" or r.get("error") is not None
            or type(r["hostProcessID"]) is not int or r["hostProcessID"] != process_id or r["deviceOperations"] is not False
            or r["firmwareBuildID"] != "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f"
            or type(r["observationLimitSeconds"]) is not int or r["observationLimitSeconds"] != 600
            or type(r["maximumAttempts"]) is not int or r["maximumAttempts"] != 40
            or type(r["minimumBackgroundSeconds"]) is not int or r["minimumBackgroundSeconds"] != 3):
        raise ValueError("active lifecycle journal is failed, incomplete, stale or mismatched")
    context = r["context"]
    if (context != expected_context
            or context["consumerManifestSHA256"] != "d042dc7d3869949d8e311fff28c5d66327ba090ba2ec8ff149e3a12019d8ea8c"
            or not re.fullmatch(r"[0-9a-f]{40}", context["sdkCommit"])
            or not re.fullmatch(r"[0-9a-f]{64}", context["preparedManifestSHA256"])):
        raise ValueError("unexpected active lifecycle context")
    c = r["cancellation"]
    if (not isinstance(c, dict) or type(c["attempt"]) is not int or not 1 <= c["attempt"] <= 40
            or c["outcome"] != "cancelled" or c["artifactReturned"] is not False
            or not number(c["requestedSeconds"], 600) or not number(c["settledSeconds"])
            or c["settledSeconds"] < c["requestedSeconds"]
            or c["lastProgress"] not in ("verifying", "preparing", "compiling", "linking", "packaging")
            or not number(r["manuallyStartedSeconds"], 600) or r["manuallyStartedSeconds"] > c["requestedSeconds"]):
        raise ValueError("missing exact active-call cancellation and typed settlement")
    gpio = "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"
    console = "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0"
    if len(r["steps"]) != 2 or len(r["completedAttempts"]) != c["attempt"] - 1:
        raise ValueError("missing known builds or inconsistent canceled attempt")
    artifact(r["steps"][0], "before-active-gpio", gpio)
    artifact(r["steps"][1], "fresh-after-active-cancel-console", console)
    for index, step in enumerate(r["completedAttempts"], 1): artifact(step, f"active-{index}-gpio", gpio)
    events = r["events"]
    if not 4 <= len(events) <= 64: raise ValueError("missing bounded real scene events")
    previous = -1
    for e in events:
        if (not number(e["seconds"]) or e["seconds"] < previous or e["phase"] not in ("active", "inactive", "background")
                or e["stage"] not in ("waiting-for-active", "before-active-gpio", "waiting-for-start", "active-builds",
                                      "awaiting-cancellation", "waiting-for-return", "fresh-after-active-cancel-console")):
            raise ValueError("invalid active lifecycle event")
        previous = e["seconds"]
    inactive = next((i for i, e in enumerate(events) if e["phase"] == "inactive" and e["stage"] == "active-builds"
                     and e["seconds"] == c["requestedSeconds"]), None)
    background = next((i for i, e in enumerate(events) if inactive is not None and i > inactive and e["phase"] == "background"), None)
    active = next((e for i, e in enumerate(events) if background is not None and i > background and e["phase"] == "active"), None)
    if (active is None or active["seconds"] > 600 or active["seconds"] - events[background]["seconds"] < 3
            or not any(e["phase"] == "active" and e["seconds"] <= r["manuallyStartedSeconds"] for e in events)
            or not number(r["freshStartedSeconds"], 600)
            or r["freshStartedSeconds"] < max(active["seconds"], c["settledSeconds"])):
        raise ValueError("missing ordered inactive cancellation, background/return and fresh admission")
    return {"status": "passed_active_call_lifecycle_checks", "runID": run_id, "hostProcessID": process_id,
            "reportSHA256": hashlib.sha256(data).hexdigest(), "context": context, "cancellation": c,
            "backgroundToActiveSeconds": active["seconds"] - events[background]["seconds"],
            "freshStartedSeconds": r["freshStartedSeconds"], "events": events, "steps": r["steps"],
            "completedAttempts": r["completedAttempts"],
            "scope": "Host requested cancellation on inactivity while SDK call pending; last progress is not an instruction pointer; no OS suspension or pressure claim"}


def main():
    """Read only explicit bounded local evidence and independently selected generated context."""
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("report", type=Path); p.add_argument("run_id"); p.add_argument("process_id", type=int); p.add_argument("host_inputs", type=Path)
    a = p.parse_args()
    with a.report.open("rb") as source: data = source.read(65537)
    with a.host_inputs.open("rb") as source: inputs = source.read(262145)
    if len(inputs) > 262144: raise ValueError("excessive host inputs")
    print(json.dumps(check(data, a.run_id, a.process_id, json.loads(inputs)["context"]), sort_keys=True))


if __name__ == "__main__":
    try: main()
    except (ValueError, OSError, KeyError, TypeError) as error: raise SystemExit(str(error)) from error
