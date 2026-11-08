"""Offline MCP/controller integration fixtures. No listener, app, board or actual compiler is started."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
import uuid

spec = importlib.util.spec_from_file_location('workbench_mcp', Path(__file__).with_name('mcp-server.py'))
mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp)
DOCS = Path(__file__).resolve().parents[2] / 'docs'


def fresh():
    """Separate caller-chosen transport and durable run identities in parser-only fixtures."""
    return str(uuid.uuid4()).upper()


def request(method, params=None, *, rid=1, modern=True):
    """Construct real stdio messages; no app scenes or successful compiler outputs are synthesized."""
    value = copy.deepcopy(params or {})
    if modern:
        value['_meta'] = {mcp.META + 'protocolVersion': mcp.MODERN, mcp.META + 'clientCapabilities': {}}
    return dict(jsonrpc='2.0', id=rid, method=method, params=value)


class MCPAdapter(unittest.TestCase):
    """Exercise the production broker in memory, then pass its replies through the shared report validator."""
    def setUp(self):
        self.calls = []
        self.broker = mcp.paired.Broker('https://127.0.0.1:8443/', 'a' * 64, clock=lambda: 0)
        invitation = self.broker.invite('Fixture')
        self.session = self.broker.pair(invitation['token'], dict(schema=1, instanceID=fresh(),
            appIdentifier=mcp.paired.BUNDLE, appVersion='8', processID=123))
        self.adapter = mcp.Adapter(Path('/unused-private-controller'), rpc=self.rpc)
        self.protocol = mcp.Protocol(self.adapter)

    def rpc(self, directory, body):
        """Call the real bounded broker state machine without opening its Unix/TLS sockets."""
        self.calls.append(copy.deepcopy(body))
        return self.broker.control(body)

    def call(self, name, args=None):
        """Use the actual MCP tools/call envelope, keeping tool failures distinct from JSON-RPC failures."""
        return self.protocol.handle(request('tools/call', dict(name=name, arguments=args or {})))

    def selection(self, **extra):
        """Every action explicitly selects its session and transport command before execution."""
        return dict(session_id=self.session['sessionID'], command_id=fresh(), **extra)

    def install_reply(self, reply):
        """Load an archived reply as inert fixture data using its exact producer identity, never as a new hardware pass."""
        self.broker = mcp.paired.Broker('https://127.0.0.1:8443/', 'a' * 64, clock=lambda: 0)
        invitation = self.broker.invite('Archived parser fixture')
        self.session = self.broker.pair(invitation['token'], {key: reply[key] for key in
            ('schema', 'instanceID', 'appIdentifier', 'appVersion', 'processID')})
        sid = self.session['sessionID']
        self.broker.command(sid, reply['command'])
        body = dict(schema=1, sessionID=sid, instanceID=reply['instanceID'], ack=0, reply=None)
        self.broker.exchange(self.session['token'], body, wait=0)
        self.broker.exchange(self.session['token'], dict(body, ack=1, reply=reply), wait=0)
        report = reply['report']
        return dict(session_id=sid, command_id=reply['command']['commandID'], scenario_id=report['scenarioID'],
                    **({'firmware_build_id': report['firmwareBuildID']} if 'firmwareBuildID' in report else {}))

    def archived(self, name):
        """Read existing measured bytes only; fixture replay is not device qualification."""
        return json.loads((DOCS / 'workbench-paired-reports/ipad' / (name + '.reply.json')).read_text())

    def test_modern_discovery_and_fixed_tools_need_no_controller(self):
        result = self.protocol.handle(request('server/discover'))['result']
        self.assertEqual(result['supportedVersions'][0], mcp.MODERN)
        self.assertEqual(result['resultType'], 'complete')
        self.assertEqual(result['capabilities'], dict(tools={}))
        tools = self.protocol.handle(request('tools/list'))['result']['tools']
        self.assertEqual([t['name'] for t in tools], ['workbench_sessions', 'workbench_submit', 'workbench_result', 'workbench_revoke'])
        self.assertTrue(all(t['inputSchema']['additionalProperties'] is False for t in tools))
        self.assertFalse(tools[2]['annotations']['readOnlyHint'])  # It can save checked evidence.
        self.assertEqual(self.calls, [])

    def test_legacy_handshake_and_modern_metadata_do_not_expand_capabilities(self):
        for version in mcp.LEGACY:
            protocol = mcp.Protocol(self.adapter)
            self.assertIn('error', protocol.handle(request('tools/list', modern=False)))
            result = protocol.handle(request('initialize', dict(protocolVersion=version, capabilities={},
                clientInfo=dict(name='Fixture', version='1')), modern=False))['result']
            self.assertEqual(result['protocolVersion'], version)
            output = io.BytesIO(); stdio = mcp.Stdio(protocol, output)
            stdio.receive(dict(jsonrpc='2.0', method='notifications/initialized'))
            self.assertIn('tools', protocol.handle(request('tools/list', modern=False))['result'])
            self.assertIn('error', protocol.handle(request('initialize', {}, modern=False)))
        wrong = request('tools/list'); wrong['params']['_meta'][mcp.META + 'protocolVersion'] = '1900-01-01'
        error = self.protocol.handle(wrong)['error']
        self.assertEqual(error['code'], -32022)
        self.assertIn(mcp.MODERN, error['data']['supported'])
        wrong = request('tools/list'); del wrong['params']['_meta'][mcp.META + 'clientCapabilities']
        self.assertEqual(self.protocol.handle(wrong)['error']['code'], -32602)
        self.assertEqual(self.calls, [])

    def test_closed_arguments_reject_runtime_paths_device_writes_and_missing_run_ids(self):
        for args in (self.selection(action='shell'), self.selection(action='run', run_id=fresh(), scenario_id='compiler.smoke', serviceURL='file:///tmp'),
                     self.selection(action='run', scenario_id='compiler.smoke'), self.selection(action='cancel'),
                     self.selection(action='list', run_id=fresh()), self.selection(action='status', run_id=fresh(), scenario_id='compiler.smoke')):
            with self.subTest(args=args):
                self.assertTrue(self.call('workbench_submit', args)['result']['isError'])
        self.assertEqual(self.call('device_upload')['error']['code'], -32602)
        self.assertEqual(self.calls, [])

    def test_submit_admission_pending_and_reused_ids_never_claim_a_scenario_pass(self):
        args = self.selection(action='run', run_id=fresh(), scenario_id='compiler.catalogue')
        result = self.call('workbench_submit', args)['result']
        self.assertFalse(result['isError'])
        self.assertEqual(result['structuredContent']['scenarioCompletion'], 'not_observed')
        selection = {key: args[key] for key in ('session_id', 'command_id')}
        result = self.call('workbench_result', selection)['result']
        self.assertEqual(result['structuredContent']['record']['state'], 'queued')
        self.assertEqual(result['structuredContent']['scenarioCompletion'], 'not_observed')
        self.call('workbench_submit', args)
        self.assertEqual(len(self.broker.sessions[args['session_id']]['commands']), 1)
        args['run_id'] = fresh()
        self.assertTrue(self.call('workbench_submit', args)['result']['isError'])
        self.assertEqual(len(self.broker.sessions[args['session_id']]['commands']), 1)

    def test_lost_submit_response_is_uncertain_and_result_recovers_without_another_enqueue(self):
        count = 0
        def uncertain(directory, body):
            nonlocal count
            if body['operation'] == 'command':
                count += 1; self.broker.control(body)
                raise OSError('simulated response loss')
            return self.rpc(directory, body)
        self.adapter.rpc = uncertain
        args = self.selection(action='run', run_id=fresh(), scenario_id='compiler.catalogue')
        result = self.call('workbench_submit', args)['result']
        self.assertTrue(result['isError'])
        self.assertEqual(result['structuredContent']['kind'], 'submission_uncertain')
        self.assertEqual(result['structuredContent']['commandID'], args['command_id'])
        self.call('workbench_result', {key: args[key] for key in ('session_id', 'command_id')})
        self.assertEqual(count, 1)

    def test_actual_archived_report_bytes_require_expected_selection_and_producer(self):
        reply = self.archived('compiler-deadline'); args = self.install_reply(reply)
        result = self.call('workbench_result', args)['result']
        self.assertFalse(result['isError'])
        self.assertTrue(result['structuredContent']['validatedReport'])
        self.assertEqual(result['structuredContent']['scenarioCompletion'], 'passed')
        del args['scenario_id']
        self.assertTrue(self.call('workbench_result', args)['result']['isError'])
        args['scenario_id'] = 'compiler.stress'
        self.assertTrue(self.call('workbench_result', args)['result']['isError'])
        args['scenario_id'] = reply['report']['scenarioID']
        self.broker.sessions[self.session['sessionID']]['instance'] = fresh()
        self.assertTrue(self.call('workbench_result', args)['result']['isError'])

    def test_failed_cancelled_and_blocked_reports_remain_nonpasses(self):
        for name, status in [('late-cancel-failed', 'failed'), ('explicit-cancel', 'cancelled')]:
            args = self.install_reply(self.archived(name))
            result = self.call('workbench_result', args)['result']
            self.assertTrue(result['isError'])
            self.assertEqual(result['structuredContent']['scenarioCompletion'], status)
        reply = self.archived('compiler-catalogue')
        reply['report']['status'] = 'blocked'; reply['report']['events'][-1]['phase'] = 'resources-unavailable'
        args = self.install_reply(reply)
        result = self.call('workbench_result', args)['result']
        self.assertTrue(result['isError'])
        self.assertEqual(result['structuredContent']['scenarioCompletion'], 'blocked')

    def test_export_is_checked_repeatable_and_never_overwrites_or_follows_a_symlink(self):
        reply = self.archived('compiler-smoke'); args = self.install_reply(reply)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.adapter.evidence = root
            first = self.call('workbench_result', args)['result']
            self.assertFalse(first['isError'])
            files = first['structuredContent']['evidence']
            self.assertEqual(len(files), 4)
            self.assertTrue(all(Path(row['path']).stat().st_mode & 0o777 == 0o600 for row in files))
            self.assertEqual(first, self.call('workbench_result', args)['result'])
            report = root / args['session_id'] / args['command_id'] / 'report.json'
            report.write_bytes(b'preserve this conflicting evidence')
            self.assertTrue(self.call('workbench_result', args)['result']['isError'])
            self.assertEqual(report.read_bytes(), b'preserve this conflicting evidence')
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); self.adapter.evidence = root
            target = root / 'elsewhere'; target.mkdir(mode=0o700)
            (root / args['session_id']).symlink_to(target, target_is_directory=True)
            self.assertTrue(self.call('workbench_result', args)['result']['isError'])
            self.assertEqual(list(target.iterdir()), [])

    def test_corrupt_report_cannot_create_evidence(self):
        for fault in ('artifact', 'rejected-envelope'):
            reply = self.archived('compiler-smoke')
            if fault == 'artifact': reply['report']['artifacts'][0]['sha256'] = '0' * 64
            else: reply['accepted'] = False
            args = self.install_reply(reply)
            with tempfile.TemporaryDirectory() as temp:
                root = Path(temp); self.adapter.evidence = root
                result = self.call('workbench_result', args)['result']
                self.assertTrue(result['isError'])
                self.assertNotIn('validatedReport', result['structuredContent'])
                self.assertEqual(list(root.iterdir()), [])

    def test_revocation_and_unknown_results_do_not_admit_or_replay_work(self):
        args = self.selection()
        self.assertTrue(self.call('workbench_result', args)['result']['isError'])
        self.assertFalse(self.call('workbench_revoke', dict(session_id=args['session_id']))['result']['isError'])
        self.assertTrue(self.call('workbench_submit', dict(args, action='list'))['result']['isError'])
        self.assertEqual(len(self.broker.sessions[args['session_id']]['commands']), 0)

    def test_malformed_frames_and_notifications_cannot_execute_commands(self):
        for raw in (b'{"id":1,"id":2}\n', b'{"x":NaN}\n', b'{"x":1e999}\n', b'\xff\n', b'[]\n',
                    b'[' * 1500 + b']' * 1500 + b'\n', b'x' * (mcp.INPUT_LIMIT + 1) + b'\n', b'{}'):
            output = io.BytesIO()
            mcp.Stdio(self.protocol, output).run(io.BytesIO(raw))
            self.assertIn('error', json.loads(output.getvalue()))
        output = io.BytesIO(); stdio = mcp.Stdio(self.protocol, output)
        stdio.receive(dict(jsonrpc='2.0', method='tools/call', params=dict(name='workbench_revoke', arguments=dict(session_id=self.session['sessionID']))))
        self.assertEqual(output.getvalue(), b'')
        self.assertEqual(self.calls, [])

    def test_stdio_cancellation_and_eof_leave_admitted_actions_to_exact_explicit_controls(self):
        entered, release, done = threading.Event(), threading.Event(), threading.Event()
        class Slow:
            def call(self, name, args):
                entered.set(); release.wait(2)
                return dict(observation='one admitted action, no replay'), False
        output = io.BytesIO(); stdio = mcp.Stdio(mcp.Protocol(Slow()), output)
        original = stdio.work
        def work(*args):
            try: original(*args)
            finally: done.set()
        stdio.work = work
        stdio.receive(request('tools/call', dict(name='workbench_sessions'), rid=1))
        self.assertTrue(entered.wait(1))
        stdio.receive(request('ping', rid=2))
        stdio.receive(dict(jsonrpc='2.0', method='notifications/cancelled', params=dict(requestId=1)))
        release.set(); self.assertTrue(done.wait(1))
        messages = [json.loads(raw) for raw in output.getvalue().splitlines()]
        self.assertEqual([msg['id'] for msg in messages], [2])
        # An EOF while another worker is blocked returns before that worker is released.
        entered.clear(); release.clear(); done.clear()
        stdio.receive(request('tools/call', dict(name='workbench_sessions'), rid=3))
        self.assertTrue(entered.wait(1))
        self.assertEqual(stdio.run(io.BytesIO(b'')), 0)
        self.assertTrue(stdio.closed)
        release.set(); self.assertTrue(done.wait(1))
        self.assertEqual([json.loads(raw)['id'] for raw in output.getvalue().splitlines()], [2])

    def test_real_stdio_process_has_clean_framing_and_exits_on_eof(self):
        with tempfile.TemporaryDirectory() as temp:
            messages = [request('server/discover'), request('tools/list', rid='tools'), request('ping', rid=3)]
            result = subprocess.run([sys.executable, '-I', '-S', '-B', str(Path(__file__).with_name('mcp-server.py')),
                '--directory', temp], input=b''.join(json.dumps(msg).encode() + b'\n' for msg in messages),
                capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            replies = [json.loads(raw) for raw in result.stdout.splitlines()]
            self.assertEqual([row['id'] for row in replies], [1, 'tools', 3])
            self.assertTrue(all('result' in row for row in replies))
            self.assertEqual(self.calls, [])

    def test_concurrent_call_bound_and_duplicate_inflight_id_reject_before_execution(self):
        release = threading.Event()
        done, all_done = [], threading.Event()
        class Slow:
            def call(self, name, args):
                release.wait(2)
                return dict(observation='bounded worker fixture'), False
        output = io.BytesIO(); stdio = mcp.Stdio(mcp.Protocol(Slow()), output)
        original = stdio.work
        def work(*args):
            try: original(*args)
            finally:
                marker = threading.Event(); done.append(marker); marker.set()
                if len(done) == 4: all_done.set()
        stdio.work = work
        for rid in range(1, 5): stdio.receive(request('tools/call', dict(name='workbench_sessions'), rid=rid))
        stdio.receive(request('tools/call', dict(name='workbench_sessions'), rid=1))
        stdio.receive(request('tools/call', dict(name='workbench_sessions'), rid=5))
        replies = [json.loads(raw) for raw in output.getvalue().splitlines()]
        self.assertEqual([row['id'] for row in replies], [1, 5])
        self.assertTrue(all(row['error']['code'] == -32600 for row in replies))
        self.assertEqual(len(stdio.active), 4)
        stdio.run(io.BytesIO(b'')); release.set()
        self.assertTrue(all_done.wait(1))

    def test_startup_rejects_public_or_symlink_authority_without_opening_a_socket(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); public = root / 'public'; public.mkdir(mode=0o755)
            link = root / 'link'; link.symlink_to(root, target_is_directory=True)
            for selection in (public, link):
                result = subprocess.run([sys.executable, '-I', '-S', '-B', str(Path(__file__).with_name('mcp-server.py')),
                    '--directory', str(selection)], input=b'', capture_output=True, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b'')
            self.assertEqual(self.calls, [])

    def test_recorded_native_codex_iphone_requests_bind_fresh_runs_and_checked_reports(self):
        """Replay the captured native host envelopes as parser data; no new host, app or hardware run occurs here."""
        import hashlib
        ledger = json.loads((DOCS / 'workbench-mcp-iphone.json').read_text())
        self.assertTrue(ledger['registration']['unrelatedSettingsPreserved'])
        self.assertEqual(ledger['codex']['modelTurnsStarted'], 0)
        for row in ledger['runs']:
            values = {}
            for key in ('report', 'reply', 'nativeReportRequest', 'nativeReportResponse', 'nativeStartRequest', 'nativeStartResponse'):
                raw = (DOCS / row[key]['path']).read_bytes()
                self.assertEqual(hashlib.sha256(raw).hexdigest(), row[key]['sha256'])
                values[key] = json.loads(raw)
            start = values['nativeStartRequest']
            self.assertEqual(start['method'], 'mcpServer/tool/call')
            self.assertEqual(start['params']['server'], ledger['registration']['server'])
            self.assertEqual(start['params']['tool'], 'workbench_submit')
            self.assertEqual(start['params']['arguments']['action'], 'run')
            self.assertEqual(start['params']['arguments']['run_id'], row['runID'])
            admission = values['nativeStartResponse']['result']['structuredContent']
            self.assertEqual(admission['scenarioCompletion'], 'not_observed')
            request = values['nativeReportRequest']; response = values['nativeReportResponse']
            self.assertEqual(request['id'], response['id'])
            self.assertEqual(request['params']['tool'], 'workbench_result')
            selected = request['params']['arguments']
            self.assertEqual(selected['session_id'], ledger['pairing']['sessionID'])
            self.assertEqual(selected['command_id'], row['reportCommandID'])
            self.assertFalse(response['result']['isError'])
            result = response['result']['structuredContent']
            self.assertTrue(result['validatedReport'])
            self.assertEqual(result['record']['reply'], values['reply'])
            self.assertEqual(result['record']['reply']['report'], values['report'])
            self.assertEqual(values['reply']['processID'], ledger['pairing']['processID'])
            self.assertEqual(values['reply']['instanceID'], ledger['pairing']['instanceID'])
            checked = mcp.paired.export_report(values['reply'], row['runID'], selected['scenario_id'], selected['firmware_build_id'])
            self.assertEqual(checked['status'], 'passed')
        self.assertTrue(ledger['revocation']['confirmedByNativeMCP'])
        self.assertFalse(ledger['revocation']['appDiagnostic']['isPaired'])

    def test_recorded_workbench_build10_native_reports_remain_bound_to_their_request_scope(self):
        """Replay exact native envelopes as parser data; this creates no app, model turn or hardware operation."""
        import hashlib
        ledgers = [json.loads((DOCS / name).read_text()) for name in
                   ('workbench-device-qualification.json', 'workbench-device-ipad-qualification.json')]
        self.assertEqual(ledgers[0]['app'], ledgers[1]['app'])
        self.assertNotEqual(ledgers[0]['pairing']['sessionID'], ledgers[1]['pairing']['sessionID'])
        self.assertNotEqual(ledgers[0]['pairing']['instanceID'], ledgers[1]['pairing']['instanceID'])
        self.assertEqual(ledgers[1]['hostDevice']['productType'], 'iPad13,4')
        self.assertEqual({row['scenarioID'] for row in ledgers[1]['runs']}, {'device.inspect', 'device.console-binary'})
        for ledger in ledgers:
            self.assertTrue(ledger['revocation']['confirmedByNativeMCP'])
            self.assertTrue(ledger['revocation']['finalSafeControllerMetadata']['revoked'])
            self.assertEqual(ledger['app']['appVersion'], '10')
            self.assertEqual(ledger['nativeHost']['modelTurnsStarted'], 0)
            for row in ledger['runs']:
                values = {}
                for key in ('report', 'reply', 'nativeReportRequest', 'nativeReportResponse', 'nativeStartRequest', 'nativeStartResponse'):
                    raw = (DOCS / row[key]['path']).read_bytes()
                    self.assertEqual(hashlib.sha256(raw).hexdigest(), row[key]['sha256'])
                    values[key] = json.loads(raw)
                start = values['nativeStartRequest']['params']['arguments']
                selected = values['nativeReportRequest']['params']['arguments']
                self.assertEqual(values['nativeStartRequest']['id'], values['nativeStartResponse']['id'])
                self.assertEqual(values['nativeReportRequest']['id'], values['nativeReportResponse']['id'])
                self.assertEqual(values['nativeStartRequest']['params']['server'], ledger['registration']['server'])
                self.assertEqual(values['nativeStartRequest']['params']['tool'], 'workbench_submit')
                self.assertFalse(values['nativeReportResponse']['result']['isError'])
                self.assertEqual(start['run_id'], row['runID'])
                self.assertEqual(start['scenario_id'], row['scenarioID'])
                self.assertEqual(selected['scenario_id'], row['scenarioID'])
                self.assertEqual(selected['session_id'], ledger['pairing']['sessionID'])
                self.assertEqual(selected['command_id'], row['reportCommandID'])
                self.assertEqual(values['nativeStartResponse']['result']['structuredContent']['scenarioCompletion'], 'not_observed')
                result = values['nativeReportResponse']['result']['structuredContent']
                self.assertTrue(result['validatedReport'])
                self.assertEqual(result['record']['reply'], values['reply'])
                self.assertEqual(values['reply']['report'], values['report'])
                self.assertEqual(values['reply']['processID'], ledger['pairing']['processID'])
                self.assertEqual(values['reply']['instanceID'], ledger['pairing']['instanceID'])
                device = mcp.paired.request_checker().selected_device(selected, row['scenarioID'])
                checked = mcp.paired.export_report(values['reply'], row['runID'], selected['scenario_id'], selected.get('firmware_build_id'), device)
                self.assertEqual(checked['status'], row['status'])
                self.assertEqual(checked['schema'], 2 if device else 1)
                self.assertIs(checked['deviceOperations'], device is not None)
                for field in mcp.paired.request_checker().DEVICE_FIELDS:
                    self.assertEqual(start.get(field), selected.get(field))

    def test_recorded_build11_managed_reports_preserve_authority_and_unknown_outcomes(self):
        """Validate actual iPad envelopes offline, including the refused commit and changed-boot uncertainty."""
        import hashlib
        ledger = json.loads((DOCS / 'workbench-managed-ipad-qualification.json').read_text())
        self.assertEqual(ledger['status'], 'completed_with_scoped_expected_nonpasses')
        self.assertTrue(ledger['revocation']['confirmedByNativeMCP'])
        self.assertTrue(ledger['controller']['stoppedAfterQualification'])
        self.assertEqual(ledger['app']['appVersion'], '11')
        rows = [row for phase in ledger['phases'] for row in phase['runs']]
        self.assertEqual(len(rows), 29)
        self.assertEqual(sum(row['status'] == 'passed' for row in rows), 27)
        seen, processes, operations = set(), set(), set()
        for phase in ledger['phases']:
            self.assertTrue(phase['allObservedStatusesAsExpected'])
            self.assertEqual(phase['modelTurnsStarted'], 0)
            for row in phase['runs']:
                values = {}
                for key in ('reply', 'report', 'nativeStartRequest', 'nativeStartResponse', 'nativeReportRequest', 'nativeReportResponse'):
                    raw = (DOCS / row[key]['path']).read_bytes()
                    self.assertEqual(len(raw), row[key]['bytes'])
                    self.assertEqual(hashlib.sha256(raw).hexdigest(), row[key]['sha256'])
                    values[key] = json.loads(raw)
                start, selected = (values[key]['params']['arguments'] for key in ('nativeStartRequest', 'nativeReportRequest'))
                self.assertEqual(values['nativeStartRequest']['params']['tool'], 'workbench_submit')
                self.assertEqual(values['nativeStartRequest']['params']['server'], ledger['registration']['server'])
                self.assertEqual(values['nativeReportRequest']['params']['tool'], 'workbench_result')
                for kind in ('Start', 'Report'):
                    self.assertEqual(values['native' + kind + 'Request']['id'], values['native' + kind + 'Response']['id'])
                self.assertEqual(start['run_id'], row['runID'])
                self.assertEqual(selected['session_id'], phase['pairing']['sessionID'])
                self.assertEqual(selected['command_id'], row['reportCommandID'])
                self.assertEqual(start['scenario_id'], selected['scenario_id'])
                result = values['nativeReportResponse']['result']['structuredContent']
                self.assertTrue(result['validatedReport'])
                self.assertEqual(result['record']['reply'], values['reply'])
                self.assertEqual(values['reply']['report'], values['report'])
                self.assertEqual(values['reply']['processID'], phase['pairing']['processID'])
                self.assertEqual(values['reply']['instanceID'], phase['pairing']['instanceID'])
                self.assertEqual(row['status'], row['expectedStatus'])
                checker = mcp.paired.request_checker()
                device = checker.selected_device(selected, row['scenarioID'])
                managed = checker.selected_managed(selected, row['scenarioID'])
                report = mcp.paired.export_report(values['reply'], row['runID'], row['scenarioID'], None, device, managed)
                self.assertEqual(report['schema'], 3 if managed else 2)
                self.assertTrue(report['deviceOperations'])
                for field in checker.DEVICE_FIELDS | checker.MANAGED_FIELDS:
                    self.assertEqual(start.get(field), selected.get(field))
                processes.add(report['processID']); seen.add(row['scenarioID'])
                if managed:
                    operations.add(managed['operationID'])
                    wrong = dict(managed, operationID=fresh())
                    with self.assertRaises(ValueError):
                        mcp.paired.export_report(values['reply'], row['runID'], row['scenarioID'], None, device, wrong)
                if row['status'] == 'outcomeUnknown':
                    checkpoint = report['managedEvidence']['checkpoint']
                    self.assertEqual(checkpoint['unknownReason'], 'bootChanged')
                    self.assertFalse(checkpoint['commitIntent'])
                    self.assertFalse(checkpoint['released'])
                if row['status'] == 'failed':
                    self.assertEqual(row['label'], 'managed.commit-refused-after-restart')
                    self.assertIn('No live pre-commit capability', str(report['events']))
        self.assertEqual(len(processes), 2)
        self.assertEqual(len(operations), 5)
        self.assertEqual(seen, {'device.inspect', 'device.console-binary', 'managed.stage', 'managed.commit',
                               'managed.abort', 'managed.disconnect', 'managed.reconcile', 'managed.restore', 'managed.retire'})
        for artifact in ledger['independentCapsuleChecks']['uniqueArtifacts']:
            for item in artifact.values():
                raw = (DOCS / item['path']).read_bytes()
                self.assertEqual(len(raw), item['bytes'])
                self.assertEqual(hashlib.sha256(raw).hexdigest(), item['sha256'])
        revocation = {}
        for key in ('nativeRequest', 'nativeResponse'):
            item = ledger['revocation'][key]
            raw = (DOCS / item['path']).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), item['sha256'])
            revocation[key] = json.loads(raw)
        self.assertEqual(revocation['nativeRequest']['params']['tool'], 'workbench_revoke')
        self.assertEqual(revocation['nativeRequest']['id'], revocation['nativeResponse']['id'])
        self.assertTrue(revocation['nativeResponse']['result']['structuredContent']['revoked'])

    def test_recorded_iphone_managed_matrix_preserves_attachment_failures_and_direct_mcp_scope(self):
        """Replay real desktop tool envelopes offline; retain USB failures separately from the managed matrix."""
        import hashlib
        ledger = json.loads((DOCS / 'workbench-managed-iphone-qualification.json').read_text())
        ipad = json.loads((DOCS / 'workbench-managed-ipad-qualification.json').read_text())
        for key in ('sourceCommit', 'appVersion', 'executableSHA256', 'consumerManifestSHA256', 'preparedInventorySHA256'):
            self.assertEqual(ledger['app'][key], ipad['app'][key])
        self.assertEqual(ledger['hostDevice']['productType'], 'iPhone16,2')
        self.assertEqual(ledger['status'], 'completed_managed_matrix_with_retained_attachment_failures')
        self.assertTrue(ledger['controller']['stoppedAfterQualification'])
        self.assertTrue(ledger['revocation']['confirmedByDesktopMCP'])

        def read(item):
            """Check the original bytes before interpreting each immutable export or tool envelope."""
            raw = (DOCS / item['path']).read_bytes()
            self.assertEqual(len(raw), item['bytes'])
            self.assertEqual(hashlib.sha256(raw).hexdigest(), item['sha256'])
            return json.loads(raw)

        rows = [row for phase in ledger['phases'] for row in phase['runs']]
        self.assertEqual(len(rows), 33)
        self.assertEqual(sum(row['status'] == 'passed' for row in rows), 29)
        self.assertEqual(sum(row.get('unexpectedFailure', False) for row in rows), 2)
        for phase in ledger['phases']:
            self.assertEqual(phase['allObservedStatusesAsExpected'], phase['name'] != 'initial-retained-a')
        processes, operations, accepted_commits, phases = set(), set(), 0, set()
        for row in rows:
            values = {key: read(row[key]) for key in ('reply', 'report', 'startRequest', 'startResponse', 'reportRequest', 'reportResponse')}
            start = values['startRequest']['arguments']
            selected = values['reportRequest']['arguments']
            self.assertEqual(values['startRequest']['tool'], 'mcp__firmingo_workbench__workbench_submit')
            self.assertEqual(values['reportRequest']['tool'], 'mcp__firmingo_workbench__workbench_result')
            self.assertEqual(start['action'], 'run')
            self.assertEqual(start['run_id'], row['runID'])
            self.assertEqual(start['command_id'], row['startCommandID'])
            self.assertEqual(selected['command_id'], row['reportCommandID'])
            self.assertEqual(start['session_id'], selected['session_id'])
            self.assertEqual(selected['session_id'], row['sessionID'])
            self.assertEqual(start['scenario_id'], row['scenarioID'])
            self.assertEqual(selected['scenario_id'], row['scenarioID'])
            self.assertEqual(values['startResponse']['structuredContent']['scenarioCompletion'], 'not_observed')
            result = values['reportResponse']['structuredContent']
            self.assertTrue(result['validatedReport'])
            self.assertEqual(result['record']['reply'], values['reply'])
            self.assertEqual(values['reply']['report'], values['report'])
            self.assertEqual(values['reply']['processID'], row['processID'])
            self.assertEqual(values['reply']['instanceID'], row['instanceID'])
            checker = mcp.paired.request_checker()
            device = checker.selected_device(selected, row['scenarioID'])
            managed = checker.selected_managed(selected, row['scenarioID'])
            report = mcp.paired.export_report(values['reply'], row['runID'], row['scenarioID'], None, device, managed)
            self.assertEqual(report['schema'], 3 if managed else 2)
            self.assertEqual(report['status'], row['status'])
            for key in checker.DEVICE_FIELDS | checker.MANAGED_FIELDS:
                self.assertEqual(start.get(key), selected.get(key))
            if managed is None or report['managedEvidence'].get('checkpoint') is not None:
                with self.assertRaises(ValueError):
                    mcp.paired.export_report(values['reply'], row['runID'], row['scenarioID'], None,
                                             dict(device, deviceID='5031503337360008'), managed)
            else:
                # Early local rejection binds operation selection but makes no device observation.
                self.assertEqual(report['managedEvidence']['outcome'], 'not_observed')
                self.assertNotIn('artifact', report['managedEvidence'])
                self.assertNotIn('recordSHA256', report['managedEvidence'])
            processes.add(report['processID']); phases.add(row['scenarioID'])
            if managed:
                operations.add(managed['operationID'])
                with self.assertRaises(ValueError):
                    mcp.paired.export_report(values['reply'], row['runID'], row['scenarioID'], None, device,
                                             dict(managed, operationID=fresh()))
                evidence = report['managedEvidence']
                accepted_commits += evidence['outcome'] == 'commit_accepted'
                if row['scenarioID'] == 'managed.retire':
                    self.assertTrue(evidence['checkpoint']['released'])
                    self.assertFalse(evidence['checkpoint']['commitIntent'])
                    self.assertEqual(evidence['checkpoint']['unknownReason'], 'bootChanged')
            if row.get('unexpectedFailure'):
                self.assertEqual(row['scenarioID'], 'device.inspect')
                self.assertEqual(report['status'], 'failed')
                self.assertNotIn('snapshot', report['deviceEvidence'])
                self.assertFalse(report['deviceEvidence']['probeAttempted'])
                self.assertEqual(report['deviceEvidence']['sentBytes'], 0)
                self.assertIn('exceeded its SDK deadline', str(report['events']))
            else:
                self.assertEqual(row['status'], row['expectedStatus'])
            if row['status'] == 'outcomeUnknown':
                checkpoint = report['managedEvidence']['checkpoint']
                self.assertEqual(checkpoint['unknownReason'], 'bootChanged')
                self.assertFalse(checkpoint['released'])
                self.assertFalse(checkpoint['commitIntent'])
            if row['label'] == 'managed.commit-refused-after-restart':
                self.assertEqual(report['status'], 'failed')
                self.assertIn('No live pre-commit capability', str(report['events']))
        self.assertEqual((len(processes), len(operations), accepted_commits), (2, 5, 2))
        self.assertEqual(phases, {'device.inspect', 'device.console-binary', 'managed.stage', 'managed.commit',
                                 'managed.abort', 'managed.disconnect', 'managed.reconcile', 'managed.restore', 'managed.retire'})
        for name in ('preRestart', 'final'):
            request, response = (read(ledger['revocation'][name][key]) for key in ('request', 'response'))
            self.assertEqual(request['tool'], 'mcp__firmingo_workbench__workbench_revoke')
            self.assertTrue(response['structuredContent']['revoked'])
        for artifact in ledger['independentCapsuleChecks']['uniqueArtifacts']:
            check = read(artifact['nativeCheck'])
            raw = (DOCS / artifact['capsule']['path']).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), check['capsuleSHA256'])
            self.assertFalse(check['ARMExecutionClaim'])
            self.assertEqual(check['exitCode'], 0)

    def test_hardware_selection_is_explicit_version_two_and_never_an_upload_command(self):
        selected=self.selection(action='run',run_id=fresh(),scenario_id='device.inspect',device_address='192.168.77.1',
            device_board='nano_rp2040_connect',device_id='5031503337360009')
        malformed=[dict(selected,scenario_id='device.console-binary'),dict(selected,device_address='8.8.8.8'),
            dict(selected,device_address='192.168.77.1:22'),dict(selected,firmware_build_id='a'*64),dict(selected,action='commit')]
        for args in malformed:self.assertTrue(self.call('workbench_submit',args)['result']['isError'])
        self.assertEqual(self.calls,[])
        result=self.call('workbench_submit',selected)['result'];self.assertFalse(result['isError'])
        sent=self.calls[-1]['command']['request']
        self.assertEqual(sent['schema'],2)
        self.assertEqual(sent['device'],dict(address='192.168.77.1',boardID='nano_rp2040_connect',deviceID='5031503337360009'))
        self.assertEqual(result['structuredContent']['scenarioCompletion'],'not_observed')
        console=dict(selected,command_id=fresh(),run_id=fresh(),scenario_id='device.console-binary',
            device_boot_id='0123456789abcdef',console_probe='raw-256-v1')
        self.assertFalse(self.call('workbench_submit',console)['result']['isError'])

    def test_managed_stage_and_commit_require_distinct_closed_selections_before_broker_access(self):
        """Queue inert schema-three requests only; no app, source compilation or device operation runs."""
        run=fresh()
        stage=self.selection(action='run',run_id=run,scenario_id='managed.stage',device_address='192.168.77.1',
            device_board='nano_rp2040_connect',device_id='5031503337360009',device_boot_id='0123456789abcdef',
            managed_operation_id=run,managed_sketch='state-a',resident_image_sha256=mcp.paired.request_checker().MANAGED_IMAGE,
            resident_evidence='Parser fixture only; no installed-image claim',managed_authorization='stage-d2-gnd')
        for bad in [dict(stage,managed_authorization='commit-once-d2-gnd'),dict(stage,managed_operation_id=fresh()),
                    dict(stage,console_probe='raw-256-v1'),dict(stage,firmware_build_id='a'*64),dict(stage,device_board='raspberry_pi_pico')]:
            self.assertTrue(self.call('workbench_submit',bad)['result']['isError'])
        self.assertEqual(self.calls,[])
        admitted=self.call('workbench_submit',stage)['result'];self.assertFalse(admitted['isError'])
        self.assertEqual(self.calls[-1]['command']['request']['schema'],3)
        self.assertEqual(self.calls[-1]['command']['request']['managed']['operationID'],run)
        commit=self.selection(action='run',run_id=fresh(),scenario_id='managed.commit',device_address='192.168.77.1',
            device_board='nano_rp2040_connect',device_id='5031503337360009',device_boot_id='0123456789abcdef',
            managed_operation_id=run,managed_record_sha256='b'*64)
        count=len(self.calls)
        self.assertTrue(self.call('workbench_submit',commit)['result']['isError']);self.assertEqual(len(self.calls),count)
        commit['managed_authorization']='commit-once-d2-gnd'
        self.assertFalse(self.call('workbench_submit',commit)['result']['isError'])
        self.assertEqual(self.calls[-1]['command']['request']['managed']['recordSHA256'],'b'*64)


if __name__ == '__main__': unittest.main()
