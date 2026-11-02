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

    def exercise_fixture(self, kind='compiler.deadline'):
        request, value = self.fixture()
        request['scenarioID'] = kind; value['request'] = request.copy(); report = value['report']; report['scenarioID'] = kind
        report['events'][0]['seconds'] = 65
        report['artifacts'] = [dict(sha256=sha) for sha in (cli.GPIO_SHA, cli.CONSOLE_SHA)]
        def build(index, source):
            return dict(index=index, input=source, sha256=cli.GPIO_SHA if source == 'gpio' else cli.CONSOLE_SHA,
                        receiptSHA256='a'*64, seconds=1, wasmLinearMemoryBytes=27983872)
        report['exercise'] = dict(kind=kind, builds=[build(1, 'gpio'), build(2, 'console')],
            progress=[dict(phase='verifying', seconds=2), dict(phase='compiling', seconds=3)], scenes=[], samples=[], droppedSamples=0,
            sceneObservationScope='Launch process only; no foreground/background claim',
            startedSeconds=2, settledSeconds=62.5, freshStartedSeconds=62.6, outcome='timedOut', runtimeDeadlineSeconds=60,
            workloadSHA256=cli.DEADLINE_SHA, workloadBytes=227646)
        return report, build

    def test_deadline_requires_actual_interval_workload_phase_and_fresh_settlement(self):
        report, _ = self.exercise_fixture()
        cli.validate_exercise(report)  # Parser-only fixture; not actual expiry evidence.
        for change in (lambda e: e.update(settledSeconds=10), lambda e: e.update(outcome='cancelled'),
                       lambda e: e.update(cancelRequestedSeconds=61), lambda e: e.update(workloadSHA256='0'*64),
                       lambda e: e.update(freshStartedSeconds=61), lambda e: e.update(runtimeDeadlineSeconds=True),
                       lambda e: e['progress'].append(dict(phase='compiling', seconds=4))):
            report, _ = self.exercise_fixture(); change(report['exercise'])
            with self.assertRaises(ValueError): cli.validate_exercise(report)

    def test_stress_requires_twenty_alternating_builds_samples_and_receipt_ids(self):
        report, build = self.exercise_fixture('compiler.stress')
        report['exercise'] = dict(kind='compiler.stress', builds=[build(i+1, 'gpio' if i%2 == 0 else 'console') for i in range(20)],
            progress=[], scenes=[], samples=[dict(seconds=0, bytes=50000000), dict(seconds=20, bytes=51000000)], droppedSamples=0)
        cli.validate_exercise(report)
        report['exercise']['builds'].pop()
        with self.assertRaises(ValueError): cli.validate_exercise(report)
        report['status'] = 'failed'
        report['exercise']['samples'][0]['bytes'] = True
        with self.assertRaises(ValueError): cli.validate_exercise(report)

    def test_launch_only_cli_cannot_accept_fabricated_lifecycle_pass(self):
        report, _ = self.exercise_fixture('host.lifecycle')
        with self.assertRaises(ValueError): cli.validate_exercise(report)
        report['status'] = 'blocked'; report.pop('exercise')
        cli.validate_exercise(report)

    def test_cancellation_needs_busy_and_cannot_accept_returned_artifact_as_settlement(self):
        report, _ = self.exercise_fixture('compiler.cancellation')
        exercise = report['exercise']; exercise.update(outcome='cancelled', cancelRequestedSeconds=3.5, busyObserved=True)
        cli.validate_exercise(report)
        for field, value in [('busyObserved', False), ('outcome', 'artifactReturned'), ('cancelRequestedSeconds', 2.5)]:
            changed = json.loads(json.dumps(report)); changed['exercise'][field] = value
            with self.assertRaises(ValueError): cli.validate_exercise(changed)

    def test_interactive_idle_requires_ordered_real_adapter_interval(self):
        report, _ = self.exercise_fixture('host.lifecycle')
        report['events'].insert(0,dict(sequence=0,seconds=1,phase='waiting-for-background',detail='Known baseline complete'))
        exercise = report['exercise']; exercise['sceneObservationScope'] = 'Actual aggregate SwiftUI app scenes; no suspension claim'
        exercise['scenes'] = [dict(phase=p,seconds=t) for p,t in [('active',0),('inactive',2),('background',3),('active',8)]]
        cli.validate_exercise(report,interactive=True)
        exercise['scenes'][-1]['seconds']=4
        with self.assertRaises(ValueError): cli.validate_exercise(report,interactive=True)

    def test_generic_active_accepts_verification_but_worker_requires_calibration_and_source_interval(self):
        report, _ = self.exercise_fixture('host.lifecycle-active'); exercise=report['exercise']
        exercise.update(sceneObservationScope='Actual aggregate SwiftUI app scenes; no suspension claim',
            scenes=[dict(phase=p,seconds=t) for p,t in [('active',0),('inactive',3),('background',4),('active',9)]],
            progress=[dict(phase='verifying',seconds=2.5)],outcome='cancelled',cancelRequestedSeconds=3,
            manuallyStartedSeconds=1.5,workloadSHA256=cli.WORKER_SHA,workloadBytes=227505)
        cli.validate_exercise(report,interactive=True)
        report['scenarioID']='host.lifecycle-worker'; exercise['kind']='host.lifecycle-worker'; exercise['builds'][0]['input']='worker'
        with self.assertRaises(ValueError): cli.validate_exercise(report,interactive=True)
        exercise['progress'].append(dict(phase='compiling',seconds=2.6)); exercise['calibratedCompileSeconds']=8
        cli.validate_exercise(report,interactive=True)
        exercise['calibratedCompileSeconds']=1
        with self.assertRaises(ValueError): cli.validate_exercise(report,interactive=True)

    def test_selected_mobile_file_checks_launch_run_app_and_receipt_identity(self):
        spec = importlib.util.spec_from_file_location('workbench_mobile', Path(__file__).with_name('check-mobile-report.py'))
        mobile = importlib.util.module_from_spec(spec); spec.loader.exec_module(mobile)
        report, _ = self.exercise_fixture('host.lifecycle')
        report['appVersion']='4'; report['firmwareBuildID']=mobile.BUILD_ID; report['catalogueSHA256']=mobile.CATALOGUE_SHA
        report['events'].insert(0,dict(sequence=0,seconds=1,phase='waiting-for-background',detail='Parser-only scene fixture'))
        for i,event in enumerate(report['events']): event['sequence']=i
        exercise=report['exercise']; exercise['sceneObservationScope']='Actual aggregate SwiftUI app scenes; no suspension claim'
        exercise['scenes']=[dict(phase=p,seconds=t) for p,t in [('active',0),('inactive',2),('background',3),('active',8)]]
        # Exact already-exported capsule/receipt vectors are data only; this fixture executes no compiler or scene action.
        recorded=json.loads((Path(__file__).resolve().parents[2]/'docs/workbench-compiler-scenarios-local.json').read_text())
        report['artifacts']=recorded['runs'][0]['report']['artifacts']
        raw=json.dumps(report).encode()
        self.assertEqual(mobile.check(raw,run_id=report['id'],pid=123,scenario='host.lifecycle',app_version='4')['status'],
                         'passed_mobile_workbench_report')
        for field,value in [('run_id',str(uuid.uuid4())),('pid',124),('app_version','3')]:
            args=dict(run_id=report['id'],pid=123,scenario='host.lifecycle',app_version='4');args[field]=value
            with self.assertRaises(ValueError): mobile.check(raw,**args)


if __name__ == '__main__': unittest.main()
