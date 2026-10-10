# Grocery receipt parsing and benchmark

The parser uses printed layout evidence, not a retailer whitelist or fixed store
coordinates. Any grocery receipt can enter the same offline scan/review flow;
this is not a guarantee that every format, language, currency, or faded image can
be accurately autofilled. Monetary parsing currently follows Philippine peso
notation and purchase quantities are whole pieces/packs. Weighed/fractional goods
remain owner review; they must never become a whole piece count.

Supported evidence includes bounded columns, labeled tables, descriptions above
or below explicit quantity/price rows, same-row @ prices, and whole-decimal
counts. @ rows retain explicit piece/pack markers. Headers locate columns but do
not override conflicting unit-price × quantity arithmetic. Missing digits are
never reconstructed to balance a receipt. Original OCR/photos remain unchanged
and all suggestions require confirmation.

## Run the benchmark

From the app root:

```sh
dart run tool/receipt_benchmark.dart > /tmp/grocery-receipt-benchmark.json
flutter test test/services/receipt_parser_test.dart test/services/receipt_benchmark_test.dart
flutter analyze
```

The JSON report lists each case separately with matched/missed and extra/unmatched
rows, alignment failures, field counts (correct, wrong, unresolved,
safeUnresolved, unaligned), and individual failures. Null synthetic expectations
specify abstention, not unknown truth. Unresolved means an aligned row has an
empty field despite known truth; unaligned means row association failed and the
field cannot be scored. An unaligned row never counts as safe abstention.
Description comparison ignores spaces/case, but retains digits and punctuation.
Evaluation anchors match descriptions independently of amounts/quantities.
Overlapping truth anchors and ambiguous candidates remain unmatched regardless
of truth order. Repeated exact descriptions align in receipt order only when
expected and actual multiplicities agree and no competing anchor claims them.
Missed and extra/unmatched counts can include alignment failures and require
inspection; they are not automatically detection or false-positive rates.

Synthetic cases in `test/fixtures/receipts` test parser contracts and layout
variations. They do not measure native OCR accuracy. Photo-derived truth lives in
`test/fixtures/grocery_benchmark/*_truth.json`, separately from unchanged captured
OCR in `test/fixtures/public_receipts`. Each truth record identifies its source,
manual verification, captures, printed descriptions/counts/amounts, and evaluation
anchors. Add only fields independently readable in the photo. Never copy parser
output into truth. Public photos remain outside the repository.

Initial photo benchmark: one manually inspected Savemore/Festive Market receipt,
replayed against original and enhanced Android captures. Original capture: 6/6
quantities, 5/6 amounts correct, one amount unresolved, 4/6 descriptions correct.
Enhanced capture: 6/6 quantities and amounts correct, 3/6 descriptions correct.
Both identify six rows and the correct total. These are replay results for one
receipt, not new device OCR tests or an accuracy estimate across grocery stores.
The raw/enhanced captures are two readings of the same receipt, not independent
samples. DALI, WalterMart and Puregold retain existing replay regressions but do
not yet have complete independently annotated photo truth in this benchmark.

Next dataset additions should cover several receipts per layout, branches,
printers, skew/fading, discounts, and weighed goods. Keep a separate holdout set
unused when tuning rules; do not claim generalization from development fixtures.
Review failures by recognition (photo vs OCR), layout association, numeric
interpretation, and identity matching before changing the owning layer.

## Verification boundary

This change affects local parser logic and evaluation tooling, not SQLite or
native OCR packaging. Run parser regressions and analysis locally. Native
first-launch offline and process-restart persistence must be verified separately
on a device; a parser replay cannot establish those results.

Local verification on 10 October 2026: all 277 Flutter tests passed after review;
`flutter analyze` reported no issues and `git diff --check` passed. The 32
synthetic benchmark cases reported zero field failures. Existing staged and
unstaged work was preserved.

Review fixes also preserve fractional-weight evidence in bounded tables, reject
invalid monetary columns without throwing, and require a quantity heading before
promoting an unlabeled trailing product numeral into a count. Consequently the
enhanced WalterMart noodles row remains unresolved when its count is only an
unlabeled numeral at the end of its description. Exact arithmetic by itself does
not establish that numeral's meaning.

An isolated Android verification app passed the internet-disabled bundled OCR
smoke test, including saving a receipt and checking its original image after
closing/reopening SQLite. This database reopen test does not establish process
restart persistence or accuracy across grocery stores.

The internet-disabled public-photo integration run also passed its two tests
(native smoke plus actual grocery OCR/save pipeline). The saved Savemore amounts
were explicitly owner-corrected in that integration test, so persistence results
are not an automatic-extraction accuracy claim. A separate force-stop/relaunch
stage passed: the saved six lines, total, date, and original image remained intact.
The first stage must use `flutter test --no-uninstall`; Flutter otherwise removes
the integration app and its data before the restart stage. Both stages used the
isolated `com.reseebo.reseebo.verification` application ID. The final stage removed
the verification app, and the script restored the phone's connectivity settings.
