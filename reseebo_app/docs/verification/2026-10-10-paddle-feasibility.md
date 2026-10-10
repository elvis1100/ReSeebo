# Paddle Android feasibility, 10 October 2026

Status: genuine artifacts bundled and native compilation passed. A guarded
physical-device probe exposed an OpenCV load failure; the documented packaging
fix is pinned and awaits a new physical probe. Both
Paddle descriptors remain `available: false`, `verifiedOnDevice: false`.
Neither choice may be advertised as usable by the production registry until the
Samsung proof below succeeds. ML Kit remains the available production engine.

## Provenance and packaging

The official SDK is vendored without source edits from PaddleOCR commit
`dab3fe35379033fdcb2d0e9572fac0b36c9a9ebf`. Its adapted Gradle wiring retains
Java 17 target, ONNX Runtime Android 1.21.1, OpenCV 4.5.3.0, Kotlin coroutines
Android 1.9.0 and AndroidX core-ktx 1.15.0. The upstream build and version catalog
are retained under `android/paddle_ocr/upstream/`. `source_manifest.json` pins
every vendored source file by immutable URL and SHA-256.

QuickBird's [official packaging guidance](https://github.com/QuickBirdEng/opencv-android)
specifically recommends 4.5.3.0 over 4.5.3 because 4.5.3 fails at runtime on
some Android versions. The Samsung probe demonstrated this failure:
`dlopen failed: cannot locate symbol __sfp_handle_exceptions` in arm64
`libopencv_java4.so`. Version 4.5.3.0 retains the same OpenCV release. The
manifest pins its Maven AAR SHA-256
`5736e3c7a23153478b62c60937fd5224eee267c59e077c053957d90c6736469e`
(53,990,420 bytes), plus hashes for its native libraries and ONNX Runtime's
native libraries. Original SDK source/catalog remain unchanged for audit.

Official reference: [Android deployment](https://github.com/PaddlePaddle/PaddleOCR/blob/dab3fe35379033fdcb2d0e9572fac0b36c9a9ebf/docs/version3.x/inference_deployment/cross_platform/android_deployment.en.md).
Its advertised small/tiny list is not evidence that Medium works on a phone.
The separately published genuine Medium detector and recognizer are bundled;
there is no substitution and no local model conversion.

| Component | Immutable model revision | ONNX bytes | SHA-256 |
| --- | --- | ---: | --- |
| PP-OCRv5 Mobile detector | e6f4fa85f00e168c862bc462aebca69eef9b3d3d | 4,826,518 | a431985659dc921974177a95adcfbb90fd9e51989a5e04d70d0b75f597b6e61d |
| English PP-OCRv5 Mobile recognizer | 3fafbc3b5dcf93dd72add9f48368be8a3a2cd33b | 7,848,423 | b5f833dfc5d0eb71da397b4efa06ebeee9b431b690a47d6af40d77d8eabc557f |
| PP-OCRv6 Medium detector | 61323801669c338b7891481ec7bac61ce31b576a | 62,032,837 | eb13b44b25bb36f89528b68720af8a61d9cf381176107f465db1757b65d086e1 |
| PP-OCRv6 Medium recognizer | 50c7eacafc52fa7bcf4194e8cd08e46f8558504b | 76,554,979 | 9c09abf0957f7968c7586464b7397b84ad2387a0497a351af40e9acc71b673ba |

`assets/ocr/model_manifest.json` records source repositories, immutable
revisions, config/dictionary files, hashes, byte counts, runtime versions,
preprocessing identity and availability evidence. The recognizer dictionaries
are embedded in each bundled `inference.yml` at `PostProcess.character_dict`.
The SDK parses that dictionary directly. Apache-2.0 model/SDK licenses, the
ONNX Runtime MIT license and third-party notices, OpenCV Apache-2.0 license,
QuickBird wrapper BSD-3-Clause license and coroutines Apache-2.0 license are
bundled as Flutter assets. The added QuickBird runtime contains libc++; its
license, including LLVM exceptions and legacy notices, is pinned to Android
LLVM commit `a2a1e703c0edb03ba29944e529ccbf457742737b` identified in the shipped
arm64 library's ELF compiler comment. All four ONNX files individually fit GitHub's 100MiB
file limit; no LFS or first-launch download is required.

Development preparation:

```powershell
python scripts/prepare_bundled_ocr.py --verify-only
python scripts/prepare_bundled_ocr.py
```

Use Python 3.11 or later. The second command restores missing/corrupt artifacts
from immutable URLs, verifies hashes before atomic replacement and never
changes availability flags. Application code contains no download path.

## Android compatibility release note

Minimum supported Android is now Android 8.0/API 26, using
`maxOf(flutter.minSdkVersion, 26)`. This is required by the pinned official SDK
and documented in its unchanged upstream build and deployment requirements.
The existing `com.reseebo.reseebo` ID is retained. Device tests opt into
`com.reseebo.reseebo.verification` through
`ORG_GRADLE_PROJECT_reseeboVerification=true`; never install/uninstall over the
owner's package.

## Native boundary and geometry

### Actual active configuration

Both engines use the pinned SDK's `PaddleOCRConfig()` and `EngineConfig()`
defaults. The detector YAML files are bundled and hash-checked as immutable
published model provenance; the bridge does **not** read them into runtime
detector configuration. The recognizer YAML is read for
`PostProcess.character_dict`, with a space appended if absent. Other recognizer
YAML settings are not applied by `ModelConfig.parse`.

| Active SDK setting | Value for both engines |
| --- | --- |
| Detector image mode | BGR |
| Side limit | 64 pixels, type `min` |
| Maximum side limit | 4,000 pixels |
| Detector threshold / box threshold / unclip ratio | 0.3 / 0.6 / 1.5 |
| Maximum candidates / dilation | 3,000 / false |
| Score mode / box type | fast / quad |
| Recognition score threshold / batch size | 0.0 / 1 |
| ONNX worker threads | 4 |

`min` raises a short side below 64 pixels; it does not resize every image to
64 pixels. The SDK caps the long side at 4,000 before rounding each dimension
to a multiple of 32 (half-to-even, minimum 32) and uses linear interpolation.
Detector normalization is hardcoded in `DetPreprocessor`: scale 1/255,
means [0.485, 0.456, 0.406], standard deviations [0.229, 0.224, 0.225], CHW.
The bundled Medium detector YAML instead declares thresholds 0.2 / 0.45 and
unclip ratio 1.4. Those published values are **not** the active configuration.
Threshold calibration is deferred to physical evidence; this clarification
does not tune settings or alter SDK source, weights, dependencies or inference.

The active configuration identity remains the immutable SDK commit in
`preprocessingRevision` (`paddle-sdk-dab3fe35379033fdcb2d0e9572fac0b36c9a9ebf`)
and `runtimeVersion`, because both constructor calls use that pinned source's
unmodified defaults. This is sufficient to reproduce the values above; no new
configuration or identity contract is introduced. The owning bridge now comments
on this distinction. Any later tuning requires physical calibration, explicit
active values and a preprocessing identity update. The manifest remains byte
identical to the inspected probe APK's embedded manifest; this review fix changes
documentation/comments only. Any future rebuilt APK still needs its own actual
package/hash inspection.

MethodChannel `reseebo/ocr` supports `recognize {engineId,imagePath}`,
`release`, and additive `engines` preflight. One mutex serializes recognition,
switching and teardown; work runs on `Dispatchers.IO`. The previous heavy
session is released before loading another. Assets are streamed through
SHA-256 validation before session creation. Native failures return explicit
channel errors instead of a fabricated empty result.

The ordinary package exposes only manifest entries whose availability and
device-proof flags are both true. The isolated verification package can probe
genuine bundled engines before acceptance. The Dart registry still applies
its manifest/proof gate; verification bypass is confined to the native probe.

The SDK's DB postprocessor maps detector coordinates back to decoded input
pixels and retains those detection quads through recognition crops. The bridge
must not invert that resize twice. It decodes encoded pixels without implicit
EXIF rotation so bounds refer to the supplied recognition image, then clamps
the returned line rectangle to its dimensions. No word/token bounds are
invented. Native geometry tests independently check a half-size/pad/crop
round trip of (100,200) and clipping to the input dimensions.

## Evidence and limitations

Artifact preparation tests were run red first: two failures because the
preparation script was absent. After implementation, both tests passed. They
exercise real files, verify a genuine fixture, reject a corrupt file and
reject a manifest path that escapes the project root. The complete downloaded
SDK/model/config/license hash verifier passed.

Initial physical probe command failed before execution: no supported device
matched `R5GL41586RA`; `adb devices` listed only `emulator-5554`. After the phone
reconnected, an unsafe host-wrapper environment-case bug caused the ordinary
package to be replaced and subsequently uninstalled by Flutter test cleanup.
See the [complete incident report](2026-10-10-paddle-verification-incident.md).
The owner reported no receipts in that app and an existing backup. Networking
settings were not changed. Native unit-test RED execution was initially blocked before
compilation by Java 21 `Unable to establish loopback connection`, rooted in
`PipeImpl` Unix-domain socket `Invalid argument: connect`. A command-local
short `jdk.net.unixdomain.tmpdir` probe returned `SELECTOR_OK`; no global JVM
configuration was changed. The vendored SDK subsequently compiled successfully,
and both native geometry tests passed (2 tests, 0 failures, 0 errors). The
device attempt returned explicit `engine_unavailable` errors because the APK
had the ordinary ID; this did not execute Paddle inference.

The corrected verification APK was inspected independently with `aapt2`; its
actual ID was `com.reseebo.reseebo.verification`, minimum SDK 26, target SDK 36,
SHA-256 `05decc2afe0a089539866cecb3f7d7b7676086ef8c5ddbc1559960524e412e64`.
The guarded prebuilt drive installed that exact binary and ran on Samsung
SM-A576B, API 36, arm64-v8a, 4,096-byte pages. Both tests failed before inference
at the OpenCV load error above. No OCR output, timing or overlays were produced.
Sampled process PSS peaks were 263,083 KiB for the v5 test and 421,611 KiB for
the Medium test; these are failed-initialization process measurements, **not**
inference memory or model allocation peaks. Debug APK includes INTERNET; its
manifest cannot establish offline acceptance. No networking setting was changed.

The corrected 4.5.3.0 photographed-receipt probe subsequently built successfully
in 83.6 seconds: actual ID `com.reseebo.reseebo.verification`, minimum 26,
target 36, SHA-256
`8c2a7d9f1e4272a97c989a0f55157c09c987115ddd8d446fa23bf34d2c9bdac2`,
496,279,541 bytes. The inspect-only helper verified and snapshotted this exact
APK. Samsung disconnected before installation; this corrected runtime has not
yet been exercised on the phone. The available emulator uses 16 KiB pages;
OpenCV's inspected arm64 ELF LOAD segments have 4 KiB alignment. No 16 KiB
compatibility is claimed and that emulator is not a substitute for Samsung proof.

Measurements requiring successful inference remain pending. Missing data is
not zero or an accuracy estimate.

| Acceptance measurement | PP-OCRv5 Mobile | PP-OCRv6 Medium |
| --- | --- | --- |
| Samsung loads and recognizes | Failed: OpenCV 4.5.3 symbol load | Failed: OpenCV 4.5.3 symbol load |
| Repeated runs without crash/OOM | Pending | Pending |
| APK byte size | 444,082,657 (shared guarded failed-probe debug APK) | Same APK |
| Sampled failed-initialization process PSS | 263,083 KiB | 421,611 KiB |
| Cold/warm elapsed milliseconds | Pending | Pending |
| Inspected receipt field agreement | Pending | Pending |
| Reviewed coordinate overlays | Pending | Pending |
| Fresh install with networking disabled | Pending | Pending |

The generated readable probe checks exact literal supplier/item/total strings
on three runs, artifact hashes, correct engine/model/runtime identity, input
dimensions, coordinate bounds and an `invalid_image` error. It measures native
plumbing on controlled text; it cannot establish accuracy on store receipts.
Two public receipt photographs are developer-only fixtures, bound to committed
independent transcription and image hashes in
`integration_test/fixtures/paddle_receipt_truth.dart`. They are not application
assets or distributed source images. Their probe reports whole-text lexical
presence separately from shared-parser supplier/date/total and uniquely
associated item quantity/gross-price agreement, including unresolved fields,
actual parsed lines, warnings and parser version. No whole-text numeric match
is claimed as item association. The original owner receipt filenames were not
found in the targeted host/shared-phone paths, so those photos are not scored.

Medium passes only after physical repeated-run, memory, timing, reviewed-output
and offline proof. An emulator run, if available, is provisional evidence only.

## Remaining physical verification

The user explicitly deferred device testing to themselves. No further agent
device installs or network changes are authorized for this phase. Follow the
[guarded user-run handoff](2026-10-10-paddle-device-handoff.md) for connected,
fresh offline and restart evidence. Both engines remain disabled pending review.

Before every installation, confirm Samsung `R5GL41586RA` and the package list.
Build separately, inspect the **actual APK** package ID with `aapt2`, and supply
an independently recorded SHA-256 to `scripts/run_paddle_probe.py`. Its default
is inspect-only; `--run` uses a revalidated immutable snapshot and Flutter drive
`--use-application-binary`, avoiding a rebuild between inspection and install.
Three host tests reject ordinary IDs, stale hashes and source replacement.
`scripts/observe_paddle_probe.py` rechecks that guard before observational ADB,
hash-checks optional public receipt inputs, copies only into the exact
verification cache under run-as, and collects full JSON, overlays and sampled
PSS. On evidence/pull errors it stops and waits for only the child process tree
it spawned before ending; three lifecycle tests cover this boundary. The
combined preparation/package/observer host test suite passes nine tests.
The ordinary package was removed in the earlier incident, so preservation of
its prior installation cannot be claimed. Restoration is a separate controller
action; this probe does not restore it.
Run native probe only after the corrected runtime APK passes that guard. Inspect receipt truth,
record each exact field's output and render coordinate overlays. Measure APK
bytes, `dumpsys meminfo` peak sampling and cold/warm runs. Fresh-install only
the verification package and prove first launch with networking unavailable.
If phone network settings must be changed, first record their prior values and
restore them in `finally`. Inspect the merged APK permissions; debug manifests
include INTERNET. Distinguish a permission-denial build from an actual
disconnected-phone proof. Change manifest availability only
after this evidence succeeds; otherwise preserve the exact failure and request
a replacement decision from the owner.
