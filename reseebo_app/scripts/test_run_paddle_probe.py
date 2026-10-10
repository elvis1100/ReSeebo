import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest


class ProbeGuardTest(unittest.TestCase):
    def load_helper(self):
        path = Path(__file__).with_name('run_paddle_probe.py')
        spec = importlib.util.spec_from_file_location('probe_helper', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_owner_apk_refused_before_device_command(self):
        helper = self.load_helper()
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'test.apk'
            apk.write_bytes(b'controlled-apk-fixture')
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            with self.assertRaisesRegex(ValueError, 'Refusing package ID'):
                helper.guarded_drive(apk, digest, Path(directory) / 'snapshots',
                    'aapt2', 'flutter', 'R5GL41586RA',
                    package_reader=lambda path, tool: 'com.reseebo.reseebo',
                    launch=lambda command: self.fail('Device command executed'))
            self.assertFalse((Path(directory) / 'snapshots').exists())

    def test_changed_apk_refused_before_package_tool_or_device(self):
        helper = self.load_helper()
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'test.apk'
            apk.write_bytes(b'tampered-apk')
            with self.assertRaisesRegex(ValueError, 'APK SHA-256 mismatch'):
                helper.guarded_drive(apk, 'a' * 64, Path(directory) / 'snapshots',
                    'aapt2', 'flutter', 'R5GL41586RA',
                    package_reader=lambda *args: self.fail('Package tool executed'),
                    launch=lambda command: self.fail('Device command executed'))

    def test_drive_uses_verified_snapshot_without_rebuilding(self):
        helper = self.load_helper()
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'test.apk'
            apk.write_bytes(b'controlled-apk-fixture')
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            commands = []
            def launch(command):
                commands.append(command)
                # A later source build cannot replace the verified binary.
                apk.write_bytes(b'later-unrelated-build')
                pinned = next(item.split('=', 1)[1] for item in command
                    if item.startswith('--use-application-binary='))
                self.assertEqual(b'controlled-apk-fixture', Path(pinned).read_bytes())
                return 0
            self.assertEqual(0, helper.guarded_drive(apk, digest,
                Path(directory) / 'snapshots', 'aapt2', 'flutter', 'R5GL41586RA',
                package_reader=lambda path, tool: 'com.reseebo.reseebo.verification',
                launch=launch))
            self.assertEqual(1, len(commands))
            self.assertIn('--device-user=0', commands[0])


if __name__ == '__main__':
    unittest.main()
