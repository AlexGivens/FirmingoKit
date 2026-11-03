"""Deterministic controller/state fixtures. No listener, network, app or device is opened by these tests."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
import uuid

spec=importlib.util.spec_from_file_location('paired',Path(__file__).with_name('paired.py'))
paired=importlib.util.module_from_spec(spec);spec.loader.exec_module(paired)


class PairedController(unittest.TestCase):
    def setUp(self):
        self.now=0
        self.broker=paired.Broker('https://127.0.0.1:8443/','a'*64,clock=lambda:self.now)
        self.invite=self.broker.invite('Fixture')
        self.instance=paired.identifier(str(uuid.uuid4()))
        self.identity=dict(schema=1,instanceID=self.instance,appIdentifier=paired.BUNDLE,appVersion='5',processID=123)
        self.session=self.broker.pair(self.invite['token'],self.identity)

    def command(self,action='list'):
        return dict(schema=1,commandID=paired.identifier(str(uuid.uuid4())),action=action)

    def exchange(self,ack=0,reply=None):
        return self.broker.exchange(self.session['token'],dict(schema=1,sessionID=self.session['sessionID'],
            instanceID=self.instance,ack=ack,reply=reply),wait=0)

    def reply(self,command):
        return dict(schema=1,command=command,instanceID=self.instance,processID=123,appIdentifier=paired.BUNDLE,appVersion='5',accepted=True,
                    state=dict(isRunning=False,awaitingLifecycleStart=False))

    def test_bootstrap_is_consumed_rotated_and_bounded(self):
        self.assertNotEqual(self.session['token'],self.invite['token'])
        with self.assertRaises(ValueError):self.broker.pair(self.invite['token'],self.identity)
        invite=self.broker.invite('Expired');self.now=121
        with self.assertRaises(ValueError):self.broker.pair(invite['token'],self.identity)
        with self.assertRaises(ValueError):self.broker.invite('x'*65)

    def test_lost_delivery_and_lost_ack_never_allocate_a_second_execution(self):
        one=self.command();self.broker.command(self.session['sessionID'],one)
        first=self.exchange();self.assertEqual(first,self.exchange())
        two=self.command();self.broker.command(self.session['sessionID'],two)
        reply=self.reply(one)
        delivered=self.exchange(1,reply)
        self.assertEqual(delivered['sequence'],2)
        reordered=json.loads(json.dumps(reply,sort_keys=True))
        self.assertEqual(delivered,self.exchange(1,reordered))
        self.assertEqual(self.broker.result(self.session['sessionID'],one['commandID'])['state'],'completed')
        self.assertEqual(self.broker.command(self.session['sessionID'],one)['sequence'],1)
        self.exchange(2,self.reply(two))
        with self.assertRaises(ValueError):self.exchange(1,reply)

    def test_replayed_reply_cannot_change_pid_command_instance_or_payload(self):
        one=self.command();self.broker.command(self.session['sessionID'],one);self.exchange()
        for field,value in [('processID',124),('instanceID',paired.identifier(str(uuid.uuid4()))),('command',self.command())]:
            reply=self.reply(one);reply[field]=value
            with self.assertRaises(ValueError):self.exchange(1,reply)
        reply=self.reply(one);self.exchange(1,reply)
        changed=copy.deepcopy(reply);changed['accepted']=False
        with self.assertRaises(ValueError):self.exchange(1,changed)

    def test_revoke_and_expiry_refuse_commands_and_acknowledgements(self):
        self.broker.control(dict(operation='revoke',sessionID=self.session['sessionID']))
        with self.assertRaises(ValueError):self.exchange()
        with self.assertRaises(ValueError):self.broker.command(self.session['sessionID'],self.command())

    def test_unknown_device_write_command_and_nested_runtime_override_reject(self):
        for action in ('commit','shell','scene','device.upload','reset'):
            with self.assertRaises(ValueError):self.broker.command(self.session['sessionID'],self.command(action))
        command=self.command('run');command['request']=dict(schema=1,requestID=paired.identifier(str(uuid.uuid4())),operation='run',
            scenarioID='compiler.smoke',serviceURL='https://example.invalid')
        with self.assertRaises(ValueError):self.broker.command(self.session['sessionID'],command)

    def test_session_command_queue_and_json_bounds(self):
        for _ in range(4):self.broker.command(self.session['sessionID'],self.command())
        with self.assertRaises(ValueError):self.broker.command(self.session['sessionID'],self.command())
        for raw in (b'{"schema":1,"schema":2}',b'{"x":NaN}',b'x'*(paired.LIMIT+1)):
            with self.assertRaises(ValueError):paired.decode(raw)
        with self.assertRaises(ValueError):paired.private_address('0.0.0.0')
        with self.assertRaises(ValueError):paired.private_address('8.8.8.8')
        self.assertEqual(paired.private_address('192.168.1.2'),'192.168.1.2')

    def test_command_uuid_reuse_requires_identical_body(self):
        command=self.command();self.broker.command(self.session['sessionID'],command)
        changed=copy.deepcopy(command);changed['action']='run';changed['request']=dict(schema=1,requestID=paired.identifier(str(uuid.uuid4())),operation='run',scenarioID='compiler.resources')
        with self.assertRaises(ValueError):self.broker.command(self.session['sessionID'],changed)

    def test_no_session_or_command_is_restored_after_restart(self):
        other=paired.Broker('https://127.0.0.1:8443/','a'*64)
        with self.assertRaises(ValueError):other.command(self.session['sessionID'],self.command())
        self.now=1801
        with self.assertRaises(ValueError):self.exchange()


if __name__=='__main__':unittest.main()
