"""Compile the test-only relay or explicitly exercise it against a finite local fake peer; never contact hardware."""
import argparse
import base64
import concurrent.futures
import json
from pathlib import Path
import socket
import struct
import subprocess
import time
import uuid


def frame(kind, request, body):
    """Independent big-endian wire vectors, not the production Swift framer."""
    return struct.pack('!4sBBBBII', b'FMGO', 1, kind, 0, 0, request, len(body)) + body


def exact(connection, length):
    """Bound every fixture socket read and reject unexpected EOF."""
    data = b''
    while len(data) < length:
        part = connection.recv(length - len(data))
        if not part: raise ValueError('Unexpected local fixture EOF')
        data += part
    return data


def packet(connection):
    """Collect one fixture frame without assuming TCP read boundaries."""
    header = exact(connection, 16)
    size = struct.unpack_from('!I', header, 12)[0]
    if size > 4096: raise ValueError('Excessive local fixture frame')
    return header + exact(connection, size)


def loopback(executable, directory):
    """Exercise actual relay sockets with fragmented/coalesced/binary vectors and one withheld real fixture reply."""
    hello = frame(1, 1, b'{"op":"hello"}')
    response = frame(2, 1, b'{"ok":true}')
    binary = frame(3, 0, bytes(range(256)))
    chunk = frame(4, 2, struct.pack('!II', 1, 0) + bytes(range(256)))
    acknowledged = frame(2, 2, b'{"ok":true}')
    commit = frame(1, 101, b'{"op":"flash.commit","target_id":2,"upload_id":1}')
    body = json.dumps({'ok': True, 'result': {'upload_id': 1, 'state': 'committing', 'size': 548,
        'received': 548, 'sha256': '0' * 64, 'slot_touched': False, 'error': 'none'}}, separators=(',', ':')).encode()
    queued = frame(2, 101, body)
    with socket.socket() as server:
        server.bind(('127.0.0.1', 0)); server.listen(1); server.settimeout(5)
        def peer():
            with server.accept()[0] as connection:
                connection.settimeout(5)
                assert packet(connection) == hello
                connection.sendall(response + binary)
                assert packet(connection) == chunk
                connection.sendall(acknowledged)
                assert packet(connection) == commit
                for byte in queued: connection.sendall(bytes([byte]))
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(peer)
            with (directory / 'stdout.log').open('xb') as stdout, (directory / 'stderr.log').open('xb') as stderr:
                process = subprocess.Popen([str(executable), '--loopback-upstream-port', str(server.getsockname()[1]), str(directory)], stdout=stdout, stderr=stderr)
                try:
                    deadline = time.monotonic() + 5
                    while not (directory / 'port.txt').exists():
                        if process.poll() is not None or time.monotonic() >= deadline: raise ValueError('Local relay startup failed')
                        time.sleep(0.01)
                    port = int((directory / 'port.txt').read_text())
                    with socket.create_connection(('127.0.0.1', port), timeout=5) as client:
                        for byte in hello: client.sendall(bytes([byte]))
                        assert packet(client) == response and packet(client) == binary
                        for start in range(0, len(chunk), 7): client.sendall(chunk[start:start + 7])
                        assert packet(client) == acknowledged
                        client.sendall(commit)
                        assert client.recv(1) == b'', 'Withheld reply leaked to downstream client'
                    future.result(timeout=5)
                    if process.wait(timeout=5) != 0: raise ValueError('Local relay executable failed')
                finally:
                    if process.poll() is None: process.kill(); process.wait(timeout=5)
    evidence = json.loads((directory / 'evidence.json').read_bytes())
    assert evidence['commitRequestsObserved'] == '1' and evidence['failure'] == ''
    assert base64.b64decode(evidence['withheldResponse'], validate=True) == queued
    print('Actual loopback proxy passed fragmented/coalesced/binary transparency and one withheld reply; no SDK/device qualification follows.')


def main():
    """Default source checks never open a socket; actual local sockets require the explicit loopback flag."""
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--compile-only', action='store_true')
    mode.add_argument('--loopback', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = root / '.build/nano-proxy-checks'; output.mkdir(parents=True, exist_ok=True)
    executable = output / 'CheckNanoProxyLoopback'
    sources = [root / 'Validation/NanoHost' / name for name in ['NanoGate.swift', 'NanoRecoveryIntent.swift', 'NanoReplyLossGate.swift', 'NanoCommitProxy.swift']]
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '6', '-warnings-as-errors',
                    '-enable-upcoming-feature', 'ApproachableConcurrency', '-module-cache-path', str(output / 'cache'),
                    *map(str, sources), str(root / 'Tools/Hardware/CheckNanoProxyLoopback.swift'), '-o', str(executable)], check=True, timeout=90)
    if args.loopback:
        directory = output / ('run-' + str(uuid.uuid4())); directory.mkdir()
        loopback(executable, directory)
    else: print('Recovery relay check compiled; no socket or device operation.')


if __name__ == '__main__': main()
