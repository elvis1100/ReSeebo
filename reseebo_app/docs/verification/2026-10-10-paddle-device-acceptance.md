# Paddle device acceptance — 2026-10-10

Status: **Paddle device checks passed; both manifest availability and device-proof flags are enabled.** The revised runtime completed offline first-launch inference and a process-restart check on the Samsung below. The ordinary app update was installed successfully with `adb install -r`; its SQLite database SHA-256 was unchanged immediately after installation.

## Device and isolation

- Samsung SM-A576B, Android API 36, 4,096-byte memory pages.
- Probe package: `com.reseebo.reseebo.verification`.
- The ordinary `com.reseebo.reseebo` installation and receipt data are preserved.
- Verification APK identity is checked before installation; receipt samples are
  local DALI and Savemore photographs with independently checked hashes.

## Connected run: streaming alone was insufficient

Runtime suffix: `reseebo-streamed-models-1`.
APK SHA-256: `ba7897d721c790402188fe3a529d9f2170f82c5655a58ecdd1945c9e52e0c4e2`.

This run produced 14 inference records and **did not complete**. Both engines
passed three generated-image runs. PP-OCRv5 Mobile completed six photographed
receipt runs. PP-OCRv6 Medium completed two photographed receipt runs before
Android reclaimed the verification process under memory pressure.

The captured Android log confirms the process kill at
`/tmp/reseebo-paddle-exit-log.txt:5268` (`lmkd`, low watermark and low swap).
Peak sampled PSS was 1,303,081 KiB for v5 and 1,968,060 KiB for v6. Samples do
not establish the absolute peak. Output evidence is retained under
`build/paddle-device-check-2026-10-10/connected-fixed/`.

Earlier failures were separate: large model buffers exhausted Android's Java
heap, and receipt transfer through `adb exec-in` truncated input. Streaming
native SHA-256 and ONNX model-file loading removed model-sized Java arrays;
those changes alone did not prevent the later native-memory pressure.

## Accepted revised runtime

Runtime suffix: `reseebo-streamed-models-2`.
APK SHA-256: `73988a6e9836c463ceb0d5b00b5a70362a7c94793c132b822cebaeafd819a63c`.

- Disable ONNX Runtime CPU memory arenas and memory-pattern optimization to
  avoid retaining allocations across varying receipt and text-line shapes.
- Stream bundled models into private temporary files and delete them after
  session creation. Clean abandoned owned copies before the next serialized
  model load.
- Preserve upstream source hashes and record the patched source hash in both
  provenance manifests. Artifact verification and four preparation tests pass.

The fixture helper writes through raw `adb shell -T` into a staging file,
reads it back to verify SHA-256, and then renames it into place. It publishes
each fixture once, preventing partial reads and repeated overwrites.

## Offline first launch and process restart

The accepted isolated APK completed the first-launch suite with 18 inference
records: three generated-image runs and three runs of each of the two photographed
receipts per engine. Flutter reported seven passes, including setup and teardown.
The production registry's native hash checks and v5 → v6 → v5 switching passed.

The same installation was restarted without another install command. Restart
marker `PADDLE_PROBE_RESTART_ONLY` selected generated-image and registry-switch
checks; the two photographed-receipt callbacks were intentional no-ops. This run
reported seven passes (five actual test callbacks plus setup/teardown), six new
inference records, and driver exit 0. The observer attached after early v5 output;
records were recovered from the exact restarted process (PID 22466) in
`process-log.txt` and independently accepted by `validate_records`. Do not read
seven passes as seven independent photo checks or a second complete 18-record run.

Network evidence records Wi-Fi 0, mobile data 0, airplane mode 1, and no active
default network during testing. Original settings were restored: Wi-Fi 1, mobile
data 0, airplane mode 0. Evidence, including connectivity, process logs,
`network-resumed*` captures, results and sampled memory, is retained under
`build/paddle-device-check-2026-10-10/`.

## Timing, memory and parsing limits

Peak sampled first-launch PSS was 840,936 KiB for v5 and 1,376,344 KiB for v6.
Restart sampling recorded v6 at 857,255 KiB; v5 has no restart memory measurement
because the sampler attached late. These are sampled values, not absolute peaks.

| Engine | Six photographed-receipt elapsed times (ms) |
| --- | --- |
| PP-OCRv5 Mobile | 4,110; 3,654; 4,286; 5,010; 4,366; 4,345 |
| PP-OCRv6 Medium | 18,133; 25,336; 92,673; 86,825; 23,544; 16,597 |

The phone switched to Telegram during the long v6 runs and was brought back to
the probe. These timings include that observed device contention; they are not
controlled speed benchmarks. v6 remains noticeably slower on this device.

Both engines matched the independent receipt dates and totals on all photo
runs. v5 did not match the Savemore supplier; v6 matched suppliers. Item quantity
and gross-amount agreement was mixed. The sample is two receipts, and every
suggested receipt field still requires review before confirmation.

Host checks on the revised source: Flutter analysis clean; 534 Flutter tests
passed with one skipped; 31 Python tests passed. The probe registers tests
synchronously and initializes its restart marker in `setUpAll`; the host guard
validates inference records in addition to Flutter exit status.

These checks establish bundled offline Paddle operation and registry switching
on this phone. They do not establish full production capture/review/save behavior,
production receipt persistence after restart, or perfect OCR accuracy.

The observer now recovers early existing-app records from the exact verification PID and merges them without duplicates; its regression test is included in the 31 Python checks.

## Installed ordinary app

The enabled regular APK (`com.reseebo.reseebo`) was built and installed successfully.
APK SHA-256: `d293b09e86bdcc9dd4a09749b802fc66aded0cb76d35758c83f77ed1dfb9ae92`.
The 323,584-byte SQLite database matched its pre-update SHA-256 exactly before relaunch.
The regular app was observed running PP-OCRv5 on a receipt after the update.
The isolated verification process was force-stopped to release its model memory;
the user's active scan was left running. Wi-Fi and airplane-mode settings were
rechecked at their original values. This update preservation check does not
replace a full capture/review/save and restart acceptance test.
