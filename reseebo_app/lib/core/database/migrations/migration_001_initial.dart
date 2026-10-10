/// Version 1 preserves amounts in centavos and costs as net/total-pieces.
/// Supplier branches and owner-confirmed aliases intentionally remain distinct.
const initialSchema = <String>[
  '''CREATE TABLE store_profiles (
    id INTEGER PRIMARY KEY CHECK(id = 1), name TEXT NOT NULL DEFAULT '',
    owner_name TEXT NOT NULL DEFAULT '', photo_path TEXT,
    default_markup_percent REAL CHECK(default_markup_percent BETWEEN 0 AND 10000),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
  )''',
  '''CREATE TABLE products (
    id TEXT PRIMARY KEY, name TEXT NOT NULL CHECK(length(trim(name)) > 0),
    brand TEXT NOT NULL CHECK(length(trim(brand)) > 0),
    variant TEXT NOT NULL CHECK(length(trim(variant)) > 0),
    size TEXT NOT NULL CHECK(length(trim(size)) > 0),
    category TEXT NOT NULL DEFAULT '', barcode TEXT NOT NULL DEFAULT '',
    photo_path TEXT, markup_percent REAL CHECK(markup_percent BETWEEN 0 AND 10000),
    selling_price_cents INTEGER CHECK(selling_price_cents BETWEEN 0 AND 100000000000),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
  )''',
  '''CREATE TABLE product_aliases (
    id TEXT PRIMARY KEY, product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    description TEXT NOT NULL CHECK(length(trim(description)) > 0),
    description_key TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    UNIQUE(product_id, description_key)
  )''',
  '''CREATE TABLE suppliers (
    id TEXT PRIMARY KEY, name TEXT NOT NULL CHECK(length(trim(name)) > 0),
    branch TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
    name_key TEXT NOT NULL, branch_key TEXT NOT NULL,
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    UNIQUE(name_key, branch_key)
  )''',
  '''CREATE TABLE receipts (
    recorded_order INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
    operation_id TEXT NOT NULL UNIQUE, content_digest TEXT NOT NULL,
    supplier_id TEXT NOT NULL REFERENCES suppliers(id) ON DELETE RESTRICT,
    purchased_at TEXT NOT NULL, purchased_date TEXT NOT NULL, purchase_time TEXT,
    has_purchase_time INTEGER NOT NULL CHECK(has_purchase_time IN (0, 1)),
    image_path TEXT NOT NULL, image_hash TEXT NOT NULL,
    receipt_number TEXT NOT NULL DEFAULT '', receipt_number_key TEXT NOT NULL DEFAULT '',
    notes TEXT NOT NULL DEFAULT '', raw_text TEXT NOT NULL DEFAULT '',
    total_cents INTEGER NOT NULL CHECK(total_cents BETWEEN 1 AND 100000000000),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
  )''',
  '''CREATE TABLE purchase_lines (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
    receipt_id TEXT NOT NULL REFERENCES receipts(id) ON DELETE RESTRICT,
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    original_description TEXT NOT NULL CHECK(length(trim(original_description)) > 0),
    quantity INTEGER NOT NULL CHECK(quantity BETWEEN 1 AND 1000000),
    unit TEXT NOT NULL CHECK(unit IN ('piece', 'pack')),
    pieces_per_pack INTEGER NOT NULL CHECK(pieces_per_pack BETWEEN 1 AND 1000000),
    total_pieces INTEGER NOT NULL CHECK(total_pieces = quantity * pieces_per_pack),
    gross_amount_cents INTEGER NOT NULL CHECK(gross_amount_cents BETWEEN 1 AND 100000000000),
    discount_cents INTEGER NOT NULL CHECK(discount_cents >= 0 AND discount_cents < gross_amount_cents),
    net_amount_cents INTEGER NOT NULL CHECK(net_amount_cents = gross_amount_cents - discount_cents),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    CHECK(unit != 'piece' OR pieces_per_pack = 1)
  )''',
  'CREATE INDEX aliases_description ON product_aliases(description_key)',
  'CREATE INDEX lines_product ON purchase_lines(product_id)',
  'CREATE INDEX lines_receipt ON purchase_lines(receipt_id)',
  'CREATE INDEX receipts_purchase_date ON receipts(purchased_date, recorded_order)',
  'CREATE INDEX receipts_image_hash ON receipts(image_hash)',
  'CREATE INDEX receipts_number ON receipts(supplier_id, receipt_number_key)',
];
