"""Tiny fixture-only Nano input/generator/export checks; never execute a compiler or contact a device."""
import base64
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
def module(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value
host = module('nano_host', 'make-nano-host.py')
runner = module('nano_runner', 'run-nano-offline.py')

class NanoHostTests(unittest.TestCase):
    def test_plan_requires_external_anchor_before_parsing_or_creating_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'test-plan.json').write_text('{}')
            with self.assertRaises(ValueError): host.test_inputs(root, '0' * 64)
            link = root / 'linked'; link.symlink_to(root, target_is_directory=True)
            with self.assertRaises(ValueError): host.test_inputs(link, '0' * 64)

    def test_reanchored_plan_cannot_replace_the_independently_pinned_consumer(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            plan = {'schema':1, 'kind':'nano-sdk-hardware-qualification-inputs', 'consumerManifestSHA256':host.CONSUMER,
                    'firmwareBuildID':host.BUILD, 'deviceOperations':False, 'installed':False, 'hardwareQualified':False}
            (root / 'consumer-manifest.json').write_text('{}')
            (root / 'test-plan.json').write_text(json.dumps(plan))
            anchor = host.host.identity(root / 'test-plan.json')['sha256']
            with self.assertRaises(ValueError): host.test_inputs(root, anchor)

    def test_generated_app_is_separate_explicit_network_host_without_firmware_app_resources(self):
        # Fixture-only verifier bypass; no compiler or firmware is accepted by this test.
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); sdk=root/'sdk'; sdk.mkdir(); inputs=root/'inputs'; inputs.mkdir()
            (inputs/'test-plan.json').write_text('{}'); output=root/'host'
            context={'sdkCommit':'1'*40, 'consumerManifestSHA256':host.CONSUMER}
            with patch.object(host, 'test_inputs', return_value={'files':[]}), patch.object(host.host, 'prepared_sdk', return_value=context):
                host.generate(sdk, 'a'*64, inputs, 'b'*64, output)
            project=(output/'NanoQualification.xcodeproj/project.pbxproj').read_text()
            self.assertIn('com.firmingokit.nanoqualification', project)
            self.assertNotIn('com.firmingokit.compilerqualification', project)
            self.assertTrue((output/'Sources/NanoApp.swift').is_file())
            self.assertFalse((output/'Sources/QualificationApp.swift').exists())
            self.assertFalse(list((output/'Sources').rglob('*.uf2')))
            info=plistlib.loads((output/'Info.plist').read_bytes())
            self.assertIn('NSLocalNetworkUsageDescription', info); self.assertNotIn('UIBackgroundModes', info)
            self.assertFalse(json.loads((output/'host-inputs.json').read_text())['deviceOperations'])
            with patch.object(host, 'test_inputs', return_value={'files':[]}), patch.object(host.host, 'prepared_sdk', return_value=context):
                with self.assertRaises(OSError): host.generate(sdk, 'a'*64, inputs, 'b'*64, output)
            self.assertTrue((output/'Sources/NanoApp.swift').exists())

    def test_offline_exports_reject_stale_failed_hardware_events_and_wrong_bytes(self):
        # Non-executable parser bytes with test-only pins, never hardware artifacts.
        files={'gpio':b'non-executable GPIO parser fixture', 'console':b'non-executable console parser fixture'}
        pins={name:(len(data),hashlib.sha256(data).hexdigest()) for name,data in files.items()}
        context={'preparedManifestSHA256':'a'*64,'consumerManifestSHA256':host.CONSUMER,'sdkCommit':'1'*40}
        report={'schema':1,'kind':'nano-sdk-hardware-qualification','runID':'fixture','firmwareBuildID':host.BUILD,
                'context':context,'hardwareQualified':False,
                'events':[{'stage':s} for s in ('offline-start','compiled-gpio','compiled-console','offline-ready')]}
        def envelope(report, files):
            value={'report':base64.b64encode(json.dumps(report).encode()).decode(),
                   'capsules':{name:base64.b64encode(data).decode() for name,data in files.items()}}
            return b'FIRMINGO_NANO_OFFLINE:'+base64.b64encode(json.dumps(value).encode())
        with patch.object(runner,'PINS',pins):
            self.assertEqual(runner.decode(envelope(report, files),context,'fixture')[1]['gpio.fms'],files['gpio'])
            for change in (lambda r:r.update(runID='stale'), lambda r:r.update(hardwareQualified=True),
                           lambda r:r['events'].pop(), lambda r:r['events'].append({'stage':'stage-requested'}),
                           lambda r:r['events'].append({'stage':'failed-or-uncertain'}), lambda r:r['context'].update(sdkCommit='2'*40)):
                changed=copy.deepcopy(report);change(changed)
                with self.assertRaises(ValueError):runner.decode(envelope(changed,files),context,'fixture')
            with self.assertRaises(ValueError):runner.decode(envelope(report,{**files,'gpio':b'corrupt'}),context,'fixture')
            with self.assertRaises(ValueError):runner.decode(b'x'*(1024**2+1),context,'fixture')
            with self.assertRaises(ValueError):runner.decode(envelope(report,files)+b'\n'+envelope(report,files),context,'fixture')

if __name__ == '__main__': unittest.main()
