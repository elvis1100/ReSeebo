# Product and receipt review — 10 October 2026

The product editor requires a full product name and size/unit. Category and
photo are optional. Separate Brand, Variant, Barcode and Selling settings
controls have been removed. Existing stored identity, barcode and pricing
values remain intact. New products use the full name instead of separate
brand/variant fields; exact automatic matching requires the entire name and
size and rejects competing catalog entries. A known identity with purchase
history cannot be changed into another product or package size.

Categories are stored offline in SQLite migration 006. The migration imports
existing product categories; starter categories are recorded when their
products are seeded. The dropdown supports Uncategorized, adding a category,
and removing a selected category. Category names deduplicate without regard
to capitalization. Removal clears product assignments atomically and retains
products, receipt lines, original images and purchase history. Category edits
persist immediately, independently of saving or cancelling the product form.

Product details already select each supplier's latest recorded purchase and
compare its per-piece cost; older prices remain in the history timeline. The
recent-price cards now show supplier branches, and their receipt links work
without a caller-supplied callback. Product titles use the saved display name.
These are recorded purchase prices, not live store prices.

The Home tab is labeled Receipts. Receipt details now group supplier, date,
receipt number, total, item count and total pieces in one summary card. The
original photos use compact thumbnails which open a full-size zoom viewer.
Compact purchase cards retain quantity/pack conversion, line amount, cost per
piece, discounts when present, receipt description, source photo and access to
product comparisons. Notes and the saved timestamp remain available.

Verification includes full Flutter tests, analyzer checks, SQLite upgrades,
category deduplication/removal and reopening, preservation of hidden product
fields, exact full-name matching, working supplier receipt links, and receipt
layout at 360 pixels with enlarged text. Native offline persistence checks use
an isolated verification application; the normal application is not replaced.

Results: all 231 Flutter tests passed. Focused storage and widget checks also
passed after the final safeguards, and `flutter analyze` reported no issues.
On Android, two offline native checks and one separate process-restart check
passed. The new full-name product, its size and category survived restart;
removing its category preserved the saved six-line receipt. Connectivity was
restored to airplane mode off / Wi-Fi on. This is native storage/OCR proof;
compact layout verification is from Flutter widget tests, not a visual phone
audit. Diagnostic logs remain under `/tmp/reseebo-catalog-*.log`.
