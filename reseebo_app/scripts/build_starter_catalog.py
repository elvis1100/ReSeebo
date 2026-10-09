#!/usr/bin/env python3
"""Build the bundled OFF subset from reviewed API records, never at runtime.

Usage: python scripts/build_starter_catalog.py reviewed-products.json
Requires Pillow. Downloads sequentially; prefers the OFF AWS image dataset.
Only writes the catalog assets. Review brand/variant/size against source labels
before expanding the subset; never import source prices or purchase histories.
"""
import io
import json
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.request

from PIL import Image, ImageOps

APP_ROOT = Path(__file__).resolve().parents[1]
CATALOG = APP_ROOT / 'assets/catalog'
HEADERS = {'User-Agent': 'Reseebo/1.0 (bundled offline starter catalog)'}


def category(row):
    name = ((row.get('product_name_en') or row['product_name']) + ' ' + row['brands']).lower()
    # Broad source taxonomy tags (e.g. plant-based beverages) occur on snacks;
    # package descriptions take priority over those broad community categories.
    groups = [
        ('Personal care', ['isopropyl alcohol']),
        ('Instant noodles', ['noodle', 'pancit', 'yakisoba', 'ramyun', 'cup batchoy', 'lucky me', 'luckyme', 'quickchow', 'tonkotsu']),
        ('Canned goods', ['corned', 'sardine', 'tuna', 'luncheon', 'beef loaf', 'meatloaf']),
        ('Sauces & seasonings', ['sauce', 'seasoning', 'ketchup', 'mayonnaise', 'mayonaise', 'sinigang', 'knorr', 'magic sarap', 'vinegar', 'sarsa', 'sandwich spread']),
        ('Pantry staples', ['peanut butter', 'oatmeal', 'instant oats', 'quaker oats', 'flour', 'spaghetti pasta', 'rumble pasta', 'green pea', 'fruit cocktail', 'mushroom', 'tomato paste', 'coconut oil', 'hotcake mix', 'cereal', 'honey stars', 'koko krunch']),
        ('Snacks & biscuits', ['biscuit', 'wafer', 'crack', 'chip', 'cookie', 'cake', 'candy', 'tamarind', 'skyflakes', 'fita', 'cloud 9', 'piatto', 'dewberry', 'choco mucho', 'choc nut', 'superstix', 'chocolat', 'choco hazelnut', 'choco spread', 'double hazelnut', 'milk with oreo', 'white chocolate', 'dark chocolate', 'whole almonds', 'tiger vanilla', 'butter coconut', 'bread pan', 'bread stix', 'sweet corn balls', 'nova', 'malkist', 'stax', 'luev-lov', 'lüv-lov', 'peanut crunch', 'choco flakes', 'choco brix', 'waffle', 'cream-o', 'crossini', 'grab nuts', 'butterscotch', 'potato', 'crisp', 'fries', 'kropeck', 'fishda', 'quake', 'brownie', 'oreo', 'calbee', 'rebisco', 'hansel', 'fruity munchsters', 'toasties']),
        ('Milk & dairy', ['milk', 'bear brand', 'cheese', 'cheddar', 'queso', 'quezo', 'cheez', 'crema', 'cream', 'ovaltine', 'milo', 'energen', 'chuckie', 'moo fortified', 'yakult', 'nutriboost', 'eden']),
        ('Coffee & tea', ['coffee', 'nescafe', 'great taste', 'tea', 'nestea', 'c2']),
        ('Drinks', ['juice', 'drink', 'water', 'cola', 'sprite', 'royal', 'mountain dew', 'gatorade', 'tropicana', 'pocari', 'tang', 'vitasoy', 'soya', 'b\'lue', 'soda', 'smart c', 'pineapple heart smart']),
        ('Bread & bakery', ['bread', 'bakery']),
    ]
    return next((label for label, words in groups if any(w in name for w in words)), 'Groceries')


def clean(value):
    return re.sub(r'\s+', ' ', value).strip()


def describe(row):
    source_name = clean(row.get('product_name_en') or row['product_name'])
    brand = clean(row['brands'].split(',')[0])
    quantity = clean(row['quantity'])
    quantity = re.sub(r'(\d)\s*(kg|g|ml|l)\b', lambda m: m[1] + ' ' + ('mL' if m[2].lower() == 'ml' else m[2]), quantity, flags=re.I)
    # Keep the full source description as the variant when brand stripping
    # would lose product identity. Never fill an unknown flavor with "Original".
    brand_tokens = re.findall(r'[^\W_]+', brand, re.UNICODE)
    brand_pattern = r'(?<!\w)' + r'[\W_]*'.join(re.escape(token) for token in brand_tokens) + r'(?!\w)'
    variant = re.sub(brand_pattern, '', source_name, flags=re.I).strip() if brand_pattern else source_name
    variant = re.sub(r'\(?\b\d+(?:\.\d+)?\s*(?:kg|g|ml|l)\b\)?', '', variant, flags=re.I)
    variant = clean(variant).strip(' -,').lstrip('! ') or source_name
    if variant.islower() or variant.isupper():
        variant = variant.title()
    display_source = re.sub(r'\(?\b\d+(?:\.\d+)?\s*(?:kg|g|ml|l)\b\)?', '', source_name, flags=re.I)
    display_source = clean(display_source)
    display_source = display_source.title() if display_source.islower() or display_source.isupper() else display_source
    name = display_source if re.search(brand_pattern, source_name, flags=re.I) else clean(f'{brand} {display_source}')
    return dict(barcode=row['code'], name=name, brand=brand, variant=variant,
                size=quantity, category=category(row),
                image_asset=f'assets/catalog/images/{row["code"]}.webp')


def photo_info(row):
    source_url = row['image_front_small_url']
    selected_key = source_url.rsplit('/', 1)[-1].split('.')[0]
    selected = row.get('images', {}).get(selected_key, {})
    raw = str(selected.get('imgid', ''))
    creator = row.get('images', {}).get(raw, {}).get('uploader', 'Open Food Facts contributors')
    aws = None
    if raw:
        path = source_url.split('/images/products/', 1)[1].rsplit('/', 1)[0]
        aws = f'https://openfoodfacts-images.s3.eu-west-3.amazonaws.com/data/{path}/{raw}.400.jpg'
    return source_url, aws, creator


def download(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=20) as response:
        return response.read()


def main():
    reviewed = json.loads(Path(sys.argv[1]).read_text())
    if isinstance(reviewed, dict):
        reviewed = reviewed['products']
    CATALOG.joinpath('images').mkdir(parents=True, exist_ok=True)
    entries, provenance, skipped = [], [], []
    previous_path = CATALOG / 'provenance.json'
    previous = {row['barcode']: row for row in json.loads(previous_path.read_text()).get('products', [])} if previous_path.exists() else {}
    for index, row in enumerate(reviewed):
        entry = describe(row)
        source, aws, creator = photo_info(row)
        destination = APP_ROOT / entry['image_asset']
        downloaded_from = previous.get(row['code'], {}).get('download_url', aws or source)
        try:
            if not destination.exists():
                try:
                    content = download(downloaded_from)
                except (urllib.error.URLError, TimeoutError):
                    downloaded_from = source
                    content = download(source)
                photo = ImageOps.exif_transpose(Image.open(io.BytesIO(content))).convert('RGB')
                photo.thumbnail((180, 180), Image.Resampling.LANCZOS)
                photo.save(destination, 'WEBP', quality=72, method=6)
            with Image.open(destination) as photo:
                dimensions = list(photo.size)
            entries.append(entry)
            provenance.append(dict(
                barcode=row['code'], source_name=row.get('product_name_en') or row['product_name'],
                source_brands=row['brands'], source_quantity=row['quantity'],
                product_url=f'https://world.openfoodfacts.org/product/{row["code"]}',
                image_url=source, download_url=downloaded_from, creator=creator,
                image_license='CC-BY-SA-3.0', image_asset=entry['image_asset'],
                image_bytes=destination.stat().st_size, image_dimensions=dimensions,
                modifications='EXIF orientation; RGB conversion; proportional resize to at most 180px; WebP quality 72',
            ))
            print(f'{index + 1}/{len(reviewed)} {row["code"]} {destination.stat().st_size} bytes', flush=True)
        except Exception as error:
            skipped.append(dict(barcode=row['code'], error=str(error)))
            print(f'SKIP {row["code"]}: {error}', flush=True)
        time.sleep(0.05)
    metadata = dict(version=1, source='Open Food Facts', retrieved_on='2026-10-09',
                    database_license='ODbL-1.0', contents_license='DbCL-1.0',
                    image_license='CC-BY-SA-3.0')
    CATALOG.joinpath('products.json').write_text(json.dumps({**metadata, 'products': entries}, ensure_ascii=False, indent=2) + '\n')
    CATALOG.joinpath('provenance.json').write_text(json.dumps({**metadata, 'products': provenance, 'skipped': skipped}, ensure_ascii=False, indent=2) + '\n')
    print(f'Bundled {len(entries)} items, {sum(row["image_bytes"] for row in provenance)} image bytes; skipped {len(skipped)}', flush=True)


if __name__ == '__main__':
    main()
