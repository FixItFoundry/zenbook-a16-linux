#!/usr/bin/env python3
"""Replay the camera/microphone overlay without changing a kernel checkout."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

BASE = 'a17d7e30ee161a146706c0752c11a389454a9062'
EXPECTED = '5cc084c973c02c41eaa968599b0e687a93222d46'


def main():
    if len(sys.argv) != 2:
        raise SystemExit(f'usage: {sys.argv[0]} LINUX_GIT')
    kernel = Path(sys.argv[1]).resolve()
    here = Path(__file__).resolve().parent
    names = (here/'series').read_text().splitlines()
    if len(names) != 10 or len(set(names)) != len(names):
        raise SystemExit('expected ten unique patches')
    if any(Path(name).name != name or not name.endswith('.patch') for name in names):
        raise SystemExit('invalid patch name')
    checks = dict(line.split('  ', 1)[::-1] for line in (here/'SHA256SUMS').read_text().splitlines())
    if set(checks) != set(names) | {'camera.config', 'test-channel-map.py', 'replay.py', 'series', 'README.md'}:
        raise SystemExit('checksum manifest does not match overlay inputs')
    for name, expected in checks.items():
        if hashlib.sha256((here/name).read_bytes()).hexdigest() != expected:
            raise SystemExit(f'checksum mismatch: {name}')
    subprocess.run([sys.executable, str(here.parents[3]/'archive/kernel/rc5-20261031/replay.py'), str(kernel)], check=True)
    with tempfile.TemporaryDirectory(prefix='a16-camera-mic-verify-') as directory:
        env = {**os.environ, 'GIT_INDEX_FILE': str(Path(directory)/'index')}

        def git(*args):
            return subprocess.check_output(['git', '-c', 'core.ignorecase=false', '-C', str(kernel), *args], env=env, text=True).strip()

        git('read-tree', BASE)
        checkpoints = {7: '077caad943f5cf151bd711d22cfe5af253ae779f',
                       8: 'f6662c3c78cfd1548bdbf64aed6fcd3cba45ef79', 9: EXPECTED}
        for index, name in enumerate(names):
            git('apply', '--cached', str(here/name))
            if index in checkpoints:
                actual = git('write-tree')
                if actual != checkpoints[index]:
                    raise SystemExit(f'source tree mismatch after {name}: {actual}')
    print(f'PASS: 104 bridge + 10 camera/microphone patches reproduce {EXPECTED}; checksums match')


if __name__ == '__main__':
    main()
