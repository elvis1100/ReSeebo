"""Restore/verify the pinned OCR artifacts; this is development tooling only.

The checked-in manifest is the trust root. This tool never resolves a moving
branch, converts a model, or changes availability/device-proof flags. Downloads
are verified before atomic replacement; APK runtime has no download path.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import urllib.request


def prepare(root: Path, manifest: dict, verify_only: bool) -> None:
    if manifest.get('schemaVersion') != 1:
        raise ValueError('Unsupported OCR manifest version')
    artifacts = list(manifest.get('sdk', {}).get('artifacts', []))
    for engine in manifest['engines']:
        artifacts.extend(engine['artifacts'])
    for artifact in artifacts:
        target = (root / artifact['path']).resolve()
        if not target.is_relative_to(root):
            raise ValueError('Artifact path is outside project root')
        expected = artifact.get('localSha256', artifact['sha256'])
        if len(expected) != 64 or any(c not in '0123456789abcdef' for c in expected):
            raise ValueError('Invalid SHA-256 in manifest')
        if target.exists():
            with target.open('rb') as current:
                actual = hashlib.file_digest(current, 'sha256').hexdigest()
            if actual == expected:
                print(f'Verified {artifact["path"]}')
                continue
            if verify_only:
                raise ValueError(f'SHA-256 mismatch: {artifact["path"]}')
        elif verify_only:
            raise ValueError(f'Missing artifact: {artifact["path"]}')
        if 'localSha256' in artifact:
            raise ValueError(f'Locally modified artifact must be restored from the project checkout: {artifact["path"]}')
        url = artifact['url']
        if not url.startswith('https://'):
            raise ValueError('Artifact download must use HTTPS')
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as out:
                temporary = Path(out.name)
                with urllib.request.urlopen(url, timeout=120) as response:
                    while block := response.read(1024 * 1024):
                        out.write(block)
            if artifact.get('encoding') == 'base64':
                temporary.write_bytes(base64.b64decode(temporary.read_bytes()))
            elif artifact.get('encoding') is not None:
                raise ValueError('Unsupported artifact encoding')
            with temporary.open('rb') as downloaded:
                actual = hashlib.file_digest(downloaded, 'sha256').hexdigest()
            if actual != expected:
                raise ValueError(f'SHA-256 mismatch: {artifact["path"]}')
            temporary.replace(target)
            print(f'Restored {artifact["path"]}')
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    root = args.root.resolve()
    manifest_path = args.manifest or root / 'assets/ocr/model_manifest.json'
    try:
        prepare(root, json.loads(manifest_path.read_text(encoding='utf-8')), args.verify_only)
    except (OSError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
