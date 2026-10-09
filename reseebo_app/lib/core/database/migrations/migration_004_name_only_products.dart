/// Name-only imports keep identity unknown until the owner supplies it.
/// Rebuild preserves IDs; foreign keys are checked before migration commits.
const nameOnlyProductsSchema = <String>[
  '''CREATE TABLE products_new (
    id TEXT PRIMARY KEY, name TEXT NOT NULL CHECK(length(trim(name)) > 0),
    brand TEXT NOT NULL DEFAULT '', variant TEXT NOT NULL DEFAULT '',
    size TEXT NOT NULL DEFAULT '',
    name_only INTEGER NOT NULL DEFAULT 0 CHECK(name_only IN (0, 1)),
    category TEXT NOT NULL DEFAULT '', barcode TEXT NOT NULL DEFAULT '',
    photo_path TEXT, markup_percent REAL CHECK(markup_percent BETWEEN 0 AND 10000),
    selling_price_cents INTEGER CHECK(selling_price_cents BETWEEN 0 AND 100000000000),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    CHECK(name_only = 1 OR
      (length(trim(brand)) > 0 AND length(trim(variant)) > 0 AND length(trim(size)) > 0))
  )''',
  '''INSERT INTO products_new
    (id, name, brand, variant, size, category, barcode, photo_path,
     markup_percent, selling_price_cents, created_at, updated_at)
    SELECT id, name, brand, variant, size, category, barcode, photo_path,
     markup_percent, selling_price_cents, created_at, updated_at FROM products''',
  'DROP TABLE products',
  'ALTER TABLE products_new RENAME TO products',
];
