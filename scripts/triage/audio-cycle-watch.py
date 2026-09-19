#!/usr/bin/env python3
"""Bounded, passive audio-event capture. No playback, routing or register I/O."""
import datetime
import glob
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time

os.umask(0o077)
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=False)
duration = 1800
limit = 32 * 1024 * 1024
stop = False


def stopping(*_):
    global stop
    stop = True


signal.signal(signal.SIGTERM, stopping)
signal.signal(signal.SIGINT, stopping)
start = time.monotonic()
meta = {'started': datetime.datetime.now().astimezone().isoformat(),
        'monotonic_start': start, 'duration_seconds': duration,
        'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
        'kernel': os.uname().release, 'mode': 'passive; no audio samples recorded'}
(out / 'metadata.json').write_text(json.dumps(meta, indent=2) + '\n')
commands = {
    'kernel': ['journalctl', '-k', '-b', '-n', '0', '-f', '-o', 'json', '--no-pager'],
    'audio-services': ['journalctl', '--user', '-b', '-n', '0', '-f', '-o', 'json',
                       '-u', 'pipewire', '-u', 'pipewire-pulse', '-u', 'wireplumber', '--no-pager'],
    'pipewire-events': ['stdbuf', '-oL', 'pw-mon', '--no-colors', '--hide-params'],
}
selector = selectors.DefaultSelector()
children, logs, sizes = {}, {}, {}
reason = 'duration expired'
next_sample = 0
try:
    for name, command in commands.items():
        child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        children[name] = child
        os.set_blocking(child.stdout.fileno(), False)
        selector.register(child.stdout, selectors.EVENT_READ, name)
        logs[name] = (out / (name + '.jsonl')).open('w', buffering=1)
        sizes[name] = 0
    with (out / 'slave-state.jsonl').open('w', buffering=1) as snapshots:
        while not stop and time.monotonic() - start < duration:
            for key, _ in selector.select(timeout=1):
                name = key.data
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    reason = name + ' stream exited'
                    stop = True
                    break
                record = json.dumps({'monotonic': time.monotonic(),
                                     'wall': time.time(),
                                     'data': chunk.decode(errors='replace')}) + '\n'
                sizes[name] += len(record.encode())
                if sizes[name] > limit:
                    reason = name + ' size limit reached'
                    stop = True
                    break
                logs[name].write(record)
            now = time.monotonic()
            if now >= next_sample:
                states = {}
                for filename in glob.glob('/sys/bus/soundwire/devices/*/status'):
                    try:
                        states[filename] = Path(filename).read_text().strip()
                    except OSError as error:
                        states[filename] = str(error)
                snapshots.write(json.dumps({'monotonic': now, 'wall': time.time(),
                                             'slaves': states}) + '\n')
                next_sample = now + 2
    if stop and reason == 'duration expired':
        reason = 'signal received'
except BaseException as error:
    reason = f'{type(error).__name__}: {error}'
    raise
finally:
    for child in children.values():
        try:
            child.terminate()
        except ProcessLookupError:
            pass
    for child in children.values():
        try:
            child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
        if child.stdout is not None:
            child.stdout.close()
    selector.close()
    for log in logs.values():
        log.close()
    (out / 'finished.json').write_text(json.dumps({'wall': time.time(),
        'monotonic': time.monotonic(), 'reason': reason, 'bytes': sizes}) + '\n')
