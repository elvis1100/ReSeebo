# ReSeebo

Offline receipt scanning, purchase history, and supplier price comparison for sari-sari stores. Photos and data stay on your phone; no account, API key, or runtime model download is required.

## Install on an Android phone

1. Copy [the release APK](releases/reseebo-1.0.0.apk) to your phone (Android 8.0 or newer).
2. Open it in Files and allow **Install unknown apps** for Files when Android prompts you. Install ReSeebo, then turn that permission off again.
3. Open ReSeebo, scan or select a receipt photo, choose an OCR model, and tap **Read receipt**. Review the supplier, date, quantities, and prices before saving.

**PP-OCRv5 Mobile** is the faster Paddle option; PP-OCRv6 Medium takes longer. The app works offline. Updating with the same signing key preserves data; uninstalling or clearing app storage deletes local data.

The supplied APK is approximately 344 MB because OCR models are bundled. [SHA-256 checksum](releases/reseebo-1.0.0.apk.sha256). This demo release uses the project's debug signing key, not a store distribution key. It was built and inspected; the documented offline device checks used an isolated debug build.

## Run from source

Install Flutter and the Android SDK. Enable Developer options and USB debugging on your phone, connect it by USB, and accept its debugging prompt. From this folder:

```bash
flutter pub get
flutter devices
flutter run -d <device-id>
```

Build with `flutter build apk --release`; output: `build/app/outputs/flutter-apk/app-release.apk`. Install the supplied APK by USB without clearing app data:

```bash
adb install -r releases/reseebo-1.0.0.apk
```

## Technical disclosure

- **Framework/storage:** Flutter, Dart, and on-device SQLite through `sqflite`.
- **AI models/runtime:** bundled Google ML Kit Latin text recognition, PaddleOCR PP-OCRv5 Mobile and PP-OCRv6 Medium; ONNX Runtime Android 1.21.1, OpenCV 4.5.3.0, and a Kotlin/coroutines native bridge. Parsing and cost calculations use local Dart code. No cloud AI API is called at runtime.
- **Libraries/APIs:** `image_picker` (Android camera/photo picker), `image`, `path`/`path_provider`, `crypto`, `intl`, `uuid`, `pdf`, and `printing` for photos, files, validation, formatting, and document export.
- **AI development tools:** OpenAI Codex assisted coding, debugging, tests, and documentation.
- **Existing code/assets:** adapted Apache-2.0 PaddleOCR Android SDK; Inter font (SIL OFL 1.1); supplied ReSeebo branding; bundled Open Food Facts catalog data (ODbL/DbCL) and contributor photos (CC BY-SA 3.0). The Open Food Facts API was used during development; catalog content is bundled offline.

Exact revisions and local changes: [models](assets/ocr/model_manifest.json), [SDK](android/paddle_ocr/source_manifest.json). Licenses: `assets/ocr/LICENSE-*.txt`, [Inter](assets/fonts/OFL.txt), [catalog attribution](assets/catalog/ATTRIBUTION.txt). See [device verification](docs/verification/2026-10-10-paddle-device-acceptance.md) for tested behavior and accuracy limits.

## License

ReSeebo's original source code is licensed under [Apache-2.0](../LICENSE). Third-party code, models, fonts, and catalog assets retain their respective licenses; see [notices](../NOTICE) and bundled attribution files.
