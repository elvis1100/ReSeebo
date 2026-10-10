/// Seed identity survives owner edits and deletions, so an app update never
/// restores an unwanted starter item or overwrites a customized product.
const starterCatalogSchema = <String>[
  '''CREATE TABLE catalog_seed_entries (
    source_key TEXT PRIMARY KEY, applied_at INTEGER NOT NULL
  )''',
];
