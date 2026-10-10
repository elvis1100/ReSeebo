"""Inspect a prebuilt verification APK before any device action.

Build separately. This helper defaults to inspection only. --run launches
Flutter drive with a hash-pinned snapshot; it cannot rebuild a different APK.
It never clears/uninstalls a package or changes device networking.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

VERIFICATION_ID = 'com.reseebo.reseebo.verification'
ROOT = Path(__file__).resolve().parents[1]


def inspect_package(apk: Path, aapt2: str) -> str:
    result = subprocess.run([aapt2, 'dump', 'badging', str(apk)],
        capture_output=True, text=True, encoding='utf-8', errors='replace', check=True)
    match = re.search(r"^package: name='([^']+)'", result.stdout, re.MULTILINE)
    if not match:
        raise ValueError('Cannot inspect APK package ID')
    return match.group(1)


def validate_apk(apk: Path, expected_sha256: str, aapt2: str,
                 package_reader=inspect_package) -> None:
    if not re.fullmatch(r'[a-f0-9]{64}', expected_sha256):
        raise ValueError('Invalid expected APK SHA-256')
    with apk.open('rb') as source:
        actual = hashlib.file_digest(source, 'sha256').hexdigest()
    if actual != expected_sha256:
        raise ValueError('APK SHA-256 mismatch; refusing device action')
    package = package_reader(apk, aapt2)
    if package != VERIFICATION_ID:
        raise ValueError(f'Refusing package ID {package}; expected {VERIFICATION_ID}')


def guarded_drive(apk: Path, expected_sha256: str, snapshots: Path,
                  aapt2: str, flutter: str, device: str,
                  package_reader=inspect_package, launch=None, keep_app_running=False, use_existing_app=None) -> int:
    validate_apk(apk, expected_sha256, aapt2, package_reader)
    if use_existing_app is not None:
        url = urlsplit(use_existing_app)
        if (url.scheme != 'http' or url.hostname != '127.0.0.1'
                or url.port is None or not 1 <= url.port <= 65535
                or url.username is not None or url.password is not None
                or url.query or url.fragment):
            raise ValueError('Existing app URL must be an HTTP service on 127.0.0.1 with a port')
    snapshots.mkdir(parents=True, exist_ok=True)
    pinned = snapshots / f'{expected_sha256}.apk'
    if not pinned.exists():
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=snapshots, suffix='.apk', delete=False) as out:
                temporary = Path(out.name)
                with apk.open('rb') as source:
                    shutil.copyfileobj(source, out)
            # Reject a source build that changed while the copy was in progress.
            validate_apk(temporary, expected_sha256, aapt2, package_reader)
            temporary.replace(pinned)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    # Check the actual binary again immediately before invoking the installer.
    validate_apk(pinned, expected_sha256, aapt2, package_reader)
    command = [flutter, 'drive', '--no-pub', '-d', device, '--device-user=0',
        (f'--use-existing-app={use_existing_app}' if use_existing_app is not None
         else f'--use-application-binary={pinned}'),
        f'--driver={ROOT / "integration_test/paddle_engine_probe_driver.dart"}',
        f'--target={ROOT / "integration_test/paddle_engine_probe_test.dart"}']
    if keep_app_running:
        command.append('--keep-app-running')
    print(json.dumps({'packageId': VERIFICATION_ID, 'sha256': expected_sha256,
        'apk': str(pinned), 'command': command}), flush=True)
    if launch is None:
        return 0
    return launch(command)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--aapt2', default='C:/Android/Sdk/build-tools/36.0.0/aapt2.exe')
    parser.add_argument('--flutter', default='C:/src/flutter/bin/flutter.bat')
    parser.add_argument('--device', default='R5GL41586RA')
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--use-existing-app',
        help='Connect to an independently verified running verification app on localhost.')
    parser.add_argument('--keep-app-running', action='store_true',
        help='Preserve the isolated verification package after the probe.')
    args = parser.parse_args()
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    try:
        launch = None
        if args.run:
            def launch(command):
                return subprocess.run(command, cwd=ROOT).returncode
        return guarded_drive(args.apk.resolve(), args.sha256,
            ROOT / 'build/verified-paddle-apks', args.aapt2, args.flutter,
            args.device, launch=launch, keep_app_running=args.keep_app_running,
            use_existing_app=args.use_existing_app)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
