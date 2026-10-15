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


if __name__ == "__main__":
    unittest.main()
