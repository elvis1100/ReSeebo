#!/usr/bin/env python3
"""Download opt-in public test photos outside the app assets.

Sources retain their copyright. These photos are for local format evaluation;
no redistribution license is assumed. Downloads are never part of app runtime.
"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

SAMPLES = {
    'dali': ('https://note.com/oyako_tagaytay/n/n929317daedad', 'https://assets.st-note.com/img/1784096562-maF463kKzO8trWBhDMZdLSCJ.jpg?width=1200'),
    'waltermart': ('https://note.com/oyako_tagaytay/n/nef72d3b3ba84', 'https://assets.st-note.com/img/1764365664-VgTH7n8F5ytZoRY0m3MabuiW.jpg?width=1200'),
    'puregold': ('https://note.com/norris_iloilo/n/n2f7474d537f5', 'https://assets.st-note.com/img/1784505179-LwubRXq4DcW2J10iBanZVQm7.jpg?width=1200'),
    'savemore': ('https://note.com/norris_iloilo/n/n2f7474d537f5', 'https://assets.st-note.com/img/1784503830-7Mbl4aXGUpkwOJ8TCL2vcqKR.jpg?width=1200'),
    'sm_hypermart': ('https://jeffwerner.ca/security_use_and_packaging/', 'https://jeffwerner.ca/images/journal/CRW_6077.jpg'),
    'pos_demo': ('https://mydmsoft.com/', 'https://mydmsoft.com/images/receipt2.jpg'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = []
    for name, (source, url) in SAMPLES.items():
        with urllib.request.urlopen(url, timeout=30) as response:
            data = response.read()
        if not data.startswith(b'\xff\xd8'):
            raise ValueError(f'{name}: expected JPEG, received another content type')
        path = args.output / f'{name}.jpg'
        path.write_bytes(data)
        manifest.append({'id': name, 'source': source, 'url': url,
                         'sha256': hashlib.sha256(data).hexdigest()})
        print(f'{name}: {len(data)} bytes')
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
