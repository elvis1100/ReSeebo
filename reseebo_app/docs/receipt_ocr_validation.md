# Receipt OCR validation

The capture flow prepares local cache copies for bundled ML Kit recognition.
The full-screen photo editor stages crop, right-angle rotation, small angle
correction, contrast, and optional faded-text enhancement. Apply keeps changes;
Cancel preserves the previous selection. New photos use enhancement by default;
Compare reveals the original and enhanced versions through a draggable divider
without changing the image selected for OCR. Original photos remain intact. Reading locks competing
controls and back navigation. Small/blank/blurred inputs stop before
OCR; the owner can explicitly continue or use manual entry. Quality measurements
are conservative pixel heuristics and still need calibration on real phones.

Review shows original photos and read-only recognized text for reference.
Fields are corrected directly; the copy-from-receipt controls are removed.
Amounts represent the final amount paid for the complete purchase line, not the unit price. New reviews do not expose a discount deduction. Pieces default for unspecified units; the owner still confirms every item and changes to packs where appropriate. Product matching is optional. Confirmed unmatched names create photo-free catalog entries in the same SQLite transaction as the receipt; repeated names in one receipt share an entry. Brand, variant, and size remain unknown until edited. Quantity units, pack contents, dates and lines require confirmation.
Relevant edits clear confirmation. Missing and conflicting readings remain
editable; the SQLite validator is the final save boundary.

## Local checks

Run from `reseebo_app`:

```powershell
flutter analyze
flutter test
```

The JSON fixtures under `test/fixtures/receipts` are synthetic parser inputs,
including source-inspired format cases. They are not captured ML Kit output and
do not measure recognition accuracy. The suite also checks real SQLite atomic
saves, original-image retention, duplicate handling and database reopening.

On 10 October 2026, `flutter test --no-pub --reporter expanded --timeout 60s` passed all 189
local tests, and `flutter analyze --no-pub` reported no issues. The corpus
contains 23 synthetic JSON fixtures. A subsequent focused run passed all 27 SQLite tests, including version-3 upgrade preservation, atomic name-only catalog creation, rollback, retry safety, and adding product photos later. These results cover
parser, image, review UI/state, SQLite behavior, raised Scan navigation, and
pull-to-refresh. Photo tests use actual rendered before/after images to check
the comparison divider and shared zoom, plus real-image gestures to verify
one-finger page scrolling and two-finger photo zoom. They do not substitute for
the native and physical-phone checks below.

On 10 October 2026, an isolated Samsung phone test with Wi-Fi and mobile data disabled also verified name-only imports using the native SQLite adapter: 265 bundled starter products on first launch, a confirmed unmatched product created without a photo, preserved receipt media, idempotent retry, and later product-photo persistence. A separate process restart retained the same 266 products, one receipt, and media. Connectivity was restored and only the verification app was removed. This verifies native storage, not the full matching UI or OCR accuracy.

## Native offline smoke test

### Android SDK prerequisite

The installed Flutter SDK requests NDK `28.2.13676358`. On this Windows host,
the SDK manager wrapper failed to install it and reported `ndk` and the version
as separate missing packages. Installing the exact package through the direct
Android CLI succeeded on 9 October 2026:

```powershell
& 'C:\Android\Sdk\cmdline-tools\latest\bin\android.exe' --no-metrics --sdk='C:\Android\Sdk' sdk install 'ndk/28.2.13676358'
```

Check `C:\Android\Sdk\ndk\28.2.13676358\source.properties` before retrying
`flutter run`. This is a development SDK download; receipt reading stays local.
The CLI supports slash-separated package paths; see the
[official SDK command reference](https://developer.android.com/tools/agents/android-cli/commands/sdk).

### Test command

```powershell
flutter test integration_test/receipt_ocr_offline_test.dart -d <android-device-id>
```

Disable internet before running this test on a fresh test installation. It uses
bundled native OCR on a generated image and saves into an isolated temporary
SQLite database. It checks word bounds, confirmed cost and original image bytes
after database reopening. It does not establish accuracy on real receipts or
simulate a full application process restart.

An earlier emulator run on 9 October 2026 was blocked before app compilation
by Gradle/Java `Unable to establish loopback connection`, caused by
`UnixDomainSockets.connect0` returning `Invalid argument: connect`. The same
failure occurred with direct Gradle `--no-daemon --stacktrace`. That earlier attempt did not verify native OCR or fresh-install offline success.
Emulator airplane mode and Wi-Fi settings were restored after the attempt.

## Physical-phone verification on 9 October 2026

A separate verification app (`com.reseebo.reseebo.verification`) was installed on the connected Samsung SM-A576B. Wi-Fi and mobile data were disabled before test launch and restored afterward; the existing Reseebo app/data were preserved. The native integration test passed with bundled OCR on a generated receipt containing an English month-first date and a separate AM/PM time row. Date/time, quantity, amount and word bounds were recognized. All 265 bundled catalog entries loaded without downloads. The receipt, cost and byte-identical original image persisted after closing and reopening SQLite.

A separate fresh-launch check rendered the native Home offline, verified all 265 products and the 20% default markup, and saved verification-only settings and a product price. Flutter removes its temporary integration app afterward, so that check alone does not prove persistence across a subsequent ordinary app launch.

A guarded verification build then seeded settings and one product price through the native adapter on its first offline launch only. After force-stopping and relaunching that app, both saved values and all 265 products remained. Scrolling down a long product list and reversing the gesture restored Home search and tabs without reloading. The verification app was removed and connectivity restored afterward. This proves process-restart persistence for settings and a product price; receipt history and original images were checked separately by SQLite reopening.

The OCR check uses a generated-image native smoke test, not measured recognition accuracy on real grocery receipts.

## Physical-phone acceptance

On 10 October 2026, a fresh isolated offline photo-UI smoke test passed on the
same Samsung phone. A generated faded receipt verified one-finger page
scrolling, the original/enhanced comparison divider, visible white editor
header controls, applying edits, and bundled OCR date/time and amount parsing.
The original bytes stayed unchanged. Connectivity was restored afterward.
Raised navigation and pull-to-refresh passed local widget tests; the combined
native navigation attempt was interrupted and did not establish that result.

1. Use a fresh test installation on Android 10+ with internet disabled before
   first launch. Preserve any existing owner's app data.
2. Capture receipts from several suppliers, including faded prints, cropped or
   rotated images, long receipts split into photos, numeric product names,
   multiple prices, pack purchases and unclear dates.
3. Compare original/enhanced previews, zoom and switch original receipt pages.
   Correct fields directly, choose exact products, and confirm
   units, pack contents and amounts. Resolve overlaps and total differences.
4. Save, close the app completely and reopen offline. Verify the receipt's
   original pages, purchase history, quantities, pack contents and costs remain.
5. Record the phone/OS, receipt samples, failed readings and correction effort.
   Add anonymized actual OCR outputs as fixtures when available. Never treat a
   store name as proof that one fixed layout applies to every branch or till.
