"""Collect guarded Paddle probe output, sampled PSS and coordinate overlays.

Networking is never changed here. Optional public receipt inputs are checked
against independent truth hashes and copied only to the verification cache.
Build separately and pass the independently inspected APK hash as required by
run_paddle_probe.py. PSS maxima are sampled process values, not allocation peaks.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import threading
import time

if __package__:
    from .run_paddle_probe import ROOT, VERIFICATION_ID, validate_apk
else:
    from run_paddle_probe import ROOT, VERIFICATION_ID, validate_apk

TRUTH_HASHES = {
    'dali': '3780251c52ef2ef361947ce623753f9deab4ca6d4934c5c65c97ea6ca2117ab2',
    'savemore': '79aa855eec4091a1658689eb3324253e5846100e15f7bb8874a386b367591234',
}


def stop_owned_child(process):
    """Stop only the process tree we spawned; never enumerate/kill Flutter globally."""
    if process is not None and process.poll() is None:
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
            capture_output=True, timeout=30, check=False)
        process.wait(timeout=30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--receipt-samples', type=Path)
    parser.add_argument('--device', default='R5GL41586RA')
    parser.add_argument('--adb', default='C:/Android/Sdk/platform-tools/adb.exe')
    parser.add_argument('--aapt2', default='C:/Android/Sdk/build-tools/36.0.0/aapt2.exe')
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding='utf-8')
    # This guard precedes even observational ADB calls. The child installer
    # independently rechecks its immutable snapshot immediately before launch.
    validate_apk(args.apk, args.sha256, args.aapt2)
    fixture_bytes = {}
    if args.receipt_samples:
        for name, expected in TRUTH_HASHES.items():
            data = (args.receipt_samples / f'{name}.jpg').read_bytes()
            if hashlib.sha256(data).hexdigest() != expected:
                raise ValueError(f'Receipt truth input hash mismatch: {name}')
            fixture_bytes[name] = data
    args.output.mkdir(parents=True, exist_ok=True)
    stop = threading.Event()
    samples, records = [], []
    active = {'engine': None}

    def adb(*command, data=None):
        return subprocess.run([args.adb, '-s', args.device, *command],
            input=data, capture_output=True, timeout=30, check=True)

    def read_private(path):
        return adb('exec-out', 'run-as', VERIFICATION_ID, 'cat', path).stdout

    def sample():
        while not stop.is_set():
            try:
                output = adb('shell', 'dumpsys', 'meminfo', VERIFICATION_ID).stdout.decode(errors='replace')
                match = re.search(r'TOTAL PSS:\s*(\d+)', output)
                if match:
                    samples.append({'time': time.time(), 'engine': active['engine'],
                        'pssKiB': int(match.group(1))})
            except subprocess.SubprocessError:
                pass  # No installed/running process during startup is expected.
            stop.wait(.5)

    thread = threading.Thread(target=sample, daemon=True)
    thread.start()
    code = 1
    process = None
    try:
        command = [sys.executable, str(ROOT/'scripts/run_paddle_probe.py'),
            '--apk', str(args.apk), '--sha256', args.sha256, '--device', args.device,
            '--aapt2', args.aapt2, '--run']
        with (args.output/'flutter.log').open('w', encoding='utf-8') as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
            for line in process.stdout:
                log.write(line); log.flush()
                print(line, end='', flush=True)
                for engine in ('ppocr_v5_mobile', 'ppocr_v6_medium'):
                    if engine+' genuine bundled inference' in line:
                        active['engine'] = engine
                start = line.find('{"fixtureDirectory":')
                if start >= 0 and fixture_bytes:
                    directory = json.JSONDecoder().raw_decode(line[start:])[0]['fixtureDirectory']
                    if directory not in (f'/data/user/0/{VERIFICATION_ID}/cache',
                                         f'/data/data/{VERIFICATION_ID}/cache'):
                        raise ValueError('Refusing fixture destination outside verification cache')
                    for name, data in fixture_bytes.items():
                        target = f'{directory}/paddle-truth-{name}.jpg'
                        adb('exec-in', 'run-as', VERIFICATION_ID, 'dd',
                            f'of={target}', data=data)
                start = line.find('{"probe":')
                if start >= 0:
                    record = json.JSONDecoder().raw_decode(line[start:])[0]
                    if 'resultPath' in record:
                        record = json.loads(read_private(record['resultPath']))
                    records.append(record)
                    label = f'{record["probe"]}-{record.get("sample", "generated")}-{record["run"]}'
                    (args.output/f'{label}-overlay.png').write_bytes(read_private(record['overlayPath']))
            code = process.wait()
    finally:
        # If JSON/pull/copy fails, Flutter must end before callers consider the
        # probe finished or restore networking in an outer offline harness.
        stop_owned_child(process)
        stop.set(); thread.join(timeout=30)
        (args.output/'memory-samples.json').write_text(json.dumps(samples, indent=2), encoding='utf-8')
        (args.output/'results.json').write_text(json.dumps(records, indent=2), encoding='utf-8')
        print('SAMPLED_PEAK_PSS_KIB', json.dumps({engine: max((s['pssKiB'] for s in samples
            if s['engine'] == engine), default=None) for engine in ('ppocr_v5_mobile', 'ppocr_v6_medium')}))
        print('PROBE_EXIT', code)
    return code


if __name__ == '__main__':
    sys.exit(main())
