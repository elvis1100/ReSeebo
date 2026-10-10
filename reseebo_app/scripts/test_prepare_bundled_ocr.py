import hashlib
import base64
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from scripts.prepare_bundled_ocr import prepare


class PreparationTest(unittest.TestCase):
    def test_gitiles_base64_license_is_decoded_then_hash_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            license_bytes = b'Copyright notice\nLicense terms\n'
            manifest = {'schemaVersion': 1, 'engines': [], 'sdk': {'artifacts': [{
                'path': 'assets/ocr/LICENSE.txt', 'encoding': 'base64',
                'sha256': hashlib.sha256(license_bytes).hexdigest(),
                'url': 'https://example.invalid/pinned/LICENSE?format=TEXT',
            }]}}
            with patch('urllib.request.urlopen', return_value=io.BytesIO(base64.b64encode(license_bytes))):
                prepare(root, manifest, False)
            self.assertEqual(license_bytes, (root/'assets/ocr/LICENSE.txt').read_bytes())

    def run_prepare(self, root, manifest):
        path = root / 'lock.json'
        path.write_text(json.dumps(manifest), encoding='utf-8')
        return subprocess.run([
            sys.executable, str(Path(__file__).with_name('prepare_bundled_ocr.py')),
            '--root', str(root), '--manifest', str(path), '--verify-only',
        ], capture_output=True, text=True)

    def test_genuine_assets_verified_and_corruption_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / 'assets/ocr/model.onnx'
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(b'genuine-model-test-fixture')
            manifest = {'schemaVersion': 1, 'engines': [{
                'id': 'ppocr_v5_mobile', 'artifacts': [{
                    'path': 'assets/ocr/model.onnx',
                    'sha256': hashlib.sha256(artifact.read_bytes()).hexdigest(),
                    'url': 'https://example.invalid/pinned/model.onnx',
                }],
            }], 'sdk': {'artifacts': []}}
            result = self.run_prepare(root, manifest)
            self.assertEqual(0, result.returncode, result.stderr)
            artifact.write_bytes(b'tampered')
            result = self.run_prepare(root, manifest)
            self.assertNotEqual(0, result.returncode)
            self.assertIn('SHA-256 mismatch', result.stderr)

    def test_untrusted_manifest_cannot_escape_project_root(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_prepare(Path(directory), {
                'schemaVersion': 1, 'engines': [{'artifacts': [{
                    'path': '../outside.onnx', 'sha256': 'a' * 64,
                    'url': 'https://example.invalid/model.onnx',
                }]}], 'sdk': {'artifacts': []},
            })
            self.assertNotEqual(0, result.returncode)
            self.assertIn('outside project root', result.stderr)


if __name__ == '__main__':
    unittest.main()
