#!/usr/bin/env python3
"""Replay the mainline release + qcom-next/qcom-topics bridge series in a temporary Git index."""
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
    if subprocess.run(
        ['git', '-C', str(kernel), 'rev-parse', '--git-dir'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode:
        raise SystemExit(f'not a Git repository: {kernel}')
    here = Path(__file__).resolve().parent
    repo = here.parent.parent
    base_series = repo / 'patches/rc5-20261013'
    bridge_series = repo / 'patches/qcom-glymur-bridge-20261018'
    meta = json.loads((here / 'build.json').read_text())
    if subprocess.run(
        ['git', '-C', str(kernel), 'cat-file', '-e', f'{meta["base"]}^{{commit}}'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode:
        raise SystemExit(
            f'base commit {meta["base"]} is missing from {kernel}; '
            'fetch the recorded Linux history first'
        )
    base_names = (base_series / 'series').read_text().splitlines()
    bridge_names = (bridge_series / 'series').read_text().splitlines()
    if (len(base_names) != meta['base_patch_count']
            or len(bridge_names) != meta['bridge_patch_count']
            or len(base_names) + len(bridge_names) != meta['patch_count']
            or len(set(base_names)) != len(base_names)
            or len(set(bridge_names)) != len(bridge_names)):
        raise SystemExit('invalid series length or duplicate patches')
    for name in [*base_names, *bridge_names]:
        if Path(name).name != name or not name.endswith('.patch'):
            raise SystemExit('invalid patch name')
    for line in (here / 'SHA256SUMS').read_text().splitlines():
        digest, name = line.split('  ', 1)
        path = (repo / name).resolve()
        if not path.is_relative_to(repo) or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit(f'checksum mismatch: {name}')
    with tempfile.TemporaryDirectory(prefix='a16-qcom-bridge-verify-') as directory:
        env = {**os.environ, 'GIT_INDEX_FILE': str(Path(directory) / 'index')}
        def git(*args):
            result = subprocess.run(
                ['git', '-C', str(kernel), *args],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            if result.returncode:
                detail = result.stderr.strip() or result.stdout.strip()
                raise SystemExit(f'git {args[0]} failed: {detail}')
            return result.stdout.strip()
        git('read-tree', meta['base'])
        for name in base_names:
            git('apply', '--cached', str(base_series / name))
        prior = git('write-tree')
        if prior != meta['prior_source_tree']:
            raise SystemExit(f'prior tree mismatch: {prior}')
        for name in bridge_names:
            git('apply', '--cached', str(bridge_series / name))
        actual = git('write-tree')
        if actual != meta['source_tree']:
            raise SystemExit(f'tree mismatch: {actual}')
    print(f'PASS: {meta["patch_count"]} patches ({len(base_names)} base + {len(bridge_names)} qcom-next/qcom-topics bridge) reproduce source tree {actual}; checksums match')


if __name__ == '__main__':
    main()
