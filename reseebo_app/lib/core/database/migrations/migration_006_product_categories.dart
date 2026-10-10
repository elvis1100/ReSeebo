/// Categories remain available independently of product assignments. Removal
/// clears assignments without changing products, receipts or purchase lines.
const productCategoriesSchema = <String>[
  '''CREATE TABLE product_categories (
    name TEXT PRIMARY KEY COLLATE NOCASE CHECK(length(trim(name)) > 0)
  )''',
  '''INSERT OR IGNORE INTO product_categories(name)
    SELECT trim(category) FROM products WHERE trim(category) != ''
    ORDER BY category COLLATE NOCASE''',
];
