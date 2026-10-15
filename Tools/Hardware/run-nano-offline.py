"""Run only offline compilation in a verified signed Nano qualification app; connections are disabled in this mode."""
import argparse
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('compiler_runner', ROOT / 'Tools/ManagedWASM/run-compiler-host.py')
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
PINS = {'gpio': (316, '958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d'),
        'console': (392, 'b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0')}


def decode(data, expected_context, run_id):
    """Reject incomplete/failed/non-offline journals and independently check the actual exported capsule bytes."""
    if len(data) > 1024**2: raise ValueError('Excessive offline output')
    prefix = b'FIRMINGO_NANO_OFFLINE:'
    envelopes = [line[len(prefix):] for line in data.splitlines() if line.startswith(prefix)]
    if len(envelopes) != 1: raise ValueError('Missing or ambiguous offline export')
    value = json.loads(base64.b64decode(envelopes[0], validate=True))
    if set(value) != {'report', 'capsules'} or set(value['capsules']) != set(PINS): raise ValueError('Unexpected offline export')
    raw = base64.b64decode(value['report'], validate=True)
    if len(raw) > 65536: raise ValueError('Excessive journal')
    report = json.loads(raw)
    if (type(report['schema']) is not int or report['schema'] != 1 or report['kind'] != 'nano-sdk-hardware-qualification' or report['runID'] != run_id
            or report['firmwareBuildID'] != 'c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f'
            or report['hardwareQualified'] is not False or report['context'] != expected_context
            or [e['stage'] for e in report['events']] != ['offline-start', 'compiled-gpio', 'compiled-console', 'offline-ready']):
        raise ValueError('Failed, incomplete, stale or non-offline journal')
    artifacts = {}
    for name, (size, digest) in PINS.items():
        contents = base64.b64decode(value['capsules'][name], validate=True)
        if len(contents) != size or hashlib.sha256(contents).hexdigest() != digest: raise ValueError('Wrong offline capsule bytes')
        artifacts[name + '.fms'] = contents
    return raw, artifacts


def main():
    """Require exact explicit app/team/generated inputs and new results; no device command is accepted."""
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('app', type=Path); p.add_argument('team'); p.add_argument('generated_host', type=Path); p.add_argument('output', type=Path)
    a = p.parse_args(); app = a.app.absolute(); output = a.output.absolute()
    details, entitlements = runner.signature(app, a.team, identifier='com.firmingokit.nanoqualification')
    with (a.generated_host / 'Sources/qualification-context.json').open('rb') as source: context = source.read(4097)
    if len(context) > 4096: raise ValueError('Excessive generated context')
    expected = json.loads(context); run_id = str(uuid.uuid4()).upper(); output.mkdir()
    try:
        (output / 'signature.local.txt').write_text(details)
        with (output / 'stdout.log').open('xb') as stdout, (output / 'stderr.log').open('xb') as stderr:
            process = subprocess.Popen([str(app / 'Contents/MacOS/NanoQualification'), '--nano-offline', '--nano-run', run_id], stdout=stdout, stderr=stderr)
            try:
                (output / 'launch.json').write_text(json.dumps({'processID': process.pid, 'runID': run_id, 'mode': 'offline-only'}) + '\n')
                code = process.wait(timeout=180)
            except BaseException:
                if process.poll() is None: process.kill()
                process.wait(timeout=10); raise
        if code: raise ValueError('Offline app failed')
        with (output / 'stdout.log').open('rb') as source: raw, artifacts = decode(source.read(1024**2 + 1), expected, run_id)
        (output / 'report.json').write_bytes(raw)
        records = []
        for name, contents in artifacts.items():
            (output / name).write_bytes(contents); records.append({'path': name, 'bytes': len(contents), 'sha256': hashlib.sha256(contents).hexdigest()})
        result = {'status': 'passed_signed_nano_offline_preparation', 'context': expected, 'runID': run_id,
                  'reportSHA256': hashlib.sha256(raw).hexdigest(), 'artifacts': records, 'teamIdentifier': a.team,
                  'entitlements': entitlements, 'hardenedRuntime': True, 'deviceOperations': False, 'hardwareQualified': False}
        (output / 'operation.json').write_text(json.dumps(result, indent=2) + '\n'); print(json.dumps(result))
    except BaseException as error:
        (output / 'failure.json').write_text(json.dumps({'status': 'failed_nano_offline_check', 'error': str(error)[:1024]}) + '\n'); raise


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error: raise SystemExit(str(error)) from error
