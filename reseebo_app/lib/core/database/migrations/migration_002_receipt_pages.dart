/// Existing single-image receipts become page zero without changing their files.
const receiptPagesSchema = <String>[
  '''CREATE TABLE receipt_images (
    receipt_id TEXT NOT NULL REFERENCES receipts(id) ON DELETE RESTRICT,
    page_index INTEGER NOT NULL CHECK(page_index >= 0),
    image_path TEXT NOT NULL CHECK(length(trim(image_path)) > 0),
    image_hash TEXT NOT NULL,
    PRIMARY KEY(receipt_id, page_index), UNIQUE(receipt_id, image_hash)
  )''',
  '''INSERT INTO receipt_images(receipt_id, page_index, image_path, image_hash)
    SELECT id, 0, image_path, image_hash FROM receipts''',
  'CREATE INDEX receipt_pages_hash ON receipt_images(image_hash)',
  'ALTER TABLE purchase_lines ADD COLUMN source_page INTEGER NOT NULL DEFAULT 0 CHECK(source_page >= 0)',
];
