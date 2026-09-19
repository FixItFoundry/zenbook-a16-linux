#!/usr/bin/env python3
"""Replay the shipped series in a temporary Git index; never alter a checkout."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) != 2:
        raise SystemExit('usage: verify.py PATH_TO_LINUX_GIT_REPOSITORY')
    kernel = Path(sys.argv[1]).resolve()
    here = Path(__file__).resolve().parent
    repo = here.parent.parent
    series = repo / 'patches/rc3-20260919'
    meta = json.loads((here / 'build.json').read_text())
    names = (series / 'series').read_text().splitlines()
    if len(names) != meta['patch_count'] or len(set(names)) != len(names):
        raise SystemExit('invalid series length or duplicate patches')
    for name in names:
        if Path(name).name != name or not name.endswith('.patch'):
            raise SystemExit('invalid patch name')
    for line in (here / 'SHA256SUMS').read_text().splitlines():
        digest, name = line.split('  ', 1)
        path = (repo / name).resolve()
        if not path.is_relative_to(repo) or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit(f'checksum mismatch: {name}')
    with tempfile.TemporaryDirectory(prefix='a16-rc3-verify-') as directory:
        env = {**os.environ, 'GIT_INDEX_FILE': str(Path(directory) / 'index')}
        def git(*args):
            return subprocess.check_output(['git', '-C', str(kernel), *args], env=env, text=True).strip()
        git('read-tree', meta['base'])
        for name in names:
            git('apply', '--cached', str(series / name))
        actual = git('write-tree')
        if actual != meta['source_tree']:
            raise SystemExit(f'tree mismatch: {actual}')
    print(f'PASS: {len(names)} patches reproduce source tree {actual}; checksums match')


if __name__ == '__main__':
    main()
