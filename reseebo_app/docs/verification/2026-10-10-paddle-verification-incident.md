# Verification application-ID incident

10 October 2026. This report records an agent error, not an OCR model failure.

The first native probe wrapper built and installed the ordinary
`com.reseebo.reseebo` package. The subsequent retry finished its Flutter test;
Flutter's default integration-test cleanup then uninstalled that package
without retaining application data. The agent failed to inspect the freshly
built APK's actual application ID before installation. Device writes were
stopped when the native `engine_unavailable` error exposed the wrong package.
The controller informed the owner. The owner said the app had no receipts and
that they have a backup. Ordinary-app restoration is controlled separately by
the controller; this report does not claim restoration has happened.

## Exact cause and sequence

1. Read-only initial Samsung baseline: `SM-A576B`, Android API 36,
   `getconf PAGE_SIZE` = 4096. User-0 package `com.reseebo.reseebo` existed,
   versionCode 1, versionName 1.0.0, minSdk 24, targetSdk 36,
   lastUpdateTime `2026-10-10 05:19:26`, firstInstallTime
   `2026-10-09 22:24:19`. The verification package was absent.
2. Direct PowerShell Gradle native tests used
   `ORG_GRADLE_PROJECT_reseeboVerification=true`. Their merged manifest
   correctly had `com.reseebo.reseebo.verification`. Both native geometry tests
   passed. This manifest was incorrectly treated as sufficient assurance for a
   later, different build invocation.
3. A temporary ignored host runner at `build/paddle_probe_runner.py` copied
   Python `os.environ`, set the verification environment variable and launched:

   ```text
   C:/src/flutter/bin/flutter.bat test --no-pub --reporter expanded integration_test/paddle_engine_probe_test.dart -d R5GL41586RA
   ```

   Windows Python normalizes environment keys to uppercase. A minimal host
   reproduction printed
   `('ORG_GRADLE_PROJECT_RESEEBOVERIFICATION', 'true')`. Gradle project property
   names are case-sensitive; the application's existing camel-case property
   lookup did not see this spelling. Flutter's rebuilt APK therefore used the
   ordinary application ID. The wrapper had no post-build APK package guard.
4. The first wrapper failed with a `cp1252` UnicodeEncodeError printing Flutter's
   `√ Built` line after a successful build. Its child Flutter process continued
   far enough to replace the ordinary app. The later retry's saved baseline
   already shows minSdk 26, lastUpdateTime `2026-10-10 06:15:02`, and the original
   firstInstallTime. This proves the first build had already replaced the app;
   wrapper failure did not guarantee the child was stopped.
5. The wrapper's stdout encoding was changed to UTF-8, and the same unguarded
   command was rerun. APK installation completed in 15.1 seconds. Both engine
   tests immediately returned `PlatformException(engine_unavailable, ...)`
   because the native verification bypass correctly rejected the ordinary ID.
   No Paddle inference occurred. The native assets/hashes themselves were not
   the failing boundary.
6. Flutter test cleanup stopped and uninstalled the identified application.
   Inspection of the installed Flutter source confirms installation uses
   `adb install -t -r <apk>` and default cleanup uses
   `adb uninstall <application ID>`. No `-k` flag is supplied. The command did
   not specify a device user; the future helper explicitly uses user 0.
7. `pm list packages --user 0 com.reseebo` and the same query with `-u` returned
   no package. `dumpsys package com.reseebo.reseebo` returned
   `Unable to find package`. Actual aapt2 inspection and Gradle output metadata
   independently confirmed the built APK ID was `com.reseebo.reseebo`.

The initial wrapper's build APK was 370,843,288 bytes. Full local incident
evidence is retained under ignored `build/paddle-incident-2026-10-10/`, including
probe logs, metadata, manifest, ordinary-app before/after metadata and network
settings. The temporary unsafe wrapper is not a checked-in execution path.

## Data and network evidence

No application-data backup was taken by this task before the probe. The saved
baseline was package metadata only, not a database or media backup. The app
stores `reseebo.sqlite` and its `media/` folder in its private application
support directory. The uninstall did not retain this private data.

Read-only narrow recovery checks found no Reseebo SQLite/archive backup under
the repository or this chat's visualization directory. The phone's external
`Android/data/com.reseebo.reseebo` and `Android/media/com.reseebo.reseebo` folders
were absent. A targeted shared DCIM/Pictures/Download search did not locate the
two exact owner-photo filenames. Two host temp databases under
`reseebo-live-ui-*` have schema version 2, four receipts/four lines, suppliers
Puregold/Wholesaler and duplicate Brand X Original Coffee products. These are
consistent with UI fixtures; they are not an established backup of the owner's
phone ledger. No recovery or reinstall was attempted during the read-only
investigation.

Network state before and after both attempts was Wi-Fi 1, mobile data 1,
airplane mode 0. Neither attempt changed networking. There was no offline proof.

## Permanent protections and verification

The app's Gradle wiring now accepts the Python-uppercase environment spelling
as well as the original camel-case project property. This compatibility fix
is insufficient on its own: every future device run must use the actual APK
guard below.

`scripts/run_paddle_probe.py` consumes an already built APK and an independently
recorded SHA-256. It runs aapt2 on that APK, requires the exact
`com.reseebo.reseebo.verification` ID, copies it to a hash-named snapshot and
validates the snapshot's hash/ID immediately before launching. It defaults to
inspection only. With `--run`, it uses Flutter drive's verified
`--use-application-binary` path and an integration-test driver; this path does
not rebuild the application. It passes `--device-user=0`, never clears or
uninstalls a package, and never changes networking.

Three host tests verify refusal of the ordinary ID before any device command,
refusal of a changed APK before the package tool/device command, and use of a
verified snapshot even if another source build replaces the source file.
All three passed. Independently running the real helper against the actual
ordinary-ID APK returned exit 1 and
`Refusing package ID com.reseebo.reseebo; expected com.reseebo.reseebo.verification`.
No ADB command was executed by that refusal check.

The controller must independently inspect the actual guarded APK ID/hash and
planned command before authorizing renewed device writes in this session.
Paddle availability flags remain false until physical inference and offline
acceptance are proved. Any future offline harness must record and restore the
prior network settings only when it actually changes them.

## Guarded follow-up outcome

After the owner reported no receipts in the removed app and an existing backup,
the controller independently inspected the corrected APK and authorized the
guarded connected probe. SHA-256 was
`05decc2afe0a089539866cecb3f7d7b7676086ef8c5ddbc1559960524e412e64`,
actual package ID `com.reseebo.reseebo.verification`, size 444,082,657 bytes.
The helper installed only that immutable binary with Flutter drive. Both native
tests reached the isolated app but failed before OCR at OpenCV 4.5.3's missing
`__sfp_handle_exceptions` symbol. The independent feasibility report records
the fix and separates those failed-initialization measurements from inference.
No ordinary package restoration or network setting change occurred in this run.
