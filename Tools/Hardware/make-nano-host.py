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
CONSUMER = '1bbc0cc19d80490914799fbec5cb4bbc0a942a73fd3bbf6e09fff2c3856e660a'
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


STATEFUL_EXPORT = '90911f7d3684dab4123d36b9a018805cc36ae58cb197c318fe720cb18d434a65'
STATEFUL_CATALOGUE = '8b8f1432d40b42502acca728083e5045f09ed493014bbde1786d3fa8aeed13cd'
STATEFUL_BUILD = 'dacbf259b96de0e050514764253403f3ef1ef51d0f9efaf1f43a10d8654c0e18'


def stateful_inputs(root, expected):
    """Require independent consumer/export/catalogue anchors even when a test plan is reanchored."""
    if root.is_symlink() or not root.is_dir(): raise ValueError('Select real FMS2 inputs')
    plan = captured(root / 'test-plan.json', 65536, expected)
    if (plan['schema'] != 2 or plan['kind'] != 'nano-fms2-sdk-qualification-inputs'
            or plan['consumerManifestSHA256'] != CONSUMER or plan['exportManifestSHA256'] != STATEFUL_EXPORT
            or plan['catalogueSHA256'] != STATEFUL_CATALOGUE or plan['firmwareBuildID'] != STATEFUL_BUILD
            or plan['installed'] is not False or plan['deviceOperations'] is not False or plan['hardwareQualified'] is not False):
        raise ValueError('Unsupported FMS2 plan')
    captured(root / 'consumer-manifest.json', 65536, CONSUMER)
    captured(root / 'catalogue.json', 16384, STATEFUL_CATALOGUE)
    firmware = captured(root / 'firmware/manifest.json', 16384, STATEFUL_EXPORT)
    records = [{'path': 'firmware/' + r['path'], 'bytes': r['bytes'], 'sha256': r['sha256']} for r in firmware['files']]
    records += [{'path': 'firmware/manifest.json', **host.identity(root / 'firmware/manifest.json', 16384)},
                {'path': 'catalogue.json', **host.identity(root / 'catalogue.json', 16384)},
                {'path': 'consumer-manifest.json', **host.identity(root / 'consumer-manifest.json', 65536)}]
    if (plan['files'] != records or len(records) != 42 or plan['profile'] != 'nano-managed-v2'
            or plan['board'] != 'nano_rp2040_connect' or plan['firmwareCommit'] != firmware['firmwareCommit']
            or plan['firmwareVersion'] != '0.1.0-statefulupload-exp1'
            or plan['residentUF2SHA256'] != '1ef766226ce6a2c51c668562cd51a71ed0bfbe1634b76b54d704c7e710ca1b2f'):
        raise ValueError('FMS2 plan evidence mismatch')
    expected_paths = {r['path'] for r in records} | {'test-plan.json'}
    observed = set()
    for path in root.rglob('*'):
        if path.is_symlink(): raise ValueError('Symlinked FMS2 evidence')
        if not path.is_dir(): observed.add(path.relative_to(root).as_posix())
    if observed != expected_paths: raise ValueError('Missing or extra FMS2 evidence')
    for record in records:
        if host.identity(root / record['path'], record['bytes']) != {k: record[k] for k in ('bytes', 'sha256')}: raise ValueError('Corrupt FMS2 evidence')
    return plan


def generate(sdk, sdk_anchor, test_root, plan_anchor, output, permission_check=False, stateful=False, recovery=False):
    """Reuse the compiler host's anchored SDK verifier, then create a separate explicit device-capable app."""
    if stateful and permission_check: raise ValueError("Stateful qualification uses its own app identity")
    if recovery and (not stateful or permission_check): raise ValueError("Recovery bundle requires explicit FMS2 inputs")
    plan = stateful_inputs(test_root, plan_anchor) if stateful else test_inputs(test_root, plan_anchor)
    host.generate(sdk, sdk_anchor, output)
    try:
        sources = output / 'Sources'
        for file in sources.iterdir():
            if file.name != 'qualification-context.json': file.unlink()
        for name in ('NanoGate.swift', 'NanoCandidate.swift', 'NanoStateProbe.swift', 'NanoRecoveryIntent.swift',
                     'NanoRecoveryCheckpoint.swift', 'NanoReplyLossGate.swift', 'NanoCommitProxy.swift', 'NanoModel.swift', 'NanoApp.swift'):
            shutil.copyfile(ROOT / 'Validation/NanoHost' / name, sources / name)
        if stateful:
            for name in ('state-a.ino', 'state-b.ino'): shutil.copyfile(ROOT / 'Validation/NanoHost' / name, sources / name)
            shutil.copyfile(test_root / 'catalogue.json', sources / 'fms2-catalogue.json')
            context_path = sources / 'qualification-context.json'
            context = json.loads(context_path.read_bytes())
            context.update(testPlanSHA256=plan_anchor, exportManifestSHA256=STATEFUL_EXPORT, catalogueSHA256=STATEFUL_CATALOGUE)
            context_path.write_text(json.dumps(context, indent=2) + '\n')
        old_project = output / 'CompilerQualification.xcodeproj'; project = output / 'NanoQualification.xcodeproj'
        old_project.rename(project)
        for file in [project / 'project.pbxproj', project / 'xcshareddata/xcschemes/CompilerQualification.xcscheme']:
            file.write_text(file.read_text().replace('CompilerQualification', 'NanoQualification').replace('com.firmingokit.compilerqualification', 'com.firmingokit.nanoqualification'))
        (project / 'xcshareddata/xcschemes/CompilerQualification.xcscheme').rename(project / 'xcshareddata/xcschemes/NanoQualification.xcscheme')
        (output / 'CompilerQualification.entitlements').rename(output / 'NanoQualification.entitlements')
        info = plistlib.loads((output / 'Info.plist').read_bytes())
        if stateful:
            file = project / 'project.pbxproj'
            file.write_text(file.read_text().replace('com.firmingokit.nanoqualification', 'com.firmingokit.nanostateful').replace('SWIFT_VERSION = 6.0;', 'SWIFT_VERSION = 6.0; OTHER_SWIFT_FLAGS = "$(inherited) -D FMS2_QUALIFICATION";'))
            info['CFBundleDisplayName'] = 'NanoStateful'
            if recovery:
                file.write_text(file.read_text().replace('com.firmingokit.nanostateful', 'com.firmingokit.nanorecovery'))
                info['CFBundleDisplayName'] = 'NanoRecovery'
        if permission_check:
            file = project / 'project.pbxproj'
            file.write_text(file.read_text().replace('com.firmingokit.nanoqualification', 'com.firmingokit.nanopermission'))
            info['CFBundleDisplayName'] = 'NanoPermission'
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
                   'firmwareBuildID': STATEFUL_BUILD if stateful else BUILD, 'statefulContract': stateful, 'permissionCheckBundle': permission_check, 'recoveryCheckBundle': recovery,
                   'signed': False, 'installed': False, 'deviceOperations': False}
        (output / 'host-inputs.json').write_text(json.dumps(receipt, indent=2) + '\n'); return receipt
    except BaseException: shutil.rmtree(output); raise


def main():
    """Require exact explicit anchors and new output; never install/launch an app or touch a device."""
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('sdk', type=Path); p.add_argument('sdk_sha256'); p.add_argument('test_inputs', type=Path)
    p.add_argument('test_plan_sha256'); p.add_argument('output', type=Path)
    p.add_argument('--permission-check-bundle', action='store_true', help='separate read-only NanoPermission identity/display name; no SDK product-name override')
    p.add_argument('--stateful-contract', action='store_true', help='separate explicit FMS2 NanoStateful bundle and state probes')
    p.add_argument('--recovery-check-bundle', action='store_true', help='separate NanoRecovery identity; requires --stateful-contract, no device action in generator')
    a = p.parse_args()
    result = generate(a.sdk.absolute(), a.sdk_sha256, a.test_inputs.absolute(), a.test_plan_sha256, a.output.absolute(), a.permission_check_bundle, a.stateful_contract, a.recovery_check_bundle)
    print(json.dumps({'status': result['operation'], 'files': len(result['files']), 'deviceOperations': False}))


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, KeyError, TypeError) as error: raise SystemExit(str(error)) from error
