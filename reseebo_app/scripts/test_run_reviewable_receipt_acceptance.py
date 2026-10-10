import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from scripts import run_reviewable_receipt_acceptance as helper
from scripts.run_paddle_probe import validate_apk


class AcceptanceGuardTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        previous_root = helper.ROOT
        helper.ROOT = self.root
        self.addCleanup(setattr, helper, 'ROOT', previous_root)
        self.apk = self.root / 'input.apk'
        self.apk.write_bytes(b'controlled-verification-apk')
        self.digest = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        self.args = SimpleNamespace(apk=self.apk, sha256=self.digest, aapt2='aapt2',
            adb='adb', flutter='flutter', device='R5GL41586RA', run=True,
            phase='review', fresh_install=False, output=self.root / 'results')
        self.commands, self.drives = [], []
        self.prior = {'nextPhase': 'review', 'pid': 123, 'processToken': 'old-process'}
        self.after = {'phase': 'review', 'nextPhase': 'verify', 'pid': 456,
                      'processToken': 'new-process', 'deferredEngines': []}
        self.current_marker = self.prior
        self.installed_bytes = self.apk.read_bytes()

    def validator(self, path, digest, aapt2):
        validate_apk(path, digest, aapt2, package_reader=lambda *args: helper.VERIFICATION_ID)

    def command(self, command, **kwargs):
        self.commands.append(command)
        args = command[3:]
        stdout = b''
        if args[:3] == ['shell', 'pm', 'path']:
            stdout = b'package:/data/app/owned-verification/base.apk\n'
        elif args[0] == 'pull':
            Path(args[2]).write_bytes(self.installed_bytes)
        elif args[:2] == ['exec-out', 'run-as']:
            stdout = json.dumps(self.current_marker).encode()
        elif args[:2] == ['shell', 'pidof']:
            stdout = b'456\n'
        elif args[0] == 'logcat':
            stdout = b'Dart VM service is listening on http://127.0.0.1:4321/nonce=/\n'
        elif args[:2] == ['forward', 'tcp:0']:
            stdout = b'5432\n'
        return subprocess.CompletedProcess(command, 0, stdout, b'')

    def drive(self, command, output):
        self.drives.append(command)
        self.current_marker = self.after
        return 0

    def runner(self, validate=None):
        return helper.AcceptanceRunner(self.args, command=self.command,
            drive=self.drive, validate=validate or self.validator)

    def test_ordinary_id_is_rejected_before_any_device_action(self):
        def reject(path, digest, aapt2):
            validate_apk(path, digest, aapt2, package_reader=lambda *args: 'com.reseebo.reseebo')
        with self.assertRaisesRegex(ValueError, 'Refusing package ID'):
            self.runner(reject).run()
        self.assertEqual([], self.commands)
        self.assertEqual([], self.drives)

    def test_changed_source_is_rejected_before_package_or_device_commands(self):
        self.apk.write_bytes(b'changed-build')
        with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
            self.runner().run()
        self.assertEqual([], self.commands)

    def test_installed_binary_mismatch_preserves_running_process_and_data(self):
        self.installed_bytes = b'another-installed-build'
        with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
            self.runner().run()
        self.assertFalse(any('force-stop' in command for command in self.commands))
        self.assertEqual([], self.drives)

    def test_phase_mismatch_is_rejected_before_force_stop(self):
        self.prior['nextPhase'] = 'verify'
        with self.assertRaisesRegex(ValueError, 'phase/PID mismatch'):
            self.runner().run()
        self.assertFalse(any('force-stop' in command for command in self.commands))

    def test_restart_attaches_without_installing_or_rebuilding_and_preserves_app(self):
        result = self.runner().run()
        self.assertEqual('verify', result['nextPhase'])
        command = self.drives[0]
        self.assertIn('--use-existing-app=http://127.0.0.1:5432/nonce=/', command)
        self.assertIn('--keep-app-running', command)
        self.assertFalse(any(arg.startswith('--use-application-binary') for arg in command))
        self.assertFalse(any(item in ('install', 'install-multiple', 'uninstall', 'clear')
                             for call in self.commands for item in call))
        self.assertTrue(any('force-stop' in call for call in self.commands))
        for call in self.commands:
            self.assertNotIn('com.reseebo.reseebo', call)

    def test_same_process_result_is_rejected(self):
        self.after['pid'] = self.prior['pid']
        with self.assertRaisesRegex(ValueError, 'Same-process continuation'):
            self.runner().run()

    def test_restart_forbids_fresh_install(self):
        self.args.fresh_install = True
        with self.assertRaisesRegex(ValueError, 'forbidden for restart'):
            self.runner().run()
        self.assertEqual([], self.commands)

    def test_seed_requires_explicit_fresh_install_when_verification_exists(self):
        self.args.phase = 'seed'
        with self.assertRaisesRegex(ValueError, 'explicit --fresh-install'):
            self.runner().run()
        self.assertFalse(any('uninstall' in command for command in self.commands))

    def test_seed_installs_immutable_snapshot_and_cleanup_retains_verification(self):
        self.args.phase = 'seed'
        self.args.fresh_install = True
        self.after = {'phase': 'seed', 'nextPhase': 'review', 'pid': 456,
                      'processToken': 'seed-process'}
        self.runner().run()
        command = self.drives[0]
        binary = next(arg.split('=', 1)[1] for arg in command
                      if arg.startswith('--use-application-binary='))
        self.assertEqual(self.digest, Path(binary).stem)
        self.assertEqual(self.installed_bytes, Path(binary).read_bytes())
        self.assertIn('--keep-app-running', command)
        uninstall = [call for call in self.commands if 'uninstall' in call]
        self.assertEqual(1, len(uninstall))
        self.assertEqual(['uninstall', '--user', '0', helper.VERIFICATION_ID], uninstall[0][3:])

    def test_host_inspection_executes_no_adb_or_flutter(self):
        self.args.run = False
        self.assertTrue(self.runner().run()['inspectionOnly'])
        self.assertEqual([], self.commands)
        self.assertEqual([], self.drives)

    def test_tampered_existing_snapshot_is_rejected(self):
        snapshots = self.root / 'snapshots'
        snapshots.mkdir()
        (snapshots / f'{self.digest}.apk').write_bytes(b'tampered-pinned-build')
        with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
            helper.pin_apk(self.apk, self.digest, 'aapt2', snapshots, self.validator)

    def test_driver_failure_retains_marker_and_removes_only_owned_forward(self):
        def fail_driver(command, output):
            self.drives.append(command)
            return 7
        runner = helper.AcceptanceRunner(self.args, command=self.command,
            drive=fail_driver, validate=self.validator)
        with self.assertRaisesRegex(ValueError, 'exit 7; data retained'):
            runner.run()
        self.assertEqual(self.prior, self.current_marker)
        self.assertFalse(any(item in ('install', 'uninstall', 'clear')
                             for call in self.commands for item in call))
        self.assertEqual(['forward', '--remove', 'tcp:5432'], self.commands[-1][3:])

    def test_command_recording_failure_removes_owned_forward_without_launch_or_reset(self):
        self.args.output.mkdir()
        # A directory at the log's exact path deterministically rejects the
        # write after restart has allocated its owned forward.
        (self.args.output / 'command.json').mkdir()
        with self.assertRaises(OSError):
            self.runner().run()
        self.assertEqual([], self.drives)
        self.assertEqual(self.prior, self.current_marker)
        removed = [call[3:] for call in self.commands
                   if call[3:5] == ['forward', '--remove']]
        self.assertEqual([['forward', '--remove', 'tcp:5432']], removed)
        self.assertFalse(any(item in ('install', 'uninstall', 'clear')
                             for call in self.commands for item in call))

    def test_driver_timeout_stops_and_waits_only_its_owned_child_tree(self):
        self.args.output.mkdir()
        events = []

        class Child:
            pid = 987
            stopped = False

            def poll(self):
                return -1 if self.stopped else None

            def wait(self, timeout):
                events.append(('wait', timeout))
                if timeout == 900:
                    raise subprocess.TimeoutExpired('owned-flutter-child', timeout)
                self.stopped = True
                return -1

        child = Child()

        def stop_tree(command, **kwargs):
            events.append(('stop', command))
            return subprocess.CompletedProcess(command, 0)

        with patch.object(helper.subprocess, 'Popen', return_value=child), \
             patch.object(helper.subprocess, 'run', side_effect=stop_tree):
            with self.assertRaises(subprocess.TimeoutExpired):
                helper.run_driver(['flutter', 'drive', '--keep-app-running'], self.args.output)
        self.assertEqual([
            ('wait', 900),
            ('stop', ['taskkill', '/PID', '987', '/T', '/F']),
            ('wait', 30),
        ], events)
        self.assertTrue(child.stopped)

    def test_finished_driver_does_not_kill_or_wait_again(self):
        class FinishedChild:
            def poll(self):
                return 0

            def wait(self, timeout):
                raise AssertionError('Completed child must not be waited again')

        with patch.object(helper.subprocess, 'run') as run:
            helper.stop_owned_child(FinishedChild())
        run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
