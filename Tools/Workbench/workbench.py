#!/usr/bin/env python3
"""Run versioned offline scenarios through one explicitly selected signed Workbench app."""
import argparse
import base64
import hashlib
import ipaddress
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


DEVICE_BOARDS = ('nano_rp2040_connect', 'raspberry_pi_pico')
DEVICE_SCENARIOS = ('device.inspect', 'device.console-binary')
DEVICE_FIELDS = {'device_address': 'address', 'device_board': 'boardID', 'device_id': 'deviceID',
                 'device_boot_id': 'bootID', 'console_probe': 'consoleProbe'}


MANAGED_SCENARIOS = ('managed.stage','managed.commit','managed.abort','managed.disconnect','managed.reconcile','managed.retire','managed.restore')
MANAGED_IMAGE = '1ef766226ce6a2c51c668562cd51a71ed0bfbe1634b76b54d704c7e710ca1b2f'
MANAGED_PINS = {'state-a':'537ce260fc33d4b23b2f8829aee6a9b12653236db6baad4c317040dbf087fd89',
                'state-b':'505c723804addf218e9018375c1f63fd036c2e0bf19d0173ae189b04418aa9b0'}
MANAGED_FIELDS = {'managed_operation_id':'operationID','managed_sketch':'sketch','resident_image_sha256':'residentImageSHA256',
                  'resident_evidence':'evidence','managed_record_sha256':'recordSHA256','managed_authorization':'authorization'}


def validate_managed_selection(value, scenario, run_id=None):
    """Explicit separately authorized phases; no remote source, path, bytes or restored commit authority."""
    if not isinstance(value,dict) or set(value)-set(MANAGED_FIELDS.values()) or scenario not in MANAGED_SCENARIOS:
        raise ValueError('invalid managed phase selection')
    operation = str(uuid.UUID(value['operationID'])).upper()
    if operation != value['operationID']: raise ValueError('select canonical managed operation UUID')
    if scenario=='managed.restore':
        if set(value)!={'operationID'}: raise ValueError('restore accepts only original operation identity')
        return value
    if scenario=='managed.stage':
        if (set(value)!={'operationID','sketch','residentImageSHA256','evidence','authorization'}
                or (run_id is not None and operation!=run_id) or value['sketch'] not in MANAGED_PINS
                or value['residentImageSHA256']!=MANAGED_IMAGE or not isinstance(value['evidence'],str)
                or not 8<=len(value['evidence'].encode())<=512 or value['authorization']!='stage-d2-gnd'):
            raise ValueError('stage requires fixed source, reviewed resident evidence and explicit D2 authorization')
    else:
        keys={'operationID','recordSHA256'} | ({'authorization'} if scenario=='managed.commit' else set())
        if (set(value)!=keys or not re.fullmatch('[0-9a-f]{64}',value['recordSHA256'])
                or (scenario=='managed.commit' and value['authorization']!='commit-once-d2-gnd')):
            raise ValueError('select exact saved transaction and separate one-shot commit authorization')
    return value


def selected_managed(arguments,scenario):
    """Use the same closed conversion for launch CLI, paired CLI and MCP expectations."""
    value={target:arguments[key] for key,target in MANAGED_FIELDS.items() if arguments.get(key) is not None}
    return validate_managed_selection(value,scenario) if value else None


def validate_device_selection(value, scenario):
    """Version-two local FMGO selection; no hostname, arbitrary port, source or update authority."""
    if (not isinstance(value, dict) or set(value)-set(DEVICE_FIELDS.values())
            or not {'address','boardID','deviceID'} <= set(value)):
        raise ValueError('select an exact device endpoint and identity')
    address = ipaddress.IPv4Address(value['address'])
    if str(address) != value['address'] or not any(address in ipaddress.IPv4Network(block) for block in ('10.0.0.0/8','172.16.0.0/12','192.168.0.0/16')):
        raise ValueError('select a canonical private IPv4 endpoint')
    if value['boardID'] not in DEVICE_BOARDS or not re.fullmatch('[0-9a-f]{16}',value['deviceID']):
        raise ValueError('select an exact SDK board/device identity')
    if scenario == 'device.inspect':
        if set(value) != {'address','boardID','deviceID'}: raise ValueError('inspection accepts no boot assumption or probe')
    elif scenario == 'device.console-binary':
        if (set(value) != set(DEVICE_FIELDS.values()) or not re.fullmatch('[0-9a-f]{16}',value['bootID'])
                or value['consoleProbe'] not in ('raw-256-v1','fms2-command-2-v1')):
            raise ValueError('inspect first, then explicitly select that boot and fixed binary probe')
    elif scenario in MANAGED_SCENARIOS:
        if (set(value)!={'address','boardID','deviceID','bootID'} or value['boardID']!='nano_rp2040_connect'
                or not re.fullmatch('[0-9a-f]{16}',value['bootID'])): raise ValueError('select original inspected Nano boot without console authority')
    else: raise ValueError('device selection is only for implemented hardware scenarios')
    return value


def selected_device(arguments, scenario):
    """Share closed flat CLI/MCP argument conversion instead of adding another endpoint parser."""
    value = {target:arguments[key] for key,target in DEVICE_FIELDS.items() if arguments.get(key) is not None}
    return validate_device_selection(value,scenario) if value else None


def validate_request(request):
    """Keep legacy offline requests closed and admit hardware only through the explicit version-two extension."""
    if (not isinstance(request,dict) or set(request)-{'schema','requestID','operation','scenarioID','firmwareBuildID','device','managed'}
            or type(request.get('schema')) is not int or request['schema'] not in (1,2,3)):
        raise ValueError('invalid request schema/options')
    uuid.UUID(request['requestID'])
    if request.get('operation') == 'list':
        if set(request) != {'schema','requestID','operation'} or request['schema'] != 1: raise ValueError('invalid discovery selection')
    elif request.get('operation') == 'run':
        if not isinstance(request.get('scenarioID'),str): raise ValueError('select an exact scenario')
        if request['schema'] == 3:
            validate_device_selection(request.get('device'),request['scenarioID'])
            validate_managed_selection(request.get('managed'),request['scenarioID'],request['requestID'])
            if 'firmwareBuildID' in request: raise ValueError('managed vectors accept no compiler override')
        elif request['schema'] == 2:
            if 'managed' in request or request['scenarioID'] in MANAGED_SCENARIOS: raise ValueError('managed workflow requires schema three')
            validate_device_selection(request.get('device'),request['scenarioID'])
            if 'firmwareBuildID' in request: raise ValueError('hardware checks need no compiler descriptor')
        elif 'device' in request or 'managed' in request or request['scenarioID'] in DEVICE_SCENARIOS+MANAGED_SCENARIOS:
            raise ValueError('hardware scenarios require a version-two device selection')
    else: raise ValueError('unsupported request operation')
    return request


def validate_device_report(report, selection):
    """Check actual hardware observation scope and every binary reply byte; nonpass reports retain partial evidence."""
    value = report.get('deviceEvidence')
    if not isinstance(value,dict) or value.get('selection') != selection or report.get('artifacts') or report.get('exercise') is not None or report.get('managedEvidence') is not None:
        raise ValueError('missing or foreign hardware evidence')
    for key in ('connectionAttempted','consoleOpened','probeAttempted','consoleClosed','disconnected'):
        if type(value.get(key)) is not bool: raise ValueError('invalid hardware state flags')
    if type(value.get('sentBytes')) is not int or not 0 <= value['sentBytes'] <= 257: raise ValueError('invalid sent-byte count')
    received = base64.b64decode(value.get('received',''),validate=True)
    if len(received)>257: raise ValueError('excessive probe evidence')
    mismatch = value.get('firstMismatchOffset')
    if mismatch is not None and (type(mismatch) is not int or not 0<=mismatch<=256): raise ValueError('invalid mismatch offset')
    if report['status'] != 'passed': return
    snapshot = value.get('snapshot')
    if (not value['connectionAttempted'] or not value['disconnected'] or not isinstance(snapshot,dict)
            or type(snapshot.get('protocolMajor')) is not int or snapshot.get('protocolMajor') != 1 or snapshot.get('deviceID') != selection['deviceID']
            or snapshot.get('boardID') != selection['boardID'] or not re.fullmatch('[0-9a-f]{16}',snapshot.get('bootID',''))
            or not isinstance(snapshot.get('channels'),list) or not 1<=len(snapshot['channels'])<=16
            or not isinstance(snapshot.get('targets'),list) or len(snapshot['targets'])>16
            or not isinstance(snapshot.get('firmwareVersion'),str) or not re.fullmatch('[A-Za-z0-9_.-]{1,32}',snapshot['firmwareVersion'])
            or type(snapshot.get('maximumPayload')) is not int or not 512<=snapshot['maximumPayload']<=65536
            or not isinstance(snapshot.get('authenticationMode'),str) or not 1<=len(snapshot['authenticationMode'])<=64):
        raise ValueError('missing validated hello/cleanup evidence')
    if report['scenarioID']=='device.inspect':
        if value['consoleOpened'] or value['probeAttempted'] or value['consoleClosed'] or value['sentBytes'] or received or mismatch is not None:
            raise ValueError('inspection cannot qualify console writes')
    elif (not value['consoleOpened'] or not value['probeAttempted'] or not value['consoleClosed']
            or snapshot['bootID'] != selection['bootID'] or not any(c.get('id')==1 and c.get('backend')=='application' for c in snapshot['channels'])
            or value['sentBytes'] != (257 if selection['consoleProbe']=='fms2-command-2-v1' else 256)
            or received != bytes(range(256)) or mismatch is not None):
        raise ValueError('binary probe/boot/cleanup assertions did not pass')


def validate_managed_report(report,request):
    """Bind observed checkpoints to device/build/record; early local refusals supply no device facts."""
    value=report.get('managedEvidence');scenario=request['scenarioID'];selection=request['managed']
    if (not isinstance(value,dict) or value.get('selection')!=selection or report.get('deviceEvidence') is not None
            or report.get('artifacts') or report.get('exercise') is not None): raise ValueError('invalid managed report scope')
    checkpoint=value.get('checkpoint')
    if checkpoint is None:
        if (report['status']=='passed' or value.get('outcome')!='not_observed'
                or value.get('recordSHA256') is not None or value.get('artifact') is not None):
            raise ValueError('managed report without checkpoint cannot claim a device outcome, record or artifact')
        return
    original=checkpoint['request'];validate_request(original)
    if (original['scenarioID']!='managed.stage' or original['device']!=request['device']
            or original['managed']['operationID']!=selection['operationID'] or checkpoint.get('schema')!=1):
        raise ValueError('foreign managed checkpoint')
    for key in ('stageIntent','commitIntent','released'):
        if type(checkpoint.get(key)) is not bool: raise ValueError('invalid checkpoint intent')
    record=checkpoint.get('record');snapshot=checkpoint.get('snapshot');unknown=checkpoint.get('unknownReason')
    if record is not None:
        required={'version','deviceID','bootID','boardID','targetID','format','uploadID','size','sha256','residentELFSHA256','firmwareImageSHA256'}
        if (not isinstance(record,dict) or set(record)!=required or record['version']!=1 or not checkpoint['stageIntent']
                or any(record[k]!=original['device'][k] for k in ('deviceID','bootID','boardID'))
                or record['targetID']!=2 or record['format']!='nano-managed-v2' or record['firmwareImageSHA256']!=MANAGED_IMAGE
                or type(record['uploadID']) is not int or not 1<=record['uploadID']<=4294967295
                or type(record['size']) is not int or record['size']!=(544 if original['managed']['sketch']=='state-a' else 548)
                or record['residentELFSHA256']!='bf32639c7fc2181c9ff6f99aaf8c64e19bda4f83f9690321e2b098bc81e451a8'
                or record['sha256']!=MANAGED_PINS[original['managed']['sketch']]): raise ValueError('changed managed SDK record')
    if scenario not in ('managed.stage','managed.restore'):
        digest=hashlib.sha256(json.dumps(record,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
        if digest!=selection['recordSHA256']: raise ValueError('foreign saved-record hash')
    current_digest=hashlib.sha256(json.dumps(record,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
    if value.get('recordSHA256')!=current_digest: raise ValueError('published record hash differs from checkpoint')
    if checkpoint['commitIntent'] and record is None: raise ValueError('commit without record')
    if snapshot is not None:
        if (not isinstance(snapshot,dict) or record is None or any(snapshot.get(k)!=record[k] for k in ('uploadID','size','sha256'))
                or type(snapshot.get('received')) is not int or not 0<=snapshot['received']<=record['size']
                or type(snapshot.get('slotTouched')) is not bool or unknown is not None): raise ValueError('foreign or ambiguous snapshot')
        state=snapshot.get('state');error=snapshot.get('errorCode');touched=snapshot['slotTouched'];complete=snapshot['received']==record['size']
        if (state not in ('accepted','verified','committing','installed','boot_confirmed','aborted','failed')
                or not isinstance(error,str) or not re.fullmatch('[a-z0-9_]{1,32}',error)
                or (state in ('accepted','verified','aborted') and touched)
                or (state in ('verified','committing','installed','boot_confirmed') and not complete)
                or (state in ('installed','boot_confirmed') and not touched)
                or (state in ('accepted','verified','committing','installed','boot_confirmed') and error!='none')
                or (state=='failed' and error=='none')): raise ValueError('invalid transaction state facts')
    if unknown is not None and unknown not in ('bootChanged','deviceChanged','targetUnavailable','recordMismatch','stageFailedNoCommit','recordNotIssued','recordUnavailable:wrong_target','recordUnavailable:unsupported','recordUnavailable:invalid_state'):
        raise ValueError('invalid unknown reason')
    if checkpoint['released'] and checkpoint['stageIntent'] and not ((snapshot or {}).get('state') in ('aborted','boot_confirmed') or (not checkpoint['commitIntent'] and (unknown=='bootChanged' or (record is None and unknown=='stageFailedNoCommit')))):
        raise ValueError('unresolved managed context released')
    artifact=value.get('artifact')
    if artifact is not None:
        data=base64.b64decode(artifact['bytes'],validate=True);receipt=base64.b64decode(artifact['receiptJSON'],validate=True)
        if (scenario!='managed.stage' or len(data)>4096 or len(receipt)>16384
                or hashlib.sha256(data).hexdigest()!=MANAGED_PINS[selection['sketch']] or artifact['sha256']!=MANAGED_PINS[selection['sketch']]): raise ValueError('changed fixed artifact')
        facts=json.loads(receipt,object_pairs_hook=unique_object)
        if (facts.get('firmwareBuildID')!='dacbf259b96de0e050514764253403f3ef1ef51d0f9efaf1f43a10d8654c0e18'
                or facts.get('capsuleSHA256')!=artifact['sha256']): raise ValueError('foreign compiler receipt')
    if report['status']!='passed': return
    if scenario=='managed.restore' and value.get('outcome')=='context_restored': return
    if scenario=='managed.retire' and value.get('outcome')=='retired_unissued' and record is None and not checkpoint['commitIntent'] and checkpoint['released'] and unknown=='stageFailedNoCommit': return
    expected={'managed.stage':'ram_verified','managed.commit':'commit_accepted','managed.abort':'aborted','managed.disconnect':'disconnected','managed.reconcile':('boot_confirmed','aborted'),'managed.retire':'retired_precommit'}
    allowed=expected[scenario];allowed=(allowed,) if isinstance(allowed,str) else allowed
    if record is None or value['outcome'] not in allowed: raise ValueError('managed phase did not pass')
    if scenario=='managed.stage' and (artifact is None or checkpoint['commitIntent'] or checkpoint['released']): raise ValueError('stage is not RAM-only')
    if scenario=='managed.commit' and (not checkpoint['commitIntent'] or (snapshot or {}).get('state')!='committing' or snapshot['slotTouched']): raise ValueError('unconfirmed commit acceptance')
    if scenario=='managed.abort' and (snapshot or {}).get('errorCode')!='none': raise ValueError('explicit abort was not acknowledged')
    if scenario in ('managed.abort','managed.reconcile') and ((snapshot or {}).get('state')!=value['outcome'] or not checkpoint['released']): raise ValueError('unconfirmed disposal/startup')
    if scenario in ('managed.abort','managed.disconnect','managed.retire') and checkpoint['commitIntent']: raise ValueError('pre-commit outcome after commit intent')
    if scenario=='managed.retire' and (unknown!='bootChanged' or not checkpoint['released']): raise ValueError('invalid pre-commit retirement')


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


def validate_exercise(report, *, interactive=False):
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
        if len(exercise['samples']) < 2 or (exercise['scenes'] and not interactive) or exercise.get('outcome') is not None:
            raise ValueError('stress run lacks bounded actual memory observations')
        return
    if kind != 'host.lifecycle':
        started, settled, fresh = (exercise.get(key) for key in ('startedSeconds', 'settledSeconds', 'freshStartedSeconds'))
        if not all(finite_seconds(v) for v in (started, settled, fresh)) or not started <= settled <= fresh:
            raise ValueError('fresh build did not follow request settlement')
        compiling = [p for p in exercise['progress'] if p['phase'] == 'compiling']
        if (kind != 'host.lifecycle-active' and (len(compiling) != 1 or exercise['progress'][-1]['phase'] != 'compiling'
                or not started <= compiling[0]['seconds'] <= settled)):
            raise ValueError('interruption was not in the first source compilation interval')
        if kind == 'compiler.deadline':
            if (exercise.get('outcome') != 'timedOut' or exercise.get('runtimeDeadlineSeconds') != 60
                    or type(exercise['runtimeDeadlineSeconds']) is not int or not 60 <= settled - started <= 75
                    or exercise.get('cancelRequestedSeconds') is not None
                    or exercise.get('workloadSHA256') != DEADLINE_SHA or exercise.get('workloadBytes') != 227646):
                raise ValueError('not a real public-deadline expiry')
        else:
            requested = exercise.get('cancelRequestedSeconds')
            progress = exercise['progress']
            if (exercise.get('outcome') != 'cancelled' or not finite_seconds(requested) or not progress
                    or not started <= progress[-1]['seconds'] <= requested <= settled):
                raise ValueError('cancellation did not settle after first-source progress')
            if kind == 'compiler.cancellation' and exercise.get('busyObserved') is not True:
                raise ValueError('missing typed SDK busy result')
    if kind.startswith('host.lifecycle'):
        if not interactive:
            raise ValueError('lifecycle qualification requires an interactive mobile report, not launch-only CLI')
        scenes = exercise['scenes']
        if (exercise.get('sceneObservationScope') != 'Actual aggregate SwiftUI app scenes; no suspension claim'
                or not scenes or scenes[0]['phase'] != 'active' or scenes[-1]['phase'] != 'active'
                or any(a['phase'] == b['phase'] for a, b in zip(scenes, scenes[1:]))):
            raise ValueError('missing actual ordered scene observations')
        backgrounds = [i for i, point in enumerate(scenes) if point['phase'] == 'background']
        if len(backgrounds) != 1:
            raise ValueError('expected one explicit background interval')
        index = backgrounds[0]
        later = next((point for point in scenes[index+1:] if point['phase'] == 'active'), None)
        if (index == 0 or scenes[index-1]['phase'] != 'inactive' or later is None
                or later['seconds'] - scenes[index]['seconds'] < 3
                or not finite_seconds(exercise.get('freshStartedSeconds'))
                or not later['seconds'] <= exercise['freshStartedSeconds'] <= report['events'][-1]['seconds']):
            raise ValueError('fresh build did not follow a meaningful real background and return')
        if kind == 'host.lifecycle':
            boundary = next((event for event in report['events'] if event['phase'] == 'waiting-for-background'), None)
            if boundary is None or scenes[index-1]['seconds'] < boundary['seconds']:
                raise ValueError('backgrounding preceded the idle baseline boundary')
        else:
            manual = exercise.get('manuallyStartedSeconds')
            if (not finite_seconds(manual) or not manual <= exercise['startedSeconds'] <= exercise['cancelRequestedSeconds']
                    or not scenes[index-1]['seconds'] <= exercise['cancelRequestedSeconds'] <= scenes[index]['seconds']
                    or exercise.get('workloadSHA256') != WORKER_SHA or exercise.get('workloadBytes') != 227505):
                raise ValueError('missing explicit active-call admission or pinned workload')
            if kind == 'host.lifecycle-worker' and (not finite_seconds(exercise.get('calibratedCompileSeconds'), 55)
                    or exercise['calibratedCompileSeconds'] < 4):
                raise ValueError('worker source calibration was not eligible')
        return
    if interactive:
        if exercise.get('sceneObservationScope') != 'Actual aggregate SwiftUI app scenes; no suspension claim':
            raise ValueError('paired mobile evidence lacks actual scene-observation scope')
        if kind == 'compiler.deadline' and (not exercise['scenes'] or any(s['phase'] != 'active' for s in exercise['scenes'])):
            raise ValueError('mobile deadline lost foreground')
    elif exercise['scenes'] or exercise.get('sceneObservationScope') != 'Launch process only; no foreground/background claim':
        raise ValueError('launch-only command cannot claim foreground qualification')


def decode_response(raw, request, pid, *, interactive=False):
    """Require exactly one bounded terminal envelope from the owned app process and exact request."""
    validate_request(request)
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
    if (not isinstance(report, dict) or type(report.get('schema')) is not int or report.get('schema') != request['schema']
            or report.get('id') != request['requestID'] or report.get('scenarioID') != request['scenarioID']
            or report.get('firmwareBuildID') != request.get('firmwareBuildID')
            or report.get('processID') != pid or report.get('appIdentifier') != 'com.firmingokit.demo'
            or report.get('deviceOperations') is not (request['schema'] >= 2)
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
                or not previous <= elapsed <= (600 if interactive else 180) or not isinstance(event.get('detail'), str)
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
    if request['schema'] == 3: validate_managed_report(report,request)
    elif request['schema'] == 2: validate_device_report(report, request['device'])
    else:
        if report.get('managedEvidence') is not None: raise ValueError('managed evidence requires schema three')
        if report.get('deviceEvidence') is not None: raise ValueError('offline report cannot contain hardware evidence')
        validate_exercise(report, interactive=interactive)
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
                   'deviceOperations': report['deviceOperations'] if report else False}
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
    for field in (DEVICE_FIELDS | MANAGED_FIELDS): parser.add_argument('--'+field.replace('_','-'))
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
    device = selected_device(vars(args),args.scenario)
    if device: request.update(schema=2,device=device)
    managed=selected_managed(vars(args),args.scenario)
    if managed: request.update(schema=3,managed=managed)
    validate_request(request)
    return launch(args.app.absolute(), args.team, args.output.absolute(), request)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error
