/// Receipt abbreviations are learned for a saved supplier branch only. Existing
/// global aliases remain untouched because their original supplier is unknown.
const supplierProductAliasesSchema = <String>[
  '''CREATE TABLE supplier_product_aliases (
    id TEXT PRIMARY KEY,
    supplier_id TEXT NOT NULL REFERENCES suppliers(id),
    product_id TEXT NOT NULL REFERENCES products(id),
    description TEXT NOT NULL,
    description_key TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(supplier_id, description_key, product_id)
  )''',
  'CREATE INDEX supplier_aliases_lookup ON supplier_product_aliases(supplier_id, description_key)',
];
