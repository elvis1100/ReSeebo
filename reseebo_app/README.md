# Reseebo app

Flutter/Dart, SQLite, app-local images, and bundled ML Kit Latin OCR. The normal entry point uses `SqliteReseeboDataAdapter`; test fixtures never populate the owner's database.

```bash
flutter pub get
flutter run
flutter analyze
flutter test
flutter build apk --release
```

Built with Flutter 3.44.8 / Dart 3.12.2. Android 10+ (API 29) and Java 17 are required. The release APK is `build/app/outputs/flutter-apk/app-release.apk`, signed with the development key for local testing. Store publishing needs a separate release signing setup. iOS requires macOS/Xcode, CocoaPods, and iOS 15.5+; iOS verification is pending.

`lib/core/adapters/i_reseebo_data_adapter.dart` owns the typed UI/service boundary. Models, parsing, pricing, OCR, file storage, and versioned database migrations live in `lib/core/`; feature screens compose their own state and widgets. OCR uses the bundled `com.google.mlkit:text-recognition:16.0.1` dependency. Manifest download metadata is not used. The release manifest removes network permissions and disables OS backup.

Money is stored as integer centavos. Cost per piece retains fractional centavos until a final amount is rounded. A line's discount is subtracted once from its entered gross amount; an already discounted receipt amount should be entered with a zero additional discount. Unclear unit/pack fields remain unresolved until the owner confirms them. Differences between detected receipt totals and saved line totals need acknowledgment; receipt-level discounts are never silently allocated.

Every purchase keeps its quantity, pack size, net amount, supplier branch, original description, and source photo. A receipt can contain up to 20 ordered original photos, saved atomically with its purchase lines through SQLite migration version 2. Existing single-photo receipts migrate without changing their images. Settings changes do not rewrite purchase snapshots. Brand/variant/size cannot be changed into a different identity after that product has purchases; create a separate product instead. Identical photo bytes are rejected at the service boundary. Matching purchase rows at adjacent photo boundaries are flagged for explicit review, because repeated purchases can be legitimate. The parser supports aligned columns, labeled quantity/unit-price/amount tables, and wrapped descriptions; multiple unlabeled prices and unknown pack sizes remain unresolved. Raw recognized text stays available for inspection and copying. Aliases are learned only from confirmed matches and can suggest multiple products without silently picking one.

Comparisons distinguish latest recorded prices from historical minima. Same-day records remain separate; where receipt times are missing, recorded order is used and disclosed. The dashboard fetches batched latest-cost summaries instead of loading every product's full comparison history. Buying estimates round up to whole recorded packs, show dates and missing records, and separate travel/delivery costs. Basket groups use the lowest product subtotal and show supplier alternatives; extra costs can change the best overall trip. Prices and supplier availability are historical evidence, not live offers. Calculated selling prices are suggestions, not DTI SRP, and tubo is estimated gross profit before operating expenses.

Receipts save atomically with lines and confirmed aliases. A retry with the same operation ID/content returns the original result. Image hashes and supplier/receipt numbers flag possible duplicate imports for explicit review. Photos are copied into persistent storage before their references are saved; failed saves preserve previous references.

Physical-device verification:

1. Install the release APK onto an Android 10+ phone. Turn off internet **before the first launch**.
2. Open the empty app, set store details and an explicit default markup, and add a product photo.
3. Scan/import real printed receipts from at least two suppliers. Try a long receipt with ordered, slightly overlapping photos; resolve overlapping rows and confirm that no purchases are counted twice. Confirm product identity and pack sizes; save a repeated purchase and two same-day purchases.
4. Force-stop and reopen the app. Check receipts, original images, product/store photos, aliases, and settings.
5. Compare the exact same product: latest per supplier, historical minimum, prior purchase changes, suggested selling price, and estimated gross profit. Check unset and 0% markup.
6. Plan an awkward quantity (e.g. 21 pieces in 10-piece packs), add per-supplier travel costs, and check basket missing-price rows. Retry a duplicate import, cancel capture, and deny camera/gallery access where the OS permits it.

Completed development checks: `flutter analyze` is clean; all 83 host tests pass, including migration, multiple-photo rollback/reopen, parser layouts, duplicate handling, dashboard query ordering/batching, guarded async navigation, and screens at phone width; the release APK builds and its signature verifies. APK inspection confirms bundled OCR model files and Inter, with no internet permission and backup disabled. Physical-device checks for the camera, native OCR on real receipts, first-launch airplane-mode operation, and full process restart remain pending, as does iOS verification.

An automated phone check uses a clearly synthetic printed receipt in two overlapping photos, in its own temporary database. With the phone already offline, run:

```bash
flutter drive --keep-app-running --timeout=180 --driver=test_driver/integration_test.dart --target=integration_test/offline_device_test.dart -d <device-id>
```

Keep `--keep-app-running`: the driver's default cleanup uninstalls the app and deletes its data. After testing, reinstall the normal release APK with `adb install -r` to restore the normal entry point while retaining records. Use the phone's main unlocked profile during the check.

The driver provides an alternative to a VM golden-stream error encountered with `flutter test` in this SDK. The automated phone run has not completed successfully. Its assertions cover native OCR, field mapping, overlap identification, and SQLite reopen persistence; follow the manual steps above for real receipts, camera behavior, and a full app process restart.
