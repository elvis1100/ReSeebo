# Receipt OCR model selector

Status on 10 October 2026: selector, engine routing and reviewable-ledger work are implemented under the approved [design](superpowers/specs/2026-10-10-ocr-selector-and-review-ledger-design.md). ML Kit Latin remains the bundled default. The later user-authorized physical checks established offline Paddle inference and registry switching on Samsung SM-A576B; both Paddle manifest flags are now enabled. See [device acceptance and measured limits](verification/2026-10-10-paddle-device-acceptance.md). The mockup remains illustrative, and full production-flow persistence is a separate verification boundary.

The approved flow also permits immediate **Needs review** saving and **Save photos for later** after unreadable OCR. Pending suggestions retain provenance and raw evidence and stay outside confirmed comparisons, restock and profit inputs. Later confirmation validates whole-piece fields; corrections update the original purchase and retain immutable prior revisions. See [acceptance preparation and user-run lifecycle handoff](verification/2026-10-10-reviewable-receipts.md) for authored tests, the retained-data APK guard and explicit evidence limits.

## Goal

Compare ML Kit, PP-OCRv5 Mobile (English recognition), and PP-OCRv6 Medium on the same receipt photos in Step 1: Photos. Choose one complete result before entering Step 2: Review. Keep the app fully offline from first launch.

[Open the interactive sample mockup](mockups/ocr_model_selector.html). It uses synthetic receipt content and simulated results; their differences do not imply that one model is more accurate.

## UI reference and direction

Inspected MPC Garden's `app/lib/widgets/ai_provider_selector.dart`: a compact rounded model button with an icon, selected model name, and downward chevron opens a “Choose model” bottom sheet. The sheet has a close control, rounded option rows, a tinted selected row, and a checkmark. This historical reference supplies the interaction pattern. Current Reseebo styling uses the approved Inter typography, deep teal `#003D43`, coral `#FF654F`, cream `#FFF7EB`, and shared `AppColors` selection surfaces, spacing and controls. Use local engine icons; no external provider disclosure is needed for bundled offline engines.

Place the selector directly above the photo preview in the Photos step. Keep photo editing and page selection available. The selector opens three rows, each with its precise model label and whether that model has a result for the current photos. Avoid “most accurate” claims and percentages that are not grounded in this receipt's truth.

Recognition stays on Photos and shows a compact result preview with raw text separate from parsed fields, detected items and total, and elapsed time. Timing describes this run, not accuracy. **Review details** explicitly opens the selected current draft in Review; **Save Needs review** persists that selected draft directly to the ledger with suggestions still provisional. **Save photos for later** preserves the originals when recognition fails or remains unreadable. Returning from Review retains edits and current results; choosing another engine does not run OCR automatically.

## Current integration points

- `lib/core/services/ocr_service.dart`: existing `OcrService` boundary returns lines and token geometry; ML Kit implements it.
- `lib/features/receipt_scan/state/capture_state.dart`: capture, edits, recognition, and draft orchestration.
- `lib/features/receipt_scan/screens/capture_screen.dart`: recognition prepares the current result preview without navigating. Explicit Review details opens Step 2; Save Needs review writes a pending ledger entry directly, and Save photos for later preserves a photos-only pending entry.
- `lib/features/receipt_scan/widgets/`: `ocr_model_picker.dart`, `ocr_result_summary.dart` and `receipt_suggestion_label.dart` supply the focused controls; reuse `ReceiptScanSteps`, the image viewer, recognized-text presentation, and shared buttons.
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

- Real bundled Paddle inference passed offline first launch and process restart on the target Samsung, and both availability/device-proof flags are enabled; see [device acceptance](verification/2026-10-10-paddle-device-acceptance.md) for exact scope and records. ML Kit remains the bundled default. Full production-flow offline persistence remains separate from these isolated runtime checks.
- Same photo bytes and editing settings feed every engine. Record engine-specific resize/normalization settings so comparisons are reproducible.
- Switching restores the correct cached result. A stale result cannot enable Continue after photo changes. Engine errors, rapid interaction, backgrounding, and disposal do not corrupt the active draft.
- Multi-photo ordering and overlap handling work consistently; only the explicitly selected model's result reaches Review.
- Exact letters, quantities, unit prices, line amounts, and totals are scored independently against photo-checked truth. OCR confidence scores are not compared as if calibrated across engines. Report per-receipt results and limits of the small sample.
- Long model names, large text, small screens, screen-reader labels, selected-state announcements, bottom-sheet focus, and touch targets remain usable.
- Confirmed receipt saving remains atomic; original images and history persist after restart. Distinguish static tests, native inference, and real-device offline/persistence proof in the report.

## Deliverables and scope

The plan/mockup describe the target, while the approved design supplies immediate pending saves, later review and durable corrections. Real routing and selector work must honor registry availability: packaged Paddle names do not become selectable accepted engines merely because artifacts compiled. Current host artifact identity and the corrected OpenCV runtime are documented in [Paddle feasibility](verification/2026-10-10-paddle-feasibility.md); its earlier probe APK cannot be reused as evidence for later ledger-feature code. The later [device acceptance record](verification/2026-10-10-paddle-device-acceptance.md) supplies measured Paddle memory, timings, two-photo agreement and offline inference results; broader production-flow lifecycle checks remain separate.
