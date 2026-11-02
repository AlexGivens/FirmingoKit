#!/usr/bin/env python3
"""Run versioned offline scenarios through one explicitly selected signed Workbench app."""
import argparse
import base64
import hashlib
import json
import os
import stat
from pathlib import Path
import plistlib
import re
import subprocess
import time
import uuid

PREFIX = b'FIRMINGO_WORKBENCH_RESULT:'
MAX_CAPTURE = 1024 * 1024


def bounded_file(path, maximum):
    """Read only bounded regular nonsymlink input, without blocking on special files."""
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= maximum:
            raise ValueError('invalid or excessive local input')
        data = source.read(maximum + 1)
        if len(data) != info.st_size:
            raise ValueError('local input changed during read')
        return data


def unique_object(pairs):
    """Reject ambiguous JSON keys at the CLI trust boundary."""
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key')
        result[key] = value
    return result


GPIO_SHA = '958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d'
CONSOLE_SHA = 'b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0'
WORKER_SHA = '9a17105b5d17f732435ab81c6bf1083386e5cb5ae8b36569259bac8cf479ec3f'
DEADLINE_SHA = 'bde5df426deb79fd8277abfd5b406cf1288b28b307646b62bc5ee1028cce26eb'
EXERCISES = ('compiler.cancellation', 'compiler.deadline', 'compiler.stress',
             'host.lifecycle', 'host.lifecycle-active', 'host.lifecycle-worker')


def finite_seconds(value, maximum=600):
    """Reject booleans, nonfinite values and timestamps outside a bounded scenario."""
    return type(value) in (int, float) and 0 <= value <= maximum


def validate_exercise(report):
    """Independently reject unsupported lifetime/deadline/stress claims in terminal app evidence."""
    kind = report['scenarioID']
    exercise = report.get('exercise')
    if kind not in EXERCISES:
        return
    if exercise is None and report['status'] != 'passed':
        return
    if not isinstance(exercise, dict) or exercise.get('kind') != kind:
        raise ValueError('missing or mismatched compiler exercise evidence')
    for field, maximum in (('builds', 40), ('progress', 8), ('scenes', 32), ('samples', 128)):
        if not isinstance(exercise.get(field), list) or len(exercise[field]) > maximum:
            raise ValueError('compiler exercise exceeds its evidence bound')
    if type(exercise.get('droppedSamples')) is not int or exercise['droppedSamples'] < 0:
        raise ValueError('invalid omitted memory sample count')
    for collection in ('progress', 'scenes', 'samples'):
        previous = 0
        for point in exercise[collection]:
            if not isinstance(point, dict) or not finite_seconds(point.get('seconds')) or point['seconds'] < previous:
                raise ValueError('invalid exercise observation ordering')
            previous = point['seconds']
            if collection == 'progress' and point.get('phase') not in ('verifying', 'preparing', 'compiling', 'linking', 'packaging'):
                raise ValueError('invalid SDK progress')
            if collection == 'scenes' and point.get('phase') not in ('active', 'inactive', 'background'):
                raise ValueError('invalid actual scene observation')
            if collection == 'samples' and (type(point.get('bytes')) is not int or not 0 < point['bytes'] < 2**50):
                raise ValueError('invalid self-process footprint observation')
    for index, build in enumerate(exercise['builds']):
        if (not isinstance(build, dict) or type(build.get('index')) is not int or build['index'] != index + 1
                or build.get('input') not in ('gpio', 'console', 'worker')
                or build.get('sha256') != (CONSOLE_SHA if build.get('input') == 'console' else GPIO_SHA)
                or not isinstance(build.get('receiptSHA256'), str) or not re.fullmatch('[0-9a-f]{64}', build['receiptSHA256'])
                or not finite_seconds(build.get('seconds'), 180)
                or type(build.get('wasmLinearMemoryBytes')) is not int or not 0 < build['wasmLinearMemoryBytes'] <= 64 * 1024**2):
            raise ValueError('invalid completed compiler build observation')
    if report['status'] != 'passed':
        return
    inputs = [build['input'] for build in exercise['builds']]
    expected = ['gpio', 'console'] * 10 if kind == 'compiler.stress' else [('worker' if kind == 'host.lifecycle-worker' else 'gpio'), 'console']
    if inputs != expected:
        raise ValueError('missing or reordered known build assertions')
    if {artifact['sha256'] for artifact in report['artifacts']} != {GPIO_SHA, CONSOLE_SHA}:
        raise ValueError('exercise lacks independently pinned capsule exports')
    if kind == 'compiler.stress':
        if len(exercise['samples']) < 2 or exercise['scenes'] or exercise.get('outcome') is not None:
            raise ValueError('stress run lacks bounded actual memory observations')
        return
    if kind != 'host.lifecycle':
        started, settled, fresh = (exercise.get(key) for key in ('startedSeconds', 'settledSeconds', 'freshStartedSeconds'))
        if not all(finite_seconds(v) for v in (started, settled, fresh)) or not started <= settled <= fresh:
            raise ValueError('fresh build did not follow request settlement')
        compiling = [p for p in exercise['progress'] if p['phase'] == 'compiling']
        if (len(compiling) != 1 or exercise['progress'][-1]['phase'] != 'compiling'
                or not started <= compiling[0]['seconds'] <= settled):
            raise ValueError('interruption was not in the first source compilation interval')
        if kind == 'compiler.deadline':
            if (exercise.get('outcome') != 'timedOut' or exercise.get('runtimeDeadlineSeconds') != 60
                    or type(exercise['runtimeDeadlineSeconds']) is not int or not 60 <= settled - started <= 75
                    or exercise.get('cancelRequestedSeconds') is not None
                    or exercise.get('workloadSHA256') != DEADLINE_SHA or exercise.get('workloadBytes') != 227646):
                raise ValueError('not a real public-deadline expiry')
        else:
            requested = exercise.get('cancelRequestedSeconds')
            if exercise.get('outcome') != 'cancelled' or not finite_seconds(requested) or not compiling[0]['seconds'] <= requested <= settled:
                raise ValueError('cancellation did not settle after first-source progress')
            if kind == 'compiler.cancellation' and exercise.get('busyObserved') is not True:
                raise ValueError('missing typed SDK busy result')
    if kind.startswith('host.lifecycle'):
        # Launch-only CLI has no real scene adapter. Even a plausible fabricated pass is forbidden.
        raise ValueError('lifecycle qualification requires an interactive mobile report, not launch-only CLI')
    if exercise['scenes'] or exercise.get('sceneObservationScope') != 'Launch process only; no foreground/background claim':
        raise ValueError('launch-only command cannot claim foreground qualification')


def decode_response(raw, request, pid):
    """Require exactly one bounded terminal envelope from the owned app process and exact request."""
    if len(raw) > MAX_CAPTURE:
        raise ValueError('app output exceeds its bound')
    envelopes = [line[len(PREFIX):] for line in raw.splitlines() if line.startswith(PREFIX)]
    if len(envelopes) != 1 or len(envelopes[0]) > 90000:
        raise ValueError('missing, excessive or ambiguous app response')
    payload = base64.b64decode(envelopes[0], validate=True)
    if len(payload) > 65536:
        raise ValueError('app response exceeds 64 KiB')
    value = json.loads(payload, object_pairs_hook=unique_object)
    if (not isinstance(value, dict) or set(value) - {'schema', 'request', 'processID', 'scenarios', 'catalogue', 'report', 'error'}
            or type(value.get('schema')) is not int or value['schema'] != 1
            or value.get('request') != request or value.get('processID') != pid
            or not isinstance(value.get('scenarios'), list) or len(value['scenarios']) > 32):
        raise ValueError('stale, malformed or foreign app response')
    error = value.get('error')
    if error is not None:
        if not isinstance(error, str) or len(error.encode()) > 4096 or value.get('report') is not None:
            raise ValueError('invalid command error')
        return value
    if request['operation'] == 'list':
        if value.get('report') is not None:
            raise ValueError('discovery returned a run')
        return value
    report = value.get('report')
    if (not isinstance(report, dict) or type(report.get('schema')) is not int or report.get('schema') != 1
            or report.get('id') != request['requestID'] or report.get('scenarioID') != request['scenarioID']
            or report.get('firmwareBuildID') != request.get('firmwareBuildID')
            or report.get('processID') != pid or report.get('appIdentifier') != 'com.firmingokit.demo'
            or report.get('deviceOperations') is not False
            or report.get('status') not in ('passed', 'failed', 'blocked', 'cancelled', 'outcomeUnknown')
            or not isinstance(report.get('events'), list) or not 1 <= len(report['events']) <= 64
            or not isinstance(report.get('artifacts'), list) or len(report['artifacts']) > 3):
        raise ValueError('invalid, incomplete or mismatched run report')
    previous = 0
    for index, event in enumerate(report['events']):
        if not isinstance(event, dict):
            raise ValueError('invalid run event')
        elapsed = event.get('seconds')
        if (event.get('sequence') != index or type(elapsed) not in (int, float)
                or not previous <= elapsed <= 180 or not isinstance(event.get('detail'), str)
                or len(event['detail'].encode()) > 4096):
            raise ValueError('invalid run timeline')
        previous = elapsed
    if report['status'] == 'passed' and report['events'][-1].get('phase') != 'complete':
        raise ValueError('passed run lacks completion assertion')
    names = set()
    for artifact in report['artifacts']:
        if not isinstance(artifact, dict):
            raise ValueError('invalid artifact')
        name = artifact.get('name')
        if (not isinstance(name, str) or not re.fullmatch('[a-z0-9-]{1,48}\\.fms', name)
                or name in names or not isinstance(artifact.get('bytes'), str)
                or len(artifact['bytes']) > 6000 or not isinstance(artifact.get('receiptJSON'), str)
                or len(artifact['receiptJSON']) > 22000):
            raise ValueError('invalid artifact export')
        names.add(name)
        data = base64.b64decode(artifact['bytes'], validate=True)
        receipt = base64.b64decode(artifact['receiptJSON'], validate=True)
        if not 260 <= len(data) <= 4096 or hashlib.sha256(data).hexdigest() != artifact.get('sha256') or len(receipt) > 16384:
            raise ValueError('artifact bytes differ from their report')
        json.loads(receipt, object_pairs_hook=unique_object)
    validate_exercise(report)
    return value


def signature(app, team):
    """Validate the selected existing app; never build, sign, install or search for another executable."""
    if app.is_symlink() or not app.is_dir() or not re.fullmatch('[A-Z0-9]{10}', team):
        raise ValueError('select a real Workbench app and exact development team')
    info = plistlib.loads(bounded_file(app / 'Contents/Info.plist', 65536))
    if info.get('CFBundleIdentifier') != 'com.firmingokit.demo' or info.get('CFBundleExecutable') != 'FirmingoWorkbench':
        raise ValueError('selected bundle is not the consolidated Workbench app')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True, timeout=30)
    details = subprocess.run(['codesign', '-dvvv', str(app)], check=True, capture_output=True, text=True, timeout=15).stderr
    if ('TeamIdentifier=' + team + '\n' not in details or 'flags=0x10000(runtime)' not in details
            or 'Authority=Apple Development:' not in details):
        raise ValueError('expected development signing/hardened runtime not present')
    entitlements = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(app)],
                                 check=True, capture_output=True, timeout=15)
    settings = plistlib.loads(entitlements.stdout)
    required = ('com.apple.security.app-sandbox', 'com.apple.security.network.client',
                'com.apple.security.files.user-selected.read-write')
    if not all(settings.get(key) is True for key in required) or settings.get('com.apple.security.network.server') is True:
        raise ValueError('Workbench sandbox capabilities differ from the offline CLI contract')
    return details, settings


def launch(app, team, output, request):
    """Launch one owned app process, bound capture/time, and export only correlated app-owned evidence."""
    details, entitlements = signature(app, team)
    executable = app / 'Contents/MacOS/FirmingoWorkbench'
    if not executable.is_file() or executable.is_symlink():
        raise ValueError('invalid Workbench executable')
    output.mkdir(parents=False, exist_ok=False)
    executable_sha = hashlib.sha256(bounded_file(executable, 64 * 1024 * 1024)).hexdigest()
    process = None
    try:
        (output / 'request.json').write_text(json.dumps(request, indent=2) + '\n')
        (output / 'signature.txt').write_text(details)
        with (output / 'stdout.log').open('xb') as stdout, (output / 'stderr.log').open('xb') as stderr:
            encoded = base64.b64encode(json.dumps(request, separators=(',', ':')).encode()).decode()
            process = subprocess.Popen([str(executable), '--workbench-request', encoded], stdout=stdout, stderr=stderr)
            started = time.monotonic()
            (output / 'launch.json').write_text(json.dumps({'requestID': request['requestID'], 'processID': process.pid,
                'executableSHA256': executable_sha, 'entitlements': entitlements}) + '\n')
            while process.poll() is None:
                if time.monotonic() - started > 180 or any((output / name).stat().st_size > MAX_CAPTURE for name in ('stdout.log', 'stderr.log')):
                    raise TimeoutError('owned Workbench app exceeded its time/output bound; incomplete context is not success')
                try:
                    process.wait(timeout=0.1)
                except subprocess.TimeoutExpired:
                    continue
        if any((output / name).stat().st_size > MAX_CAPTURE for name in ('stdout.log', 'stderr.log')):
            raise ValueError('final app capture exceeds its bound')
        if hashlib.sha256(bounded_file(executable, 64 * 1024 * 1024)).hexdigest() != executable_sha:
            raise ValueError('selected executable changed during run')
        value = decode_response((output / 'stdout.log').read_bytes(), request, process.pid)
        report = value.get('report')
        expected_exit = 2 if value.get('error') is not None else (
            {'passed': 0, 'blocked': 3, 'cancelled': 4, 'failed': 1, 'outcomeUnknown': 1}[report['status']] if report else 0)
        if process.returncode != expected_exit:
            raise ValueError('app exit status disagrees with structured result')
        result = json.dumps(value, indent=2) + '\n'
        (output / 'result.json').write_text(result)
        for artifact in (report or {}).get('artifacts', []):
            (output / artifact['name']).write_bytes(base64.b64decode(artifact['bytes'], validate=True))
        summary = {'schema': 1, 'requestID': request['requestID'], 'status': report['status'] if report else ('commandError' if value.get('error') else 'listed'),
                   'resultSHA256': hashlib.sha256(result.encode()).hexdigest(), 'result': str(output / 'result.json'),
                   'deviceOperations': False}
        if not report:
            summary['scenarios'] = value['scenarios']; summary['catalogue'] = value.get('catalogue'); summary['error'] = value.get('error')
        print(json.dumps(summary, indent=2))
        return expected_exit
    except BaseException as error:
        if process is not None and process.poll() is None:
            process.kill(); process.wait(timeout=10)
        (output / 'failure.json').write_text(json.dumps({'schema': 1, 'requestID': request['requestID'],
            'status': 'commandError', 'error': str(error)[:2048], 'automaticReplay': False}) + '\n')
        raise


def main():
    """Closed CLI; no app discovery, service override, hardware argument or implicit default scenario."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('list', 'run'))
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--team', required=True)
    parser.add_argument('--output', type=Path, required=True, help='new local result directory')
    parser.add_argument('--scenario')
    parser.add_argument('--build-id')
    parser.add_argument('--request-id', default=None, help='fresh UUID; replay is rejected by the app journal')
    args = parser.parse_args()
    if ((args.operation == 'list' and (args.scenario or args.build_id))
            or (args.operation == 'run' and (not args.scenario or not re.fullmatch('[a-z0-9.-]{1,96}', args.scenario)))
            or (args.build_id and not re.fullmatch('[0-9a-f]{64}', args.build_id))):
        parser.error('select an explicit scenario/build only for run')
    request = dict(schema=1, requestID=str(uuid.UUID(args.request_id) if args.request_id else uuid.uuid4()).upper(), operation=args.operation)
    if args.scenario:
        request['scenarioID'] = args.scenario
    if args.build_id:
        request['firmwareBuildID'] = args.build_id
    return launch(args.app.absolute(), args.team, args.output.absolute(), request)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error
