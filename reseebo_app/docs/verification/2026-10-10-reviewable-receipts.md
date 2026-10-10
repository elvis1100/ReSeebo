# Reviewable receipts: acceptance preparation

Later update, 10 October 2026: [Paddle device acceptance](2026-10-10-paddle-device-acceptance.md) supersedes the disabled-Paddle and deferred-Paddle-inference statements below. Both manifest flags are enabled after offline Samsung checks. Broader production-flow persistence checks remain separate; the original evidence below is retained as history.

The later deadline request hands broader testing to the user. See
[the final code handoff](2026-10-10-deadline-handoff.md) for whole-project analysis,
bounded final UI checks and the unrun full-suite/final-APK/review gates. The
device checks below remain explicitly skipped.

Status on 10 October 2026: tests and retained-data handoff authored; 15 new Python
host guard tests and the full 24-test Python guard suite passed with exit 0.
The new Dart acceptance test was formatted (one file changed, exit 0) and
passed focused `flutter analyze --no-pub` with no issues (2.9s, exit 0). Root's
native geometry target passed 2 tests and bundled-artifact verification checked
51 manifest entries, both exit 0. The full
Flutter suite and ordinary Android build remain pending. The test has not run
on a device. The user explicitly skipped physical/device acceptance
because device testing is unavailable. Existing optional fixtures/guarded
instructions remain reference material; no physical checks or device APK work
are required for the remaining host scope. No agent
ADB, install, networking change, native inference, offline-first-launch or true
process-restart proof is recorded by this document.

ML Kit Latin is the real bundled default. PP-OCRv5 Mobile and PP-OCRv6 Medium
have genuine packaged artifacts but remain `available=false` and
`verifiedOnDevice=false`. Host compilation and an inspected APK do not satisfy
physical acceptance. The initial Paddle runtime failed with
`__sfp_handle_exceptions`; the corrected OpenCV 4.5.3.0 APK is described in
[the Paddle handoff](2026-10-10-paddle-device-handoff.md). Its hash and byte size
apply only to that earlier probe APK, which predates the ledger feature. The
retained optional handoff would require a separately built and independently
inspected reviewable-receipt acceptance APK if the user later chose that work;
there is no current acceptance APK build request.

## Evidence ledger

| Evidence class | Current status | What it can establish |
| --- | --- | --- |
| New acceptance Dart source/analyzer | Root formatting exit 0 (1 changed file); focused analysis no issues in 2.9s, exit 0 | Static source/contract compatibility; no integration/device execution |
| New Python guard tests | 15 passed, exit 0; full Python guard suite 24 passed, exit 0 | Wrong APK/hash refusal, immutable source, retained-data restart command boundary under controlled host inputs; no real ADB/Flutter launch |
| Existing widget/static checks | Reported separately by owning tasks/root | UI, state and validation regressions; no phone proof |
| Existing real SQLite tests | Reported separately by Task 6/root | Atomic writes, rollback, revisions, idempotency and media persistence on local SQL |
| New Android integration lifecycle | Explicitly user-skipped, not run | Authored only; no Android OCR/SQLite/process proof |
| Android native geometry tests | `:app:testDebugUnitTest` BUILD SUCCESSFUL in 1m 22s, exit 0; JUnit 2 tests, 0 skipped/failures/errors | Host coordinate-transform/clipping contracts; no native inference or device/session proof |
| Bundled artifact identities | `prepare_bundled_ocr.py --verify-only`, exit 0; 51 Verified manifest entries, including repeated paths | Pinned SHA integrity only; not 51 distinct assets and not accepted inference |
| Each engine's fresh-install offline inference | Explicitly user-skipped; no accepted engines recorded here | No physical inference claim |
| Real receipt-photo accuracy and overlay inspection | Explicitly user-skipped, not run | No real-photo accuracy claim |

Do not report skipped Paddle tests as passing engine acceptance. Do not call an
adapter/database close and reopen a process restart. A connected native run
does not establish offline-first-launch behavior.

## Authored device test

`integration_test/reviewable_receipt_offline_test.dart` uses actual Android
sqflite, the real adapter, the bundled engine registry and real media files.
Each available engine gets its own database/media directory under the
verification package's private support directory. The ordinary ledger is never
opened. Unavailable descriptors produce explicitly named skipped tests with
the registry's reason; there is no fallback inference or simulated engine.

Task 1 supplies local generated receipt fixtures using `image.arial48`, not
bundled shop photographs. This test reuses that technique: two ordered pages
with independently specified coffee/soap amounts and a blank unreadable page.
It uses only packaged Dart/image resources and creates files on-device; no
download, account or cloud call is involved. These fixtures establish plumbing
and lifecycle behavior, not field accuracy on the owner's receipts. The public
photos bound to `fixtures/paddle_receipt_truth.dart` remain developer-only inputs
and are not downloaded or reclassified as bundled application assets here.

One immutable test APK automatically reads a retained `lifecycle.json` marker:

1. **seed:** assert an empty ledger and packaged starter catalog; recognize
   both ordered pages cold and warm with the chosen real engine; save/retry a
   Needs review snapshot with extracted provenance and no confirmed purchases;
   save the unreadable original photos-only. Remove the picker-like source
   directory and verify owned image bytes/hashes, dimensions, preprocessing
   identity and recognition/comparison coordinate links.
2. **review:** require a different native PID and process token, then reopen
   pending evidence. Reject incomplete confirmation with no active purchase;
   edit amounts, reject a stale revision, confirm/retry and resolve the original
   import link. Save and confirm a correction, retaining initial order, line
   IDs, recorded time, originals and one active purchase. Fill and confirm the
   photos-only import using explicit owner values.
3. **verify:** require another different PID/token, reopen current/prior
   snapshots and original media, check owner/extracted origins and unchanged raw
   OCR/geometry, verify one history purchase with revised 13000-centavo unit
   cost, immutable revision 1 and the confirmed photos-only receipt.

The marker advances only after all available engines complete a phase. A fourth
launch rejects `complete`; it does not silently start a new acceptance run.
Failures retain the database and media for inspection. A failure partway through
seed/review may require a new explicitly requested verification-only fresh run;
there is no automatic reset/retry that could erase evidence. These assertions
do not simulate a process crash during file copy or SQL commit: retain the local
fault/rollback tests and record actual crash-injection testing separately.

## Host checks to run after the shared test slot is released

Root completed normal repository static preparation on 10 October 2026 from
the app root, with raw evidence in `task-9-dart-root.log`:

```text
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe format integration_test/reviewable_receipt_offline_test.dart
Formatted 1 file (1 changed) in 0.01 seconds. Exit 0.
C:\src\flutter\bin\flutter.bat analyze --no-pub integration_test/reviewable_receipt_offline_test.dart
No issues found! (ran in 2.9s). Exit 0.
```

This focused analysis does not establish the full repository analysis/test
suite or an ordinary Android APK build; those host results remain pending.

For the remaining full-repository checks from `reseebo_app`, record full output,
counts and exit codes; do not suppress warnings. These commands do not run the
phone acceptance test:

```powershell
& 'C:\src\flutter\bin\flutter.bat' analyze
& 'C:\src\flutter\bin\flutter.bat' test
```

Initial authorized Python host execution used `-m unittest discover -s scripts -p
test_*.py -v`: `Ran 23 tests in 0.830s`, `OK`, exit 0. The exact package-module
invocation `-m unittest scripts.test_run_reviewable_receipt_acceptance -v`
reported `Ran 14 tests in 0.170s`, `OK`, exit 0. All phone/Flutter process calls
in those Python tests used controlled host callbacks/mocks. They establish guard
behavior, not actual installed APKs, new app processes, inference or offline
acceptance. The observer test's printed `PROBE_EXIT 1` is its deliberately
corrupt-evidence cleanup fixture; the unittest suite exited 0.

The first isolated 11-test run had one erroneous assertion: it classified the
`installed.apk` pull destination as an install action. The assertion now checks
exact install/uninstall/clear command arguments. A separate package-module run
then exposed a missing package-aware import; that invocation passed after the
new helper adopted the existing relative-import convention. These were real
host failures and fixes; no claim is made that all guards were observed RED.

The independent review then identified command-log writing outside the owned
forward's cleanup block. A controlled directory at `command.json` reproduced
missing port cleanup: one test failed with exit 1. Moving only that write inside
the existing `try/finally` made the full new-module suite pass: `Ran 15 tests in
0.243s`, `OK`, exit 0. The full Python regression suite reported `Ran 24 tests
in 0.824s`, `OK`, exit 0. Raw RED/GREEN/full logs are retained with the Task 9
SDD report. All device/process boundaries remained controlled host fixtures.

Root subsequently ran `:app:testDebugUnitTest`: `BUILD SUCCESSFUL in 1m 22s`,
exit 0, saved in `final-native-unit.log`. The real current JUnit XML for
`com.reseebo.reseebo.ocr.PaddleGeometryTest` records tests 2, skipped 0, failures
0, errors 0, timestamp `2026-10-09T23:45:20.758Z` (10 October locally). Its two
tests cover resize/pad/crop coordinate inversion and clipping outside-image
bounds. This is host geometry evidence, not phone inference or session proof.

The native build retained the future-support warnings for Gradle 8.14.0,
AGP 8.11.1 and Kotlin 2.2.20, the embedded Kotlin/Kotlin DSL compatibility
warning, SDK XML tools mismatch warning and Gradle deprecations. No warnings
were suppressed and no toolchain upgrade was performed for this evidence.

Root's existing `scripts/prepare_bundled_ocr.py --verify-only` returned exit 0,
saved in `final-artifact-identity.log`, with 51 `Verified` manifest entries.
Repeated paths are included in that count; it is not 51 distinct assets. This
check establishes pinned artifact SHA integrity only. Dart/Flutter commands
were deliberately withheld during initial acceptance authoring while Task 6
owned the shared check slot; later root static results are recorded above.

## Optional previously authored immutable verification APK handoff

The user has explicitly skipped device work. This pre-existing optional handoff
is retained for reference; it is not a request to run device checks or an
outstanding task. No new device build, install or phase is scheduled.

No commands below have run as part of this task. Use the Samsung serial
`R5GL41586RA`, user 0, and manually disconnect Wi-Fi/mobile data before the
first fresh installation. Record the phone identity and networking state for
all three phases; host USB VM-service communication is separate from phone
internet. Do not enable Paddle flags to make the skipped tests green.

Build separately, preserving prior environment values. The verification flag
must be set for the build; independently inspected APK identity is the safety
gate, not an environment variable. API 26 is the Android 8.0 minimum floor.

```powershell
Set-Location -LiteralPath 'C:\Users\John Brayl\Documents\GitHub\TeamCus\reseebo_app'
$receiptPriorVerification = [Environment]::GetEnvironmentVariable('ORG_GRADLE_PROJECT_reseeboVerification', 'Process')
try {
  $env:ORG_GRADLE_PROJECT_reseeboVerification = 'true'
  & 'C:\src\flutter\bin\flutter.bat' build apk --debug --no-pub --target integration_test/reviewable_receipt_offline_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Build failed; do not install.' }
} finally {
  [Environment]::SetEnvironmentVariable('ORG_GRADLE_PROJECT_reseeboVerification', $receiptPriorVerification, 'Process')
}
$receiptPython = 'C:\Users\John Brayl\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$receiptApk = Join-Path $PWD 'build\app\outputs\flutter-apk\app-debug.apk'
Get-FileHash -Algorithm SHA256 -LiteralPath $receiptApk
& 'C:\Android\Sdk\build-tools\36.0.0\aapt2.exe' dump badging $receiptApk
```

Stop unless the **actual** package is exactly
`com.reseebo.reseebo.verification`, minimum SDK 26, and the target/byte size are
recorded. Copy the independently printed hash into the value below. Never reuse
the Paddle probe hash for this different APK. The helper defaults to host-only
inspection and copies/revalidates a hash-named immutable snapshot before any
device action.

```powershell
$receiptExpectedHash = 'REPLACE_WITH_INDEPENDENTLY_INSPECTED_64_CHARACTER_SHA256'
& $receiptPython scripts/run_reviewable_receipt_acceptance.py --apk $receiptApk --sha256 $receiptExpectedHash
if ($LASTEXITCODE -ne 0) { throw 'Guard rejected APK; stop here.' }
```

Seed with `--fresh-install` permits removing **only existing verification
data**, after the exact APK hash/package guard. Export any needed prior
verification evidence first. The helper has no ordinary-package install,
uninstall, clear, force-stop or run-as command. The first Flutter drive uses the
immutable binary and `--keep-app-running`, which local Flutter source confirms
suppresses its normal stop/uninstall cleanup.

```powershell
& $receiptPython scripts/run_reviewable_receipt_acceptance.py --apk $receiptApk --sha256 $receiptExpectedHash --phase seed --fresh-install --run --output build/reviewable-user-seed
if ($LASTEXITCODE -ne 0) { throw 'Seed failed; retain logs/data before a new run.' }
& $receiptPython scripts/run_reviewable_receipt_acceptance.py --apk $receiptApk --sha256 $receiptExpectedHash --phase review --run --output build/reviewable-user-review
if ($LASTEXITCODE -ne 0) { throw 'Review failed; retain logs/data.' }
& $receiptPython scripts/run_reviewable_receipt_acceptance.py --apk $receiptApk --sha256 $receiptExpectedHash --phase verify --run --output build/reviewable-user-verify
if ($LASTEXITCODE -ne 0) { throw 'Verify failed; retain logs/data.' }
```

Restart phases inspect/pull the installed verification base APK and recheck its
actual hash/package against the pinned build before force-stop. They never
reinstall. They start the exact verification activity, observe a new PID and
loopback VM service URI, forward only that owned port and attach using
`--use-existing-app`. The same immutable APK chooses phases from its persistent
marker, without different compile-time defines. On failure the helper stops and
waits only its owned host child tree; it retains verification storage and removes
only its owned port forwarding. Split APKs and mismatched markers are rejected.

Inspect `flutter.log`, `command.json` and `lifecycle.json` in each output folder.
`memory-after-phase.txt` is an after-phase PSS observation, **not peak per-engine
memory**. Cold/warm timings appear in `REVIEWABLE_ENGINE` log records; parser
and coordinate evidence are inspected through stored snapshots. Capture native
Paddle probe timings/peak memory separately if/when its own user tests run.

The runner's host guards passed with controlled test inputs; its real
installed-binary/VM-service handoff remains unexecuted and requires the first
user-run attempt to validate. A timeout
or failed connection is not a passing restart. Keep its logs and the retained
marker; do not substitute direct `flutter test -d` or an unguarded rebuild.

## Optional manual checks retained for reference

The integration target exercises adapter contracts and does not navigate the
product UI. After the owner restores/runs the completed app, keep networking
disabled and verify Photos → model sheet → recognition → Save Needs review;
open originals and recognition overlays, enlarged text at 360/412dp, photo
editing/page reorder, Review and confirm, correction history, and stable ledger
links after a true close/relaunch. Compare exact brand, variant and size against
the photographed receipt. Confirm a pending estimate does not alter cost,
restock or profit inputs; a confirmed correction should alter the current cost
without adding another purchase.

Record the ordinary app's prior installation/data status before and after from
the owner's own observations; the earlier incident is documented separately and
must not be rewritten as successful preservation. Save screenshots, failure
details and real-photo truth alongside engine-specific results. Restore only
the networking settings the owner explicitly changed for their check.

## Acceptance ruling

All physical acceptance was explicitly skipped by the user and is outside the
remaining host work. This authored lifecycle harness does
not establish first-launch offline behavior, three accepted engines, UI device
usability, peak memory, real-photo OCR accuracy, or crash consistency. Update
this evidence ledger only with exact commands, exit codes, counts, inspected APK
identity, device/network records and distinct-process results actually obtained.
