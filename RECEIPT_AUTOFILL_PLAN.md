# Receipt Autofill Improvement Plan — 10 October 2026

**Status:** Implemented and verified with automated tests and public samples on a physical device. Native verification of the exact two attached photos remains open. Work proceeds sequentially. Historical completion notes in `IMPLEMENTATION_PLAN.md` do not establish that these receipts pass real-device verification.

**Execution evidence:** See [receipt autofill results](reseebo_app/docs/receipt_autofill_results.md). Public samples supplement the two user-provided layouts; they do not establish support for every branch or POS version. The exact attached Wellbest and DALI photos have no local file path in this session, so their native OCR gate remains open.

**Outcome:** Prefill supported purchase dates, quantities, line amounts, and exact product matches from bundled on-device OCR. Keep unclear fields editable and require owner confirmation before saving. No additional AI model in this iteration.

## 1. Capture the actual failure evidence

- [x] Inspect the current parser, review state, adapter, and existing tests before edits; preserve unrelated staged and unstaged changes.
- [ ] Capture OCR text, line/token bounds, and resulting draft from the Wellbest and DALI photos on the demo phone using local diagnostics. Keep diagnostics local; avoid logging receipt/customer details by default.
- [x] Separate recognition failures (missing/misread text) from layout reconstruction, parsing, matching, and review-field display failures.
- [x] Create regression fixtures from actual OCR output. Any manually transcribed fixture must be labeled synthetic and must not count as device OCR proof.

**Gate:** Identify where each missing field is lost before changing extraction behavior. Attached chat photos need to be available locally/on-device for this validation.

## 2. Reconstruct product blocks and quantities

**Owners:** `lib/core/services/receipt_layout.dart`, `receipt_parser.dart`; extract a dedicated service if block reconstruction becomes substantial.

- [x] Associate a description with its nearby quantity/unit-price/amount row using vertical proximity, horizontal alignment, and receipt section boundaries. Handle wrapped descriptions and modest skew.
- [x] Support `10 X 15.75 157.50 V`, `1 PC 144.00 144.00 V`, and `3 PC 21.00 63.00 V` without requiring printed item-column headers.
- [x] Prefer explicit quantity markers and token bounds. Preserve item codes, numeric brands, and product sizes; do not interpret `64G` or `150g` as purchased quantities.
- [x] Stop item association at totals, taxes, payment, and footer sections. Missing rows must not borrow another product's quantity or amount.
- [x] Keep product-line count separate from purchased-unit count: Wellbest has 2 product lines / 11 units; DALI has 3 product lines / 5 units. Treat printed counts as validation evidence, not a way to invent missing items.
- [x] Do not infer pieces-per-pack from product weight or a bare `X` marker. Keep pack conversion unresolved when the receipt does not establish it.

## 3. Resolve line amounts with arithmetic evidence

- [x] Use labeled columns where available; otherwise combine block geometry, quantity markers, and quantity × unit-price agreement to identify the line amount.
- [x] Use integer cents for monetary validation. Document any rounding tolerance; do not silently repair OCR digits until an equation happens to match.
- [x] Recognize peso prefixes and tax suffixes without treating payment or VAT rows as products.
- [x] Compare complete line amounts with the receipt total. A match supports extraction but does not prove product identity or pack conversion.
- [x] Leave competing candidates, discounts, missing amounts, and inconsistent arithmetic unresolved with a specific review message. Do not allocate a receipt-wide discount without owner input.
- [x] Calculate cost per piece only after quantity, purchase unit, conversion, and final amount are valid; keep confirmation guards at the service/database boundary.

## 4. Resolve transaction dates safely

**Owner:** `lib/core/services/receipt_purchase_datetime.dart`.

- [x] Prioritize transaction date/time labels and their adjacent values. Exclude `Date Issued`, accreditation/permit dates, expiry dates, and POS-provider footer dates.
- [x] Parse `10/08/26` and `08.10.26` as candidates; never assume their month/day order from the current date or device locale.
- [x] For an ambiguous date, present both interpretations and ask the owner to choose. Offer an explicit option to remember the supplier's numeric date order locally.
- [x] If remembered, store the preference with a versioned SQLite migration and typed adapter contract; scope it to the selected supplier/branch and provide a way to change or clear it.
- [x] Apply a preference only after the supplier is resolved; do not rewrite historical purchases or overwrite owner-edited draft fields. Conflicting transaction dates still require review.
- [x] Retain time when supported; an unknown time remains unknown.

## 5. Prefill exact products with sufficient evidence

**Owners:** local matching service/adapter and `features/receipt_scan/state/receipt_review_state.dart`.

- [x] Retain unique owner-confirmed alias prefills. Ambiguous aliases must remain selectable suggestions.
- [x] Add unique catalog identity matching using explicit brand, variant, and size evidence. Normalize casing, spacing, and equivalent units while preserving meaningful identity differences.
- [x] Keep partial/fuzzy matches as suggestions. Do not automatically merge sizes, flavors, pack forms, or name-only catalog entries based on similarity.
- [x] For first-time abbreviations, let the owner confirm the exact product and retain the existing local alias-learning behavior.
- [x] Keep original OCR evidence separate from editable descriptions; edits that change identity must invalidate the previous product match.

## 6. Make autofill and uncertainty visible

- [x] Use concise field states such as `Filled from receipt`, `Previously matched`, and `Needs review`, based on evidence rather than invented confidence percentages.
- [x] Let the owner inspect the relevant source text/photo region and correct every suggested field.
- [x] Preserve edits during reloads and supplier/date preference changes; recompute only dependent suggestions and invalidate affected confirmations.
- [x] Keep receipt saving atomic, retain source images and purchase history, and preserve existing duplicate/overlap review guards.

## 7. Verify before declaring completion

| Receipt | Expected extracted purchase details | Date expectation |
|---|---|---|
| Wellbest | Birch Tree Fortified 64g: 10 × ₱15.75 = ₱157.50; Ariel 58g: 1 × ₱93.00 = ₱93.00; total ₱250.50 | `10/08/26 15:45`; date order requires confirmation or a confirmed supplier preference |
| DALI | UFC Golden Fiesta Canola Oil 1L: 1 × ₱144.00; Mr. Zippy Kalamansi: 1 × ₱27.50; Wagyu Carne Norte 150g: 3 × ₱21.00 = ₱63.00; total ₱234.50 | `08.10.26 16:00`; exclude footer `Date Issued: 08/01/20`; confirm date order |

The table transcribes visible purchase evidence, not guaranteed OCR output or confirmed catalog identities. Missing product sizes/variants remain unresolved.

- [x] Add focused parser tests for both layouts, separated OCR cells, skew, wrapped descriptions, missing rows, numeric brands/codes, tax/payment boundaries, discounts, and inconsistent totals.
- [x] Test ambiguous/conflicting dates, footer exclusion, preference changes, and preservation of manual edits.
- [x] Test unique identity/alias matches, multiple candidates, size conflicts, and incomplete identities.
- [x] Add review widget/state tests for displayed prefills, corrections, and confirmation invalidation; SQLite tests for any preference migration and persistence.
- [x] From `reseebo_app/`, run `flutter analyze`, focused affected tests, and the full Flutter test suite after integration.
- [x] On a physical device, verify public samples offline in the isolated app, save a reviewed Savemore receipt, stop/restart the process, and verify original image bytes, lines, date/time, and supplier preference persist.
- [ ] On a physical device, test the exact attached Wellbest and DALI photos after a fresh first launch with internet disabled, scan both photos, review/save, restart, and verify receipt images, amounts, quantities, dates, and matches persist.
- [x] Report static checks, parser fixtures, local storage checks, and real-device offline results separately. Unavailable device evidence remains an explicit open gate.

**Completion criterion:** Actual phone scans produce the supported fields above, ambiguous data stays visibly unresolved, corrections survive review, and confirmed purchases persist offline after restart.

## 8. Reassess recognition only if evidence requires it

- [ ] If OCR misses readable text, first evaluate existing crop/straighten controls and capture quality with the same receipt samples.
- [ ] Consider another bundled recognition/layout model only if measured recognition or layout failures remain after these changes. Compare offline first-launch operation, accuracy, app size, latency, and memory on the demo phone before proposing integration.

