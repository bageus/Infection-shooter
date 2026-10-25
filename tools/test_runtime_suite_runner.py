#!/usr/bin/env python3
"""Exercise actual shell runner isolation, heavy-load serialization and failure reporting."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

RUNNER = Path(__file__).resolve().with_name('run_runtime_suites.sh')
FAKE_GODOT = '''#!/usr/bin/env python3
import os, sys, time
from pathlib import Path
name = Path(sys.argv[-1]).stem
print('user-data=' + os.environ['XDG_DATA_HOME'], flush=True)
if name == 'run_error_tests':
    print('SCRIPT ERROR: intentional runner probe', flush=True)
if name == 'run_exit_tests':
    sys.exit(3)
if name == 'run_timeout_tests':
    sys.exit(124)
if name in ['run_menu_tests', 'run_startup_resource_memory_tests']:
    active = Path(os.environ['PROBE_ROOT']) / 'heavy-active'
    try:
        fd = os.open(active, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        print('ERROR: authored maps overlapped', flush=True)
        sys.exit(2)
    os.close(fd)
    time.sleep(.2)
    active.unlink()
'''


class RunnerTests(unittest.TestCase):
    def run_suites(self, names):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        binary = root / 'godot'
        binary.write_text(FAKE_GODOT)
        binary.chmod(0o755)
        suites = root / 'suites.txt'
        suites.write_text(''.join('game/tests/' + name + '.gd\n' for name in names))
        env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'], PROBE_ROOT=str(root))
        work = root / 'work'
        result = subprocess.run(['bash', str(RUNNER), str(suites), str(work), '3'],
                                env=env, text=True, capture_output=True, timeout=10)
        return result, work

    def test_full_maps_are_serialized_and_data_is_isolated(self):
        names = ['run_menu_tests', 'run_startup_resource_memory_tests', 'run_fast_tests']
        result, work = self.run_suites(names)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('All 3 suites passed', result.stdout)
        for name in names:
            self.assertIn('user-data=' + str(work / 'data' / name), (work / (name + '.log')).read_text())
        self.assertEqual(len((work / 'timings.txt').read_text().splitlines()), 3)

    def test_script_errors_and_process_failures_are_not_hidden(self):
        result, work = self.run_suites(['run_error_tests', 'run_exit_tests'])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len((work / 'failed.txt').read_text().splitlines()), 2)
        self.assertIn('exited 3', result.stdout)
        self.assertIn('SCRIPT ERROR', result.stdout)

    def test_timeout_exit_is_a_failure(self):
        result, work = self.run_suites(['run_timeout_tests'])
        self.assertEqual(result.returncode, 1)
        self.assertIn('exited 124', result.stdout)
        self.assertTrue((work / 'failed.txt').exists())


if __name__ == '__main__':
    unittest.main()
