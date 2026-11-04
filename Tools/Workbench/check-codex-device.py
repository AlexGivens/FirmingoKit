#!/usr/bin/env python3
"""Explicit live Codex-host/MCP compiler or selected-device checks; never builds, pairs, flashes or starts a model turn."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import threading
import time
import tomllib
import uuid


def private_write(path, value):
    """Keep exact caller IDs and own protocol evidence private, exclusive and outside source control."""
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as file:
        json.dump(value, file, indent=2, allow_nan=False); file.write('\n')


class CodexHost:
    """Actual app-server RPC in an ephemeral metadata context; no model, agent or persisted chat is created."""
    def __init__(self, executable, directory, server):
        self.directory, self.server, self.number = directory, server, 0
        self.incoming = queue.Queue(maxsize=128)
        self.error = open(directory / 'host-stderr.log', 'xb')
        os.chmod(directory / 'host-stderr.log', 0o600)
        # Disable unrelated configured MCP servers only in this short-lived host process.
        options = []
        config = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex'))) / 'config.toml'
        with config.open('rb') as file: configured = tomllib.load(file).get('mcp_servers', {})
        for name in configured:
            if name != server:
                if not re.fullmatch('[A-Za-z0-9_-]+', name): raise ValueError('Unsupported configured server name for scoped host override')
                options.extend(['-c', 'mcp_servers.' + name + '.enabled=false'])
        self.process = subprocess.Popen([executable, *options, 'app-server', '--stdio'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.error)
        self.reader = threading.Thread(target=self.read, daemon=True); self.reader.start()

    def read(self):
        """Only bounded own request replies enter the queue; unrelated notifications/history are not collected."""
        try:
            while True:
                raw = self.process.stdout.readline(1048577)
                if not raw: break
                if len(raw) > 1048576: raise ValueError('Host response exceeds one MiB')
                message = json.loads(raw)
                if 'id' in message: self.incoming.put(message, timeout=2)
        except (ValueError, OSError, queue.Full):
            pass
        finally:
            try: self.incoming.put({'eof': True}, timeout=2)
            except queue.Full: pass

    def call(self, method, params):
        """Save one exact request before sending; host uncertainty never resends an MCP action."""
        self.number += 1; number = self.number
        request = dict(id=number, method=method, params=params)
        private_write(self.directory / (str(number) + '-request.json'), request)
        self.process.stdin.write(json.dumps(request).encode() + b'\n'); self.process.stdin.flush()
        end = time.monotonic() + 30
        while time.monotonic() < end:
            try: response = self.incoming.get(timeout=max(.1, end - time.monotonic()))
            except queue.Empty: break
            if response.get('eof'): raise ValueError('Codex host ended; inspect saved IDs without replay')
            if response.get('id') != number: raise ValueError('Unexpected Codex response ID')
            # thread/start returns metadata only; do not archive context instructions or user configuration.
            saved = dict(response)
            if method == 'thread/start' and 'result' in response:
                saved = dict(id=number, result=dict(ephemeralRequested=True, modelTurnsStarted=0,
                    threadID=response['result']['thread']['id']))
            private_write(self.directory / (str(number) + '-response.json'), saved)
            if 'error' in response: raise ValueError(str(response['error'])[:512])
            return response['result']
        raise TimeoutError('Codex response not observed; inspect saved command/run UUIDs without replay')

    def initialize(self, cwd):
        """Initialize the native host and a nonpersistent test context; never send turn/start."""
        self.identity = self.call('initialize', dict(clientInfo=dict(name='firmingo-workbench-qualification', version='0.1.0'),
            capabilities=dict(experimentalApi=True)))
        self.process.stdin.write(b'{"method":"initialized"}\n'); self.process.stdin.flush()
        started = self.call('thread/start', dict(ephemeral=True, cwd=str(cwd)))
        self.thread = started['thread']['id']
        inventory = self.call('mcpServerStatus/list', dict(threadId=self.thread, serverName=self.server, detail='toolsAndAuthOnly'))
        entry = next((item for item in inventory['data'] if item['name'] == self.server), None)
        expected = {'workbench_sessions', 'workbench_submit', 'workbench_result', 'workbench_revoke'}
        if not entry or entry.get('toolsError') or set(entry['tools']) != expected:
            raise ValueError('Registered Codex host did not discover the expected Workbench surface')

    def tool(self, name, arguments, *, allow_error=False):
        """Every live action goes through Codex's own MCP host, not the adapter implementation or broker directly."""
        result = self.call('mcpServer/tool/call', dict(threadId=self.thread, server=self.server, tool=name, arguments=arguments))
        if result.get('isError') and not allow_error: raise ValueError(json.dumps(result.get('structuredContent', {}))[:512])
        return result

    def command(self, session, action, *, run=None, scenario=None, build=None, device=None, managed=None):
        """Submit once, then observe that exact controller command; no implicit run replay or latest-run selection."""
        command = str(uuid.uuid4()).upper()
        arguments = dict(session_id=session, command_id=command, action=action)
        if run: arguments['run_id'] = run
        if action == 'run':
            arguments['scenario_id'] = scenario
            if build: arguments['firmware_build_id'] = build
            if device: arguments.update(device)
            if managed: arguments.update(managed)
        self.tool('workbench_submit', arguments)
        selection = dict(session_id=session, command_id=command)
        if action == 'report':
            selection['scenario_id'] = scenario
            if build: selection['firmware_build_id'] = build
            if device: selection.update(device)
            if managed: selection.update(managed)
        end = time.monotonic() + 30
        while time.monotonic() < end:
            result = self.tool('workbench_result', selection, allow_error=True)['structuredContent']
            if 'record' not in result: raise ValueError(json.dumps(result)[:512])
            if result['record']['state'] == 'completed': return result
            if result['record']['state'] == 'archived': raise ValueError('Command result archived; no replay permitted')
            time.sleep(.2)
        raise TimeoutError('Controller result not observed; query command ' + command + ' without replay')

    def close(self):
        """EOF stops the temporary host and its MCP child; active scenario authority remains an explicit controller concern."""
        self.process.stdin.close()
        try: self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try: self.process.wait(timeout=3)
            except subprocess.TimeoutExpired: self.process.kill(); self.process.wait(timeout=3)
        self.error.close()


def main():
    """Require explicit registered host, reviewed pairing/build and a new private evidence directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--codex', required=True, type=Path)
    parser.add_argument('--server', default='firmingo-workbench')
    parser.add_argument('--pairing', required=True, type=Path)
    parser.add_argument('--build-id')
    parser.add_argument('--device-address')
    parser.add_argument('--device-id')
    parser.add_argument('--device-board')
    parser.add_argument('--device-boot-id')
    parser.add_argument('--managed-action',choices=['stage','commit','abort','disconnect','reconcile','retire','restore'])
    for name in ['managed-operation-id','managed-sketch','resident-image-sha256','resident-evidence','managed-record-sha256','managed-authorization']: parser.add_argument('--'+name)
    parser.add_argument('--console-probe', choices=['raw-256-v1','fms2-command-2-v1'])
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--revoke', action='store_true', help='Explicitly revoke the selected pairing after successful collection')
    args = parser.parse_args()
    hardware = any([args.device_address,args.device_id,args.device_board,args.console_probe])
    if args.managed_action:
        if not all([args.device_address,args.device_id,args.device_board]) or args.build_id or args.console_probe:
            parser.error('Select exact managed device fields without a compiler descriptor or console probe')
        if args.managed_action=='stage':
            if args.revoke: parser.error('Do not revoke a staged live capability; select a later explicit disposal/reconciliation action')
            if not all([args.managed_sketch,args.resident_image_sha256,args.resident_evidence,args.managed_authorization]): parser.error('Stage requires fixed sketch, reviewed resident and explicit stage authorization')
            scenarios=['device.inspect','managed.stage']
        else:
            if not all([args.managed_operation_id,args.device_boot_id]): parser.error('Follow-up requires original operation and boot')
            scenarios=['managed.'+args.managed_action]
    elif hardware:
        if not all([args.device_address,args.device_id,args.device_board]) or args.build_id: parser.error('Select device address/ID/board without a compiler descriptor')
        scenarios = ['device.inspect'] + (['device.console-binary'] if args.console_probe else [])
    else:
        if args.device_boot_id or any(getattr(args,name) for name in ['managed_operation_id','managed_sketch','resident_image_sha256','resident_evidence','managed_record_sha256','managed_authorization']): parser.error('Select an explicit managed action')
        if not args.build_id or not re.fullmatch('[0-9a-f]{64}', args.build_id): parser.error('Select an exact descriptor SHA-256')
        scenarios = ['compiler.smoke','compiler.diagnostics']
    if args.pairing.stat().st_size > 4096: parser.error('Pairing metadata is excessive')
    pairing = json.loads(args.pairing.read_text())
    session = str(uuid.UUID(pairing['sessionID'])).upper()
    if type(pairing['processID']) is not int or not isinstance(pairing['instanceID'], str): parser.error('Invalid selected app identity')
    args.output.mkdir(mode=0o700)
    private_write(args.output / 'selection.json', dict(pairing=pairing, buildID=args.build_id, server=args.server,
        scenarios=scenarios, managedAction=args.managed_action, managedOperationID=args.managed_operation_id, originalBootID=args.device_boot_id, deviceAddress=args.device_address, deviceID=args.device_id, deviceBoard=args.device_board, consoleProbe=args.console_probe, revokeAfter=args.revoke))
    host = CodexHost(str(args.codex), args.output, args.server)
    summary = []
    try:
        host.initialize(Path.cwd())
        sessions = host.tool('workbench_sessions', {})['structuredContent']['sessions']
        selected = next((item for item in sessions if item['sessionID'] == session), None)
        if (not selected or not selected['paired'] or selected['expired'] or selected['revoked']
                or any(selected[key] != pairing[key] for key in ['processID', 'instanceID', 'appVersion'])):
            raise ValueError('The selected app is not currently paired with the expected producer identity')
        registry = host.command(session, 'list')['record']['reply']
        if not registry['accepted']: raise ValueError('App registry unavailable')
        observed_boot = None
        for scenario in scenarios:
            managed = None
            device = None
            if hardware:
                device = dict(device_address=args.device_address,device_id=args.device_id,device_board=args.device_board)
                if scenario.startswith('managed.'):
                    device['device_boot_id']=observed_boot if scenario=='managed.stage' else args.device_boot_id
                if scenario == 'device.console-binary':
                    if not observed_boot: raise ValueError('No freshly inspected boot; no console probe can be sent')
                    device.update(device_boot_id=observed_boot,console_probe=args.console_probe)
            run = str(uuid.uuid4()).upper()
            if scenario.startswith('managed.'):
                managed={name:getattr(args,name) for name in ['managed_operation_id','managed_sketch','resident_image_sha256','resident_evidence','managed_record_sha256','managed_authorization'] if getattr(args,name) is not None}
                if scenario=='managed.stage':
                    run=str(uuid.UUID(args.managed_operation_id)).upper() if args.managed_operation_id else run
                    managed['managed_operation_id']=run
            result = host.command(session, 'run', run=run, scenario=scenario, build=args.build_id, device=device, managed=managed)
            end = time.monotonic() + 120
            while result['record']['reply']['state']['isRunning']:
                if time.monotonic() >= end: raise TimeoutError('Run observation exceeded bound; no replay permitted')
                time.sleep(2)
                result = host.command(session, 'status', run=run)
            result = host.command(session, 'report', run=run, scenario=scenario, build=args.build_id, device=device, managed=managed)
            report = result['record']['reply']['report']
            private_write(args.output / (scenario + '.json'), result)
            if not result.get('validatedReport') or result['scenarioCompletion'] != 'passed': raise ValueError('Non-pass observation saved; inspect its explicit transaction outcome without replay')
            if report['processID'] != pairing['processID']: raise ValueError('Report process differs from selected paired app')
            if scenario == 'device.inspect': observed_boot = report['deviceEvidence']['snapshot']['bootID']
            summary.append(dict(scenarioID=scenario, runID=run, processID=report['processID'], status=report['status'],
                reportCommandID=result['commandID'], evidence=result.get('evidence', [])))
            print(scenario + ': passed through native Codex MCP host, PID ' + str(report['processID']), flush=True)
        revoked = False
        if args.revoke:
            revoked = host.tool('workbench_revoke', dict(session_id=session))['structuredContent'].get('revoked') is True
            if not revoked: raise ValueError('Revocation not confirmed')
        private_write(args.output / 'summary.json', dict(schema=1, status='passed', sessionID=session,
            codexHost=host.identity, ephemeralHostContext=True, modelTurnsStarted=0, runs=summary, revoked=revoked))
    finally: host.close()


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error: raise SystemExit(str(error)) from error
