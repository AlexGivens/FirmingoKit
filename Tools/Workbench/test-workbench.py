"""CLI result fixtures are non-executable protocol data; no app, socket or device is launched."""
import base64
import copy
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
    def managed_fixture(self, state='boot_confirmed'):
        """Typed parser data only; this reports no actual compilation, transaction or hardware observation."""
        operation=str(uuid.uuid4()).upper()
        device=dict(address='192.168.77.1',boardID='nano_rp2040_connect',deviceID='5031503337360009',bootID='0123456789abcdef')
        original=dict(schema=3,requestID=operation,operation='run',scenarioID='managed.stage',device=device,
            managed=dict(operationID=operation,sketch='state-a',residentImageSHA256=cli.MANAGED_IMAGE,
                         evidence='Parser fixture only; no installed-image claim',authorization='stage-d2-gnd'))
        record=dict(version=1,deviceID=device['deviceID'],bootID=device['bootID'],boardID=device['boardID'],targetID=2,
            format='nano-managed-v2',uploadID=7,size=544,sha256=cli.MANAGED_PINS['state-a'],
            residentELFSHA256='bf32639c7fc2181c9ff6f99aaf8c64e19bda4f83f9690321e2b098bc81e451a8',firmwareImageSHA256=cli.MANAGED_IMAGE)
        digest=hashlib.sha256(json.dumps(record,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        request=dict(schema=3,requestID=str(uuid.uuid4()).upper(),operation='run',scenarioID='managed.reconcile',device=device,
            managed=dict(operationID=operation,recordSHA256=digest))
        checkpoint=dict(schema=1,request=original,stageIntent=True,record=record,commitIntent=True,released=state in ('boot_confirmed','aborted'),
            snapshot=dict(uploadID=7,size=544,received=544,sha256=record['sha256'],state=state,
                          slotTouched=state in ('boot_confirmed','installed','failed'),errorCode='install_failed' if state=='failed' else 'none'))
        report=dict(schema=3,id=request['requestID'],scenarioID=request['scenarioID'],status='passed',processID=123,
            appIdentifier='com.firmingokit.demo',deviceOperations=True,artifacts=[],
            events=[dict(sequence=0,seconds=.1,phase='complete',detail='Parser fixture')],
            managedEvidence=dict(selection=request['managed'],checkpoint=checkpoint,outcome=state,recordSHA256=digest))
        return request,dict(schema=1,request=request,processID=123,scenarios=[],report=report)

    def test_managed_saved_record_scope_and_terminal_outcomes_are_independent(self):
        """The actual controller checker rejects foreign records and false startup/release claims."""
        request,value=self.managed_fixture()
        self.assertEqual(cli.decode_response(self.envelope(value),request,123)['report']['managedEvidence']['outcome'],'boot_confirmed')
        for fault in ('record','boot','release','slot','compiler','device-probe','selection'):
            broken=copy.deepcopy(value);e=broken['report']['managedEvidence'];checkpoint=e['checkpoint']
            if fault=='record':checkpoint['record']['uploadID']=8
            if fault=='boot':checkpoint['request']['device']['bootID']='f'*16
            if fault=='release':checkpoint['released']=False
            if fault=='slot':checkpoint['snapshot']['slotTouched']=False
            if fault=='compiler':broken['report']['firmwareBuildID']='a'*64
            if fault=='device-probe':broken['report']['deviceEvidence']={}
            if fault=='selection':e['selection']['recordSHA256']='a'*64
            with self.subTest(fault=fault),self.assertRaises((ValueError,KeyError)):
                cli.decode_response(self.envelope(broken),request,123)
        for state in ('committing','installed','failed'):
            request,value=self.managed_fixture(state)
            with self.assertRaises(ValueError):cli.decode_response(self.envelope(value),request,123)
            value['report']['status']='failed' if state=='failed' else 'outcomeUnknown'
            self.assertEqual(cli.decode_response(self.envelope(value),request,123)['report']['status'],value['report']['status'])

    def test_managed_boot_change_never_licenses_postcommit_retirement(self):
        """Only a durable no-commit intent and bootChanged observation permit releasing host context."""
        request,value=self.managed_fixture()
        request['scenarioID']='managed.retire';value['report']['scenarioID']='managed.retire'
        evidence=value['report']['managedEvidence'];checkpoint=evidence['checkpoint'];checkpoint.pop('snapshot')
        checkpoint['unknownReason']='bootChanged';evidence['outcome']='retired_precommit'
        with self.assertRaises(ValueError):cli.decode_response(self.envelope(value),request,123)
        checkpoint['commitIntent']=False
        self.assertEqual(cli.decode_response(self.envelope(value),request,123)['report']['status'],'passed')

    def test_managed_restore_and_unissued_retirement_do_not_invent_transaction_success(self):
        """A saved pre-record checkpoint exposes a null-record hash and permits explicit host disposal only."""
        request,value=self.managed_fixture();evidence=value['report']['managedEvidence'];checkpoint=evidence['checkpoint']
        checkpoint.pop('record');checkpoint.pop('snapshot');checkpoint['commitIntent']=False;checkpoint['released']=False
        request['scenarioID']='managed.restore';request['managed']={'operationID':checkpoint['request']['requestID']}
        value['report']['scenarioID']='managed.restore';evidence['selection']=request['managed'];evidence['outcome']='context_restored'
        evidence['recordSHA256']=hashlib.sha256(b'null').hexdigest()
        self.assertEqual(cli.decode_response(self.envelope(value),request,123)['report']['status'],'passed')
        request['scenarioID']='managed.retire';value['report']['scenarioID']='managed.retire'
        request['managed']['recordSHA256']=evidence['recordSHA256'];checkpoint['unknownReason']='stageFailedNoCommit'
        checkpoint['released']=True;evidence['outcome']='retired_unissued'
        self.assertEqual(cli.decode_response(self.envelope(value),request,123)['report']['managedEvidence']['outcome'],'retired_unissued')
        checkpoint['commitIntent']=True
        with self.assertRaises(ValueError):cli.decode_response(self.envelope(value),request,123)

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

    def test_recorded_mobile_report_corpus_remains_independently_verifiable(self):
        # Replaying original JSON is parser regression coverage, not a fresh physical run.
        spec=importlib.util.spec_from_file_location('workbench_mobile_corpus',Path(__file__).with_name('check-mobile-report.py'))
        mobile=importlib.util.module_from_spec(spec);spec.loader.exec_module(mobile)
        docs=Path(__file__).resolve().parents[2]/'docs'
        for device in ('ipad','iphone'):
            ledger=json.loads((docs/('workbench-'+device+'-qualification.json')).read_text())
            self.assertEqual(len(ledger['reports']),3)
            for row in ledger['reports']:
                with self.subTest(device=device,scenario=row['scenarioID']):
                    raw=(docs/row['reportPath']).read_bytes()
                    self.assertEqual(hashlib.sha256(raw).hexdigest(),row['reportSHA256'])
                    result=mobile.check(raw,run_id=row['runID'],pid=ledger['launch']['processID'],
                        scenario=row['scenarioID'],app_version=ledger['app']['appVersion'])
                    self.assertEqual(result['status'],'passed_mobile_workbench_report')

    def test_version_two_device_selection_rejects_ambient_network_and_probe_authority(self):
        selected=dict(address='192.168.77.1',boardID='nano_rp2040_connect',deviceID='5031503337360009')
        request=dict(schema=2,requestID=str(uuid.uuid4()).upper(),operation='run',scenarioID='device.inspect',device=selected)
        cli.validate_request(request)
        for change in (lambda r:r.update(schema=1),lambda r:r.update(firmwareBuildID='a'*64),
                       lambda r:r['device'].update(port=22),lambda r:r['device'].update(address='127.0.0.1'),
                       lambda r:r['device'].update(address='8.8.8.8'),lambda r:r.update(scenarioID='device.console-binary')):
            value=json.loads(json.dumps(request));change(value)
            with self.assertRaises((ValueError,TypeError)):cli.validate_request(value)

    def test_hardware_report_cannot_pass_without_exact_bytes_boot_and_cleanup(self):
        request,value=self.fixture();request.update(schema=2,scenarioID='device.console-binary',device=dict(address='192.168.77.1',
            boardID='nano_rp2040_connect',deviceID='5031503337360009',bootID='0123456789abcdef',consoleProbe='raw-256-v1'))
        value['request']=request.copy();report=value['report'];report.update(schema=2,scenarioID=request['scenarioID'],deviceOperations=True)
        report['deviceEvidence']=dict(selection=request['device'].copy(),connectionAttempted=True,disconnected=True,consoleOpened=True,
            probeAttempted=True,sentBytes=256,received=base64.b64encode(bytes(range(256))).decode(),consoleClosed=True,
            snapshot=dict(protocolMajor=1,firmwareVersion='fixture',maximumPayload=4096,authenticationMode='open-development',deviceID=request['device']['deviceID'],boardID=request['device']['boardID'],
                bootID=request['device']['bootID'],channels=[dict(id=1,backend='application')],targets=[]))
        self.assertEqual(cli.decode_response(self.envelope(value),request,123)['report']['status'],'passed')
        for change in (lambda e:e.update(received=base64.b64encode(bytes(256)).decode()),lambda e:e.update(consoleClosed=False),
                       lambda e:e.update(disconnected=False),lambda e:e['snapshot'].update(bootID='1123456789abcdef'),
                       lambda e:e.update(sentBytes=True)):
            damaged=json.loads(json.dumps(value));change(damaged['report']['deviceEvidence'])
            with self.assertRaises(ValueError):cli.decode_response(self.envelope(damaged),request,123)
        report['status']='failed';report['deviceEvidence']['received']=''
        self.assertEqual(cli.decode_response(self.envelope(value),request,123)['report']['status'],'failed')


if __name__ == '__main__': unittest.main()
