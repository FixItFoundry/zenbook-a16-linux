"""Hardware-free regression tests: python3 -m unittest discover -s scripts/triage."""
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent


class CaptureCleanup(unittest.TestCase):
    def run_failure(self, fail_open=False):
        children = []
        real_popen = subprocess.Popen
        real_open = Path.open

        def spawn(*args, **kwargs):
            if children and not fail_open:
                raise FileNotFoundError('injected second spawn failure')
            child = real_popen([sys.executable, '-c', 'import time; time.sleep(60)'],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            children.append(child)
            return child

        def open_log(path, *args, **kwargs):
            if path.name == 'audio-services.jsonl' and fail_open:
                raise OSError('injected log open failure')
            return real_open(path, *args, **kwargs)

        previous_mask = os.umask(0o077)
        import signal
        handlers = {s: signal.getsignal(s) for s in (signal.SIGTERM, signal.SIGINT)}
        try:
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / 'capture'
                with patch.object(sys, 'argv', ['capture', str(output)]), \
                     patch('subprocess.Popen', side_effect=spawn), \
                     patch.object(Path, 'open', open_log):
                    with self.assertRaises(OSError):
                        runpy.run_path(str(HERE / 'audio-cycle-watch.py'), run_name='__main__')
                self.assertTrue(children)
                self.assertTrue(all(child.poll() is not None for child in children))
                self.assertTrue(all(child.stdout.closed for child in children))
                self.assertIn('injected', json.loads((output / 'finished.json').read_text())['reason'])
        finally:
            os.umask(previous_mask)
            for sig, handler in handlers.items():
                signal.signal(sig, handler)
            for child in children:
                if child.poll() is None:
                    child.kill()
                    child.wait()
                child.stdout.close()

    def test_second_spawn_failure(self):
        self.run_failure()

    def test_log_open_failure(self):
        self.run_failure(fail_open=True)


class Storage(unittest.TestCase):
    def shell(self, command, *args):
        return subprocess.run(['bash', '-c', 'source "$1"; ' + command, 'test',
                               str(HERE / 'capture-storage.sh'), *map(str, args)],
                              capture_output=True, text=True)

    def test_rotation_bounds_and_order(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'counters.log'
            for i in range(5):
                path.write_text(str(i) * 10)
                self.assertEqual(self.shell('rotate_counters "$2" 10', path).returncode, 0)
            self.assertEqual(Path(str(path) + '.1').read_text(), '4' * 10)
            self.assertEqual(Path(str(path) + '.3').read_text(), '2' * 10)
            self.assertEqual(len(list(Path(directory).iterdir())), 3)

    def test_small_log_and_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'counters.log'
            path.write_text('small')
            self.assertEqual(self.shell('rotate_counters "$2" 10', path).returncode, 0)
            self.assertTrue(path.exists())
            self.assertNotEqual(self.shell('capture_budget_available "$2" 0', directory).returncode, 0)
            self.assertEqual(self.shell('capture_budget_available "$2" 1024', directory).returncode, 0)

    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'counters.log'
            path.write_text('1234567890')
            Path(str(path) + '.1').symlink_to(path)
            self.assertNotEqual(self.shell('rotate_counters "$2" 10', path).returncode, 0)
            self.assertEqual(path.read_text(), '1234567890')


class MixerGate(unittest.TestCase):
    def check(self, state):
        source = (HERE / 'check-boot-housekeeping.sh').read_text()
        function = source[source.index('mixer_ran() {'):source.index("check 'mixer ran")]
        return subprocess.run(['bash', '-c', 'systemctl() { printf "%s\\n" "$MOCK_STATE"; };\n'
                               + function + '\nmixer_ran'],
                              env={**os.environ, 'MOCK_STATE': state}, capture_output=True).returncode

    def test_only_executed_success_passes(self):
        state = 'Result=success\nActiveState=active\nSubState=exited\nExecMainStatus=0\nExecMainStartTimestampMonotonic=123'
        self.assertEqual(self.check(state), 0)
        for old, new in [('=123', '=0'), ('=active', '=inactive'),
                         ('=success', '=exit-code'), ('ExecMainStatus=0', 'ExecMainStatus=1')]:
            with self.subTest(new=new):
                self.assertNotEqual(self.check(state.replace(old, new)), 0)


if __name__ == '__main__':
    unittest.main()
