const supplierDateOrderSchema = <String>[
  "ALTER TABLE suppliers ADD COLUMN date_order TEXT CHECK (date_order IS NULL OR date_order IN ('monthFirst', 'dayFirst'))",
];
