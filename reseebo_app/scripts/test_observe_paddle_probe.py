import unittest
import argparse
from pathlib import Path
import tempfile
import signal
import json
from unittest.mock import Mock, patch

from scripts.observe_paddle_probe import main, stop_owned_child, publish_fixture, VERIFICATION_ID, collect_probe_record


class ObserverCleanupTest(unittest.TestCase):
    def test_early_logs_merge_unique_runs_without_duplicate_pulls(self):
        with tempfile.TemporaryDirectory() as directory:
            output, records, read = Path(directory), [], Mock(return_value=b'overlay')
            def line(run):
                return 'I/flutter: ' + json.dumps({'probe': 'ppocr_v5_mobile',
                    'run': run, 'overlayPath': f'/cache/{run}.png'})
            collect_probe_record(line(2), records, read, output)
            for run in range(3):
                collect_probe_record(line(run), records, read, output)
            self.assertEqual({0, 1, 2}, {r['run'] for r in records})
            self.assertEqual(3, len(records))
            self.assertEqual(3, read.call_count)
            self.assertEqual(3, len(list(output.glob('*-overlay.png'))))

    def test_fixture_is_published_only_after_copy_completes(self):
        adb = Mock(return_value=Mock(stdout=b'complete-photo'))
        directory = f'/data/user/0/{VERIFICATION_ID}/cache'
        publish_fixture(adb, directory, 'dali', b'complete-photo')
        target = f'{directory}/paddle-truth-dali.jpg'
        self.assertEqual(adb.call_args_list[0].args,
            ('shell', '-T', 'run-as', VERIFICATION_ID, 'dd', f'of={target}.incoming'))
        self.assertEqual(adb.call_args_list[0].kwargs, {'data': b'complete-photo'})
        self.assertEqual(adb.call_args_list[2].args,
            ('shell', 'run-as', VERIFICATION_ID, 'mv', f'{target}.incoming', target))

    def test_truncated_fixture_is_never_published(self):
        adb = Mock(return_value=Mock(stdout=b'truncated'))
        with self.assertRaisesRegex(ValueError, 'copy hash mismatch'):
            publish_fixture(adb, '/verification/cache', 'dali', b'complete-photo')
        self.assertFalse(any('mv' in call.args for call in adb.call_args_list))

    def test_corrupt_evidence_stops_owned_tree_before_observer_exits(self):
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(apk=Path(directory)/'verified.apk', sha256='a'*64,
                output=Path(directory)/'evidence', receipt_samples=None,
                device='phone', adb='adb', aapt2='aapt2', flutter='flutter')
            process = Mock(pid=321, stdout=['{"probe": broken}\n'])
            process.poll.return_value = None
            with patch('argparse.ArgumentParser.parse_args', return_value=args), \
                 patch('scripts.observe_paddle_probe.validate_apk'), \
                 patch('threading.Thread'), \
                 patch('subprocess.Popen', return_value=process), \
                 patch('scripts.observe_paddle_probe.sys.platform', 'win32'), \
                 patch('subprocess.run') as run:
                with self.assertRaises(ValueError):
                    main()
            run.assert_called_once_with(['taskkill', '/PID', '321', '/T', '/F'],
                capture_output=True, timeout=30, check=False)
            process.wait.assert_called_once_with(timeout=30)

    def test_running_probe_tree_is_stopped_by_its_exact_child_pid(self):
        process = Mock(pid=321)
        process.poll.return_value = None
        with patch('subprocess.run') as run, \
             patch('scripts.observe_paddle_probe.sys.platform', 'win32'):
            stop_owned_child(process)
        run.assert_called_once_with(['taskkill', '/PID', '321', '/T', '/F'],
            capture_output=True, timeout=30, check=False)
        process.wait.assert_called_once_with(timeout=30)

    def test_linux_stops_only_the_owned_process_group(self):
        process = Mock(pid=321)
        process.poll.return_value = None
        with patch('scripts.observe_paddle_probe.sys.platform', 'linux'), \
             patch('scripts.observe_paddle_probe.os.killpg') as kill:
            stop_owned_child(process)
        kill.assert_called_once_with(321, signal.SIGTERM)
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
