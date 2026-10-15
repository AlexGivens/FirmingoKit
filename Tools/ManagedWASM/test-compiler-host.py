"""Tiny generator/file-boundary fixtures never sign, launch, compile source or contact a device."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("compiler_host", Path(__file__).with_name("make-compiler-host.py"))
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)
runner_spec = importlib.util.spec_from_file_location("compiler_host_runner", Path(__file__).with_name("run-compiler-host.py"))
runner = importlib.util.module_from_spec(runner_spec)
runner_spec.loader.exec_module(runner)
stress_spec = importlib.util.spec_from_file_location("compiler_stress_checker", Path(__file__).with_name("check-compiler-stress.py"))
stress = importlib.util.module_from_spec(stress_spec)
stress_spec.loader.exec_module(stress)
lifecycle_spec = importlib.util.spec_from_file_location("compiler_lifecycle_checker", Path(__file__).with_name("check-compiler-lifecycle.py"))
lifecycle = importlib.util.module_from_spec(lifecycle_spec)
lifecycle_spec.loader.exec_module(lifecycle)
active_spec = importlib.util.spec_from_file_location("compiler_active_checker", Path(__file__).with_name("check-active-compiler-lifecycle.py"))
active = importlib.util.module_from_spec(active_spec)
active_spec.loader.exec_module(active)
deadline_spec = importlib.util.spec_from_file_location("compiler_deadline_checker", Path(__file__).with_name("check-compiler-deadline.py"))
deadline = importlib.util.module_from_spec(deadline_spec)
deadline_spec.loader.exec_module(deadline)


class CompilerHostTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="firmingo-host-fixture-")
        self.root = Path(self.temporary.name)
        self.sdk = self.root / "sdk"; self.sdk.mkdir()
        (self.sdk / "Fixture+Only.swift").write_bytes(b"non-executable fixture, NEVER DEPLOY")
        self.value = {"schema": 1, "operation": "prepared_experimental_sdk_package", "sdkCommit": "1" * 40,
                      "qualification": "experimental-unqualified", "published": False,
                      "consumerManifestSHA256": "d042dc7d3869949d8e311fff28c5d66327ba090ba2ec8ff149e3a12019d8ea8c",
                      "files": [{"path": "Fixture+Only.swift", **host.identity(self.sdk / "Fixture+Only.swift")} ]}

    def tearDown(self):
        self.temporary.cleanup()

    def save(self, value):
        data = json.dumps(value).encode(); (self.sdk / "prepared-package.json").write_bytes(data)
        return hashlib.sha256(data).hexdigest()

    def test_observed_bytes_bounds_symlinks_and_fifo_are_checked_without_blocking(self):
        path = self.sdk / "Fixture+Only.swift"
        self.assertEqual(host.identity(path)["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
        with self.assertRaises(ValueError): host.identity(path, 1)
        link = self.root / "link"; link.symlink_to(path)
        with self.assertRaises(OSError): host.identity(link)
        fifo = self.root / "fifo"; os.mkfifo(fifo)
        with self.assertRaises(ValueError): host.identity(fifo)

    def test_independent_anchor_and_required_binary_source_roles_cannot_be_omitted(self):
        anchor = self.save(self.value)
        with self.assertRaisesRegex(ValueError, "anchor"): host.prepared_sdk(self.sdk, "0" * 64)
        with self.assertRaisesRegex(ValueError, "omits"): host.prepared_sdk(self.sdk, anchor)

    def test_reanchored_unsafe_duplicate_boolean_and_corrupt_fixture_inputs_fail(self):
        for change in (lambda value: value["files"][0].update(path="../outside"),
                       lambda value: value["files"].append(value["files"][0]),
                       lambda value: value["files"][0].update(bytes=True),
                       lambda value: value["files"][0].update(sha256="0" * 64),
                       lambda value: value.update(published=True),
                       lambda value: value.update(consumerManifestSHA256="0" * 64)):
            value = copy.deepcopy(self.value); change(value)
            with self.assertRaises(ValueError): host.prepared_sdk(self.sdk, self.save(value))

    def test_project_only_fixture_keeps_prepared_sdk_outside_host_and_grants_no_device_permissions(self):
        # Bypass SDK proof only for project-template fixtures; this is not an accepted compiler package.
        output = self.root / "host"
        with patch.object(host, "prepared_sdk", return_value=self.value):
            receipt = host.generate(self.sdk, "a" * 64, output)
        self.assertFalse(receipt["signed"]); self.assertFalse(receipt["installed"])
        self.assertFalse(receipt["deviceOperations"])
        project = (output / "CompilerQualification.xcodeproj/project.pbxproj").read_text()
        self.assertIn('relativePath = "../sdk";', project)
        self.assertNotIn("WGR9T9JH4L", project)
        info = plistlib.loads((output / "Info.plist").read_bytes())
        self.assertNotIn("NSLocalNetworkUsageDescription", info)
        self.assertNotIn("CFBundleDocumentTypes", info)
        entitlements = plistlib.loads((output / "CompilerQualification.entitlements").read_bytes())
        self.assertEqual(entitlements, {"com.apple.security.app-sandbox": True, "com.apple.security.network.client": True})
        self.assertNotIn("com.apple.security.cs.allow-jit", entitlements)
        self.assertTrue((output / "Sources/QualificationLifecycle.swift").is_file())
        self.assertTrue((output / "Sources/QualificationActiveLifecycle.swift").is_file())
        self.assertTrue((output / "Sources/QualificationDeadline.swift").is_file())
        self.assertEqual(host.identity(output / "Sources/worker-compile-workload.txt"),
                         {"bytes": 227505, "sha256": "9a17105b5d17f732435ab81c6bf1083386e5cb5ae8b36569259bac8cf479ec3f"})
        self.assertNotIn("UIBackgroundModes", info)

    def test_existing_destination_is_preserved_and_partial_new_output_is_removed(self):
        output = self.root / "existing"; output.mkdir(); (output / "keep").write_bytes(b"preserve")
        with patch.object(host, "prepared_sdk", return_value=self.value):
            with self.assertRaises(OSError): host.generate(self.sdk, "a" * 64, output)
        self.assertEqual((output / "keep").read_bytes(), b"preserve")
        with patch.object(host, "prepared_sdk", return_value=self.value), patch.object(host, "ROOT", self.root):
            with self.assertRaises(OSError): host.generate(self.sdk, "a" * 64, self.root / "partial")
        self.assertFalse((self.root / "partial").exists())

    def test_journal_envelope_rejects_failed_stale_missing_duplicate_and_unbounded_results(self):
        import base64
        value = {"schema": 1, "runID": "fixture", "status": "passed", "stage": "complete", "deviceOperations": False,
                 "firmwareBuildID": "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f",
                 "context": {"consumerManifestSHA256": self.value["consumerManifestSHA256"], "sdkCommit": "1" * 40, "preparedManifestSHA256": "a" * 64},
                 "steps": [{"name": name, "seconds": 0.01} for name in ("resources", "cold-gpio", "warm-console", "frontend-error", "busy-cancellation", "fresh-after-cancellation")]}
        for step in value["steps"]:
            if step["name"] in ("cold-gpio", "warm-console", "fresh-after-cancellation"):
                step.update(wasmLinearMemoryBytes=27983872, capsuleSHA256="b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0" if step["name"] == "warm-console" else "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d")
        envelope = lambda value: b"FIRMINGO_COMPILER_REPORT:" + base64.b64encode(json.dumps(value).encode()) + b"\n"
        data = envelope(value)
        self.assertEqual(runner.decode_report(data, "fixture")[1], value)
        for changed in (b"", data + data, b"x" * (1024**2 + 1)):
            with self.assertRaises(ValueError): runner.decode_report(changed, "fixture")
        for change in (lambda value: value.update(status="failed"), lambda value: value.update(runID="stale"),
                       lambda value: value["steps"].pop(), lambda value: value.update(deviceOperations=True),
                       lambda value: value["steps"][1].update(capsuleSHA256="0" * 64),
                       lambda value: value["steps"][1].update(wasmLinearMemoryBytes=True),
                       lambda value: value["steps"][0].update(seconds=float("nan"))):
            changed = copy.deepcopy(value); change(changed)
            with self.assertRaises(ValueError): runner.decode_report(envelope(changed), "fixture")

    def test_repeated_build_report_rejects_interrupted_stale_corrupt_artifacts_and_invalid_memory(self):
        # Parser-only observations; these values never qualify a compiler, device or memory budget.
        value = {"schema": 2, "kind": "repeated-builds", "runID": "fixture", "status": "passed", "stage": "complete",
                 "iterations": 2, "deviceOperations": False, "hostProcessID": 123,
                 "firmwareBuildID": "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f",
                 "context": {"consumerManifestSHA256": self.value["consumerManifestSHA256"], "sdkCommit": "1" * 40, "preparedManifestSHA256": "a" * 64},
                 "steps": [{"name": "build-1-gpio", "seconds": 0.1, "wasmLinearMemoryBytes": 27983872,
                            "capsuleSHA256": "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"},
                           {"name": "build-2-console", "seconds": 0.1, "wasmLinearMemoryBytes": 27983872,
                            "capsuleSHA256": "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0"}],
                 "hostFootprintSamples": [{"seconds": 0.01, "bytes": 50000000, "stage": "resources"},
                                          {"seconds": 1, "bytes": 51000000, "stage": "idle-after-builds"}], "droppedSamples": 0}
        encode = lambda value: json.dumps(value).encode()
        self.assertEqual(stress.check(encode(value), "fixture", 2)["hostFootprintSampledPeakBytes"], 51000000)
        for change in (lambda value: value.update(status="running"), lambda value: value.update(runID="old"),
                       lambda value: value.update(iterations=True), lambda value: value.update(error="failed"),
                       lambda value: value["steps"].pop(), lambda value: value["steps"][1].update(capsuleSHA256="0" * 64),
                       lambda value: value["hostFootprintSamples"][1].update(seconds=0),
                       lambda value: value["hostFootprintSamples"][1].update(seconds=float("inf")),
                       lambda value: value["hostFootprintSamples"][0].update(bytes=True),
                       lambda value: value.update(droppedSamples=True)):
            changed = copy.deepcopy(value); change(changed)
            with self.assertRaises(ValueError): stress.check(encode(changed), "fixture", 2)
        with self.assertRaises(ValueError): stress.check(b"x" * (2 * 1024**2 + 1), "fixture", 2)
        with self.assertRaises(ValueError): stress.check(encode(value), "fixture", 41)

    def test_idle_lifecycle_requires_exact_launch_context_artifacts_and_real_transition_sequence(self):
        # Parser-only events; fixture acceptance is not physical lifecycle evidence.
        run = "12345678-1234-4234-8234-123456789ABC"
        context = {"consumerManifestSHA256": self.value["consumerManifestSHA256"], "sdkCommit": "1" * 40, "preparedManifestSHA256": "a" * 64}
        value = {"schema": 3, "kind": "idle-background-return", "runID": run, "status": "passed", "stage": "complete",
                 "context": context, "hostProcessID": 123, "deviceOperations": False, "observationLimitSeconds": 600, "minimumBackgroundSeconds": 3,
                 "firmwareBuildID": "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f",
                 "steps": [{"name": "before-background-gpio", "seconds": 0.1, "wasmLinearMemoryBytes": 27983872,
                            "capsuleSHA256": "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"},
                           {"name": "after-foreground-console", "seconds": 0.1, "wasmLinearMemoryBytes": 27983872,
                            "capsuleSHA256": "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0"}],
                 "events": [{"phase": "active", "stage": "waiting-for-active", "seconds": 0},
                            {"phase": "background", "stage": "waiting-for-background", "seconds": 1},
                            {"phase": "active", "stage": "waiting-for-background", "seconds": 6}]}
        encode = lambda value: json.dumps(value).encode()
        self.assertEqual(lifecycle.check(encode(value), run, 123, context)["backgroundToActiveSeconds"], 5)
        for change in (lambda v: v.update(status="running"), lambda v: v.update(stage="waiting-for-background"),
                       lambda v: v.update(hostProcessID=124), lambda v: v.update(hostProcessID=True),
                       lambda v: v.update(error="failed"), lambda v: v.update(runID="old"),
                       lambda v: v["context"].update(preparedManifestSHA256="b" * 64),
                       lambda v: v["steps"].pop(), lambda v: v["steps"][1].update(capsuleSHA256="0" * 64),
                       lambda v: v["steps"][0].update(wasmLinearMemoryBytes=True),
                       lambda v: v["events"][1].update(phase="inactive"),
                       lambda v: v["events"][1].update(stage="before-background-gpio"),
                       lambda v: v["events"][2].update(seconds=2), lambda v: v["events"][2].update(seconds=601),
                       lambda v: v["events"][0].update(seconds=True), lambda v: v["events"][2].update(seconds=float("nan")),
                       lambda v: v["events"].reverse(), lambda v: v["events"].extend(v["events"] * 32)):
            changed = copy.deepcopy(value); change(changed)
            with self.assertRaises(ValueError): lifecycle.check(encode(changed), run, 123, context)
        with self.assertRaises(ValueError): lifecycle.check(encode(value), run, 125, context)
        with self.assertRaises(ValueError): lifecycle.check(b"x" * 65537, run, 123, context)

    def active_fixture(self):
        """Parser-only values never establish actual scene events or compiler execution."""
        run = "12345678-1234-4234-8234-123456789ABC"
        context = {"consumerManifestSHA256": self.value["consumerManifestSHA256"], "sdkCommit": "1" * 40, "preparedManifestSHA256": "a" * 64}
        gpio = "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"
        step = lambda name, digest: {"name": name, "capsuleSHA256": digest, "seconds": 0.1, "wasmLinearMemoryBytes": 27983872}
        value = {"schema": 4, "kind": "inactive-cancel-background-return", "runID": run, "status": "passed", "stage": "complete",
                 "context": context, "hostProcessID": 123, "deviceOperations": False, "observationLimitSeconds": 600,
                 "minimumBackgroundSeconds": 3, "maximumAttempts": 40, "manuallyStartedSeconds": 1, "freshStartedSeconds": 10.1,
                 "firmwareBuildID": "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f",
                 "steps": [step("before-active-gpio", gpio), step("fresh-after-active-cancel-console", "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0")],
                 "completedAttempts": [step("active-1-gpio", gpio)],
                 "cancellation": {"attempt": 2, "requestedSeconds": 3, "settledSeconds": 3.5, "lastProgress": "compiling", "outcome": "cancelled", "artifactReturned": False},
                 "events": [{"phase": "active", "stage": "waiting-for-active", "seconds": 0},
                            {"phase": "inactive", "stage": "active-builds", "seconds": 3},
                            {"phase": "background", "stage": "waiting-for-return", "seconds": 4},
                            {"phase": "active", "stage": "waiting-for-return", "seconds": 10}]}
        return value, run, context

    def test_active_lifecycle_requires_pending_call_cancellation_settlement_and_fresh_admission(self):
        value, run, context = self.active_fixture()
        encode = lambda v: json.dumps(v).encode()
        self.assertEqual(active.check(encode(value), run, 123, context)["cancellation"]["outcome"], "cancelled")
        for change in (lambda v: v.update(status="running"), lambda v: v.update(hostProcessID=124),
                       lambda v: v["context"].update(sdkCommit="2" * 40), lambda v: v.update(error="cleanup failed"),
                       lambda v: v["cancellation"].update(artifactReturned=True), lambda v: v["cancellation"].update(outcome="pending"),
                       lambda v: v["cancellation"].update(attempt=True), lambda v: v["cancellation"].update(attempt=41),
                       lambda v: v["cancellation"].update(settledSeconds=2), lambda v: v["cancellation"].update(lastProgress="invented"),
                       lambda v: v["cancellation"].update(lastProgress="admitted"),
                       lambda v: v["completedAttempts"].clear(), lambda v: v["completedAttempts"][0].update(name="active-2-gpio"),
                       lambda v: v["events"][1].update(stage="waiting-for-start"), lambda v: v["events"][1].update(seconds=3.1),
                       lambda v: v["events"][2].update(phase="inactive"), lambda v: v["events"][3].update(seconds=5),
                       lambda v: v.update(freshStartedSeconds=9), lambda v: v.update(manuallyStartedSeconds=4),
                       lambda v: v["steps"][1].update(capsuleSHA256="0" * 64), lambda v: v["steps"].pop(),
                       lambda v: v["events"][0].update(seconds=float("nan"))):
            changed = copy.deepcopy(value); change(changed)
            with self.assertRaises(ValueError): active.check(encode(changed), run, 123, context)
        with self.assertRaises(ValueError): active.check(b"x" * 65537, run, 123, context)

    def test_worker_lifecycle_rejects_verification_entry_wrapper_wrong_workload_and_short_calibration(self):
        value, run, context = self.active_fixture()
        value.update(schema=5, kind="worker-compile-inactive-cancel-return", workerWorkloadBytes=227505,
                     workerWorkloadSHA256="9a17105b5d17f732435ab81c6bf1083386e5cb5ae8b36569259bac8cf479ec3f",
                     preflightCompilePhaseSeconds=10)
        value["cancellation"].update(compilingNotificationCount=1, compilePhaseBeganSeconds=2)
        encode = lambda v: json.dumps(v).encode()
        self.assertEqual(active.check(encode(value), run, 123, context, worker=True)["status"], "passed_worker_compile_lifecycle_checks")
        with self.assertRaises(ValueError): active.check(encode(value), run, 123, context)
        for change in (lambda v: v.update(schema=4, kind="inactive-cancel-background-return"),
                       lambda v: v.update(workerWorkloadSHA256="0" * 64), lambda v: v.update(workerWorkloadBytes=True),
                       lambda v: v.update(preflightCompilePhaseSeconds=3.99), lambda v: v.update(preflightCompilePhaseSeconds=float("nan")),
                       lambda v: v["cancellation"].update(lastProgress="verifying"),
                       lambda v: v["cancellation"].update(compilingNotificationCount=2),
                       lambda v: v["cancellation"].update(compilingNotificationCount=True),
                       lambda v: v["cancellation"].update(compilePhaseBeganSeconds=3.1),
                       lambda v: v["cancellation"].update(compilePhaseBeganSeconds=0.9)):
            changed = copy.deepcopy(value); change(changed)
            with self.assertRaises(ValueError): active.check(encode(changed), run, 123, context, worker=True)

    def test_production_deadline_rejects_injected_timeouts_wrong_phases_interruptions_and_stale_results(self):
        # Synthetic parser data: never evidence of physical expiry or cleanup.
        prior, run, context = self.active_fixture()
        value = {"schema": 6, "kind": "production-deadline-fresh-recovery", "runID": run, "context": context,
                 "hostProcessID": 123, "firmwareBuildID": prior["firmwareBuildID"], "deviceOperations": False,
                 "status": "passed", "stage": "complete", "runtimeDeadlineSeconds": 60, "observationLimitSeconds": 180,
                 "workloadSHA256": "bde5df426deb79fd8277abfd5b406cf1288b28b307646b62bc5ee1028cce26eb", "workloadBytes": 227646,
                 "deadlineStartedSeconds": 2, "deadlineSettledSeconds": 62.5, "freshStartedSeconds": 62.6,
                 "outcome": "timedOut", "artifactReturned": False,
                 "progress": [{"phase": p, "seconds": 2 + i / 10} for i, p in enumerate(("verifying", "verifying", "preparing", "compiling"))],
                 "events": [{"phase": "inactive", "stage": "waiting-for-active", "seconds": 0},
                            {"phase": "active", "stage": "waiting-for-active", "seconds": 0.1}],
                 "steps": copy.deepcopy(prior["steps"])}
        value["steps"][0]["name"] = "before-deadline-gpio"; value["steps"][1]["name"] = "fresh-after-deadline-console"
        encode = lambda v: json.dumps(v).encode()
        self.assertEqual(deadline.check(encode(value), run, 123, context)["deadlineElapsedSeconds"], 60.5)
        for change in (lambda v: v.update(schema=5), lambda v: v.update(status="running"),
                       lambda v: v.update(hostProcessID=True), lambda v: v.update(error="cleanup failed"),
                       lambda v: v["context"].update(sdkCommit="2" * 40), lambda v: v.update(workloadSHA256="0" * 64),
                       lambda v: v.update(workloadBytes=True), lambda v: v.update(runtimeDeadlineSeconds=1),
                       lambda v: v.update(runtimeDeadlineSeconds=True), lambda v: v.update(outcome="cancelled"),
                       lambda v: v.update(artifactReturned=True), lambda v: v.update(deadlineSettledSeconds=61.99),
                       lambda v: v.update(deadlineSettledSeconds=78), lambda v: v.update(freshStartedSeconds=62.4),
                       lambda v: v["progress"].pop(), lambda v: v["progress"].append({"phase": "compiling", "seconds": 4}),
                       lambda v: v["progress"][3].update(phase="linking"), lambda v: v["progress"][0].update(seconds=1.9),
                       lambda v: v["progress"][3].update(seconds=63), lambda v: v["progress"][2].update(seconds=float("nan")),
                       lambda v: v["events"].append({"phase": "inactive", "stage": "deadline", "seconds": 60}),
                       lambda v: v["events"][1].update(phase="background"), lambda v: v["events"][1].update(seconds=63),
                       lambda v: v["steps"].pop(), lambda v: v["steps"][0].update(wasmLinearMemoryBytes=True),
                       lambda v: v["steps"][1].update(capsuleSHA256="0" * 64)):
            changed = copy.deepcopy(value); change(changed)
            with self.assertRaises(ValueError): deadline.check(encode(changed), run, 123, context)
        with self.assertRaises(ValueError): deadline.check(encode(value), run, 124, context)
        with self.assertRaises(ValueError): deadline.check(b"x" * 65537, run, 123, context)


if __name__ == "__main__":
    unittest.main()
