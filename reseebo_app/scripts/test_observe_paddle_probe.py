import unittest
import argparse
from pathlib import Path
import tempfile
from unittest.mock import Mock, patch

from scripts.observe_paddle_probe import main, stop_owned_child


class ObserverCleanupTest(unittest.TestCase):
    def test_corrupt_evidence_stops_owned_tree_before_observer_exits(self):
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(apk=Path(directory)/'verified.apk', sha256='a'*64,
                output=Path(directory)/'evidence', receipt_samples=None,
                device='phone', adb='adb', aapt2='aapt2')
            process = Mock(pid=321, stdout=['{"probe": broken}\n'])
            process.poll.return_value = None
            with patch('argparse.ArgumentParser.parse_args', return_value=args), \
                 patch('scripts.observe_paddle_probe.validate_apk'), \
                 patch('threading.Thread'), \
                 patch('subprocess.Popen', return_value=process), \
                 patch('subprocess.run') as run:
                with self.assertRaises(ValueError):
                    main()
            run.assert_called_once_with(['taskkill', '/PID', '321', '/T', '/F'],
                capture_output=True, timeout=30, check=False)
            process.wait.assert_called_once_with(timeout=30)

    def test_running_probe_tree_is_stopped_by_its_exact_child_pid(self):
        process = Mock(pid=321)
        process.poll.return_value = None
        with patch('subprocess.run') as run:
            stop_owned_child(process)
        run.assert_called_once_with(['taskkill', '/PID', '321', '/T', '/F'],
            capture_output=True, timeout=30, check=False)
        process.wait.assert_called_once_with(timeout=30)

    def test_completed_child_does_not_kill_any_process(self):
        process = Mock(pid=321)
        process.poll.return_value = 0
        with patch('subprocess.run') as run:
            stop_owned_child(process)
        run.assert_not_called()
        process.wait.assert_not_called()


if __name__ == '__main__':
    unittest.main()
