# System optimization review — 10 October 2026

Applied `3. System_Optimization_Prompt.md` to the current app, preserving existing
staged and unstaged receipt, catalog, and insights work.

## Changes

- Removed 17 unreferenced Dart files: superseded controllers, old receipt cards,
  an unused alias picker and camera overlay, an unused model export, and two
  unreachable planner screens with their exclusive widgets. Current navigation
  is unchanged. Pricing services and tested basket calculations remain.
- Removed the unused `cupertino_icons` dependency and refreshed its lockfile.
- Rank the catalog once per product-picker load and use a set for membership
  checks, rather than reranking for each fallback suggestion. Tokenize the
  receipt description once per ranking operation. Matching rules are unchanged;
  no latency benchmark or OCR accuracy improvement is claimed.
- Guard catalog loads and retry actions, show progress during retries, and
  disable adding products while the catalog is loading. Added a widget
  regression for failure, retry, action guards, and recovery.

## Existing contracts checked

Models, services, feature state and widgets are already separate. Shared theme,
controls, bundled Inter font and catalog assets are present. Dashboard search
filters loaded data locally. Receipt history reads already have a row limit;
no speculative pagination or schema change was introduced.

The SQLite boundary validates purchases, copies original images before saving,
commits receipt and lines atomically, and removes newly copied files on failure.
Operation IDs and payload checks support safe retries. Editable drafts survive
failed saves; UI success follows the committed write. Existing regression tests
cover rollback, duplicate handling, image retention and database reopening.
Routine app code has no receipt-content print/debugPrint logging.

## Verification

- Baseline: `flutter analyze` clean; all 277 existing tests passed.
- After picker/service/dependency changes: analysis clean; 278 tests passed,
  including the new retry regression.
- Final cleanup: `flutter analyze --no-pub` clean, all 278 tests passed,
  and `git diff --check` passed.
- Samsung device: `receipt_ocr_offline_test.dart` passed with Wi-Fi and mobile
  data disabled, using `com.reseebo.reseebo.verification`. Connectivity returned
  to Wi-Fi enabled / mobile data disabled afterward. The test creates a fresh
  isolated database, exercises bundled OCR on a generated receipt, saves a
  confirmed purchase, and verifies original image bytes after database reopen.
  The verification package already existed; this is not a fresh-install or
  full-process-restart test. The main installed app was not updated.
- Fresh-install first launch, a full app restart, real-receipt accuracy, and the
  complete offline comparison/calculation UI were not newly verified here.

This cleanup does not fix the measured Wellbest cross-item association or DALI
money-marker rejection documented in `receipt_accuracy_investigation.md`.
OCR comparison and product matching do not substitute for those parser fixes.
