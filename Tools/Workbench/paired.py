#!/usr/bin/env python3
"""Explicit pinned-TLS Workbench controller and local CLI. No board, compiler, UI inspection or app discovery."""
import argparse
import base64
import collections
import contextlib
import hashlib
import http.server
import ipaddress
import importlib.util
import json
import os
from pathlib import Path
import secrets
import signal
import socket
import socketserver
import ssl
import stat
import subprocess
import threading
import time
import uuid

LIMIT = 98304
BUNDLE = 'com.firmingokit.demo'
ACTIONS = ('list', 'run', 'status', 'cancel', 'beginLifecycle', 'report')


def identifier(value):
    """Canonical uppercase UUID, with no path semantics."""
    return str(uuid.UUID(value)).upper()


def unique(pairs):
    """Reject ambiguous JSON before admission."""
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key')
        result[key] = value
    return result


def decode(raw):
    """Bound one UTF-8 object; NaN is not a protocol number."""
    if not 0 < len(raw) <= LIMIT:
        raise ValueError('invalid message size')
    value = json.loads(raw, object_pairs_hook=unique, parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite JSON')))
    if not isinstance(value, dict):
        raise ValueError('expected JSON object')
    return value


def encode(value):
    """Bound serialized output before handing it to any socket."""
    raw = json.dumps(value, separators=(',', ':'), allow_nan=False, sort_keys=True).encode()
    if len(raw) > LIMIT:
        raise ValueError('response exceeds protocol bound')
    return raw


def private_address(value):
    """Match the app's explicit private IPv4/loopback invitation boundary."""
    address = ipaddress.IPv4Address(value)
    if not any(address in ipaddress.IPv4Network(block) for block in ('10.0.0.0/8','172.16.0.0/12','192.168.0.0/16','127.0.0.0/8')):
        raise ValueError('bind an explicit private IPv4 or loopback address')
    return str(address)


class Broker:
    """Bounded in-memory sessions and commands. A broker/app restart never restores or replays commands."""
    def __init__(self, endpoint, certificate, clock=time.monotonic):
        self.endpoint, self.certificate, self.clock = endpoint, certificate, clock
        self.lock = threading.Condition()
        self.sessions = {}

    def invite(self, label):
        if not isinstance(label, str) or not 0 < len(label.encode()) <= 64:
            raise ValueError('invalid pairing label')
        with self.lock:
            if len(self.sessions) >= 8:
                raise ValueError('session limit reached; restart the controller explicitly')
            sid, token = identifier(str(uuid.uuid4())), secrets.token_hex(32)
            self.sessions[sid] = dict(label=label, invite=token, inviteUntil=self.clock()+120, token=None, paired=False,
                revoked=False, instance=None, pid=None, appVersion=None, until=None, seen=None, ack=0, sent=0,
                commands=collections.OrderedDict(), queue=collections.deque())
            return dict(schema=1, sessionID=sid, endpoint=self.endpoint, certificateSHA256=self.certificate, token=token, label=label)

    def pair(self, credential, body):
        if (set(body) != {'schema','instanceID','appIdentifier','appVersion','processID'} or type(body['schema']) is not int
                or body['schema'] != 1 or body['appIdentifier'] != BUNDLE or type(body['processID']) is not int
                or body['processID'] <= 0 or not isinstance(body['appVersion'],str) or not 0 < len(body['appVersion']) <= 16):
            raise ValueError('invalid app pairing identity')
        instance = identifier(body['instanceID'])
        with self.lock:
            for sid, session in self.sessions.items():
                if session['invite'] and secrets.compare_digest(session['invite'], credential):
                    if session['paired'] or session['revoked'] or self.clock() > session['inviteUntil']:
                        raise ValueError('invitation expired or consumed')
                    session.update(invite=None, paired=True, token=secrets.token_hex(32), instance=instance,
                        pid=body['processID'], appVersion=body['appVersion'], until=self.clock()+1800, seen=self.clock())
                    return dict(schema=1, sessionID=sid, token=session['token'])
        raise ValueError('invalid invitation')

    def session(self, sid):
        value = self.sessions.get(identifier(sid))
        if not value or value['revoked'] or not value['paired'] or self.clock() > value['until']:
            raise ValueError('session is unavailable, expired or revoked')
        return value

    def exchange(self, credential, body, wait=2):
        if set(body) != {'schema','sessionID','instanceID','ack','reply'} or type(body['schema']) is not int or body['schema'] != 1:
            raise ValueError('invalid acknowledgement envelope')
        with self.lock:
            sid = identifier(body['sessionID']); session = self.session(sid)
            if (not secrets.compare_digest(session['token'], credential) or body['instanceID'] != session['instance']
                    or type(body['ack']) is not int or body['ack'] < 0):
                raise ValueError('invalid session identity')
            ack, reply = body['ack'], body['reply']
            if ack == 0:
                if session['ack'] != 0 or reply is not None:
                    raise ValueError('invalid initial acknowledgement')
            else:
                record = next((item for item in session['commands'].values() if item['sequence'] == ack), None)
                if (record is None or ack not in (session['ack'], session['ack']+1) or ack > session['sent']
                        or not isinstance(reply,dict) or reply.get('schema') != 1 or reply.get('command') != record['command']
                        or reply.get('instanceID') != session['instance'] or reply.get('processID') != session['pid']
                        or reply.get('appIdentifier') != BUNDLE or reply.get('appVersion') != session['appVersion']
                        or type(reply.get('accepted')) is not bool):
                    raise ValueError('stale or mismatched command response')
                encode(reply)
                digest = hashlib.sha256(encode(reply)).hexdigest()
                if record['reply'] is not None and record['digest'] != digest:
                    raise ValueError('changed acknowledgement replay')
                if ack > session['ack']:
                    if not session['queue'] or session['queue'][0] != record['command']['commandID']:
                        raise ValueError('out of order acknowledgement')
                    session['queue'].popleft(); session['ack'] = ack
                    record.update(reply=reply, digest=digest, state='completed')
                    # Keep at most 32 bounded full responses. IDs/tombstones remain until session expiration.
                    completed = [r for r in session['commands'].values() if r['reply'] is not None]
                    for old in completed[:-32]: old['reply'] = None; old['state'] = 'archived'
                    self.lock.notify_all()
            session['seen'] = self.clock()
            if not session['queue'] and wait:
                self.lock.wait_for(lambda: session['queue'] or session['revoked'], timeout=min(wait,2))
            self.session(sid)
            if not session['queue']:
                return dict(schema=1,sessionID=sid,sequence=session['ack'],command=None)
            record = session['commands'][session['queue'][0]]
            record['state'] = 'delivered'; session['sent'] = record['sequence']
            return dict(schema=1,sessionID=sid,sequence=record['sequence'],command=record['command'])

    def command(self, sid, command):
        if (set(command)-{'schema','commandID','action','request','runID'} or command.get('schema') != 1
                or type(command['schema']) is not int or command.get('action') not in ACTIONS):
            raise ValueError('unsupported control action')
        cid = identifier(command['commandID'])
        if cid != command['commandID']:
            raise ValueError('noncanonical command ID')
        action = command['action']
        if action == 'list':
            if command.get('runID') is not None or command.get('request') is not None: raise ValueError('invalid list selection')
        elif action == 'run':
            request = command.get('request')
            if (command.get('runID') is not None or not isinstance(request,dict)
                    or set(request)-{'schema','requestID','operation','scenarioID','firmwareBuildID'}
                    or request.get('schema') != 1 or request.get('operation') != 'run'):
                raise ValueError('invalid run request')
            identifier(request['requestID'])
        elif command.get('request') is not None or not command.get('runID'):
            raise ValueError('select exact run UUID')
        else: identifier(command['runID'])
        if len(encode(command)) > 4096: raise ValueError('command too large')
        with self.lock:
            session = self.session(sid)
            old = session['commands'].get(cid)
            if old:
                if old['command'] != command: raise ValueError('changed command ID replay')
                return dict(commandID=cid,state=old['state'],sequence=old['sequence'])
            if len(session['commands']) >= 256 or len(session['queue']) >= 4:
                raise ValueError('session command/queue limit exceeded')
            sequence = len(session['commands'])+1
            session['commands'][cid] = dict(command=command,sequence=sequence,state='queued',reply=None,digest=None)
            session['queue'].append(cid); self.lock.notify_all()
            return dict(commandID=cid,state='queued',sequence=sequence)

    def result(self, sid, cid):
        with self.lock:
            session = self.session(sid); record = session['commands'].get(identifier(cid))
            if not record: raise ValueError('unknown command')
            return dict(commandID=identifier(cid),state=record['state'],sequence=record['sequence'],reply=record['reply'])

    def control(self, body):
        action = body.get('operation')
        if action == 'invite': return self.invite(body.get('label'))
        if action == 'command': return self.command(body['sessionID'],body['command'])
        if action == 'result': return self.result(body['sessionID'],body['commandID'])
        with self.lock:
            if action == 'sessions':
                return [dict(sessionID=sid,label=s['label'],paired=s['paired'],revoked=s['revoked'],instanceID=s['instance'],
                    processID=s['pid'],appVersion=s['appVersion'],lastSeenSeconds=None if s['seen'] is None else self.clock()-s['seen'],
                    expired=(self.clock() > (s['until'] or s['inviteUntil']))) for sid,s in self.sessions.items()]
            if action == 'revoke':
                session = self.sessions.get(identifier(body['sessionID']))
                if not session: raise ValueError('unknown session')
                session.update(revoked=True,token=None,invite=None); self.lock.notify_all()
                return dict(revoked=True)
        raise ValueError('unsupported local operation')


class ControlHandler(socketserver.StreamRequestHandler):
    """Private Unix socket carries local operator commands; not exposed on the network listener."""
    def handle(self):
        self.request.settimeout(10)
        try:
            raw=self.rfile.readline(LIMIT+2)
            if not raw.endswith(b'\n'): raise ValueError('incomplete local frame')
            result=dict(ok=True,value=self.server.broker.control(decode(raw)))
        except (ValueError,KeyError,TypeError,OSError) as error: result=dict(ok=False,error=str(error)[:256])
        with contextlib.suppress(OSError): self.wfile.write(encode(result)+b'\n')


class ControlServer(socketserver.ThreadingUnixStreamServer):
    daemon_threads=True


class MobileHandler(http.server.BaseHTTPRequestHandler):
    """Only authenticated bounded POSTs; no browser origin, redirects, arbitrary paths or request logging."""
    protocol_version='HTTP/1.1'
    def log_message(self,*args): pass
    def do_POST(self):
        try:
            if (self.path not in ('/v1/pair','/v1/exchange') or self.headers.get('Origin') is not None
                    or self.headers.get('Transfer-Encoding') is not None or len(self.headers.get_all('Content-Length',[]))!=1
                    or len(self.headers.get_all('Authorization',[]))!=1 or self.headers.get('Content-Type')!='application/json'):
                raise ValueError('invalid request')
            count=int(self.headers['Content-Length'])
            if not 0<count<=LIMIT: raise ValueError('invalid size')
            auth=self.headers['Authorization']
            if not auth.startswith('Bearer ') or len(auth)!=71: raise ValueError('invalid credential')
            value=decode(self.rfile.read(count))
            result=self.server.broker.pair(auth[7:],value) if self.path=='/v1/pair' else self.server.broker.exchange(auth[7:],value)
            raw=encode(result); self.send_response(200)
        except (ValueError,KeyError,TypeError,OSError):
            raw=b'{"error":"paired request rejected"}'; self.send_response(403); self.close_connection=True
        self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)))
        self.send_header('Cache-Control','no-store');self.end_headers()
        with contextlib.suppress(OSError): self.wfile.write(raw)


class MobileServer(http.server.ThreadingHTTPServer):
    """Eight bounded TLS workers. Handshakes/read waits cannot block the listener or grow threads indefinitely."""
    daemon_threads=True
    def __init__(self,address,context):
        self.context=context;self.slots=threading.BoundedSemaphore(8)
        super().__init__(address,MobileHandler)
    def process_request(self,request,client_address):
        if not self.slots.acquire(blocking=False): request.close();return
        super().process_request(request,client_address)
    def process_request_thread(self,request,client_address):
        try:
            request.settimeout(10)
            request=self.context.wrap_socket(request,server_side=True)
            super().process_request_thread(request,client_address)
        except OSError: request.close()
        finally: self.slots.release()


def private_write(path,raw):
    """Never overwrite an existing operator/evidence file; permissions protect invitations and controller keys."""
    descriptor=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(descriptor,'wb') as file: file.write(raw)


def rpc(directory,body):
    """Use only the selected current user's protected controller socket."""
    directory=directory.absolute()
    info=directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid!=os.getuid() or info.st_mode & 0o077:
        raise ValueError('controller directory must be owned and private (0700)')
    with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as client:
        client.settimeout(15);client.connect(str(directory/'control.sock'));client.sendall(encode(body)+b'\n')
        with client.makefile('rb') as file: raw=file.readline(LIMIT+2)
    value=decode(raw)
    if not value.get('ok'): raise ValueError(value.get('error','controller rejected command'))
    return value['value']


def serve(args):
    """Start an explicit local TLS broker with fresh in-memory authority; never restore queued work."""
    bind=private_address(args.bind);directory=args.directory.absolute()
    directory.mkdir(mode=0o700,parents=False,exist_ok=False)
    key,cert=directory/'key.pem',directory/'certificate.pem'
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=Firmingo Workbench Controller',
        '-addext','subjectAltName=IP:'+bind,'-addext','basicConstraints=critical,CA:FALSE',
        '-addext','keyUsage=critical,digitalSignature,keyEncipherment','-addext','extendedKeyUsage=serverAuth','-keyout',str(key),'-out',str(cert)],check=True,capture_output=True,timeout=30)
    key.chmod(0o600);cert.chmod(0o600)
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.minimum_version=ssl.TLSVersion.TLSv1_2;context.load_cert_chain(cert,key)
    mobile=MobileServer((bind,args.port),context)
    fingerprint=hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert.read_text())).hexdigest()
    endpoint='https://'+bind+':'+str(mobile.server_address[1])+'/'
    broker=Broker(endpoint,fingerprint);mobile.broker=broker
    control=ControlServer(str(directory/'control.sock'),ControlHandler);control.broker=broker
    (directory/'control.sock').chmod(0o600)
    private_write(directory/'ready.json',encode(dict(schema=1,endpoint=endpoint,certificateSHA256=fingerprint,processID=os.getpid())))
    thread=threading.Thread(target=mobile.serve_forever,daemon=True);thread.start()
    print(json.dumps(dict(status='controller_ready',directory=str(directory),endpoint=endpoint)),flush=True)
    signal.signal(signal.SIGTERM,lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    try: control.serve_forever()
    except KeyboardInterrupt: pass
    finally: mobile.shutdown();mobile.server_close();control.server_close()


def issue(directory, session, command, timeout):
    """Queue once and query by exact command ID; transport uncertainty never causes an automatic resend."""
    rpc(directory,dict(operation='command',sessionID=identifier(session),command=command))
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        record=rpc(directory,dict(operation='result',sessionID=identifier(session),commandID=command['commandID']))
        if record['state']=='completed':
            reply=record['reply']
            if reply.get('command')!=command: raise ValueError('mismatched command result')
            return reply
        if record['state']=='archived': raise ValueError('result archived; do not replay the command')
        time.sleep(0.1)
    raise TimeoutError('response not observed; query this exact command ID without replay: '+command['commandID'])


def export_report(reply, run_id, scenario, build_id):
    """Independently validate current paired-app report identity and real artifacts before export can count as a pass."""
    spec=importlib.util.spec_from_file_location('workbench_export',Path(__file__).with_name('workbench.py'))
    checker=importlib.util.module_from_spec(spec);spec.loader.exec_module(checker)
    report=reply.get('report')
    if not scenario or not isinstance(report,dict): raise ValueError('select the expected scenario when exporting its terminal report')
    request=dict(schema=1,requestID=identifier(run_id),operation='run',scenarioID=scenario)
    if build_id: request['firmwareBuildID']=build_id
    envelope=dict(schema=1,request=request,processID=reply['processID'],scenarios=[],report=report)
    checker.decode_response(checker.PREFIX+base64.b64encode(encode(envelope)),request,reply['processID'],interactive=True)
    return report


def send(args):
    """Finite command or automatic run/wait/export, with scenario outcomes separate from transport admission."""
    if not 1<=args.timeout<=600: raise ValueError('select a one-to-six-hundred-second observation bound')
    command=dict(schema=1,commandID=identifier(args.command_id or str(uuid.uuid4())),action=args.action)
    if args.action=='run':
        if not args.scenario: raise ValueError('select an exact scenario')
        request=dict(schema=1,requestID=identifier(args.run_id or str(uuid.uuid4())),operation='run',scenarioID=args.scenario)
        if args.build_id: request['firmwareBuildID']=args.build_id
        command['request']=request
    elif args.action!='list':
        if not args.run_id: raise ValueError('select exact run UUID')
        command['runID']=identifier(args.run_id)
    elif args.run_id or args.scenario or args.build_id: raise ValueError('list accepts no run selection')
    if args.wait and args.action!='run': raise ValueError('--wait is for one explicit run')
    if args.action=='report' and not args.scenario: raise ValueError('select the expected scenario for terminal report export')
    if args.output:
        args.output.mkdir(mode=0o700,parents=False,exist_ok=False)
        private_write(args.output/'command.json',encode(command))
    reply=issue(args.directory,args.session,command,min(args.timeout,30))
    if args.output: private_write(args.output/'admission.json',encode(reply))
    first=reply
    if args.wait:
        if args.action!='run': raise ValueError('--wait is for one explicit run')
        run_id=command['request']['requestID'];end=time.monotonic()+args.timeout
        while reply['accepted'] and reply['state'].get('status')=='running':
            if reply['state']['awaitingLifecycleStart'] or reply['state'].get('phase')=='waiting-for-background':
                break
            if time.monotonic()>=end: raise TimeoutError('run observation timed out; query status without replay: '+run_id)
            time.sleep(1)
            reply=issue(args.directory,args.session,dict(schema=1,commandID=identifier(str(uuid.uuid4())),action='status',runID=run_id),15)
        if reply['accepted'] and reply['state'].get('status')!='running':
            reply=issue(args.directory,args.session,dict(schema=1,commandID=identifier(str(uuid.uuid4())),action='report',runID=run_id),15)
    else:run_id=args.run_id
    report=None
    if reply.get('report') is not None:
        report=export_report(reply,run_id,args.scenario,args.build_id)
    if args.output:
        private_write(args.output/'reply.json',encode(reply))
        if report is not None:
            private_write(args.output/'report.json',json.dumps(report,indent=2).encode()+b'\n')
            for artifact in report['artifacts']:
                private_write(args.output/artifact['name'],base64.b64decode(artifact['bytes'],validate=True))
    if report is not None:
        print(json.dumps(dict(accepted=reply['accepted'],runID=report['id'],status=report['status'],scenarioID=report['scenarioID'],
            processID=reply['processID'],instanceID=reply['instanceID'],output=str(args.output) if args.output else None,deviceOperations=False),indent=2))
        return {'passed':0,'blocked':3,'cancelled':4,'failed':1,'outcomeUnknown':1}[report['status']]
    print(json.dumps(reply,indent=2))
    return 0 if reply['accepted'] else 2


def redact_launch(value, invitation, encoded):
    """Remove both credential forms from every CoreDevice metadata branch before persistence."""
    if isinstance(value, str):
        return value.replace(encoded, '<invitation redacted>').replace(invitation['token'], '<credential redacted>')
    if isinstance(value, list):
        return [redact_launch(item, invitation, encoded) for item in value]
    if isinstance(value, dict):
        return {key: redact_launch(item, invitation, encoded) for key, item in value.items()}
    return value


def pair_device(args):
    """Bootstrap only the explicitly selected already-installed app through paired Apple development tools."""
    args.output.mkdir(mode=0o700,parents=False,exist_ok=False)
    invitation=rpc(args.directory,dict(operation='invite',label=args.label))
    private_write(args.output/'invitation.json',encode(invitation))
    encoded=base64.b64encode(encode(invitation)).decode()
    raw=args.output/'launch-raw.json'
    result=subprocess.run(['xcrun','devicectl','device','process','launch','--device',args.device,'--terminate-existing','--activate',
        '--json-output',str(raw),BUNDLE,'--','--workbench-pair',encoded],capture_output=True,text=True,timeout=45)
    if result.returncode:
        messages=[]
        def collect(value):
            if isinstance(value,dict):
                for key,item in value.items():
                    if key in ('NSLocalizedDescription','NSLocalizedFailureReason') and isinstance(item,dict) and isinstance(item.get('string'),str):
                        messages.append(redact_launch(item['string'],invitation,encoded)[:1024])
                    else:collect(item)
            elif isinstance(value,list):
                for item in value:collect(item)
        if raw.exists():
            collect(json.loads(raw.read_text()).get('error',{}));raw.unlink()
        private_write(args.output/'launch-failure.json',encode(dict(schema=1,status='launch_failed',sessionID=invitation['sessionID'],messages=messages[:8],automaticRetry=False)))
        reason=messages[-1] if messages else 'check the selected development device connection'
        raise ValueError('selected Workbench launch failed; no retry: '+reason)
    value=redact_launch(json.loads(raw.read_text()),invitation,encoded);launch=value['result']
    private_write(args.output/'launch.json',encode(value));raw.unlink()
    deadline=time.monotonic()+60
    while time.monotonic()<deadline:
        session=next(x for x in rpc(args.directory,dict(operation='sessions')) if x['sessionID']==invitation['sessionID'])
        if session['paired']:
            if session['processID']!=launch['process']['processIdentifier']: raise ValueError('paired app differs from actual launch PID')
            private_write(args.output/'pairing.json',encode(session));print(json.dumps(session,indent=2));return 0
        time.sleep(0.25)
    # Only this app's fixed safe snapshot is collected; never scan another app/container.
    diagnostic=args.output/'controller-diagnostic.json'
    copied=subprocess.run(['xcrun','devicectl','device','copy','from','--device',args.device,'--domain-type','appDataContainer',
        '--domain-identifier',BUNDLE,'--source','Documents/FirmingoWorkbench/controller.json','--destination',str(diagnostic)],
        capture_output=True,text=True,timeout=20)
    if copied.returncode==0:
        value=decode(diagnostic.read_bytes())
        if value.get('processID')==launch['process']['processIdentifier']:
            print(json.dumps(dict(status='pairing_not_observed',diagnostic=value),indent=2))
    raise TimeoutError('pairing not observed; inspect the safe diagnostic and create a fresh invitation explicitly after correcting the cause')


def main():
    parser=argparse.ArgumentParser(description=__doc__);subs=parser.add_subparsers(dest='operation',required=True)
    server=subs.add_parser('serve');server.add_argument('--directory',type=Path,required=True);server.add_argument('--bind',required=True);server.add_argument('--port',type=int,default=0)
    for name in ('sessions','invite','revoke','result','command','pair-device'):
        sub=subs.add_parser(name);sub.add_argument('--directory',type=Path,required=True)
        if name in ('revoke','result','command'):sub.add_argument('--session',required=True)
        if name in ('invite','pair-device'):sub.add_argument('--label',required=True);sub.add_argument('--output',type=Path,required=True)
        if name=='result':sub.add_argument('--command-id',required=True)
        if name=='pair-device':sub.add_argument('--device',required=True)
        if name=='command':
            sub.add_argument('--action',choices=ACTIONS,required=True);sub.add_argument('--run-id');sub.add_argument('--scenario');sub.add_argument('--build-id');sub.add_argument('--command-id')
            sub.add_argument('--timeout',type=float,default=180);sub.add_argument('--output',type=Path);sub.add_argument('--wait',action='store_true')
    args=parser.parse_args()
    if args.operation=='serve':serve(args);return 0
    if args.operation=='command':return send(args)
    if args.operation=='pair-device':return pair_device(args)
    if args.operation=='invite':
        args.output.mkdir(mode=0o700,parents=False,exist_ok=False)
        invitation=rpc(args.directory,dict(operation='invite',label=args.label));private_write(args.output/'invitation.json',encode(invitation))
        private_write(args.output/'invitation.base64',base64.b64encode(encode(invitation)))
        print(json.dumps(dict(sessionID=invitation['sessionID'],invitationFile=str(args.output/'invitation.base64'))));return 0
    body=dict(operation=args.operation)
    if hasattr(args,'session'):body['sessionID']=identifier(args.session)
    if hasattr(args,'command_id'):body['commandID']=identifier(args.command_id)
    print(json.dumps(rpc(args.directory,body),indent=2));return 0


if __name__=='__main__':
    try: raise SystemExit(main())
    except (ValueError,OSError,KeyError,subprocess.SubprocessError) as error: raise SystemExit(str(error)) from error
