# Reseebo

Offline receipt scanning and supplier price history for Philippine sari-sari stores. Flutter/Dart, local SQLite, and bundled ML Kit OCR; no account or runtime downloads.

Run from this folder:

```bash
flutter pub get
flutter run -d <android-device-id>
flutter analyze
flutter test
```

The bottom bar places a raised **Scan Receipt** action between **Home** and **Settings**. Home has a compact green gradient store card with the store name and markup; tapping the card opens Settings. Counts appear in the Receipts and Products tabs. **+ Add** sits beside the Products search field. Coordinated scrolling restores search and tabs when scrolling back, and pressed effects follow rounded control shapes. Both Home and Settings show the logo and **Reseebo**. Pull down to refresh Home, Settings, or product details; Settings preserves unsaved edits. Product details focus on supplier comparison and price history, without the restock/profit planner. New store profiles start as **Sari-sari Store**, with **20% default markup**. The fixed header icon is a placeholder for the future app logo; Settings does not edit it.

Use **Edit / enhance photo** to open the full-screen editor for crop, rotate, straighten, and contrast. Photos are enhanced by default, with an Enhanced badge on the preview. The scan page supports one-handed scrolling; full-screen editing provides more space for zooming. **Compare** reveals the preserved original and enhanced photo with a draggable divider, without changing the OCR selection. The header check applies edits; the back arrow cancels them. Faded-text enhancement and Reset edits share a compact control row. Original photos remain intact, and reading disables competing actions. Review a scan by correcting supplier/date and item fields directly, optionally matching existing products, and confirming product names, quantities, and costs. Unmatched items create name-only catalog entries without photos when the receipt is saved; add a photo later from Edit product. Original photos and recognized text remain available for reference. Pieces are selected by default; select Packs and enter pack contents when needed. The unit selector and date/time selections use green. Review shows the purchase date only; time controls and optional receipt number and notes inputs are hidden without clearing existing values. The Product name field sits below optional product matching, with a matte-green field background and Cost representing the total for the item. Clear dates/times and previously confirmed product descriptions prefill locally; uncertain fields remain editable.

The bundled catalog includes **288 Philippine grocery products**, with 180px WebP photos totaling about **1.19 MiB**. It supplies product identities, without sample purchases or prices. Existing settings, custom products and receipt history survive upgrades. Catalog seeding preserves edited/deleted starter items and existing barcode/identity matches. Read [catalog sources and licenses](docs/starter_catalog.md); photo credits are also available offline in Settings.

Android uses persistent local storage and original receipt images. Browser mode is a labeled sample-data demo. Rebuilding or updating the same signed app keeps local data; uninstalling or clearing app storage removes it.

For native offline OCR and persistence checks, see [receipt validation](docs/receipt_ocr_validation.md). Local parser tests and synthetic images do not establish accuracy on every real receipt.
