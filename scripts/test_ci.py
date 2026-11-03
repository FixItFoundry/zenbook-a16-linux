"""Keep CI failures visible and track replays independent."""
import contextlib
import io
import json
import shutil
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import ci


class CIChecks(unittest.TestCase):
    def test_discovers_suites_but_never_hardware_scripts(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            for name in ('scripts/test_safe.py', 'scripts/test62-run.sh', 'packaging/foo/test_package.py',
                         'kernel/bar/test_package.py', 'internal/test_private.py'):
                path = repo / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            names = [name for name, _ in ci.checks(repo)]
            self.assertEqual(names, ['kernel/bar/test_package.py', 'packaging/foo/test_package.py',
                                     'scripts/test_safe.py'])

    def test_each_track_replays_its_own_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            linux = repo / 'linux.git'
            both = list(ci.checks(repo, linux))
            self.assertEqual([name for name, _ in both], ['stable source replay', 'rc source replay'])
            self.assertNotEqual(both[0][1], both[1][1])
            for track in ('stable', 'rc'):
                selected = list(ci.checks(repo, linux, track))
                self.assertEqual(selected, [item for item in both if item[0].startswith(track)])
                self.assertEqual(selected[0][1][-1], str(linux))
                self.assertEqual(selected[0][1][selected[0][1].index('--track') + 1], track)

    def test_failure_does_not_hide_later_results_or_return_success(self):
        with patch.object(ci.subprocess, 'run', side_effect=[Mock(returncode=7), Mock(returncode=0)]) as run:
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = ci.run_checks([('first', ['false']), ('second', ['true'])], Path('/tmp'))
            self.assertEqual(code, 1)
            self.assertEqual(run.call_count, 2)
            self.assertIn('FAIL: first', output.getvalue())

    def test_empty_run_fails(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(ci.run_checks([], Path('/tmp')), 1)

    def test_missing_rpm_tools_cannot_be_a_passing_skipped_test(self):
        with patch.object(ci.sys, 'argv', ['ci.py']), patch.object(ci.sys, 'platform', 'linux'), \
             patch.object(ci.shutil, 'which', side_effect=lambda name: None if name == 'rpmbuild' else name), \
             patch.object(ci, 'run_checks') as run, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                ci.main()
            self.assertEqual(error.exception.code, 2)
            run.assert_not_called()



    def test_overlay_rejects_tampered_or_incomplete_inputs_before_git(self):
        real_repo = Path(__file__).resolve().parents[1]
        for case in ('patch', 'checksum', 'duplicate', 'escape', 'config'):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory)
                here = repo / ci.CANDIDATE
                shutil.copytree(real_repo / ci.CANDIDATE, here)
                series = here / 'series'
                if case == 'patch':
                    target = here / series.read_text().splitlines()[0]
                    target.write_bytes(target.read_bytes() + b'tampered\n')
                elif case == 'checksum':
                    target = here / 'SHA256SUMS'
                    target.write_text('\n'.join(target.read_text().splitlines()[1:]) + '\n')
                elif case == 'duplicate':
                    series.write_text(series.read_text() * 2)
                elif case == 'escape':
                    series.write_text('../outside.patch\n')
                else:
                    meta = json.loads((here / 'tracks.json').read_text())['stable']
                    for name in meta['config_inputs']:
                        target = repo / name
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_text('tampered configuration\n')
                with patch.object(ci.subprocess, 'run') as baseline:
                    with self.assertRaises(SystemExit):
                        ci.verify_candidate(repo, repo / 'unused.git', 'stable')
                    baseline.assert_not_called()


if __name__ == '__main__':
    unittest.main()
