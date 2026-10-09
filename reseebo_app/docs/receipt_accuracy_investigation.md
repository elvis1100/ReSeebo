# Receipt accuracy investigation — 10 October 2026

## Decision

Keep the current bundled ML Kit engine while fixing measured association and
monetary-token failures. The exact owner Wellbest and DALI photos now confirm
that the current parser loses or misassigns fields even when OCR reads their
characters. PP-OCRv5 improves some text but does not resolve these failures.
This is evidence against a blind engine replacement, not proof that ML Kit is
the best engine for all suppliers.

No production extraction behavior, model packaging, catalog, or SQLite schema
was changed in this investigation.

## Measured results

The Savemore photo was compared against the existing independently annotated
six-item truth. ML Kit was freshly captured on Samsung SM-A576B, Android 16.
PP-OCRv5 ran locally on desktop CPU through RapidOCR 3.10.0 and ONNX Runtime
1.31.0, using mobile detection, English recognition, and a PP-OCRv4 orientation
classifier. Its JSON records include model hashes. It has not been deployed or
timed on Android. Both engines' output was replayed through the same Dart parser.

| Engine and pixels | Exact descriptions | Correct counts | Correct line amounts | Expected rows correct on all three fields |
| --- | --- | --- | --- | --- |
| ML Kit, original | 4/6 | 6/6 | 5/6; one unresolved | 3/6 |
| ML Kit, enhanced | 3/6 | 6/6 | 6/6 | 3/6 |
| PP-OCRv5, original | 5/6 | 5/6; one wrong | 5/6; one unresolved | 4/6 |
| PP-OCRv5, identical enhanced pixels | 4/6 | 5/6; one wrong | 5/6; one unresolved | 3/6 |

All four passes identify six expected rows, no extra/unmatched rows, and the
correct receipt total. Original and enhanced passes are readings of one receipt,
not independent samples. Description scoring ignores case/spacing; it does not
establish an exact catalog match. The truth does not score pack conversion,
discounts, or quantity units, so complete-row counts apply only to declared fields.

PP-OCRv5 reads OISHI correctly on the original, whereas ML Kit reads 01SHI.
Both read the printed 200ml as 200m1. PP-OCRv5 reads the Monde purchased count as
11 rather than 1; arithmetic inconsistency leaves its line amount unresolved,
but does not prevent the wrong quantity suggestion. A matching receipt total
therefore cannot certify the extracted purchase lines.

Desktop inference on the four original public photos took approximately
3.6–7.0 seconds per image; this is neither Android latency nor a production
performance benchmark. DALI, WalterMart, and Puregold outputs have no complete
independent truth in this investigation and are not assigned accuracy scores.
Puregold produced text, but recognition completeness is not correctness.

## Exact owner samples: captured and scored

The owner supplied local originals: `20261009_201745.jpg` is Wellbest and
`20261009_201820.jpg` is Batangas DALI. Both were inspected at original resolution
and with enlarged item crops before examining OCR. The different public DALI
photo is still separate. The native capture test passed for both owner images;
source and enhanced-image hashes were checked after export.

Independent truth excludes numeric product codes from editable product names,
retains the Ariel promotional prefix, and uses the literal printed DALI spelling:

| Receipt | Item | Purchased count | Unit price | Line amount |
| --- | --- | --- | --- | --- |
| Wellbest | BIRCH TREE FORTIFIED 64G TP | 10 | 15.75 | 157.50 |
| Wellbest | 6+1ARIEL LAU LIQ.SR FRS 58G | 1 | 93.00 | 93.00 |
| User DALI | UFC Golden Fiesta Canola Oil SUP 1L | 1 PC | 144.00 | 144.00 |
| User DALI | Mr. Zippy Dishwashing Liquid Kalamansi | 1 PC | 27.50 | 27.50 |
| User DALI | Wagi Carne Norte 150g | 3 PC | 21.00 | 63.00 |

Wellbest totals 250.50 with 11 purchased units; DALI totals 234.50 with five.
The earlier chat transcription of Wagyu was incorrect; the original crop reads
Wagi. Ariel starts with 6+1, which is not the purchased quantity. X indicates a
purchased count but does not prove pieces versus packs. No photo-ground-truth
JSON was fabricated from shortened synthetic test descriptions.

| Receipt / engine / pixels | Matched expected rows | Exact names | Correct counts | Correct line amounts | Extra/unmatched rows |
| --- | --- | --- | --- | --- | --- |
| Wellbest / ML Kit / original | 1/2 | 0/2 | 0/2 | 0/2 | 1 |
| Wellbest / ML Kit / enhanced | 2/2 | 0/2 | 2/2 | 1/2 | 0 |
| Wellbest / PP-OCRv5 / original | 2/2 | 0/2 | 0/2 | 1/2 | 0 |
| Wellbest / PP-OCRv5 / enhanced | 2/2 | 0/2 | 0/2 | 1/2 | 1 |
| Owner DALI / ML Kit / original | 1/3 | 0/3 | 1/3 | 1/3 | 1 |
| Owner DALI / ML Kit / enhanced | 0/3 | 0/3 | 0/3 | 0/3 | 2 |
| Owner DALI / PP-OCRv5 / original | 1/3 | 1/3 | 1/3 | 1/3 | 2 |
| Owner DALI / PP-OCRv5 / enhanced | 1/3 | 1/3 | 1/3 | 1/3 | 2 |

Counts are post-parser field correctness, not pure OCR character accuracy.
Unmatched truth rows are scored unaligned, not as wrong recognized digits or
safe abstention. Extra/unmatched rows can include rows whose description was
lost; they are not automatically additional purchases. All owner DALI totals
are correct; all Wellbest totals are unresolved. None of these passes yields a
fully correct receipt. The eight owner captures are two independent receipts.

### Confirmed failure causes

1. **Wellbest cross-item association.** In original ML Kit output, Birch's count
   row is `10 X 13.75`, with the line amount `157.50` at a higher baseline in the
   right column. The numeric-before-description fallback binds the count row to
   the following Ariel description, producing quantity 10 and amount 13.75 on
   Ariel. The true Ariel count is 1. This is a layout ownership failure, not a
   problem solved by repairing one character.
2. **DALI terminal marker rejection.** ML Kit reads some printed V markers as
   `Ų`. ASCII-only money patterns reject those price rows. Recognized product
   descriptions then remain detached and disappear; numeric fragments become
   incomplete product suggestions. Original Zippy survives with an ASCII V,
   whereas its enhanced reading ending in Ų does not. Preserve the description
   and money candidates even when a terminal marker is uncertain.
3. **Unsupported P currency prefix.** Both engines read Wellbest's total as
   `P250.50`. Layout/parser monetary handling accepts ₱/PHP but fails to recognize
   the P form as a total. This is a constrained monetary-token support gap.
4. **Product-code contamination.** Wellbest descriptions retain their leading
   numeric item codes. Even PP-OCR's correctly read Birch name is scored wrong
   as an editable product name because the code remains part of it. Keep a code
   as separate evidence instead of making it part of brand/variant/size matching.
5. **Recognition errors remain.** ML Kit reads Birch's unit price as 13.75 instead
   of 15.75; the enhanced parser appropriately leaves its contradictory total
   unresolved. PP-OCR reads 15.75, but the existing layout loses its association.
   DALI's first purchased count is read as PC/T PC by ML Kit and I PC by PP-OCR.
   Do not invent a count or correct missing digits just to reconcile arithmetic.

Sanitized uncorrected captures now live in `test/fixtures/owner_receipts`, with
independent truth in `test/fixtures/grocery_benchmark/user_*_truth.json`.
Each sanitized capture was replayed and verified to produce exactly the same
suggestions and field scores as its complete private diagnostic capture.
The benchmark supports each truth's `captureDirectory`, keeping owner samples
separate from downloaded public samples. Complete OCR and photos remain in /tmp.

## Reproduce

Keep photos, complete receipt OCR, models, and generated results under /tmp.
Original photos are not redistributed or bundled into the app.

```bash
python -m venv /tmp/reseebo-ocr-compare-venv
/tmp/reseebo-ocr-compare-venv/bin/pip install rapidocr==3.10.0 onnxruntime==1.31.0

# From reseebo_app; use a fresh output folder for each experiment.
/tmp/reseebo-ocr-compare-venv/bin/python scripts/compare_receipt_ocr.py \
  --output /tmp/reseebo-new-ocr-run /tmp/reseebo-receipt-download-check/savemore.jpg
dart run tool/score_receipt_capture.dart \
  /tmp/reseebo-new-ocr-run/savemore.json \
  test/fixtures/grocery_benchmark/savemore_truth.json
```

Models download only during experimental setup. Inference is local; no image is
sent to cloud OCR. The production app does not use this Python script. Installing
the models on a desktop does not prove bundled first-launch Android operation.

The isolated native capture harness accepts arbitrary named local JPEG samples:

```bash
adb push /tmp/reseebo-user-receipts/user_wellbest.jpg /tmp/reseebo-user-receipts/user_dali.jpg /data/local/tmp/
ORG_GRADLE_PROJECT_reseeboVerification=true flutter build apk --debug \
  --target=integration_test/receipt_accuracy_capture_test.dart \
  --dart-define=RECEIPT_SAMPLE_DIR=/data/local/tmp \
  --dart-define=RECEIPT_SAMPLE_NAMES=user_wellbest,user_dali
ORG_GRADLE_PROJECT_reseeboVerification=true flutter test \
  integration_test/receipt_accuracy_capture_test.dart -d R5GL539N5VX --no-uninstall \
  --dart-define=RECEIPT_SAMPLE_DIR=/data/local/tmp \
  --dart-define=RECEIPT_SAMPLE_NAMES=user_wellbest,user_dali
```

The log prints a unique app-support evidence directory. Pull that directory with
`adb exec-out run-as com.reseebo.reseebo.verification tar ...` into /tmp.
Each JSON retains uncorrected lines/tokens, original and recognition image hashes,
and elapsed recognition time. Enhanced JPEG copies enable identical-pixel
alternative-engine comparisons. Capture reruns retain separate directories;
Python refuses output collisions. Never install over or clear the owner's
ordinary com.reseebo.reseebo app.

## Next implementation decision

The next implementation should fix association and monetary-token handling
before selecting an engine. Preserve descriptions with unresolved fields; keep
count, unit-price, line-amount and tax-marker evidence separate; prevent a count
row from crossing into the next product; handle P-prefixed totals; separate item
codes from names. Validate these changes against the unchanged captures and
synthetic negative cases. Extend to several real receipts per intended supplier
and keep a receipt-level holdout unused for tuning.

The layout layer currently reconstructs strings that the parser then rescans.
The real captures demonstrate association failures. Replace that boundary with typed
item evidence: description/code, raw count marker, candidate price cells, bounds,
and header context. Resolve economic fields once, preserve contradictions, and
measure changes against held-out receipts. Do not start a broad rewrite based
only on synthetic tests or select a replacement engine from one photo.

## Verification boundary

Both the initial and final native capture passed for public Savemore, DALI, and
WalterMart. Exported final original/enhanced image hashes were verified against
the input and exported pixels. The 104 relevant parser/autofill/benchmark tests
passed, and final `flutter analyze --no-pub` reported no issues.
No new first-launch internet-disabled or
purchase-persistence claim is made: these diagnostics do not save receipts and
the app's OCR model and storage behavior were not changed.

Local evidence: /tmp/reseebo-native-accuracy, /tmp/reseebo-ocr-comparison,
/tmp/reseebo-ocr-enhanced-comparison, /tmp/reseebo-native-accuracy-final.
These directories are temporary artifacts,
not permanent benchmark fixtures.

Owner evidence: /tmp/reseebo-user-native/accuracy-captures-MIEUGJ,
/tmp/reseebo-user-ocr-original, /tmp/reseebo-user-ocr-enhanced,
/tmp/reseebo-user-truth. Original owner files remain unchanged in Downloads.
