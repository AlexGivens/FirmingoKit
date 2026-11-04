#!/usr/bin/env python3
"""Tools-only MCP stdio adapter over an explicitly selected paired Workbench controller."""
import argparse
import base64
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import stat
import sys
import threading

spec = importlib.util.spec_from_file_location('workbench_paired', Path(__file__).with_name('paired.py'))
paired = importlib.util.module_from_spec(spec)
spec.loader.exec_module(paired)

MODERN = '2026-07-28'
LEGACY = ('2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05')
INFO = dict(name='firmingo-workbench', version='0.2.0')  # Adapter version, not a product release.
META = 'io.modelcontextprotocol/'
INPUT_LIMIT, OUTPUT_LIMIT = 16384, 524288
INSTRUCTIONS = ('Use an explicitly paired session. Submit once with caller-chosen command/run UUIDs; '
    'query workbench_result without resubmitting after uncertainty. Run admission is not a pass. '
    'Collect reports with an explicit expected scenario/build. Home/return remains a real device action. '
    'MCP cancellation/exit stops observation, not an admitted scenario; use an exact-run cancel or revoke explicitly.')


def field(description, *, pattern=None, enum=None):
    """Small closed primitive schemas, validated locally without fetching schemas or dependencies."""
    value = dict(type='string', description=description, minLength=1, maxLength=128)
    if pattern: value['pattern'] = pattern
    if enum: value['enum'] = enum
    return value


UUID = field('Explicit UUID; never inferred from another operation.',
    pattern=r'^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$')
SCENARIO = field('Exact scenario ID from the app registry, or expected scenario when collecting a report.',
    pattern=r'^[a-z][a-z0-9.-]{0,95}$')
BUILD = field('Exact firmware descriptor SHA-256; metadata selection does not attest installed firmware.',
    pattern=r'^[0-9a-f]{64}$')


def tool(name, description, properties, required, *, read_only):
    """Describe only the existing finite controller surface, with conservative replay annotations."""
    return dict(name=name, description=description,
        inputSchema=dict(type='object', properties=properties, required=required, additionalProperties=False),
        annotations=dict(readOnlyHint=read_only, destructiveHint=not read_only,
                         idempotentHint=read_only, openWorldHint=False))


HARDWARE = dict(device_address=field('Canonical private IPv4; FMGO port is fixed at 7420.'),
    device_board=field('Explicit SDK board identifier.',enum=list(paired.request_checker().DEVICE_BOARDS)),
    device_id=field('Expected stable device ID.',pattern=r'^[0-9a-f]{16}$'),
    device_boot_id=field('Boot from a separate successful inspection; required before console bytes.',pattern=r'^[0-9a-f]{16}$'),
    console_probe=field('Explicit fixed binary probe for the already-running application.',enum=['raw-256-v1','fms2-command-2-v1']))


TOOLS = [
    tool('workbench_sessions', 'List safe pairing metadata from the selected controller; does not pair or start an app.', {}, [], read_only=True),
    tool('workbench_submit', 'Queue one existing controller command. Returns transport admission only, never scenario success. '
         'Choose command_id before calling; recover uncertainty with workbench_result using that ID. '
         'run requires a fresh run_id and scenario_id; list takes no run; other actions require an exact run_id. '
         'report expectations are supplied to workbench_result.',
         dict(session_id=UUID, command_id=UUID, action=field('Closed controller action.', enum=list(paired.ACTIONS)),
              run_id=UUID, scenario_id=SCENARIO, firmware_build_id=BUILD, **HARDWARE),
         ['session_id', 'command_id', 'action'], read_only=False),
    tool('workbench_result', 'Read one command result without enqueueing anything. Pending/archived is not a pass. '
         'A report requires scenario_id and its exact firmware_build_id when applicable; validates identity, timeline and bytes '
         'through the existing CLI checker. Valid reports are also saved when an evidence directory is configured.',
         dict(session_id=UUID, command_id=UUID, scenario_id=SCENARIO, firmware_build_id=BUILD, **HARDWARE),
         ['session_id', 'command_id'], read_only=False),
    tool('workbench_revoke', 'Explicitly revoke this pairing; the app cancels only controller-owned work on its next exchange. '
         'Does not terminate the app, flash a board or stop the controller.',
         dict(session_id=UUID), ['session_id'], read_only=False)
]
# Result reads can create checked evidence files, but never replace differing bytes.
TOOLS[2]['annotations'].update(destructiveHint=False, idempotentHint=True)


def arguments(name, value):
    """Reject unknown/nested runtime, file, update and shell authority before contacting the controller."""
    definition = next((item for item in TOOLS if item['name'] == name), None)
    if definition is None: raise ProtocolError(-32602, 'Unknown tool')
    schema = definition['inputSchema']
    if not isinstance(value, dict) or set(value) - set(schema['properties']) or set(schema['required']) - set(value):
        raise ValueError('Select exactly the documented tool arguments')
    for key, item in value.items():
        rule = schema['properties'][key]
        if (not isinstance(item, str) or not rule['minLength'] <= len(item) <= rule['maxLength']
                or ('pattern' in rule and not re.fullmatch(rule['pattern'], item))
                or ('enum' in rule and item not in rule['enum'])):
            raise ValueError('Invalid argument: ' + key)
    return value


def private_directory(path, *, create=False):
    """Only operator-selected, owned 0700 nonsymlink directories hold controller access or evidence."""
    if create:
        try: path.mkdir(mode=0o700)
        except FileExistsError: pass
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('Select an owned private directory (0700), without a symlink')


def save_report(root, session_id, command_id, reply):
    """Export only checked report bytes under UUID paths; repeat reads verify existing files instead of overwriting them."""
    private_directory(root)
    session = root / session_id
    private_directory(session, create=True)
    directory = session / command_id
    private_directory(directory, create=True)
    files = {'reply.json': paired.encode(reply),
             'report.json': json.dumps(reply['report'], indent=2, allow_nan=False).encode() + b'\n'}
    for artifact in reply['report']['artifacts']:
        files[artifact['name']] = base64.b64decode(artifact['bytes'], validate=True)
    records = []
    for name, raw in files.items():
        target = directory / name
        try: paired.private_write(target, raw)
        except FileExistsError:
            info = target.lstat()
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077
                    or info.st_size != len(raw) or target.read_bytes() != raw):
                raise ValueError('Existing evidence differs or is unsafe; no file was overwritten')
        records.append(dict(path=str(target), bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest()))
    return records


class Adapter:
    """No transport implementation or compiler: delegates every operation to the existing local broker API."""
    def __init__(self, directory, evidence=None, rpc=paired.rpc):
        self.directory, self.evidence, self.rpc = directory, evidence, rpc

    def call(self, name, value):
        args = arguments(name, value)
        sid = paired.identifier(args['session_id']) if 'session_id' in args else None
        cid = paired.identifier(args['command_id']) if 'command_id' in args else None
        try:
            device = paired.request_checker().selected_device(args,args.get('scenario_id'))
            if device is not None and (name not in ('workbench_submit','workbench_result') or (name=='workbench_submit' and args.get('action')!='run')):
                raise ValueError('Hardware selection belongs only to a selected run or report query')
            if name == 'workbench_sessions':
                return dict(sessions=self.rpc(self.directory, dict(operation='sessions'))), False
            if name == 'workbench_revoke':
                return self.rpc(self.directory, dict(operation='revoke', sessionID=sid)), False
            if name == 'workbench_submit':
                action = args['action']
                command = dict(schema=1, commandID=cid, action=action)
                if action == 'run':
                    if 'run_id' not in args or 'scenario_id' not in args: raise ValueError('run requires explicit run_id and scenario_id')
                    command['request'] = dict(schema=1, requestID=paired.identifier(args['run_id']), operation='run', scenarioID=args['scenario_id'])
                    if 'firmware_build_id' in args: command['request']['firmwareBuildID'] = args['firmware_build_id']
                    if device is not None: command['request'].update(schema=2,device=device)
                    paired.request_checker().validate_request(command['request'])
                else:
                    if 'scenario_id' in args or 'firmware_build_id' in args: raise ValueError('Only run accepts scenario/build selection on submission')
                    if action == 'list':
                        if 'run_id' in args: raise ValueError('list accepts no run selection')
                    else:
                        if 'run_id' not in args: raise ValueError('Select the exact run_id')
                        command['runID'] = paired.identifier(args['run_id'])
                # No issue()/wait loop: one queue operation, even if the MCP connection later disappears.
                try: record = self.rpc(self.directory, dict(operation='command', sessionID=sid, command=command))
                except OSError:
                    return dict(kind='submission_uncertain', sessionID=sid, commandID=cid,
                        recovery='Query workbench_result with this exact command ID; do not replay the action.'), True
                return dict(sessionID=sid, commandID=cid, command=command, admission=record,
                            scenarioCompletion='not_observed'), False
            record = self.rpc(self.directory, dict(operation='result', sessionID=sid, commandID=cid))
            if (not isinstance(record, dict) or record.get('commandID') != cid
                    or record.get('state') not in ('queued', 'delivered', 'completed', 'archived')):
                raise ValueError('Mismatched command result')
            result = dict(sessionID=sid, commandID=cid, record=record, scenarioCompletion='not_observed')
            reply = record.get('reply')
            if record['state'] != 'completed':
                if reply is not None: raise ValueError('Incomplete command unexpectedly has a reply')
                return result, record['state'] == 'archived'
            if not isinstance(reply, dict) or reply.get('command', {}).get('commandID') != cid:
                raise ValueError('Mismatched app command response')
            peers = self.rpc(self.directory, dict(operation='sessions'))
            peer = next((item for item in peers if item['sessionID'] == sid), None)
            if (peer is None or reply.get('instanceID') != peer['instanceID'] or reply.get('processID') != peer['processID']
                    or reply.get('appVersion') != peer['appVersion'] or reply.get('appIdentifier') != paired.BUNDLE
                    or type(reply.get('accepted')) is not bool):
                raise ValueError('Reply does not match the paired producer')
            if reply.get('report') is not None:
                if not reply['accepted']: raise ValueError('Rejected app command cannot qualify a report')
                command = reply['command']
                if command.get('action') != 'report' or not args.get('scenario_id'): raise ValueError('Select the expected report scenario_id')
                report = paired.export_report(reply, command['runID'], args['scenario_id'], args.get('firmware_build_id'), device)
                if report.get('appVersion') != peer['appVersion']: raise ValueError('Report app version differs from its producer')
                result.update(validatedReport=True, scenarioCompletion=report['status'])
                if self.evidence: result['evidence'] = save_report(self.evidence, sid, cid, reply)
                return result, not reply['accepted'] or report['status'] != 'passed'
            return result, not reply['accepted']
        except (ValueError, OSError, KeyError, TypeError) as error:
            return dict(kind='controller_or_validation_error', message=str(error)[:512], sessionID=sid, commandID=cid,
                        automaticReplay=False), True


class ProtocolError(Exception):
    """Wire-level failures stay separate from controller/validation failures returned as tool errors."""
    def __init__(self, code, message, data=None):
        super().__init__(message)
        self.code, self.data = code, data


def identifier(value):
    """MCP request IDs are short strings or safe integers; booleans/null are not IDs."""
    return ((isinstance(value, str) and 0 < len(value) <= 128)
            or (type(value) is int and abs(value) <= 9007199254740991))


class Protocol:
    """Tools-only current per-request protocol plus explicit legacy initialization; no advertised extra capabilities."""
    def __init__(self, adapter):
        self.adapter, self.legacy, self.initialized = adapter, None, False

    def context(self, request):
        if (not isinstance(request, dict) or set(request) - {'jsonrpc', 'id', 'method', 'params'}
                or request.get('jsonrpc') != '2.0' or not identifier(request.get('id')) or not isinstance(request.get('method'), str)):
            raise ProtocolError(-32600, 'Invalid request')
        params = request.get('params', {})
        if not isinstance(params, dict): raise ProtocolError(-32602, 'Expected object params')
        meta = params.get('_meta', {})
        if not isinstance(meta, dict): raise ProtocolError(-32602, 'Expected object _meta')
        modern = META + 'protocolVersion' in meta
        if modern:
            version = meta[META + 'protocolVersion']
            if version != MODERN:
                raise ProtocolError(-32022, 'Unsupported protocol version', dict(supported=[MODERN, *LEGACY], requested=version))
            if not isinstance(meta.get(META + 'clientCapabilities'), dict): raise ProtocolError(-32602, 'Missing clientCapabilities metadata')
        elif request['method'] not in ('initialize', 'ping') and not self.initialized:
            raise ProtocolError(-32600, 'Initialize first or supply modern request metadata')
        return {key: value for key, value in params.items() if key != '_meta'}, modern

    def handle(self, request):
        rid = request.get('id') if isinstance(request, dict) and identifier(request.get('id')) else None
        try:
            params, modern = self.context(request)
            method = request['method']
            if method == 'initialize':
                if modern or self.legacy is not None: raise ProtocolError(-32600, 'Already initialized or modern request')
                if (set(params) != {'protocolVersion', 'capabilities', 'clientInfo'} or not isinstance(params['protocolVersion'], str)
                        or not isinstance(params['capabilities'], dict) or not isinstance(params['clientInfo'], dict)):
                    raise ProtocolError(-32602, 'Invalid initialization')
                self.legacy = params['protocolVersion'] if params['protocolVersion'] in LEGACY else LEGACY[0]
                result = dict(protocolVersion=self.legacy, capabilities=dict(tools={}), serverInfo=INFO, instructions=INSTRUCTIONS)
            elif method == 'server/discover' and modern:
                if params: raise ProtocolError(-32602, 'Discovery takes only metadata')
                result = dict(supportedVersions=[MODERN, *LEGACY], capabilities=dict(tools={}), instructions=INSTRUCTIONS)
            elif method == 'ping':
                if params: raise ProtocolError(-32602, 'ping takes no arguments')
                result = {}
            elif method == 'tools/list':
                if params: raise ProtocolError(-32602, 'No cursor: the complete fixed tool list fits in one response')
                result = dict(tools=TOOLS)
            elif method == 'tools/call':
                if set(params) - {'name', 'arguments'} or not isinstance(params.get('name'), str):
                    raise ProtocolError(-32602, 'Invalid tool call')
                try: value, failed = self.adapter.call(params['name'], params.get('arguments', {}))
                except ValueError as error: value, failed = dict(kind='invalid_arguments', message=str(error)[:512]), True
                result = dict(content=[dict(type='text', text=json.dumps(value, separators=(',', ':'), allow_nan=False))],
                              structuredContent=value, isError=failed)
            else: raise ProtocolError(-32601, 'Method not found')
            if modern: result.update(resultType='complete', _meta={META + 'serverInfo': INFO})
            return dict(jsonrpc='2.0', id=rid, result=result)
        except ProtocolError as error:
            value = dict(code=error.code, message=str(error))
            if error.data is not None: value['data'] = error.data
            return dict(jsonrpc='2.0', id=rid, error=value)


def finite_float(value):
    """JSON exponent overflow cannot smuggle non-finite metadata into the protocol."""
    number = float(value)
    if not math.isfinite(number): raise ValueError('Nonfinite JSON')
    return number


class Stdio:
    """Four bounded daemon workers keep cancellation and EOF responsive while local controller RPC is pending."""
    def __init__(self, protocol, output):
        self.protocol, self.output = protocol, output
        self.lock, self.active, self.closed = threading.RLock(), {}, False

    def send(self, value):
        raw = json.dumps(value, separators=(',', ':'), allow_nan=False).encode() + b'\n'
        if len(raw) > OUTPUT_LIMIT: raise ValueError('MCP response exceeds bound')
        with self.lock:
            if not self.closed:
                try: self.output.write(raw); self.output.flush()
                except OSError: self.closed = True

    def work(self, request, cancelled):
        rid = request['id']
        try:
            if cancelled.is_set(): return
            response = self.protocol.handle(request)
            with self.lock:
                if not cancelled.is_set(): self.send(response)
        except (OSError, ValueError, KeyError, TypeError):
            with self.lock:
                if not cancelled.is_set():
                    self.send(dict(jsonrpc='2.0', id=rid, error=dict(code=-32603, message='Internal adapter failure; query the explicit command ID without replay')))
        finally:
            with self.lock: self.active.pop(rid, None)

    def receive(self, request):
        if isinstance(request, dict) and 'id' not in request:
            if request.get('jsonrpc') != '2.0': return
            if request.get('method') == 'notifications/initialized' and self.protocol.legacy:
                self.protocol.initialized = True
            elif request.get('method') == 'notifications/cancelled':
                params = request.get('params', {})
                rid = params.get('requestId') if isinstance(params, dict) else None
                if identifier(rid):
                    with self.lock:
                        if rid in self.active: self.active[rid].set()
            # Notifications never run tools, write files or receive replies.
            return
        try: self.protocol.context(request)
        except ProtocolError:
            self.send(self.protocol.handle(request)); return
        rid = request['id']
        with self.lock:
            if rid in self.active or len(self.active) >= 4:
                self.send(dict(jsonrpc='2.0', id=rid, error=dict(code=-32600, message='Duplicate active ID or four pending calls; no action admitted')))
                return
            if request['method'] != 'tools/call': self.send(self.protocol.handle(request)); return
            cancelled = threading.Event(); self.active[rid] = cancelled
            threading.Thread(target=self.work, args=(request, cancelled), daemon=True).start()

    def run(self, source):
        try:
            while True:
                raw = source.readline(INPUT_LIMIT + 2)
                if not raw: return 0
                try:
                    if len(raw) > INPUT_LIMIT or not raw.endswith(b'\n'): raise ValueError('Invalid framing')
                    request = json.loads(raw.decode('utf-8'), object_pairs_hook=paired.unique,
                        parse_float=finite_float, parse_constant=lambda _: (_ for _ in ()).throw(ValueError('Nonfinite JSON')))
                    self.receive(request)
                except (ValueError, UnicodeError, RecursionError):
                    self.send(dict(jsonrpc='2.0', id=None, error=dict(code=-32700, message='Invalid bounded JSON line')))
                    if len(raw) > INPUT_LIMIT or not raw.endswith(b'\n'): return 2
        finally:
            with self.lock:
                self.closed = True
                for event in self.active.values(): event.set()


def main():
    """Startup selects authority paths out of band; no controller, app or network service is started implicitly."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True, help='Existing private paired-controller directory')
    parser.add_argument('--evidence-directory', type=Path, help='Existing private directory for validated RPC reports only')
    args = parser.parse_args()
    directory = args.directory.absolute(); private_directory(directory)
    evidence = args.evidence_directory.absolute() if args.evidence_directory else None
    if evidence: private_directory(evidence)
    return Stdio(Protocol(Adapter(directory, evidence)), sys.stdout.buffer).run(sys.stdin.buffer)


if __name__ == '__main__':
    try: raise SystemExit(main())
    except (ValueError, OSError) as error: raise SystemExit(str(error)) from error
