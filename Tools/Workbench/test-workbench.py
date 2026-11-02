"""CLI result fixtures are non-executable protocol data; no app, socket or device is launched."""
import base64
import importlib.util
import hashlib
import contextlib
import io
import tempfile
from unittest.mock import patch
import json
from pathlib import Path
import unittest
import uuid

spec = importlib.util.spec_from_file_location('workbench', Path(__file__).with_name('workbench.py'))
cli = importlib.util.module_from_spec(spec); spec.loader.exec_module(cli)


class WorkbenchCLI(unittest.TestCase):
    def fixture(self):
        request = dict(schema=1, requestID=str(uuid.uuid4()).upper(), operation='run', scenarioID='compiler.catalogue')
        report = dict(schema=1, id=request['requestID'], scenarioID=request['scenarioID'], status='passed',
                      processID=123, appIdentifier='com.firmingokit.demo', deviceOperations=False,
                      events=[dict(sequence=0, seconds=0.1, phase='complete', detail='Metadata only')], artifacts=[])
        return request, dict(schema=1, request=request.copy(), processID=123, scenarios=[], report=report)

    def envelope(self, value):
        return cli.PREFIX + base64.b64encode(json.dumps(value).encode()) + b'\n'

    def test_terminal_correlated_metadata_case(self):
        request, value = self.fixture()
        self.assertEqual(cli.decode_response(self.envelope(value), request, 123)['report']['status'], 'passed')

    def test_stale_process_run_and_extra_commands_reject(self):
        for fault in ['pid', 'id', 'command', 'schema', 'hardware', 'running']:
            with self.subTest(fault=fault):
                request, value = self.fixture()
                if fault == 'pid': value['processID'] = 124
                if fault == 'id': value['report']['id'] = str(uuid.uuid4())
                if fault == 'command': value['request']['operation'] = 'commit'
                if fault == 'schema': value['schema'] = True
                if fault == 'hardware': value['report']['deviceOperations'] = True
                if fault == 'running': value['report']['status'] = 'running'
                with self.assertRaises(ValueError): cli.decode_response(self.envelope(value), request, 123)

    def test_missing_duplicate_and_ambiguous_json_envelopes_reject(self):
        request, value = self.fixture()
        for data in [b'', self.envelope(value) * 2, cli.PREFIX + base64.b64encode(b'{"schema":1,"schema":2}')]:
            with self.assertRaises((ValueError, KeyError)): cli.decode_response(data, request, 123)

    def test_blocked_never_becomes_passed(self):
        request, value = self.fixture(); value['report']['status'] = 'blocked'
        value['report']['events'][0]['phase'] = 'resources-unavailable'
        self.assertEqual(cli.decode_response(self.envelope(value), request, 123)['report']['status'], 'blocked')

    def test_safe_artifact_digest_is_checked(self):
        request, value = self.fixture()
        data = b'FMS2' + bytes(256)  # Non-executable protocol fixture; never a device input.
        artifact = dict(name='gpio.fms', bytes=base64.b64encode(data).decode(),
                        sha256=hashlib.sha256(data).hexdigest(), receiptJSON=base64.b64encode(b'{}').decode())
        value['report']['artifacts'] = [artifact]
        self.assertEqual(len(cli.decode_response(self.envelope(value), request, 123)['report']['artifacts']), 1)
        artifact['sha256'] = '0' * 64
        with self.assertRaises(ValueError): cli.decode_response(self.envelope(value), request, 123)

    def test_launcher_retains_blocked_and_rejects_exit_status_disagreement(self):
        for actual_exit in (3, 0):
            with tempfile.TemporaryDirectory() as temp:
                root = Path(temp); app = root / 'App.app'; executable = app / 'Contents/MacOS/FirmingoWorkbench'
                executable.parent.mkdir(parents=True); executable.write_bytes(b'non-executable fixture')
                request, value = self.fixture(); value['report']['status'] = 'blocked'
                value['report']['events'][0]['phase'] = 'resources-unavailable'
                class Process:
                    pid = 123
                    returncode = actual_exit
                    def poll(self): return self.returncode
                def spawn(args, stdout, stderr):
                    self.assertEqual(args[1], '--workbench-request')
                    self.assertEqual(json.loads(base64.b64decode(args[2])), request)
                    stdout.write(self.envelope(value)); return Process()
                output = root / 'results'
                with patch.object(cli, 'signature', return_value=('fixture', {})), patch.object(cli.subprocess, 'Popen', side_effect=spawn):
                    if actual_exit == 3:
                        with contextlib.redirect_stdout(io.StringIO()):
                            self.assertEqual(cli.launch(app, 'TESTTEAM00', output, request), 3)
                        self.assertEqual(json.loads((output / 'result.json').read_text())['report']['status'], 'blocked')
                    else:
                        with self.assertRaises(ValueError): cli.launch(app, 'TESTTEAM00', output, request)
                        self.assertTrue((output / 'failure.json').exists())
                        self.assertFalse((output / 'result.json').exists())

    def test_missing_completion_invalid_timing_and_unsafe_artifact_reject(self):
        for fault in ['completion', 'time', 'artifact']:
            request, value = self.fixture()
            if fault == 'completion': value['report']['events'][0]['phase'] = 'running'
            if fault == 'time': value['report']['events'][0]['seconds'] = float('nan')
            if fault == 'artifact': value['report']['artifacts'] = [dict(name='../bad.fms')]
            with self.assertRaises(ValueError): cli.decode_response(self.envelope(value), request, 123)


if __name__ == '__main__': unittest.main()
