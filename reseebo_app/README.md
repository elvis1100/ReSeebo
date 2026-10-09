# Reseebo

Offline receipt scanning, supplier price history, and purchase planning for Philippine sari-sari stores. Flutter/Dart, local SQLite, and bundled ML Kit OCR; no account or runtime downloads.

Run from this folder:

```bash
flutter pub get
flutter run -d <android-device-id>
flutter analyze
flutter test
```

Home keeps a floating Scan Receipt button; Add product sits inside the Products tab. Both Home and Settings show the logo and **Reseebo**, with a reload action. The store profile starts as **Sari-sari Store**, with **20% default markup**. The fixed header icon is a placeholder for the future app logo; Settings does not edit it. Home keeps its floating Scan Receipt button. Review a scan by checking supplier/date, matching exact products, and confirming quantities and the final amount paid. Pieces are selected by default; select Packs and enter pack contents when needed. Optional receipt details and photo tools expand on demand. Clear dates/times and previously confirmed product descriptions prefill locally; uncertain fields remain editable.

The bundled catalog includes **265 Philippine grocery products**, with 180px WebP photos totaling about **1.08 MiB**. It supplies product identities, without sample purchases or prices. Existing settings, custom products and receipt history survive upgrades. Catalog seeding preserves edited/deleted starter items and existing barcode/identity matches. Read [catalog sources and licenses](docs/starter_catalog.md); photo credits are also available offline in Settings.

Android uses persistent local storage and original receipt images. Browser mode is a labeled sample-data demo. Rebuilding or updating the same signed app keeps local data; uninstalling or clearing app storage removes it.

For native offline OCR and persistence checks, see [receipt validation](docs/receipt_ocr_validation.md). Local parser tests and synthetic images do not establish accuracy on every real receipt.
