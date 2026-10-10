# OCR selector and reviewable ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three real bundled OCR choices and immediate, editable Needs review receipt saving while preserving the current Flutter UI and confirmed purchase calculations.

**Architecture:** A versioned OCR registry feeds the existing shared parser. A separate local suggestion service adds provenance without changing raw evidence. Separate SQLite pending records and immutable correction revisions protect the existing confirmed purchase constraints; the dashboard combines their summaries.

**Tech Stack:** Flutter/Dart, SQLite/sqflite, bundled ML Kit Latin, Kotlin, Paddle ONNX models, ONNX Runtime Android 1.21.1, OpenCV Android 4.5.3, coroutines 1.9.0, Java 17. Paddle dependencies are initially pinned to the official Android example; any necessary compatibility change requires recorded feasibility evidence.

**Spec:** `docs/superpowers/specs/2026-10-10-ocr-selector-and-review-ledger-design.md` (approved). Also read `docs/ocr_model_selector_plan.md` and the root AGENTS.md before execution.

**Latest user scope:** physical/device testing is explicitly skipped; the user
will handle it. Device steps below record the original acceptance design and
are optional reference, not outstanding host work. Both Paddle availability
gates remain false. The approved logo design adds a cream animated in-app
welcome screen, unchanged supplied logo, teal/coral palette and rounded icons.
Work stays on the user's current `models` branch with a central implementation
commit; the user will push it.

## Global Constraints

- Runtime works fully offline from first launch; bundle models, dictionaries, native libraries and licenses. Development downloads must not become application downloads.
- Target engine labels: ML Kit Latin, PP-OCRv5 Mobile, PP-OCRv6 Medium. Never substitute a smaller engine under another label or mix engines across receipt pages.
- Preserve Photos, Review and Save, navigation, photo editing, page strips, original-photo access and digital receipt presentation. Reuse existing shared controls, Inter typography and theme tokens.
- Mark suggested values and unresolved imports Needs review. Pending values never enter confirmed comparison, restock or profit inputs. No additional generative model or cloud calls.
- Preserve raw OCR, owner edits, exact brand/variant/size distinctions, whole-piece validation, original images and initial recorded ordering.
- Extend database version 7 using migration 8; do not weaken existing confirmed table constraints. Save files and receipt data with existing rollback guarantees.
- The user approved parallel subagents for this implementation. Keep ownership disjoint, serialize shared-contract edits, and preserve unrelated changes. Stage only reviewed task-owned files.
- Run Flutter commands from `reseebo_app`. Physical verification uses `R5GL41586RA` and `com.reseebo.reseebo.verification`; never replace/uninstall `com.reseebo.reseebo`.
- Paddle's Android SDK requires API 26. Set the application's minimum to `maxOf(flutter.minSdkVersion, 26)` only with Task 1 compatibility evidence; record this Android 8.0 floor in release notes.

## Review Focus

1. OCR finishes after photos change or state closes: its result cannot replace current data or notify disposed state (Task 3).
2. Weight, ambiguous pack contents or competing product sizes: defaults/history cannot fabricate a usable piece cost (Task 4).
3. Process stops during media copy or confirmation: reopening retains the prior committed state, with no half purchase or removed original (Tasks 5–6).
4. Two saves/corrections use stale revisions or repeated operation IDs: retries return the original result; changed payloads and stale edits are rejected (Tasks 5–6).
5. Owners enlarge text on a 360dp screen: selector, estimates and actions remain readable and reachable without overflow (Tasks 7–8).

---

## File map and execution order

Paths below are relative to `reseebo_app`. Keep existing monolithic models and adapters compatible; extract only the new focused responsibilities.

| Task | Files and responsibility |
| --- | --- |
| 1 | `android/paddle_ocr/` (vendored official SDK, license and source manifest), `android/settings.gradle.kts`, `android/app/build.gradle.kts`, `android/app/src/main/kotlin/com/reseebo/reseebo/MainActivity.kt`, new `.../ocr/PaddleOcrChannel.kt`, `.../ocr/PaddleEngineSession.kt`, `assets/ocr/model_manifest.json`, bundled assets under `assets/ocr/`, `pubspec.yaml`, `scripts/prepare_bundled_ocr.py`, `integration_test/paddle_engine_probe_test.dart`, `docs/verification/2026-10-10-paddle-feasibility.md`. Native feasibility and reproducible artifacts. |
| 2 | New `lib/core/models/ocr_engine.dart`, `lib/core/services/ocr_engine_registry.dart`, `paddle_ocr_service.dart`; modify `ocr_service.dart`, `receipt_parser.dart`, `models/models.dart`, all three adapter interface/implementations. Shared engine routing and run identity. |
| 3 | New `lib/features/receipt_scan/models/scan_result.dart`, `services/scan_result_cache.dart`; modify `state/capture_state.dart`. Cache and lifecycle. |
| 4 | New `lib/core/models/receipt_field_provenance.dart`, `services/receipt_suggestion_service.dart`; modify `models/models.dart`, `state/receipt_review_state.dart`. Local suggestions and protected edits. |
| 5 | New `lib/core/models/pending_receipt.dart`, `services/receipt_snapshot_codec.dart`, `database/migrations/migration_008_reviewable_receipts.dart`, `database/pending_receipt_repository.dart`; modify database, adapters and `errors/app_exception.dart`. Durable pending receipts and ledger summaries. |
| 6 | New `lib/core/database/confirmed_receipt_writer.dart`; modify SQLite adapter and repository. Atomic confirmation, correction history and idempotent writes. |
| 7 | New scan widgets `ocr_model_picker.dart`, `ocr_result_summary.dart`, `receipt_suggestion_label.dart`; modify capture/review screens, scan states and `main.dart`. Same-style selector and immediate saves. |
| 8 | New `features/receipts/state/pending_receipt_controller.dart`, `screens/pending_receipt_screen.dart`, `widgets/receipt_review_status.dart`, `widgets/receipt_revision_history.dart`, `features/dashboard/widgets/pending_receipt_list_item.dart`; modify dashboard, confirmed receipt screen/controller and `main.dart`. Reopening, editing and confirming. |
| 9 | New `integration_test/reviewable_receipt_offline_test.dart`, `docs/verification/2026-10-10-reviewable-receipts.md`; update selector documentation. End-to-end acceptance. |

Do Task 1 first. If an engine is infeasible, record the exact failure and request a replacement decision before promising all three engines. Tasks 4–6 can still proceed sequentially with ML Kit; do not ship fake selector choices. Keep mock engines limited to tests.

## Shared interface decisions

The task that introduces each contract owns its validation and documentation. Later tasks use these names unchanged.

- Task 2: `enum OcrEngineId { mlKit, ppOcrV5Mobile, ppOcrV6Medium }`; wire IDs `mlkit`, `ppocr_v5_mobile`, `ppocr_v6_medium`. Immutable `OcrEngineDescriptor` exposes `id`, `label`, `modelVersion`, `runtimeVersion`, `available`. Immutable `OcrRunMetadata` exposes engine/model/runtime/parser versions, ordered input digest, preprocessing revision and elapsed milliseconds.
- Task 2: `OcrEngineRegistry.descriptors`, `Future<List<OcrTextLine>> recognize(OcrEngineId engineId, String imagePath)`, `Future<void> close()`. Registry serializes native work and releases a previously loaded heavy engine before loading another. ML Kit retains the existing `OcrService` contract.
- Task 2: append `OcrEngineId engineId = OcrEngineId.mlKit` to both adapter processing methods; append `String preprocessingRevision = '1'` to `processReceiptImages`. `ReceiptParser.version` is a constant changed whenever parsing semantics change. Add nullable `ReceiptDraft.ocrRun` so old/manual drafts remain valid.
- Task 3: immutable `ScanResult` contains `key`, `engineId`, nullable `draft`, nullable `error`, elapsed milliseconds. `ScanResultCache.keyFor(...)` uses ordered original/recognition/comparison content hashes, photo edit revisions, preprocessing identity, engine/model/runtime identity and parser version. `CaptureState.selectEngine(OcrEngineId)`, `Future<void> recognizeSelected()`, `ReceiptDraft selectedDraftSnapshot()`, `ReceiptDraft photosOnlyDraftSnapshot()`; no implicit inference on selection.
- Task 4: `enum ReceiptFieldOrigin { extracted, calculated, history, assumed, ownerEdited }`. Immutable `ReceiptFieldProvenance` exposes origin, explanation and optional source purchase/receipt/supplier/date. Metadata fields use `ReceiptMetadataField { supplier, purchasedAt, total }`; line fields use `ReceiptSuggestionField { description, product, quantity, unit, piecesPerPack, amount }`. Add typed provenance maps to draft/lines; `snapshot()` deep-copies them.
- Task 4: `ReceiptSuggestionService.suggest(ReceiptDraft draft, {required List<Product> products, required List<PurchaseRecord> confirmedHistory, required DateTime importedAt}) -> ReceiptDraft`. The service is pure and returns a private snapshot. Adapter/state resolves confirmed supplier aliases before calling it and fetches history only for uniquely matched product IDs.
- Task 5: `PendingReceipt` exposes id, revision, createdAt, updatedAt, draft, nullable correctionOfReceiptId and baseConfirmedRevision. `PendingSaveResult` exposes id, revision, alreadySaved. `LedgerEntry` exposes id, status (`confirmed` or `needsReview`), recordedAt, supplier display, nullable provisional total, and either confirmed receipt ID or pending ID. A correction links to the original confirmed receipt rather than adding another purchase count.
- Task 5: `ReceiptSnapshotCodec.encode(ReceiptDraft) -> String`, `decode(String) -> ReceiptDraft`; version 1 includes every editable/evidence field and provenance, ordered original/recognition/comparison paths, hashes and transforms. Reject unknown versions and malformed types explicitly; never silently drop fields.
- Task 5: add immutable `ReceiptImageReference(path, sha256, width, height, preprocessingIdentity)` and `ReceiptPageMedia(original, recognition, comparison)` in `pending_receipt.dart`, plus `ReceiptDraft.mediaEvidence` (defaults to empty for legacy drafts). Original is required; recognition/comparison references are nullable. Decode pixel dimensions while persisting; copy these references in snapshots. Reconstruct a new draft when rewriting its existing final image-path properties.
- Task 5 adapter additions: `savePendingReceipt(ReceiptDraft draft, {required String operationId, String? pendingId, int? expectedRevision, String? correctionOfReceiptId, int? expectedConfirmedRevision}) -> Future<PendingSaveResult>`; `getPendingReceipt(String id) -> Future<PendingReceipt>`; `getLedgerEntries({int limit = 200, String? query}) -> Future<List<LedgerEntry>>`. Insert requires no expected revision; update requires the existing revision. `RevisionConflictException` is a typed `AppException`.
- Task 6 adapter additions: `confirmPendingReceipt(String id, {required int expectedRevision, required String operationId}) -> Future<SaveReceiptResult>`; `getConfirmedReceiptEdit(String receiptId) -> Future<ConfirmedReceiptEdit>`; `getReceiptRevisions(String receiptId) -> Future<List<ReceiptRevision>>`. The edit DTO contains receiptId, revision and private draft; revision DTO contains revision, recordedAt and prior immutable draft.
- Task 6: corrections always save through `savePendingReceipt` with confirmed ID/base revision, then use `confirmPendingReceipt`. Confirmation performs an atomic update instead of a second purchase. Existing `saveConfirmedReceipt` remains supported for complete/manual first-time saves.

### Task 1: Prove and package real Paddle inference

**Files:** Task 1 row above; test `android/app/src/test/kotlin/com/reseebo/reseebo/ocr/PaddleGeometryTest.kt` and `integration_test/paddle_engine_probe_test.dart`.

**Interfaces:** Consumes original recognition-image bytes and the existing isolated application-ID flag. Produces MethodChannel `reseebo/ocr`, method `recognize` with `{engineId, imagePath}`, method `release`; response `{engineId, modelVersion, runtimeVersion, elapsedMs, imageWidth, imageHeight, lines}`. Each line has text, left/top/width/height and optional tokens in input-pixel coordinates. Missing assets/unsupported IDs/native errors raise explicit channel errors; no success-shaped empty fallback.

- [ ] Write geometry tests asserting a resize/pad/crop round trip maps `(100, 200)` back to `(100, 200)` within one pixel, with bounds inside the input image. Write the device probe requiring the requested engine ID, correct manifest hashes, nonempty output for readable truth fixtures and explicit unreadable-image errors.
- [ ] Run the geometry test and `flutter test integration_test/paddle_engine_probe_test.dart -d R5GL41586RA` with the verification application flag. Expect failure from absent bridge/models; do not weaken assertions to pass.
- [ ] Implement the preparation script: resolve and record immutable official SDK/model commits, download detector/English recognizer/dictionary/config/license artifacts, verify SHA-256, and convert to ONNX only if required using a pinned reproducible conversion command. Pin the SDK's transitive source list/license in the manifest. Bundle PP-OCRv5 Mobile English and the actual PP-OCRv6 Medium detector/recognizer; document any unsupported operator instead of substituting a model. Use the [official Android deployment](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/inference_deployment/cross_platform/android_deployment.en.md) and its [version catalog](https://github.com/PaddlePaddle/PaddleOCR/blob/main/deploy/ppocr-android/gradle/libs.versions.toml).
- [ ] Implement `PaddleEngineSession.recognize(engineId: String, imagePath: String)` as suspend background work wrapping the pinned official SDK. Implement the channel with one mutex and guaranteed release; invert transforms, preserve detected lines and omit unavailable word bounds rather than inventing token locations. Register via MainActivity; retain Java 17 and existing verification suffix. Package assets and dependencies; record the API 26 compatibility floor.
- [ ] Run native unit tests and the probe on both Paddle engines. Capture exact per-field agreement against inspected truth, APK bytes, process peak memory, cold/warm elapsed times and coordinate overlays; report measurements without unsupported accuracy scores. Fresh-install only the verification package, disable networking, and repeat both runs. Confirm the ordinary app remains installed and untouched. Medium passes only if it loads, recognizes and completes repeated runs without crash/OOM, with usable reviewed output; record failures honestly.
- [ ] Commit task-owned native bridge, verified assets/manifest, tests and feasibility report: `feat: bundle verified Paddle OCR engines`. If blocked, commit the evidence without exposing an enabled engine and pause the three-engine portion for a user decision.

### Task 2: Route complete receipts through a versioned engine registry

**Files:** Task 2 row; tests `test/services/ocr_engine_registry_test.dart`, `test/services/receipt_engine_routing_test.dart`; extend `test/services/receipt_ocr_comparison_test.dart`.

**Interfaces:** Consumes Task 1 channel and `OcrService`. Produces registry, engine types, adapter parameters and run metadata from Shared interface decisions.

- [ ] Write tests named `selected_engine_reads_every_page`, `engine_failure_never_calls_fallback`, `shared_parser_keeps_page_provenance`, `close_releases_loaded_engine_once`. Assert two ordered pages call only the requested engine; a page-two exception produces no mixed draft; page/source/bounds survive the parser; release is awaited. Test omitted engine still calls ML Kit.
- [ ] Run `flutter test test/services/ocr_engine_registry_test.dart test/services/receipt_engine_routing_test.dart`; expect missing-contract failures.
- [ ] Implement `PaddleOcrService.recognize(String imagePath)` and `close()` through the channel, plus registry lazy loading and descriptor identity from the manifest. Route adapter processing through the registry, keeping the shared parser, original/comparison OCR evidence and overlap handling intact. Record parser/preprocessing/model identity on each successful draft; update mock adapter signatures.
- [ ] Run focused tests plus `flutter test test/services/receipt_parser_test.dart test/services/receipt_ocr_comparison_test.dart test/services/receipt_autofill_test.dart`; expect all pass and existing OCR parsing regressions unchanged.
- [ ] Commit: `feat: route receipt scans through explicit OCR engines`.

### Task 3: Cache scan results and reject stale completions

**Files:** Task 3 row; tests `test/services/scan_result_cache_test.dart`, extend `test/services/capture_state_test.dart`.

**Interfaces:** Consumes Task 2 descriptors/processing/run metadata and existing photo edits. Produces cache, selected result and private snapshot methods from Shared interface decisions. Recognition no longer navigates automatically; Task 7 wires actions.

- [ ] Write tests `switch_restores_result_without_inference`, `content_order_edit_and_version_invalidate`, `late_result_after_invalidation_is_ignored`, `dispose_never_notifies`, `failed_engine_does_not_erase_other_result`, `review_snapshot_does_not_mutate_cache`. Assert cached switch causes zero extra calls; each key component changes the key; delayed completion leaves current result absent; all busy paths restore controls; mutation of a review snapshot leaves cached draft unchanged.
- [ ] Run `flutter test test/services/scan_result_cache_test.dart test/services/capture_state_test.dart`; expect missing cache/lifecycle behavior failures.
- [ ] Implement cache key calculation with SHA-256 of actual bytes (not path/mtime), generation checks before state publication and disposal, per-engine results/errors, serialized recognize/retry, and deep snapshot handoff. Keep photo picker/editor behavior; release native sessions on closing. Cache outputs, never three live heavy model sessions.
- [ ] Run the focused tests including failed inference and cancelled input selection; expect pass with no unhandled async errors.
- [ ] Commit: `feat: cache OCR runs and guard scan lifecycle`.

### Task 4: Suggest missing fields without rewriting evidence or owner edits

**Files:** Task 4 row; new test `test/services/receipt_suggestion_service_test.dart`; extend `test/receipt_autofill_state_test.dart`, `test/receipt_review_state_test.dart`. Existing parser autofill tests remain parser tests.

**Interfaces:** Consumes current exact matching, confirmed alias suggestions, `PurchaseRecord` and existing date-choice logic. Produces provenance and pure suggestion service. Review state fetches history using existing confirmed-only comparison queries and guards late responses.

- [ ] Write tests with these exact assertions: same-supplier confirmed price 1,200 centavos is preferred over another supplier's newer 1,500; quantity 2 produces 2,400 estimated centavos; two matching catalog sizes produce no price; unknown pack denominator produces no piece cost; fractional weight produces no default counted quantity. Missing count suggests 1/pieces with assumed origin and `confirmed == false`; missing cost without evidence/history stays null even if printed receipt total is known.
- [ ] Add `owner_amount_survives_quantity_and_history_refresh`, `contradictory_printed_prices_remain_candidates`, `ambiguous_date_keeps_candidates`, `raw_evidence_is_byte_for_byte_unchanged`. Assert owner amount 1,300 remains after refresh; default import date is assumed, not confirmed; only complete line amounts contribute to a calculated total and incomplete sums are labeled partial rather than presented as a complete receipt total.
- [ ] Run `flutter test test/services/receipt_suggestion_service_test.dart test/receipt_autofill_state_test.dart`; expect absent-service failures.
- [ ] Implement typed provenance and snapshot copying. Seed extracted/calculated origins from existing parser evidence; use unique exact identity/confirmed aliases only. Choose historical prices using the existing date/time/saved-order contract, same supplier first; scale using known total-piece denominators with integer/rational centavo arithmetic and round once at the final line amount. Label source purchase/date/supplier and rounding. Never infer a pack size, allocate a remainder or modify raw text. Unknown names/suppliers stay display fallbacks with null identity.
- [ ] Integrate suggestions into `ReceiptReviewState` after matching. Explicit edit methods mark ownerEdited, invalidate confirmation and recompute only dependent non-owner fields; changing supplier invalidates supplier aliases/history. A manual clear is an owner edit and must stay empty. Keep existing discount-to-net preparation consistent so estimates are not discounted twice.
- [ ] Run focused tests plus existing parser, matching, date-choice and review-state suites; expect pass. Commit: `feat: suggest reviewable receipt fields with provenance`.

### Task 5: Persist pending receipts, evidence and a combined ledger

**Files:** Task 5 row; tests `test/services/receipt_snapshot_codec_test.dart`, `test/storage/pending_receipt_storage_test.dart`; extend `test/storage/sqlite_adapter_test.dart`.

**Interfaces:** Consumes draft snapshots/provenance, `LocalFileStore`, database executor and serialized adapter write queue. Produces Task 5 adapter operations/DTOs plus `PendingReceiptRepository` with the same save/load/feed signatures receiving its executor/file dependencies at construction.

- [ ] Write codec round-trip tests preserving nulls, ambiguous dates, raw text, original/comparison OCR line/token bounds, warnings, page order, source-page/duplicate linkage, run identity, all provenance and owner-cleared fields. Unknown codec version must throw a typed readable exception, not return an empty draft.
- [ ] Write SQLite tests `migrate_v7_retains_confirmed_data`, `save_failed_scan_and_reopen`, `pending_estimates_do_not_create_history`, `same_operation_retries_once`, `changed_payload_reusing_operation_is_rejected`, `stale_revision_keeps_current_data`, `failed_media_copy_cleans_only_new_files`. Save a zero-line photos-only draft and reload from a fresh adapter after deleting picker-cache sources; owned originals remain readable. Assert no products/suppliers/aliases/purchase lines are added. Test duplicate original hashes and receipt-number/supplier checks against both pending and confirmed records, with explicit owner override.
- [ ] Run `flutter test test/services/receipt_snapshot_codec_test.dart test/storage/pending_receipt_storage_test.dart`; expect missing schema/API failures.
- [ ] Implement migration 8: `pending_receipts` (snapshot version/payload, revision, timestamps, correction/base revision), `receipt_write_operations` (operation ID, kind, canonical digest, stable target/result/revision), `receipt_revisions` (immutable receipt ID/revision/prior payload/timestamp), `receipt_evidence` (current confirmed full snapshot/revision), and `ledger_entry_links` (stable pending ID to confirmed receipt ID). Initial pending/confirmed revision is 1; each committed edit increments it by 1. Legacy confirmed rows without evidence have revision 1 until their first correction. Add indexes/FKs; reuse current original media tables. Register schema version 8 and validate migration/FKs.
- [ ] Implement codec and repository. Persist every referenced original/recognition/comparison image once per content/role as needed, rewrite snapshot references to owned paths, retain content hashes/preprocessing identity, and commit pending row plus operation result atomically. Validate nullable types, 1–20 ordered photos, at most 1,000 lines, page alignment and owned evidence references at the storage boundary. Compare canonical content before idempotent return; reject stale revisions before replacing files. Failed writes remove only newly created copies; old committed media stays referenced. Pending duplicate errors reuse the existing review dialog contract; updates exclude their own pending/confirmed correction source from duplicate candidates. Preserve operation results after deleting a confirmed pending row so late retries still resolve its stable link.
- [ ] Implement combined feed in SQLite/mock adapters, sorted by recorded time with stable tie order and consistent search/limit. Keep `getRecentReceipts` and all comparison/cost queries confirmed-only. Pending correction appears as status on its existing confirmed ledger entry, with a route to the correction; it does not inflate receipt counts.
- [ ] Run focused storage tests and `flutter test test/storage`; expect pass, unchanged confirmed validation and confirmed-only calculations. Commit: `feat: store editable pending receipts and OCR evidence`.

### Task 6: Confirm imports and apply corrections atomically

**Files:** Task 6 row; tests `test/storage/pending_confirmation_test.dart`, `test/storage/receipt_correction_test.dart`; extend `test/storage/latest_product_costs_test.dart`.

**Interfaces:** Consumes Task 5 operation/revision tables, codec/repository and existing `ReceiptValidator`. Produces Task 6 adapter operations/DTOs. `ConfirmedReceiptWriter.write(DatabaseExecutor executor, ReceiptDraft snapshot, {String? replacingReceiptId}) -> Future<SaveReceiptResult>` operates inside the caller's transaction and never opens another transaction or write-queue operation.

- [ ] Write tests `confirmation_is_atomic_and_retryable`, `invalid_pending_stays_pending`, `confirmed_entry_link_survives`, `correction_preserves_recorded_order_and_images`, `stale_correction_does_not_replace_purchase`, `prior_revision_is_immutable`. Inject failure after receipt creation but before lines and assert zero new receipt/alias/history plus the intact pending row. Repeated same confirmation returns the same receipt ID. An unresolved amount cannot confirm. Edit amount 1,000 to 1,300: one receipt remains, comparison reflects 1,300, and prior revision retains 1,000.
- [ ] Add tests that correction line IDs map to actual saved purchase IDs; page order and original-image ordering remain stable; previous OCR evidence is retained in history; correcting product identity updates aliases only from explicit confirmed evidence without silently taking over another product's alias. Old revisions never enter current price queries. A changed command under a used operation ID throws; two confirmations with different IDs still produce one receipt.
- [ ] Run `flutter test test/storage/pending_confirmation_test.dart test/storage/receipt_correction_test.dart`; expect absent confirmation/update behavior failures.
- [ ] Extract the existing confirmed transaction body into `ConfirmedReceiptWriter`; keep validation, supplier/product creation, duplicate behavior, alias learning and initial-save idempotency unchanged. Map draft IDs to generated saved-line IDs in persisted evidence. Use the adapter's outer serialized write boundary, avoiding nested queue/transaction deadlocks.
- [ ] Implement confirmation: load pending snapshot/revision, validate a private copy, persist/reuse owned media, create/update confirmed receipt, store current evidence and stable link, record operation result and remove pending row in one transaction. For corrections check both revisions, archive the prior full snapshot, preserve initial recorded-at/saved sequence and original ordering, replace current line values, increment confirmed revision and retain prior media. Legacy receipts without OCR evidence build editable drafts from stored receipt/lines/photos without claiming extracted provenance. Invalid corrections remain pending while old confirmed data stays active.
- [ ] Run all storage tests plus comparison/restock/pricing suites; expect pass with exactly one active purchase after any retry/correction. Commit: `feat: confirm pending receipts and retain correction history`.

### Task 7: Add the selector and immediate save actions in the existing UI

**Files:** Task 7 row; new `test/ocr_model_picker_test.dart`, `test/receipt_immediate_save_test.dart`; extend capture/review/widget suites.

**Interfaces:** Consumes CaptureState snapshots, engine descriptors, Task 4 origins and Task 5 pending save API. Add `CaptureScreen.onPendingSaved(PendingSaveResult)` alongside existing draft-ready callback. Existing review receives optional pending/correction context and supports Save Needs review separately from its confirmed Save action.

- [ ] Write widget tests asserting ML Kit initial selection, exact three verified labels, selecting without inference, cached result restoration, explicit engine retry and one selected draft handed to Review. Save Needs review should call pending save without marking lines/date confirmed. OCR failure and no recognized lines still expose Save photos for later; zero photos do not. Double-tap disabled save must produce one operation ID/write.
- [ ] Add 360dp and 412dp tests at text scale 2.0: open/scroll selector, tap primary/secondary actions, expand raw text and show long engine/error labels with `expect(tester.takeException(), isNull)`. Preserve the existing receipt UI tests and shared control types. Test manual edits followed by replacing a result require explicit discard; cancelling preserves edits and cached state.
- [ ] Run `flutter test test/ocr_model_picker_test.dart test/receipt_immediate_save_test.dart`; expect missing selector/save behavior failures.
- [ ] Implement the model pill above photo preview, rounded selector sheet and compact recognition summary using existing colors/spacing/cards/buttons. Show actual item count/total/elapsed run time, no accuracy percentage. Selecting does not run OCR. Keep existing photo/manual controls and Photos–Review–Save step styling. Show estimated/partial totals and provisional cost-per-piece with origin labels.
- [ ] Wire Read receipt to selected recognition/result summary; primary Save Needs review snapshots then persists one stable command; secondary Review details opens current review. Photos-only save uses original ordered pages without fabricated lines. Review state preserves provenance and exposes pending save without validation intended only for confirmed purchases. Reuse duplicate-choice handling; keep current confirmed/manual save route.
- [ ] Run these tests and `flutter test test/capture_screen_test.dart test/receipt_review_screen_test.dart test/receipt_details_layout_test.dart test/receipt_review_widgets_test.dart`; expect all pass. Commit: `feat: add same-style OCR selection and immediate receipt saves`.

### Task 8: Reopen, edit and confirm pending receipts and corrections

**Files:** Task 8 row; tests `test/pending_receipt_screen_test.dart`, `test/ledger_pending_entries_test.dart`, `test/receipt_correction_ui_test.dart`.

**Interfaces:** Consumes ledger entries, pending/confirmed edit DTOs and Task 6 operations. `PendingReceiptController.load(String id)`, `save(ReceiptDraft draft) -> Future<PendingSaveResult>`, `confirm() -> Future<SaveReceiptResult>` tracks expected revision and one command ID per attempted content save; successful edit creates the next command ID. Lifecycle guards mirror the existing detail controller.

- [ ] Write widget/controller tests `pending_is_visible_after_reopen`, `edit_keeps_owner_value_and_photos`, `confirm_routes_to_same_entry`, `conflict_preserves_unsaved_input`, `confirmed_edit_creates_pending_correction`, `history_shows_prior_values`. Assert Unknown supplier is visible without a created supplier, amber Needs review includes text, comparison cost remains unchanged until confirmation, and conflicts require reload/merge choice rather than overwriting. Confirmed detail remains readable while a correction is pending.
- [ ] Add dashboard tests separating confirmed count from pending count/provisional totals, including one correction with no second purchase count. Test late detail loads, empty OCR, all-original photo access, preserved token overlay image space, and 360/412dp at text scale 2.0 without overflow. Assert existing confirmed cards/navigation remain available.
- [ ] Run `flutter test test/pending_receipt_screen_test.dart test/ledger_pending_entries_test.dart test/receipt_correction_ui_test.dart`; expect absent pending routes/controllers failures.
- [ ] Implement pending detail with existing receipt/photo widgets, origins and Edit receipt / Review and confirm actions. Reuse ReviewMatchScreen for editing a private snapshot; Save Needs review persists nullable edits and confirmation uses the validated boundary. Show validation problems inline and retain pending data. Resolve stable links after confirmation so reopened pending routes lead to the saved receipt.
- [ ] Change dashboard loading to combined summaries while catalog/latest-cost data continues using confirmed APIs. Add pending card/status and distinct counts with current theme. Add confirmed Edit receipt using `getConfirmedReceiptEdit`, saving a pending correction with base revision; show correction history from immutable revisions and keep initial purchase recorded ordering. Wire callbacks in main; do not introduce a second navigation shell.
- [ ] Run focused tests plus dashboard, detail, review and refresh suites. Commit: `feat: reopen and review ledger imports and receipt corrections`.

### Task 9: Verify offline first launch, restart and regression behavior

**Files:** Task 9 row; reuse existing device receipt fixtures and Task 1 manifest.

**Interfaces:** Consumes all approved contracts. Produces separate static/widget, real SQLite and physical-device verification evidence plus known limitations.

- [ ] Write device acceptance test for each real engine: upload ordered receipt pages, recognize, save pending, reload stored snapshot, edit amount, confirm and correct it; assert engine identity, preserved originals/evidence, provenance, one active purchase and correct revised cost. Include an unreadable receipt saved photos-only and later filled/confirmed. Do not count a same-process reload as process-restart proof.
- [ ] Run focused device test and fix actual failures within its owning task. Use `ORG_GRADLE_PROJECT_reseeboVerification=true` for Flutter device builds; verify APK application ID before installing. Test fixture images must be bundled/read locally when offline.
- [ ] Run `flutter analyze` and `flutter test` from app root; record actual counts/exit codes. Run Android native geometry/session tests. No warnings may be suppressed merely to get a green report; unrelated existing warnings are identified separately.
- [ ] Fresh-install only the verification package while offline. Verify all engines cold/warm without downloads, save pending/photos-only entries, force-stop and relaunch, then open/edit/confirm/correct. Verify originals and recognition-coordinate overlays, stable ledger links, revisions and comparison recalculation after another restart. Check ordinary app package/storage remained untouched. Record APK size, memory and timings separately per engine.
- [ ] Self-review diff against approved spec and unchanged UI baseline; use the chosen execution method's final independent review. Fix material findings and rerun affected checks. Update selector documentation to actual behavior, artifact identities and explicit engine limitations; record verification results without claiming perfect OCR or phone checks that did not run.
- [ ] Commit task-owned evidence/tests/docs: `test: verify offline OCR and reviewable ledger lifecycle`. Present changed behavior, tests and any remaining blocker. Do not mark three-engine/offline acceptance complete until physical proof passes.

## Self-review before handoff

- Spec coverage: native feasibility (1), routing/evidence (2), caching/edit isolation (3), suggestions/origins (4), durable nullable saves/feed (5), atomic confirmation/corrections/history (6), same-style upload actions (7), later editing/counts/navigation (8), offline/restart acceptance (9).
- Interface consistency: new IDs, provenance fields, snapshot codec, pending revision API and correction path are defined above and consumed unchanged; existing confirmed APIs remain compatible.
- Review Focus: each listed failure has named tests in its owning task. Storage tests use real SQLite, not mock-only assertions.
- Scope: no backend, generative model, global redesign, weighted confirmed schema or unrelated SDK upgrade. Native versions may change only for demonstrated model compatibility, with manifest/evidence updated.
- Execution: the user approved the design, implementation plan and parallel subagent work. Independent native, scan and suggestion work may proceed together; storage, correction and UI tasks consume reviewed contracts in dependency order.
