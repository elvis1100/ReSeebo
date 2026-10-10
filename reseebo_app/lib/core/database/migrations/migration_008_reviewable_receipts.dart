/// Pending rows never satisfy confirmed purchase FKs. Operation results and
/// stable links intentionally outlive pending deletion during confirmation.
const reviewableReceiptsSchema = <String>[
  '''CREATE TABLE pending_receipts (
    id TEXT PRIMARY KEY, snapshot_version INTEGER NOT NULL CHECK(snapshot_version = 1),
    snapshot_payload TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision >= 1),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    supplier_name_key TEXT NOT NULL DEFAULT '', supplier_branch_key TEXT NOT NULL DEFAULT '',
    receipt_number_key TEXT NOT NULL DEFAULT '',
    search_text TEXT NOT NULL DEFAULT '',
    correction_of_receipt_id TEXT REFERENCES receipts(id) ON DELETE RESTRICT,
    base_confirmed_revision INTEGER CHECK(base_confirmed_revision >= 1),
    CHECK((correction_of_receipt_id IS NULL AND base_confirmed_revision IS NULL) OR
      (correction_of_receipt_id IS NOT NULL AND base_confirmed_revision IS NOT NULL))
  )''',
  '''CREATE UNIQUE INDEX pending_correction_source ON pending_receipts(correction_of_receipt_id)
    WHERE correction_of_receipt_id IS NOT NULL''',
  'CREATE INDEX pending_recorded ON pending_receipts(created_at, id)',
  'CREATE INDEX pending_number ON pending_receipts(supplier_name_key, supplier_branch_key, receipt_number_key)',
  '''CREATE TABLE pending_receipt_images (
    pending_id TEXT NOT NULL REFERENCES pending_receipts(id) ON DELETE CASCADE,
    page_index INTEGER NOT NULL CHECK(page_index BETWEEN 0 AND 19),
    image_path TEXT NOT NULL CHECK(length(trim(image_path)) > 0), image_hash TEXT NOT NULL,
    PRIMARY KEY(pending_id, page_index), UNIQUE(pending_id, image_hash)
  )''',
  'CREATE INDEX pending_image_hash ON pending_receipt_images(image_hash)',
  '''CREATE TABLE receipt_write_operations (
    operation_id TEXT PRIMARY KEY CHECK(length(trim(operation_id)) > 0),
    kind TEXT NOT NULL CHECK(kind IN ('pending_save', 'pending_confirm', 'confirmed_save', 'confirmed_correction')),
    canonical_digest TEXT NOT NULL, target_id TEXT NOT NULL,
    result_revision INTEGER NOT NULL CHECK(result_revision >= 1), result_payload TEXT NOT NULL,
    request_media_payload TEXT NOT NULL, created_at INTEGER NOT NULL
  )''',
  'CREATE INDEX write_operations_target ON receipt_write_operations(target_id)',
  '''CREATE TABLE receipt_evidence (
    receipt_id TEXT PRIMARY KEY REFERENCES receipts(id) ON DELETE RESTRICT,
    revision INTEGER NOT NULL CHECK(revision >= 1), snapshot_version INTEGER NOT NULL CHECK(snapshot_version = 1),
    snapshot_payload TEXT NOT NULL, updated_at INTEGER NOT NULL
  )''',
  '''CREATE TABLE receipt_revisions (
    receipt_id TEXT NOT NULL REFERENCES receipts(id) ON DELETE RESTRICT,
    revision INTEGER NOT NULL CHECK(revision >= 1), snapshot_version INTEGER NOT NULL CHECK(snapshot_version = 1),
    snapshot_payload TEXT NOT NULL, recorded_at INTEGER NOT NULL,
    PRIMARY KEY(receipt_id, revision)
  )''',
  '''CREATE TABLE ledger_entry_links (
    pending_id TEXT PRIMARY KEY,
    confirmed_receipt_id TEXT NOT NULL REFERENCES receipts(id) ON DELETE RESTRICT,
    created_at INTEGER NOT NULL
  )''',
  'CREATE INDEX ledger_link_receipt ON ledger_entry_links(confirmed_receipt_id)',
];
