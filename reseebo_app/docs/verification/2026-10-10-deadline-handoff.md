# Deadline handoff

The user requested code delivery for a deadline and will handle broader testing.
All planned production areas are implemented on `models`: bundled OCR routing
with unavailable Paddle choices disabled, local suggestions, immediate Needs
review saving, durable pending edits, atomic confirmation/corrections, revision
history, combined ledger routes and the approved ReSeebo welcome/palette/icons.

The supplied logo was copied unchanged. Original receipt photos and raw OCR are
retained. Pending estimates do not enter confirmed purchase calculations.

## Actual checks

- Whole-project `flutter analyze --no-pub`: no issues, 17.9 seconds, exit 0.
- Final bounded pending/ledger/correction large-text and root-navigation checks:
  9 passed. This is not the complete new UI suite.
- Selector/cache/review covering run before the final ledger UI: 132 passed,
  one opt-in profile skipped. Duplicate-confirmation fix: 27 covering checks
  passed, including two regressions using actual mock persistence.
- Confirmation/storage covering run: 160 passed. Native geometry: 2 passed.
- Python host guard suite: 24 passed. Bundled manifest: 51 entries verified
  against pinned hashes, including repeated paths.

The full Flutter suite and an ordinary APK build after the last ledger UI edits
have not run. The first new ledger UI run had 13 passes and 18 failures; actual
layout/Material problems and identified fixture assumptions were then fixed.
Only the bounded selection above was rerun for the deadline. Do not describe
the remaining cases, the whole suite or a final APK as verified.

Physical/device tests, offline first launch and process restart were explicitly
skipped. Both Paddle engines retain `available=false` and
`verifiedOnDevice=false`. Static/native host results do not establish accepted
Paddle inference. Final independent review of the last ledger UI and the whole
implementation remains deferred; earlier tasks have their scoped reviews.
Working review records are retained in the ignored SDD workspace for follow-up.

## Run from the app root

```powershell
flutter run -d R5GL41586RA
```

The user can test upload → Read receipt → Save Needs review → open from ledger →
edit → confirm, then edit a confirmed receipt and confirm its correction.
Verify that original photos remain accessible and the correction keeps one
purchase. Broader automated checks can use `flutter test --no-pub`.

Implementation rulings are preserved in
[the decision record](2026-10-10-implementation-decisions.md). Detailed host and
optional device evidence remain in
[the verification record](2026-10-10-reviewable-receipts.md).
