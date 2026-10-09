# Receipt OCR model selector

Status: proposed implementation; the accompanying mockup is illustrative, not an accuracy benchmark or working OCR integration.

## Goal

Compare ML Kit, PP-OCRv5 Mobile (English recognition), and PP-OCRv6 Medium on the same receipt photos in Step 1: Photos. Choose one complete result before entering Step 2: Review. Keep the app fully offline from first launch.

[Open the interactive sample mockup](mockups/ocr_model_selector.html). It uses synthetic receipt content and simulated results; their differences do not imply that one model is more accurate.

## UI reference and direction

Inspected MPC Garden's `app/lib/widgets/ai_provider_selector.dart`: a compact rounded model button with an icon, selected model name, and downward chevron opens a “Choose model” bottom sheet. The sheet has a close control, rounded option rows, a tinted selected row, and a checkmark. Adapt this interaction using Reseebo's existing Inter typography, deep green `#0F5132`, pale green selection surfaces, spacing, and shared controls. Use local engine icons; no external provider disclosure is needed for bundled offline engines.

Place the selector directly above the photo preview in the Photos step. Keep photo editing and page selection available. The selector opens three rows, each with its precise model label and whether that model has a result for the current photos. Avoid “most accurate” claims and percentages that are not grounded in this receipt's truth.

After recognition, show a compact result preview with raw text available separately from parsed fields, detected items and total, and elapsed time. Timing describes this run, not accuracy. Provide “Recognize” for an untested selection, “Run again” for a completed selection, and “Continue to review” only when the selected model has a current successful result. Allow direct return to the selector to compare another model.

## Current integration points

- `lib/core/services/ocr_service.dart`: existing `OcrService` boundary returns lines and token geometry; ML Kit implements it.
- `lib/features/receipt_scan/state/capture_state.dart`: capture, edits, recognition, and draft orchestration.
- `lib/features/receipt_scan/screens/capture_screen.dart`: currently hands a successful draft immediately to review. Separate recognition from continuing to Step 2.
- `lib/features/receipt_scan/widgets/`: add `ocr_model_selector.dart` and a feature-specific recognition preview; reuse `ReceiptScanSteps`, the image viewer, recognized-text presentation, and shared buttons.
- Local data adapter: inspect recognition and multi-photo merging contracts before changing model routing.

## Implementation sequence

1. **Prove Android feasibility.** Pin both Paddle model variants, model checksums, licenses, preprocessing, and inference runtime. Bundle all required files, including recognition dictionaries. Run each engine on the target phone offline and record APK size, peak memory, cold/warm latency, and exact-letter/price results. Desktop ONNX evaluation does not satisfy this gate. If a model cannot run reliably, document the blocker rather than presenting a placeholder as a working engine.
2. **Implement engine routing.** Add an explicit engine identifier and registry around the existing OCR interface. Keep parsing shared. Convert each engine's word/line coordinates into the same original-input coordinate system. Load heavy engines lazily and release native resources; avoid retaining three loaded models or running them simultaneously.
3. **Add independent result state.** Cache each model's raw lines, parsed draft, timings, and error for the current ordered photo set. Key results by photo content, edits/preprocessing revision, engine/model version, and parser version. Switching does not rerun OCR; edits, adding/removing/reordering photos, or changing preprocessing invalidate the relevant results. Keep this comparison cache in the scan session initially.
4. **Build selector and preview.** Implement the MPC Garden pill/bottom-sheet pattern with Reseebo tokens. Start with ML Kit selected. Selecting a different model does not automatically run it. During recognition, disable actions that alter input or engine; show progress with an accessible status. Restore controls on success or error. Guard late async completion with a request/session revision so it cannot overwrite newer input or disposed state.
5. **Make Step 2 explicit.** Continue only with the selected model's complete current draft. For multiple photos, use the selected engine on every page and the existing overlap/merge process. Do not mix engines or silently combine the best-looking fields. Preserve original photos and raw OCR evidence. Returning from Review retains caches, but choosing another result must explicitly handle existing user edits rather than overwriting them.
6. **Validate and document.** Run focused state/widget/parser checks, `flutter analyze`, and native offline verification. Update model/runtime provenance and measured comparison results only after tests run.

## Failure and review behavior

An engine failure remains attached to that engine and offers retry or selecting another engine. Preserve successful results from the other engines. Never substitute another model silently. Unreadable or contradictory prices remain uncertain and require review; arithmetic and catalog matching must not invent OCR characters. Step 2 retains all existing confirmation and purchase validation rules.

## Acceptance checks

- All three engines perform real bundled inference on the target phone, including first launch with internet disabled; no runtime model downloads, account, API key, or cloud inference.
- Same photo bytes and editing settings feed every engine. Record engine-specific resize/normalization settings so comparisons are reproducible.
- Switching restores the correct cached result. A stale result cannot enable Continue after photo changes. Engine errors, rapid interaction, backgrounding, and disposal do not corrupt the active draft.
- Multi-photo ordering and overlap handling work consistently; only the explicitly selected model's result reaches Review.
- Exact letters, quantities, unit prices, line amounts, and totals are scored independently against photo-checked truth. OCR confidence scores are not compared as if calibrated across engines. Report per-receipt results and limits of the small sample.
- Long model names, large text, small screens, screen-reader labels, selected-state announcements, bottom-sheet focus, and touch targets remain usable.
- Confirmed receipt saving remains atomic; original images and history persist after restart. Distinguish static tests, native inference, and real-device offline/persistence proof in the report.

## Deliverables and scope

This proposal supplies the plan and interactive mockup first. Subsequent implementation supplies three on-device engines, the selector, cached comparison previews, explicit continuation, focused tests, and measured device evidence. Production model switching has not been implemented by this document. Package-size and performance tradeoffs will be recorded from the feasibility run before finalizing integration.
