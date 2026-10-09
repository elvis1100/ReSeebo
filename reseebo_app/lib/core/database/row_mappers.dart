import '../models/models.dart';

StoreProfile profileFromRow(Map<String, Object?> row) => StoreProfile(
  name: row['name'] as String,
  ownerName: row['owner_name'] as String,
  photoPath: row['photo_path'] as String?,
  defaultMarkupPercent: (row['default_markup_percent'] as num?)?.toDouble(),
);

Product productFromRow(Map<String, Object?> row) => Product(
  id: row['id'] as String,
  name: row['name'] as String,
  nameOnly: row['name_only'] == 1,
  brand: row['brand'] as String,
  variant: row['variant'] as String,
  size: row['size'] as String,
  category: row['category'] as String,
  barcode: row['barcode'] as String,
  photoPath: row['photo_path'] as String?,
  markupPercent: (row['markup_percent'] as num?)?.toDouble(),
  sellingPriceCents: row['selling_price_cents'] as int?,
);

Supplier supplierFromRow(Map<String, Object?> row, {String prefix = ''}) =>
    Supplier(
      id: row['${prefix}id'] as String,
      name: row['${prefix}name'] as String,
      branch: row['${prefix}branch'] as String,
      notes: row['${prefix}notes'] as String,
      dateOrder: row['${prefix}date_order'] == null
          ? null
          : NumericDateOrder.values.byName(
              row['${prefix}date_order'] as String,
            ),
    );

Receipt receiptFromRow(
  Map<String, Object?> row, {
  List<String> imagePaths = const [],
}) => Receipt(
  id: row['id'] as String,
  supplier: supplierFromRow(row, prefix: 'supplier_'),
  purchasedAt: DateTime.parse(row['purchased_at'] as String),
  hasPurchaseTime: row['has_purchase_time'] == 1,
  createdAt: DateTime.fromMillisecondsSinceEpoch(
    row['created_at'] as int,
    isUtc: true,
  ),
  imagePath: row['image_path'] as String,
  imagePaths: imagePaths,
  lineCount: row['line_count'] as int,
  totalCents: row['total_cents'] as int,
  receiptNumber: row['receipt_number'] as String,
  notes: row['notes'] as String,
);

PurchaseRecord purchaseFromRow(Map<String, Object?> row) => PurchaseRecord(
  id: row['id'] as String,
  receiptId: row['receipt_id'] as String,
  productId: row['product_id'] as String,
  supplier: supplierFromRow(row, prefix: 'supplier_'),
  purchasedAt: DateTime.parse(row['purchased_at'] as String),
  hasPurchaseTime: row['has_purchase_time'] == 1,
  recordedAt: DateTime.fromMillisecondsSinceEpoch(
    row['recorded_at'] as int,
    isUtc: true,
  ),
  originalDescription: row['original_description'] as String,
  quantity: row['quantity'] as int,
  unit: PurchaseUnit.values.byName(row['unit'] as String),
  piecesPerPack: row['pieces_per_pack'] as int,
  netAmountCents: row['net_amount_cents'] as int,
  discountCents: row['discount_cents'] as int,
  imagePath: row['image_path'] as String,
  receiptNumber: row['receipt_number'] as String,
  sequence: row['sequence'] as int,
  sourcePage: row['source_page'] as int,
);

const receiptSelect = '''SELECT r.*,
  s.id AS supplier_id, s.name AS supplier_name,
  s.branch AS supplier_branch, s.notes AS supplier_notes, s.date_order AS supplier_date_order,
  (SELECT COUNT(*) FROM purchase_lines l WHERE l.receipt_id = r.id) AS line_count
  FROM receipts r JOIN suppliers s ON s.id = r.supplier_id''';

const purchaseSelect = '''SELECT l.*,
  r.purchased_at, r.has_purchase_time, r.created_at AS recorded_at,
  COALESCE((SELECT i.image_path FROM receipt_images i
    WHERE i.receipt_id = r.id AND i.page_index = l.source_page), r.image_path) AS image_path,
  r.receipt_number,
  s.id AS supplier_id, s.name AS supplier_name,
  s.branch AS supplier_branch, s.notes AS supplier_notes, s.date_order AS supplier_date_order
  FROM purchase_lines l JOIN receipts r ON r.id = l.receipt_id
  JOIN suppliers s ON s.id = r.supplier_id''';
