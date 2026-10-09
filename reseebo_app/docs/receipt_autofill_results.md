# Receipt autofill verification — 10 October 2026

Receipt autofill now uses explicit quantity markers, spatial row association,
word-box skew estimates, labeled columns, and exact centavo arithmetic for
unlabeled unit-price/line-total pairs. It supports quantity rows before or after
a description, `PC` and `X`, and same-row `@` prices. `X` establishes a count,
not a pack conversion. Missing counts never borrow product-size numbers.

Purchase dates exclude issue/permit/accreditation dates. Ambiguous numeric dates
show both interpretations, retaining the clock. An owner can remember the order
for a selected supplier branch, or change/clear it in the supplier editor.
SQLite migration 005 adds this preference without rewriting purchase history.

A unique catalog identity can prefill when brand, variant, and size are explicit
(including equivalent metric units). Unique confirmed aliases continue to
prefill. Partial identities, competing products, and conflicting sizes remain
owner choices. Reloads and delayed alias responses preserve manual edits.

Review fields identify extracted values and product-match provenance. All
purchases still require owner confirmation and atomic database validation.
Original photos and OCR evidence remain available in the existing review panel.

## Downloaded samples and actual OCR

Photos were downloaded to `/tmp/reseebo-receipt-samples` and independently
redownloaded with the checked-in script to `/tmp/reseebo-receipt-download-check`.
The app never downloads these files. Copyright remains with the source authors;
original photos are not redistributed in app assets or committed to this repo.
Each download manifest records source URLs and SHA-256 hashes.

| Sample | Source | Observed layout / limitation |
| --- | --- | --- |
| DALI | [First-hand shopping post](https://note.com/oyako_tagaytay/n/n929317daedad) | Descriptions above PC rows; a multi-quantity row with a unit price; issued dates in the footer. OCR misses counts and misreads some digits. |
| WalterMart | [First-hand grocery post](https://note.com/oyako_tagaytay/n/nef72d3b3ba84) | Item/price/quantity/amount headings; code continuation rows; mixed counted and weighed goods; separate payment and VAT sections. Whole-piece quantities remain unresolved when evidence is missing or fractional. |
| Puregold | [First-hand shopping post](https://note.com/norris_iloilo/n/n2f7474d537f5) | Faded dotted print, numeric rows and coded descriptions. OCR is too incomplete for reliable autofill on this image. |
| Savemore / Festive Market | [Same first-hand post](https://note.com/norris_iloilo/n/n2f7474d537f5) | Same-row quantity, abbreviated product, @ unit price, and right-aligned amount. Six product lines, ten purchased units; issue date excluded. |
| SM Hypermart | [Historical first-hand photo](https://jeffwerner.ca/security_use_and_packaging/) | Receipt occupies a small area of a bag photo; insufficient detail for reliable OCR. This is a negative sample, not proof of SM format support. |
| DMS POS demonstration | [Vendor sample printouts](https://mydmsoft.com/) | Labeled columns and receipt-wide senior/VAT discounts. Crop out the explanatory panel using the app's local transform before OCR. This is a vendor example, not a real customer purchase. |

Native ML Kit output was captured on the connected Android phone, both directly
and through `LocalReceiptImageService` enhancement. Sanitized item/total-region
records are in `test/fixtures/public_receipts/`; tokens and bounds are retained,
without transcription corrections. Public photos contain additional identifying
fields: complete diagnostic logs are opt-in and local under `/tmp`, not repo
fixtures or normal app logging.

The Wellbest and DALI layouts supplied in chat are separately covered by
explicitly transcribed/synthetic tests. Their attached originals are not
available as local files, so this does not prove recognition of those exact
photos. A chain name never activates guessed fixed coordinates or date order.

## Earlier offline phone results

These are counts of populated suggestions, **not accuracy percentages**. Some
recognized amounts/names disagree with the inspected pixels and require owner
correction. Missing digits are never reconstructed just to make totals match.

| Sample | Product lines | Quantities filled | Amounts filled | Receipt total / transaction date |
| --- | ---: | ---: | ---: | --- |
| DALI | 10 | 5 | 6 | ₱602.75; date unreadable |
| WalterMart | 18 | 0 | 18 | ₱1,502.62; 21 Nov 2025, 2:10 PM |
| Puregold | 0 | 0 | 0 | Unresolved; faded print |
| Savemore | 6 | 6 | 5 | ₱197.60; 17 Apr 2026, 6:47 PM |
| SM Hypermart | 0 | 0 | 0 | Unresolved; tiny receipt in photo |
| DMS POS demonstration | 3 | 3 | 2 | ₱161.45; 25 Oct 2019, 9:05:42 AM |

The POS demonstration's third line remains unresolved because OCR reads unit
price `22.90` and total `44.09` for two units; the arithmetic disagrees. The
receipt-wide discount stays an owner decision. In that build, Savemore's fifth
amount remained unresolved when the @ marker/description was misread; the
follow-up below resolves this case using exact printed arithmetic. Original and enhanced
recognition have different failures, so enhancement alone is not an accuracy
claim; existing photo controls allow owner review and retry.

## Quantity, amount, name and matching follow-up

The next parser pass resolves a missing `@` only when the extracted count and
one trailing unit-price column multiply exactly to the printed total. Adjacent
numeric rows without headers use the same check. A trailing whole count with a
wrapped unit-price/total pair also resolves only on exact agreement. Bare
monetary values such as `290.00 180.38` cannot become a count of 290: decimal
counts require an explicit count marker or a quantity heading. `PO`/`PČ` on a
numeric count row preserve the count while leaving pieces/packs unconfirmed.

Purchased counts and trailing prices are removed from editable product names;
raw OCR remains unchanged. Damaged money text can be removed from a name without
turning it into a price. Product sizes (including `1.5L`), internal unit text,
and pack-conversion details remain available. Exact catalog matching accepts a
complete identity with missing spaces, as well as ounce and counted sizes
such as `12s`. It still rejects missing fields, conflicting sizes and duplicate
catalog identities. Correcting a description immediately retries exact matching.
No catalog products are invented from uncertain OCR.

Local replay of the downloaded enhanced Savemore OCR now fills all six counts
and all six amounts, including the fifth line at ₱41.00 (previously blank).
The enhanced WalterMart replay now fills the noodles count of two with ₱37.00,
previously missing. These are local parser replays of captured native OCR, not
new photo-recognition or physical-device results. Unreadable digits, fractional
weights and inconsistent arithmetic still require owner review. Both date
choices and the supplier date preference are unchanged.

The shared error, danger and price-increase foreground is dark burgundy
`#7F1D1D`, paired with the existing pale red status surface and forest green.

Follow-up validation: all **222 Flutter tests** pass; `flutter analyze` reports
no issues. The earlier offline first-launch and process-restart results below
apply to the preceding device build; this follow-up does not change storage or
the OCR model and has not been rerun on a phone.

## Verification boundaries

Final checks: `flutter analyze` reported no issues; all **215 Flutter tests**
passed; the two offline native tests and the separate process-restart check
passed. The phone's original connectivity settings were restored afterward.

- Parser replay tests check both raw and enhanced native OCR evidence, including
  malformed amounts, missing quantities, conflicting arithmetic, total labels,
  and preserving incomplete rows. Synthetic cases cover the supplied Wellbest
  and DALI arithmetic, numeric brands/codes, ambiguous dates, and negative cases.
- State/widget checks cover identity matching, date choices, branch preferences,
  manual corrections, and late matching responses. SQLite checks cover upgrade
  from older versions, reopening, preference clearing, history and image retention.
- Device tests use the opt-in `.verification` application ID and separate
  databases. Offline native smoke tests and public sample diagnostics are
  distinct from whole-field accuracy measurements.
- A reviewed Savemore receipt is saved, the verification process is stopped, and
  another test invocation reopens it offline. It checks six lines, amounts,
  purchase date/time, the exact original photo bytes, and the supplier preference.
  Known amounts supplied as owner corrections are not counted as OCR successes.

Faded, cropped, or misread text can still produce incomplete or incorrect
suggestions. An arithmetic match validates amounts, not the product identity.
The owner must inspect the receipt before confirming. Weighed goods require
manual handling under the current whole-piece model; no weight conversion is
invented. No additional AI model or cloud service was introduced.

## Reproduce

Run from `reseebo_app/`:

```bash
python scripts/download_receipt_samples.py --output /tmp/reseebo-receipt-samples
flutter analyze
flutter test
adb push /tmp/reseebo-receipt-samples/*.jpg /data/local/tmp/
ORG_GRADLE_PROJECT_reseeboVerification=true flutter build apk --debug --target=integration_test/public_receipt_samples_test.dart --dart-define=RECEIPT_SAMPLE_DIR=/data/local/tmp
ORG_GRADLE_PROJECT_reseeboVerification=true flutter test integration_test/public_receipt_samples_test.dart -d <device-id> --no-uninstall --dart-define=RECEIPT_SAMPLE_DIR=/data/local/tmp
adb shell am force-stop com.reseebo.reseebo.verification
ORG_GRADLE_PROJECT_reseeboVerification=true flutter test integration_test/public_receipt_samples_test.dart -d <device-id> --dart-define=RECEIPT_SAMPLE_DIR=/data/local/tmp --dart-define=RECEIPT_VERIFY_RESTART=true
```

For fresh-install offline proof, first remove only the verification app for the
active Android user, disable internet on the phone, and restore the prior
connectivity afterward. The host needs build dependencies installed beforehand.
The isolated prebuild ensures Flutter reads the verification package ID from the existing APK before starting the test; this also prevents cleanup targeting a stale ordinary-app APK ID. Do not uninstall the owner's ordinary `com.reseebo.reseebo` app. The first test
invocation uses `--no-uninstall` so the ledger survives Flutter test cleanup, and must pass before the restart invocation; the latter removes only its
verification database/media directory after success.
