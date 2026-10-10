"""Guard a prebuilt acceptance APK; retain verification data between processes.

Defaults to host-only inspection. Device operations require --run. Seed may
install only a hash-pinned verification APK. Review/verify never install or
rebuild: they inspect the installed binary, launch a new process and attach
Flutter drive to its observed VM service. No networking setting is changed.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit, urlunsplit

if __package__:
    from .run_paddle_probe import ROOT, VERIFICATION_ID, validate_apk
else:
    from run_paddle_probe import ROOT, VERIFICATION_ID, validate_apk

MARKER = 'files/reviewable-receipt-acceptance/lifecycle.json'
COMPONENT = f'{VERIFICATION_ID}/com.reseebo.reseebo.MainActivity'
TARGET = ROOT / 'integration_test/reviewable_receipt_offline_test.dart'
DRIVER = ROOT / 'integration_test/paddle_engine_probe_driver.dart'


def pin_apk(apk, digest, aapt2, snapshots, validate=validate_apk):
    """Validate source, copy atomically, then validate the exact launched bytes."""
    validate(apk, digest, aapt2)
    snapshots.mkdir(parents=True, exist_ok=True)
    pinned = snapshots / f'{digest}.apk'
    if not pinned.exists():
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=snapshots, suffix='.apk', delete=False) as out:
                temporary = Path(out.name)
                with apk.open('rb') as source:
                    shutil.copyfileobj(source, out)
            validate(temporary, digest, aapt2)
            temporary.replace(pinned)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    validate(pinned, digest, aapt2)
    return pinned


def stop_owned_child(process):
    if process is not None and process.poll() is None:
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                       capture_output=True, timeout=30, check=False)
        process.wait(timeout=30)


def run_driver(command, output):
    process = None
    try:
        with (output / 'flutter.log').open('w', encoding='utf-8') as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log,
                                       stderr=subprocess.STDOUT)
            return process.wait(timeout=900)
    finally:
        # On timeout/error, wait for only our child's tree. Do not stop or
        # uninstall the Android application; its private evidence is retained.
        stop_owned_child(process)


class AcceptanceRunner:
    def __init__(self, args, command=subprocess.run, drive=run_driver, validate=validate_apk):
        self.args, self.command, self.drive, self.validate = args, command, drive, validate

    def adb(self, *arguments, check=True):
        return self.command([self.args.adb, '-s', self.args.device, *arguments],
                            capture_output=True, timeout=30, check=check)

    def marker(self):
        result = self.adb('exec-out', 'run-as', VERIFICATION_ID, 'cat', MARKER)
        value = json.loads(result.stdout)
        if not isinstance(value, dict):
            raise ValueError('Invalid lifecycle marker')
        return value

    def installed_paths(self):
        result = self.adb('shell', 'pm', 'path', '--user', '0', VERIFICATION_ID, check=False)
        return re.findall(r'^package:(.+)$', result.stdout.decode().strip(), re.MULTILINE)

    def verify_installed(self, pinned):
        paths = self.installed_paths()
        if len(paths) != 1 or not paths[0].startswith('/data/app/') or not paths[0].endswith('/base.apk'):
            raise ValueError('Expected one installed verification base APK; split/missing packages refused')
        with tempfile.TemporaryDirectory(prefix='reseebo-installed-') as directory:
            pulled = Path(directory) / 'installed.apk'
            self.adb('pull', paths[0], str(pulled))
            self.validate(pulled, self.args.sha256, self.args.aapt2)
        # A later rebuild or altered host snapshot cannot affect this run.
        self.validate(pinned, self.args.sha256, self.args.aapt2)

    def restart_uri(self, prior_pid):
        self.adb('shell', 'am', 'force-stop', '--user', '0', VERIFICATION_ID)
        # Do not erase logcat. Filter by the observed new PID instead.
        self.adb('shell', 'am', 'start', '--user', '0', '-W', '-n', COMPONENT)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            result = self.adb('shell', 'pidof', VERIFICATION_ID, check=False)
            text = result.stdout.decode().strip()
            if re.fullmatch(r'\d+', text) and int(text) != prior_pid:
                logs = self.adb('logcat', '-d', f'--pid={text}').stdout.decode(errors='replace')
                match = re.search(r'Dart VM service (?:is )?listening on (http://[^\s]+)', logs)
                if match:
                    uri = urlsplit(match.group(1).rstrip('.,'))
                    if uri.hostname not in ('127.0.0.1', 'localhost') or uri.port is None:
                        raise ValueError('Refusing a non-loopback VM service URI')
                    port = self.adb('forward', 'tcp:0', f'tcp:{uri.port}').stdout.decode().strip()
                    if not re.fullmatch(r'\d+', port):
                        raise ValueError('Invalid forwarded VM service port')
                    return urlunsplit((uri.scheme, f'127.0.0.1:{port}', uri.path, uri.query, '')), port
            time.sleep(.25)
        raise ValueError('New verification process/VM service was not observed; evidence retained')

    def run(self):
        args = self.args
        pinned = pin_apk(args.apk, args.sha256, args.aapt2,
                         ROOT / 'build/verified-reviewable-apks', self.validate)
        if not args.run:
            return {'inspectionOnly': True, 'packageId': VERIFICATION_ID,
                    'sha256': args.sha256, 'apk': str(pinned)}
        args.output.mkdir(parents=True, exist_ok=True)
        prior, forwarded = None, None
        base = [args.flutter, 'drive', '--no-pub', '-d', args.device, '--device-user=0',
                '--keep-app-running', f'--driver={DRIVER}', f'--target={TARGET}']
        if args.phase == 'seed':
            if self.installed_paths():
                if not args.fresh_install:
                    raise ValueError('Verification package already installed; explicit --fresh-install required for seed')
                # Fixed verified ID only. Never use a source package name or a
                # caller-supplied package argument for this fresh-install step.
                self.adb('uninstall', '--user', '0', VERIFICATION_ID)
            self.validate(pinned, args.sha256, args.aapt2)
            base.append(f'--use-application-binary={pinned}')
        else:
            if args.fresh_install:
                raise ValueError('--fresh-install is forbidden for restart phases')
            self.verify_installed(pinned)
            prior = self.marker()
            if prior.get('nextPhase') != args.phase or not isinstance(prior.get('pid'), int):
                raise ValueError('Lifecycle phase/PID mismatch; no process stopped')
            uri, forwarded = self.restart_uri(prior['pid'])
            base.append(f'--use-existing-app={uri}')
        try:
            (args.output / 'command.json').write_text(json.dumps(base, indent=2), encoding='utf-8')
            code = self.drive(base, args.output)
            if code != 0:
                raise ValueError(f'Acceptance driver failed with exit {code}; data retained')
            self.verify_installed(pinned)
            after = self.marker()
            expected = {'seed': 'review', 'review': 'verify', 'verify': 'complete'}[args.phase]
            if after.get('phase') != args.phase or after.get('nextPhase') != expected:
                raise ValueError('Completed lifecycle marker does not match requested phase')
            if prior is not None and (after.get('pid') == prior.get('pid') or
                                      after.get('processToken') == prior.get('processToken')):
                raise ValueError('Same-process continuation is not restart evidence')
            (args.output / 'lifecycle.json').write_text(json.dumps(after, indent=2), encoding='utf-8')
            (args.output / 'memory-after-phase.txt').write_bytes(
                self.adb('shell', 'dumpsys', 'meminfo', VERIFICATION_ID).stdout)
            return after
        finally:
            if forwarded is not None:
                self.adb('forward', '--remove', f'tcp:{forwarded}', check=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--phase', choices=('seed', 'review', 'verify'), default='seed')
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--fresh-install', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/reviewable-acceptance')
    parser.add_argument('--device', default='R5GL41586RA')
    parser.add_argument('--adb', default='C:/Android/Sdk/platform-tools/adb.exe')
    parser.add_argument('--aapt2', default='C:/Android/Sdk/build-tools/36.0.0/aapt2.exe')
    parser.add_argument('--flutter', default='C:/src/flutter/bin/flutter.bat')
    args = parser.parse_args()
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    try:
        print(json.dumps(AcceptanceRunner(args).run(), indent=2))
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
