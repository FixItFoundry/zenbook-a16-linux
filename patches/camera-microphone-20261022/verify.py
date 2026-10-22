#!/usr/bin/env python3
"""Replay the camera/microphone overlay without changing a kernel checkout."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

BASE = '65fd4b07749a5d6b48f5b2dbbfc3e78681f04bf1'
EXPECTED = '622916bf1849749a5aa3cdbccf5179de4423ae76'


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
    if set(checks) != set(names) | {'camera.config', 'test-channel-map.py', 'verify.py', 'series', 'README.md'}:
        raise SystemExit('checksum manifest does not match overlay inputs')
    for name, expected in checks.items():
        if hashlib.sha256((here/name).read_bytes()).hexdigest() != expected:
            raise SystemExit(f'checksum mismatch: {name}')
    subprocess.run([sys.executable, str(here.parents[1]/'kernel/rc5-qcom-bridge-20261018/verify.py'), str(kernel)], check=True)
    with tempfile.TemporaryDirectory(prefix='a16-camera-mic-verify-') as directory:
        env = {**os.environ, 'GIT_INDEX_FILE': str(Path(directory)/'index')}

        def git(*args):
            return subprocess.check_output(['git', '-c', 'core.ignorecase=false', '-C', str(kernel), *args], env=env, text=True).strip()

        git('read-tree', BASE)
        checkpoints = {7: '27e7dd0621d1f752bf778a67d8787a98e1c43444',
                       8: 'ffe6f4155024d97ef2607af7d165d1d0386514ad', 9: EXPECTED}
        for index, name in enumerate(names):
            git('apply', '--cached', str(here/name))
            if index in checkpoints:
                actual = git('write-tree')
                if actual != checkpoints[index]:
                    raise SystemExit(f'source tree mismatch after {name}: {actual}')
    print(f'PASS: 104 bridge + 10 camera/microphone patches reproduce {EXPECTED}; checksums match')


if __name__ == '__main__':
    main()
