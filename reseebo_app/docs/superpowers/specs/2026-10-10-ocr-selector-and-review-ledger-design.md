# OCR selection and immediate ledger saving

Date: 10 October 2026. Status: design for user review; product implementation
has not started. This extends `docs/ocr_model_selector_plan.md` with the user's
approved Needs review workflow and existing UI preservation requirement.

## Intended result

An owner uploads receipt photos, reads them with a selected bundled engine,
sees populated suggestions, and can immediately save the result to the ledger.
Saving does not require manually confirming every item. The saved receipt is
marked **Needs review**, retains original photos and evidence, and can be opened
and corrected later. Confirmed purchases remain available for comparisons.

The user approved filling suggested costs and marking receipts Needs review.
They also approved the preceding recommendation that these suggestions do not
affect confirmed cost comparisons until reviewed. Estimates remain visible in
the receipt, including an explicitly provisional cost per piece when the
required positive amount and piece denominator are available.

All inference and storage work offline from first launch. No account, cloud
inference, runtime model download, or additional generative language model is
introduced by this design. OCR reads text; a separate local autofill service
derives suggestions from evidence and saved purchase history.

## Preserve the current UI

Retain the current Photos, Review and Save steps, app bars, photo editor, page
strip, digital receipt presentation, original-photo access, catalog matching,
and existing navigation. Reuse AppButton, AppCard, Notice, shared fields,
AppColors, AppSpacing, the theme's Inter typography and existing corner radii.
Avoid redesigning surrounding screens or changing global tokens.

Add a compact model pill immediately above the Photos preview. It opens a
rounded bottom sheet with precise engine names, selection state and current
result status. ML Kit is initially selected. Add a compact recognition summary
using the existing receipt/card style: item count, receipt total, elapsed time,
raw-text disclosure and error/retry state. These values report this run, not
accuracy. Selecting an engine never starts recognition automatically.

After recognition, the primary action can save the selected result directly
as Needs review. A secondary Review details action opens the existing editable
review flow. Existing manual-entry and photo-edit actions remain available.
Once photos exist, Save photos for later is also available without successful
OCR, so a failed reading never prevents preserving a receipt in the ledger.
Needs review receipt cards use an amber label with text as well as color.
Receipt details offer Edit receipt and Review and confirm using existing
controls. No model, estimate, or status badge may clip long labels or enlarged
text at 360dp or 412dp.

## Real engine feasibility before routing

Target ML Kit Latin, PP-OCRv5 Mobile with English recognition, and PP-OCRv6
Medium as specified by the supplied plan. Pin exact model/runtime versions,
artifact hashes, dictionaries, licenses and preprocessing in a provenance
manifest. Package all required native libraries and model assets in the APK.
Any development-time downloads are separate from application behavior.

First prove both Paddle variants on the connected Samsung SM-A576B using an
isolated verification application. Record APK bytes, native process memory,
cold/warm timings, and output against inspected receipt truth. Repeat from a
fresh verification installation with phone networking disabled. Never replace
or uninstall the owner's ordinary application to perform this proof.

Paddle's official Android example uses ONNX Runtime and OpenCV. Its advertised
model list does not prove Medium performance on this phone. Medium therefore
has its own feasibility test; do not relabel a smaller model or show a working
option backed by simulated output. If a requested engine fails, preserve the
working ML Kit path, report the exact blocker and obtain a decision on an
alternative before finalizing the promised three-engine integration.

Primary references:

- [Paddle Android deployment](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/inference_deployment/cross_platform/android_deployment.en.md)
- [PP-OCRv6 documentation](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/algorithm/PP-OCRv6/PP-OCRv6.en.md)
- [English PP-OCRv5 recognition model](https://huggingface.co/PaddlePaddle/en_PP-OCRv5_mobile_rec)

## Routing, coordinates and scan state

Introduce an explicit engine identifier and versioned registry at the existing
OcrService boundary. All engines return immutable OCR lines and available word
bounds in the exact recognition-input image's coordinate system. Detector
resize, padding, rotation and crop transforms are inverted before returning
coordinates. Parsing and multi-page overlap handling remain shared.

Use one selected engine for every ordered page. Do not silently substitute an
engine or mix fields from multiple engines. Serialize native inference, load
heavy engines lazily and dispose their sessions when switching/closing. Cache
outputs rather than retaining three loaded models. Run native work off the UI
thread and attach failures to the engine which produced them.

Cache raw evidence, parsed draft, timing and error per engine in the scan
session. Keys include ordered photo-content hashes, edit/preprocessing revision,
model/runtime identity and parser version. Changing photos, order or processing
invalidates results. A request/session generation prevents late completions
from restoring stale data or notifying disposed state. Switching restores a
current cached result without rerunning OCR. Input/engine controls are disabled
during recognition and restored on every exit path.

Review receives a private snapshot of only the selected current result.
Returning from Review preserves caches. Replacing a result after manual edits
requires an explicit replace/discard decision; never overwrite edits silently.

## Missing-field suggestions

Keep raw OCR unchanged. Every suggested field records an origin: extracted,
receipt calculation, catalog/history estimate, assumed default, or owner edit.
Estimates are labeled and never acquire owner confirmation automatically.
Changing a driving field recomputes dependent suggestions while preserving any
explicit owner-edited dependent value. An inference cannot feed itself back
into the service as new OCR evidence.

Apply suggestions in this order:

1. Use unambiguous receipt evidence and existing exact arithmetic. Keep printed
   line totals distinct from unit prices. Preserve contradictory candidates for
   review rather than reconstructing OCR characters to make totals agree.
2. Use a unique exact catalog identity or confirmed supplier alias where
   available. Never match a competing size/variant to fill a price.
3. For a missing line cost with an exact product identity, propose its latest
   confirmed purchase price from that supplier, then the latest confirmed
   price from another supplier. Label the historical date/supplier and estimated
   origin. Convert only when the required unit/pack denominator is known.
4. A missing counted quantity can suggest one and a missing count unit can
   suggest pieces. Mark both as assumptions. Do not turn fractional weights
   into piece counts. Do not assume pack contents or expand unknown product
   identities. Pack conversion must remain unresolved without evidence.
5. A missing transaction date can suggest the import date, labeled estimated;
   preserve ambiguous printed alternatives. A missing supplier/name uses a
   visible Unknown label in pending storage without creating a catalog entity.
6. A missing receipt total may be the sum of available complete line amounts,
   labeled calculated. Do not distribute a printed remainder among unknown
   items or invent an arbitrary peso cost when neither receipt nor history
   supports one. Save unresolved fields as well; they do not block Needs review.

This fulfills low-effort saving without presenting guessed values as verified
purchase facts. Confirmation still requires valid complete whole-piece data;
weighted purchases remain editable pending receipts under the current model.

## Durable pending receipts and later corrections

Add a versioned SQLite migration after schema version 7. Store pending imports
separately from the current constrained receipts/purchase_lines tables so null
or suggested values do not weaken confirmed purchase invariants. Persist an
explicit versioned snapshot containing editable fields, origins, engine/run
identity and OCR evidence. Store ordered original photo files durably.
Retain each recognition image referenced by token bounds, with its content hash
and preprocessing identity, so reopening never overlays those bounds on a
different original or newly regenerated image. Preserve these references when
confirming or revising the receipt.

Expose adapter operations to save/load/update pending receipts and obtain a
ledger feed combining pending and confirmed entries. Pending entries do not
create products, supplier aliases or purchase-history prices. Confirmed-only
queries continue to drive comparisons, buying recommendations and profit.
Receipt-count indicators distinguish pending items from confirmed purchases;
totals displayed for pending receipts are explicitly provisional.

Pending saves and edits use operation IDs and expected revisions to prevent
duplicate submissions and stale updates. Original-image hashes and existing
receipt-number/supplier evidence inform duplicate detection; importing a
possible duplicate requires an explicit user choice. File copy and SQLite
transaction cleanup preserve existing atomic save behavior.

Confirming a pending receipt validates its private snapshot using the existing
purchase boundary, atomically creates the confirmed purchase and removes the
pending record. The ledger entry remains navigable to the resulting receipt.
Repeated confirmation returns the same result instead of adding another purchase.
Confirmed aliases are learned only from the confirmed result.

Later edits of confirmed receipts use a separate update operation rather than
reusing initial-save idempotency. Before replacing current values, store the
prior receipt/line snapshot in an immutable revision table. Update receipt and
line values atomically, retain originals and initial recorded ordering, and
recalculate comparisons from the current revision. Old revisions remain
available as correction history and are not counted as new purchases.
Edits that no longer meet confirmed validation are saved as pending corrections;
the last confirmed purchase remains active until the correction is confirmed.

## Verification and acceptance

- Retain the existing 19 receipt UI baseline tests. Add tests for small-screen
  and enlarged-text selector sheets, preview, pending badges and later editing.
- Verify cache isolation, stale-completion rejection, per-engine errors, retry,
  photo invalidation, disposal and preserving Review edits.
- Test every estimate origin, exact identity, historical price selection,
  missing amounts, assumed counts, fractional weights, contradictory prices,
  pack conversion, and protecting manual values. Assert raw OCR is unchanged.
- Use real SQLite tests for migration from version 7, pending save/edit/reopen,
  duplicate/idempotent writes, atomic confirmation, revision conflict handling,
  correction history and original-photo retention. Confirm pending estimates
  never enter confirmed comparison/profit queries.
- Run flutter analyze, focused checks and the full suite from reseebo_app.
- On the isolated physical-phone app, prove each bundled engine offline, then
  save a pending receipt, stop/restart the process, edit/confirm it and verify
  preserved photos, evidence, revisions and recalculated costs offline.
- Report static/widget, database, native inference and process-restart results
  separately. Desktop output and simulated mockups never count as phone proof.

## Review and execution boundary

The original selector plan supplies engine comparison requirements; this design
supplies the additional user-approved immediate-save behavior. Review this
design before the detailed implementation plan is written. Work is sequential
under AGENTS.md; a separate request is required before using parallel agents.
