# Bundled Philippine grocery starter catalog

The app ships 265 Open Food Facts products tagged as sold in the Philippines, with explicit brands, product descriptions, package quantities and downloaded product photographs. Products are suggestions for the owner's catalog. There are no sample purchases, suppliers, costs, markups or selling prices.

Research date: 2026-10-09. The source API is community-maintained; source-backed does not mean every package has been manually verified against a current Philippine wholesaler. Owners must check exact brand, variant and size when matching their receipts. Different package sizes stay separate. Missing or conflicting quantities, shorthand color-only variants and questionable descriptions were excluded rather than completed by guessing. The subset focuses on shelf groceries, snacks, noodles, canned food, seasonings, coffee, milk and drinks; it is not an exhaustive wholesaler inventory.

## Sources and redistribution

- Product dataset: [Open Food Facts structured API](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/), filtered by `countries_tags=en:philippines`. The public `.net` read endpoint was used because `.org` returned HTTP 503 during this research.
- Image downloads: [official AWS image dataset instructions](https://openfoodfacts.github.io/openfoodfacts-server/api/aws-images-dataset/). Selected front-image records identify the matching raw photograph in the AWS dataset; missing AWS images fall back to the source's small front image, downloaded sequentially.
- Licenses: [Open Food Facts licensing guidance](https://openfoodfacts.github.io/openfoodfacts-server/api/tutorials/license-be-on-the-legal-side/). Dataset subset and its derived descriptions remain under [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/); individual contents use [DbCL 1.0](https://opendatacommons.org/licenses/dbcl/1-0/). Photos, including the resized WebP derivatives, remain under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/).

`assets/catalog/products.json` is the distributable database subset. `provenance.json` records every source name, brand, quantity, barcode, product page, photo URL, downloaded photo URL, supplied contributor, dimensions, byte size and transformation. `ATTRIBUTION.txt` is bundled for the in-app credits. The license notices apply to these catalog resources, not the owner's private receipts and custom additions.

The 265 photos total 1,127,718 bytes (about 1.08 MiB), with no photo larger than 9,344 bytes. Each photo is proportionally resized to at most 180×180 pixels, encoded in WebP at quality 72, and loaded with an `asset:` URI. All data, provenance, credits and photos are bundled. Launch, catalog search and receipt matching require no runtime downloads.

## Seeding and upgrades

SQLite migration 3 adds `catalog_seed_entries`. On adapter open, a single transaction inserts previously unseen seed identities. Existing products with the same barcode or normalized brand/variant/size are preserved. The seed ledger prevents owner-edited or deleted starter items from being reintroduced. Product prices, photos, purchase history, custom products and store settings are never overwritten by a later seed run.

Changing the source subset only adds newly keyed items on the next launch; editing a seed description does not silently replace a user's saved identity. SQLite adapter tests inject an empty or controlled starter subset where isolation is needed. Tests verify repeat opening, custom edits, deletions, existing matches, failure rollback, bundled-photo availability and editable asset photo references.

## Rebuilding assets

`python scripts/build_starter_catalog.py scripts/reviewed_starter_products.json` rebuilds the checked-in reviewed subset. The script also accepts a new `reviewed-products.json` and consumes a reviewed list of source API records (fields used: `code`, `product_name`, `product_name_en`, `brands`, `quantity`, `categories_tags`, `image_front_small_url`, `images`). It requires Python and Pillow, downloads only during development, keeps existing thumbnails and writes the two bundled manifests. Review source descriptions and image labels before expanding the list. Preserve source metadata and the attribution notices when redistributing the subset.
