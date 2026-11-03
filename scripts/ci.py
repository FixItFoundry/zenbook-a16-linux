#!/usr/bin/env python3
"""Run hardware-free checks; optionally replay each maintained kernel track."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
TRACKS = ('stable', 'rc')
CANDIDATE = 'patches/rc/glymur-usb3'


def verify_candidate(repo, linux_git, track):
    here = (repo / CANDIDATE).resolve()
    names = (here / 'series').read_text().splitlines()
    if not names or len(set(names)) != len(names):
        raise SystemExit('empty series or duplicate patches')
    if any(Path(name).name != name or not name.endswith('.patch') for name in names):
        raise SystemExit('invalid patch name')
    checks = [line.split('  ', 1) for line in (here / 'SHA256SUMS').read_text().splitlines()]
    required = set(names) | {'series', 'tracks.json', 'README.md'}
    if len(checks) != len(required) or {name for _, name in checks} != required:
        raise SystemExit('checksum manifest does not cover the overlay inputs')
    for expected, name in checks:
        path = (here / name).resolve()
        if not path.is_relative_to(here) or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise SystemExit(f'checksum mismatch: {name}')
    meta = json.loads((here / 'tracks.json').read_text())[track]
    for name in meta['config_inputs']:
        path = (repo / name).resolve()
        if not path.is_relative_to(repo) or hashlib.sha256(path.read_bytes()).hexdigest() != meta['config_sha256'][name]:
            raise SystemExit(f'configuration checksum mismatch: {name}')
    kernel = linux_git.resolve()
    subprocess.run([sys.executable, str(repo / meta['base_verifier']), str(kernel)], check=True)
    with tempfile.TemporaryDirectory(prefix='a16-usb-verify-') as directory:
        env = {**os.environ, 'GIT_INDEX_FILE': str(Path(directory) / 'index')}

        def git(*command):
            return subprocess.check_output(
                ['git', '-c', 'core.ignorecase=false', '-C', str(kernel), *command],
                env=env, text=True).strip()

        git('read-tree', meta['prior_source_tree'])
        for name in names:
            git('apply', '--cached', str(here / name))
        actual = git('write-tree')
        if actual != meta['source_tree']:
            raise SystemExit(f'{track} source tree mismatch: {actual}')
        for name in reversed(names):
            git('apply', '--cached', '--reverse', str(here / name))
        if git('write-tree') != meta['prior_source_tree']:
            raise SystemExit('reverse application did not restore the baseline')
    print(f'PASS: {track} USB candidate {actual}; checksums and reverse replay match')

def checks(repo, linux_git=None, track='both'):
    # Run files separately: several suites share the test_package module name.
    for folder in ('iso', 'kernel', 'packaging', 'scripts'):
        for path in sorted((repo / folder).rglob('test_*.py')):
            yield str(path.relative_to(repo)), [sys.executable, '-B', str(path)]
    if linux_git is not None:
        for name in TRACKS:
            if track in ('both', name):
                yield f'{name} source replay', [sys.executable, '-B', str(repo / 'scripts/ci.py'), '--replay-only',
                                               '--track', name, '--linux-git', str(linux_git)]


def run_checks(commands, repo):
    commands = list(commands)
    if not commands:
        print('FAIL: no checks found', flush=True)
        return 1
    failed = []
    for name, command in commands:
        print(f'\n=== {name} ===', flush=True)
        result = subprocess.run(command, cwd=repo,
                                env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
        if result.returncode:
            failed.append(name)
    print('\nFAIL: ' + ', '.join(failed) if failed else '\nPASS: all requested checks', flush=True)
    return int(bool(failed))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--linux-git', type=Path, help='Linux Git object store for source replay')
    parser.add_argument('--track', choices=('both', *TRACKS), default='both')
    parser.add_argument('--replay-only', action='store_true', help='check source/config inputs without fixture tests')
    args = parser.parse_args()
    if args.replay_only:
        if args.linux_git is None:
            parser.error('--replay-only requires --linux-git')
        for track in TRACKS:
            if args.track in ('both', track):
                verify_candidate(REPO, args.linux_git, track)
        return 0
    if sys.platform != 'linux':
        parser.error('run CI on Linux; use ci-vm.sh for a disposable KVM guest')
    missing = [name for name in ('bash', 'git', 'make', 'rpm', 'rpmbuild') if not shutil.which(name)]
    if missing:
        parser.error('missing required tools (do not skip package checks): ' + ', '.join(missing))
    if args.linux_git is None:
        if args.track != 'both':
            parser.error('--track requires --linux-git')
        print('Source replay: NOT RUN (supply --linux-git for both tracks)', flush=True)
    else:
        args.linux_git = args.linux_git.resolve()
    return run_checks(checks(REPO, args.linux_git, args.track), REPO)


if __name__ == '__main__':
    raise SystemExit(main())
