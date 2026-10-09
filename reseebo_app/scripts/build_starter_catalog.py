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
    name = ((row.get('product_name_en') or row.get('product_name') or '') + ' ' + (row.get('brands') or '')).lower()
    # Broad source taxonomy tags (e.g. plant-based beverages) occur on snacks;
    # package descriptions take priority over those broad community categories.
    groups = [
        ('Personal care', ['isopropyl alcohol', 'soap', 'shampoo', 'toothpaste', 'detergent', 'ariel']),
        ('Instant noodles', ['noodle', 'pancit', 'yakisoba', 'ramyun', 'cup batchoy', 'lucky me', 'luckyme', 'quickchow', 'tonkotsu', 'mi goreng']),
        ('Canned goods', ['corned', 'sardine', 'tuna', 'luncheon', 'beef loaf', 'meatloaf', 'carne norte', 'sisig']),
        ('Sauces & seasonings', ['sauce', 'seasoning', 'ketchup', 'mayonnaise', 'mayonaise', 'sinigang', 'knorr', 'magic sarap', 'vinegar', 'sarsa', 'sandwich spread', 'adobo']),
        ('Pantry staples', ['peanut butter', 'oatmeal', 'instant oats', 'quaker oats', 'flour', 'spaghetti pasta', 'rumble pasta', 'green pea', 'fruit cocktail', 'mushroom', 'tomato paste', 'coconut oil', 'hotcake mix', 'cereal', 'honey stars', 'koko krunch', 'spaghetti']),
        ('Snacks & biscuits', ['biscuit', 'wafer', 'crack', 'chip', 'cookie', 'cake', 'candy', 'tamarind', 'skyflakes', 'fita', 'cloud 9', 'piatto', 'dewberry', 'choco mucho', 'choc nut', 'superstix', 'chocolat', 'choco hazelnut', 'choco spread', 'double hazelnut', 'milk with oreo', 'white chocolate', 'dark chocolate', 'whole almonds', 'tiger vanilla', 'butter coconut', 'bread pan', 'bread stix', 'sweet corn balls', 'nova', 'malkist', 'stax', 'luev-lov', 'lüv-lov', 'peanut crunch', 'choco flakes', 'choco brix', 'waffle', 'cream-o', 'crossini', 'grab nuts', 'butterscotch', 'potato', 'crisp', 'fries', 'kropeck', 'fishda', 'quake', 'brownie', 'oreo', 'calbee', 'rebisco', 'hansel', 'fruity munchsters', 'toasties', 'patata', 'sugo', 'fudgee', 'v-cut', 'vcut']),
        ('Milk & dairy', ['milk', 'bear brand', 'cheese', 'cheddar', 'queso', 'quezo', 'cheez', 'crema', 'cream', 'ovaltine', 'milo', 'energen', 'chuckie', 'moo fortified', 'yakult', 'nutriboost', 'eden', 'birch tree']),
        ('Coffee & tea', ['coffee', 'nescafe', 'great taste', 'tea', 'nestea', 'c2']),
        ('Drinks', ['juice', 'drink', 'water', 'cola', 'sprite', 'royal', 'mountain dew', 'gatorade', 'tropicana', 'pocari', 'tang', 'vitasoy', 'soya', 'b\'lue', 'soda', 'smart c', 'pineapple heart smart']),
        ('Bread & bakery', ['bread', 'bakery']),
    ]
    return next((label for label, words in groups if any(w in name for w in words)), 'Groceries')


def clean(value):
    return re.sub(r'\s+', ' ', value).strip()


def describe(row):
    source_name = clean(row.get('product_name_en') or row.get('product_name') or '')
    brands_val = row.get('brands') or ''
    brand = clean(brands_val.split(',')[0]) if brands_val else ''
    quantity = clean(row.get('quantity') or '')
    quantity = re.sub(r'(\d)\s*(kg|g|ml|l)\b', lambda m: m[1] + ' ' + ('mL' if m[2].lower() == 'ml' else m[2]), quantity, flags=re.I)
    # Keep the full source description as the variant when brand stripping
    # would lose product identity. Never fill an unknown flavor with "Original".
    brand_tokens = re.findall(r'[^\W_]+', brand, re.UNICODE)
    brand_pattern = r'(?<!\w)' + r'[\W_]*'.join(re.escape(token) for token in brand_tokens) + r'(?!\w)' if brand_tokens else ''
    variant = re.sub(brand_pattern, '', source_name, flags=re.I).strip() if brand_pattern else source_name
    variant = re.sub(r'\(?\b\d+(?:\.\d+)?\s*(?:kg|g|ml|l)\b\)?', '', variant, flags=re.I)
    variant = clean(variant).strip(' -,').lstrip('! ') or source_name
    if variant.islower() or variant.isupper():
        variant = variant.title()
    display_source = re.sub(r'\(?\b\d+(?:\.\d+)?\s*(?:kg|g|ml|l)\b\)?', '', source_name, flags=re.I)
    display_source = clean(display_source)
    display_source = display_source.title() if display_source.islower() or display_source.isupper() else display_source
    name = display_source if (brand_pattern and re.search(brand_pattern, source_name, flags=re.I)) else clean(f'{brand} {display_source}')
    return dict(barcode=row['code'], name=name, brand=brand, variant=variant,
                size=quantity, category=category(row),
                image_asset=f'assets/catalog/images/{row["code"]}.webp')


def photo_info(row):
    source_url = row.get('image_front_small_url') or ''
    selected_key = source_url.rsplit('/', 1)[-1].split('.')[0] if source_url else ''
    selected = row.get('images', {}).get(selected_key, {})
    raw = str(selected.get('imgid', ''))
    creator = row.get('images', {}).get(raw, {}).get('uploader', 'Open Food Facts contributors')
    has_transform = bool(selected.get('angle')) or any(c in selected for c in ['x1', 'y1', 'x2', 'y2'])
    sel_sz = selected.get('sizes', {}).get('400') or selected.get('sizes', {}).get('200')
    raw_sz = row.get('images', {}).get(raw, {}).get('sizes', {}).get('400')
    if sel_sz and raw_sz:
        sel_aspect = sel_sz['w'] / sel_sz['h']
        raw_aspect = raw_sz['w'] / raw_sz['h']
        if (sel_aspect < 0.95 and raw_aspect > 1.05) or (sel_aspect > 1.05 and raw_aspect < 0.95):
            has_transform = True
    aws = None
    if raw and not has_transform and source_url:
        path = source_url.split('/images/products/', 1)[1].rsplit('/', 1)[0]
        aws = f'https://openfoodfacts-images.s3.eu-west-3.amazonaws.com/data/{path}/{raw}.400.jpg'
    elif has_transform and source_url:
        # Use server-rendered image which already has user's rotation and crop applied
        aws = source_url.replace('.200.', '.400.') if '.200.' in source_url else source_url
    return source_url, aws, creator, has_transform


def download(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=20) as response:
        return response.read()


def generate_attribution(provenance):
    header = """Starter grocery catalog

Contains information from Open Food Facts, made available here under the Open Database License (ODbL) 1.0. Individual database contents are available under the Database Contents License (DbCL) 1.0.

Product photos: © Open Food Facts contributors. Photos and resized WebP derivatives are distributed under Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0).

Photos were proportionally resized to at most 180 pixels and encoded as WebP. Source product pages, photo URLs, contributor names (where supplied), sizes and transformations are included in the bundled assets/catalog/provenance.json file. The freely redistributable catalog subset is bundled as assets/catalog/products.json.

Open Food Facts: https://world.openfoodfacts.org
ODbL: https://opendatacommons.org/licenses/odbl/1-0/
DbCL: https://opendatacommons.org/licenses/dbcl/1-0/
Photos: https://creativecommons.org/licenses/by-sa/3.0/

Product names, labels and quantities are community-contributed reference information. Check the exact brand, variant and package size when matching a receipt. No purchase prices, sales prices or purchase records come from this catalog. Product trademarks belong to their respective owners. Open Food Facts and its contributors do not endorse Reseebo.

Photo details
"""
    items = []
    for row in provenance:
        name = row['source_name']
        qty = row['source_quantity']
        creator = row['creator']
        p_url = row['product_url']
        i_url = row['image_url']
        items.append(f"{name} — {qty}\nPhoto: {creator} (CC BY-SA 3.0)\n{p_url}\n{i_url}\n")
    return header + "\n" + "\n".join(items)


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
        source, aws, creator, has_transform = photo_info(row)
        destination = APP_ROOT / entry['image_asset']
        downloaded_from = (aws or source) if has_transform else previous.get(row['code'], {}).get('download_url', aws or source)
        try:
            if not destination.exists() or has_transform:
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
            modifications = ('EXIF orientation; server rotation/crop; proportional resize to at most 180px; WebP quality 72'
                             if has_transform else
                             'EXIF orientation; RGB conversion; proportional resize to at most 180px; WebP quality 72')
            provenance.append(dict(
                barcode=row['code'], source_name=row.get('product_name_en') or row.get('product_name') or '',
                source_brands=row.get('brands') or '', source_quantity=row.get('quantity') or '',
                product_url=f'https://world.openfoodfacts.org/product/{row["code"]}',
                image_url=source, download_url=downloaded_from, creator=creator,
                image_license='CC-BY-SA-3.0', image_asset=entry['image_asset'],
                image_bytes=destination.stat().st_size, image_dimensions=dimensions,
                modifications=modifications,
            ))
            print(f'{index + 1}/{len(reviewed)} {row["code"]} {destination.stat().st_size} bytes', flush=True)
        except Exception as error:
            skipped.append(dict(barcode=row['code'], error=str(error)))
            print(f'SKIP {row["code"]}: {error}', flush=True)
        time.sleep(0.05)
    metadata = dict(version=1, source='Open Food Facts', retrieved_on='2026-10-10',
                    database_license='ODbL-1.0', contents_license='DbCL-1.0',
                    image_license='CC-BY-SA-3.0')
    CATALOG.joinpath('products.json').write_text(json.dumps({**metadata, 'products': entries}, ensure_ascii=False, indent=2) + '\n')
    CATALOG.joinpath('provenance.json').write_text(json.dumps({**metadata, 'products': provenance, 'skipped': skipped}, ensure_ascii=False, indent=2) + '\n')
    CATALOG.joinpath('ATTRIBUTION.txt').write_text(generate_attribution(provenance))
    print(f'Bundled {len(entries)} items, {sum(row["image_bytes"] for row in provenance)} image bytes; skipped {len(skipped)}', flush=True)


if __name__ == '__main__':
    main()

