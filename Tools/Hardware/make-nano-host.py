"""Generate an explicit Nano SDK qualification app from anchored prepared SDK/resident inputs; never contact a board."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('compiler_host', ROOT / 'Tools/ManagedWASM/make-compiler-host.py')
host = importlib.util.module_from_spec(spec); spec.loader.exec_module(host)
CONSUMER = 'd042dc7d3869949d8e311fff28c5d66327ba090ba2ec8ff149e3a12019d8ea8c'
BUILD = 'c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f'


def captured(path, maximum, expected):
    """Bound metadata reads and hash the actual parsed snapshot against its independent anchor."""
    if host.identity(path, maximum)['sha256'] != expected: raise ValueError('Metadata anchor mismatch')
    with path.open('rb') as source: data = source.read(maximum + 1)
    if len(data) > maximum or hashlib.sha256(data).hexdigest() != expected: raise ValueError('Metadata changed during read')
    return json.loads(data)


def test_inputs(root, expected):
    """Check the caller's plan anchor and all evidence bytes against the independently pinned consumer manifest."""
    if root.is_symlink() or not root.is_dir(): raise ValueError('Select a real test-input directory')
    plan = captured(root / 'test-plan.json', 65536, expected)
    if (type(plan['schema']) is not int or plan['schema'] != 1 or plan['kind'] != 'nano-sdk-hardware-qualification-inputs'
            or plan['consumerManifestSHA256'] != CONSUMER or plan['firmwareBuildID'] != BUILD
            or plan['deviceOperations'] is not False or plan['installed'] is not False or plan['hardwareQualified'] is not False):
        raise ValueError('Unexpected Nano test plan')
    consumer = captured(root / 'consumer-manifest.json', 65536, CONSUMER)
    if (plan['board'] != 'nano_rp2040_connect' or plan['profile'] != 'nano-managed-v1'
            or plan['firmwareCommit'] != consumer['review']['firmwareCommit']
            or plan['catalogueSHA256'] != consumer['catalogueSHA256'] or plan['apiAddress'] != '0x10022c9c'
            or plan['firmwareVersion'] != '0.1.0-m9exp1'):
        raise ValueError('Test plan target/build facts mismatch')
    records = [f for f in consumer['files'] if f['path'].startswith('firmware/') or f['path'] == 'catalogue.json']
    records.append({'path': 'consumer-manifest.json', **host.identity(root / 'consumer-manifest.json', 65536)})
    if plan['files'] != records or len(records) != 14: raise ValueError('Test evidence inventory mismatch')
    expected_paths = {f['path'] for f in records} | {'test-plan.json'}
    found = set()
    for file in root.rglob('*'):
        if file.is_symlink(): raise ValueError('Symlinked test evidence')
        if file.is_dir(): continue
        relative = file.relative_to(root).as_posix()
        if relative not in expected_paths: raise ValueError('Unlisted test evidence')
        found.add(relative)
    if found != expected_paths: raise ValueError('Missing test evidence')
    for f in records:
        if host.identity(root / f['path'], f['bytes']) != {k: f[k] for k in ('bytes', 'sha256')}:
            raise ValueError('Corrupt test evidence: ' + f['path'])
    for key, path in (('residentUF2', 'firmware/resident.uf2'), ('residentELF', 'firmware/resident.elf')):
        if plan[key] != next(f for f in records if f['path'] == path): raise ValueError('Resident identity mismatch')
    return plan


def generate(sdk, sdk_anchor, test_root, plan_anchor, output):
    """Reuse the compiler host's anchored SDK verifier, then create a separate explicit device-capable app."""
    plan = test_inputs(test_root, plan_anchor)
    host.generate(sdk, sdk_anchor, output)
    try:
        sources = output / 'Sources'
        for file in sources.iterdir():
            if file.name != 'qualification-context.json': file.unlink()
        for name in ('NanoGate.swift', 'NanoModel.swift', 'NanoApp.swift'):
            shutil.copyfile(ROOT / 'Validation/NanoHost' / name, sources / name)
        old_project = output / 'CompilerQualification.xcodeproj'; project = output / 'NanoQualification.xcodeproj'
        old_project.rename(project)
        for file in [project / 'project.pbxproj', project / 'xcshareddata/xcschemes/CompilerQualification.xcscheme']:
            file.write_text(file.read_text().replace('CompilerQualification', 'NanoQualification').replace('com.firmingokit.compilerqualification', 'com.firmingokit.nanoqualification'))
        (project / 'xcshareddata/xcschemes/CompilerQualification.xcscheme').rename(project / 'xcshareddata/xcschemes/NanoQualification.xcscheme')
        (output / 'CompilerQualification.entitlements').rename(output / 'NanoQualification.entitlements')
        info = plistlib.loads((output / 'Info.plist').read_bytes())
        info['NSLocalNetworkUsageDescription'] = 'Connect to the explicitly selected Nano to qualify Firmingo communication and managed-sketch uploads.'
        (output / 'Info.plist').write_bytes(plistlib.dumps(info))
        evidence = output / 'TestInputs'; evidence.mkdir()
        for f in plan['files'] + [{'path': 'test-plan.json', **host.identity(test_root / 'test-plan.json', 65536)}]:
            target = evidence / f['path']; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(test_root / f['path'], target)
            if host.identity(target, f['bytes']) != {k: f[k] for k in ('bytes', 'sha256')}: raise ValueError('Test evidence changed while copying')
        (output / 'host-inputs.json').unlink()
        files = [{'path': f.relative_to(output).as_posix(), **host.identity(f)} for f in sorted(output.rglob('*')) if f.is_file()]
        receipt = {'schema': 1, 'operation': 'generated_nano_sdk_qualification_host', 'files': files,
                   'preparedManifestSHA256': sdk_anchor, 'testPlanSHA256': plan_anchor, 'consumerManifestSHA256': CONSUMER,
                   'firmwareBuildID': BUILD, 'signed': False, 'installed': False, 'deviceOperations': False}
        (output / 'host-inputs.json').write_text(json.dumps(receipt, indent=2) + '\n'); return receipt
    except BaseException: shutil.rmtree(output); raise


def main():
    """Require exact explicit anchors and new output; never install/launch an app or touch a device."""
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('sdk', type=Path); p.add_argument('sdk_sha256'); p.add_argument('test_inputs', type=Path)
    p.add_argument('test_plan_sha256'); p.add_argument('output', type=Path); a = p.parse_args()
    result = generate(a.sdk.absolute(), a.sdk_sha256, a.test_inputs.absolute(), a.test_plan_sha256, a.output.absolute())
    print(json.dumps({'status': result['operation'], 'files': len(result['files']), 'deviceOperations': False}))


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, KeyError, TypeError) as error: raise SystemExit(str(error)) from error
