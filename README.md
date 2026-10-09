# Reseebo

Offline receipt, supplier-price, and tubo tracking for sari-sari stores. The Flutter app is in [`reseebo_app/`](reseebo_app/). Android 10+ is the primary target; iOS 15.5+ is configured as a secondary target.

```bash
cd reseebo_app
flutter pub get
flutter run
```

Install Flutter and add its `bin` directory to `PATH`. The commands below work in Bash and PowerShell from the app directory.

```bash
flutter analyze
flutter test
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Receipt capture, OCR, review, product matching, SQLite records, photos, comparisons, and planning use on-device services. The Latin OCR model and Inter font ship with the app. Dependency downloads happen during development; app operation requires no account, API key, or internet. There is no production demo-data seeding.

Start by scanning/importing a receipt (up to 20 ordered photos for a long receipt), confirm its supplier/date and each product's brand, variant, size, quantity, pack conversion, and amount, then save. Identical imported photos are skipped; possible overlapping purchase rows require a decision to keep both or remove the overlap. Every original photo is preserved. Products, store details, and markup can also be entered from the dashboard. Profile setup is optional. After saving, open a product’s “Compare prices” action. Prices and history share one tab; optional selling-price and whole-pack restock controls share another. The basket planner lets you search and select products, then groups them by recorded supplier prices and shows extra costs separately.

See [the app guide](reseebo_app/README.md) for data rules and physical-device checks. Project requirements remain in [scope](1.%20Project_Scoping_Prompt.md), [UI brief](1.1%20Frontend_Prompt.md), [local services brief](1.2%20Backend_Integration_Prompt.md), and [the idea](SARI-SARI-RECEIPT-IDEA.md).
