# User-run Paddle device checks

The user deferred device testing to themselves. These commands are a handoff;
the agent has not run them. Both Paddle options remain disabled in the ordinary
app until connected and offline physical evidence has been reviewed. The probe
uses genuine models through the isolated verification app.

The earlier incident removed the ordinary `com.reseebo.reseebo` installation.
The owner reported no receipts and an existing backup. These instructions do
not restore or install that package. The owner will restore the completed app
themselves with Flutter run; ensure verification environment flags are unset
for that separate production build. Do not use the integration-probe APK as
the ordinary app. See the incident report for the exact history.

## Set up and inspect the immutable probe

Open PowerShell in the app root. Use Samsung serial `R5GL41586RA`, user 0.
The available 16 KiB emulator is not accepted as a substitute for this phone.

```powershell
Set-Location -LiteralPath 'C:\Users\John Brayl\Documents\GitHub\TeamCus\reseebo_app'
$paddlePython = 'C:\Users\John Brayl\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$paddleAdb = 'C:\Android\Sdk\platform-tools\adb.exe'
$paddleAapt = 'C:\Android\Sdk\build-tools\36.0.0\aapt2.exe'
$paddleSerial = 'R5GL41586RA'
$paddleExpectedHash = '8c2a7d9f1e4272a97c989a0f55157c09c987115ddd8d446fa23bf34d2c9bdac2'
$paddleApk = Join-Path $PWD "build\verified-paddle-apks\$paddleExpectedHash.apk"

Get-FileHash -Algorithm SHA256 -LiteralPath $paddleApk
& $paddleAapt dump badging $paddleApk
& $paddlePython scripts/run_paddle_probe.py --apk $paddleApk --sha256 $paddleExpectedHash
if ($LASTEXITCODE -ne 0) { throw 'APK guard rejected the probe; stop here.' }
```

The hash must match the expected value above; actual package must be exactly
`com.reseebo.reseebo.verification`, minimum SDK 26, target 36. The guard rejects
any other package/hash before device launch and uses the revalidated hash-named
snapshot with Flutter drive `--use-application-binary`. It cannot rebuild an
ordinary-ID APK between inspection and installation. Debug INTERNET permission
is present; offline acceptance requires a disconnected phone.

This APK is 496,279,541 bytes and contains the corrected OpenCV 4.5.3.0 runtime.
It predates later app feature work; its actual detector defaults are unchanged
and documented in the feasibility report. Do not replace its expected hash
with a different APK's hash without separately inspecting that APK's actual ID.
If the snapshot is unavailable, build a new probe separately (not via Flutter
test/drive), inspect its actual package and hash, then pass that new inspected
hash to the same guard. The known hash above does not apply to a new build.

```powershell
$paddlePriorVerification = [Environment]::GetEnvironmentVariable('ORG_GRADLE_PROJECT_reseeboVerification', 'Process')
$paddlePriorJavaOptions = [Environment]::GetEnvironmentVariable('JAVA_TOOL_OPTIONS', 'Process')
try {
  $env:ORG_GRADLE_PROJECT_reseeboVerification = 'true'
  New-Item -ItemType Directory -Force -Path 'build\jdk-sockets' | Out-Null
  $env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir="C:/Users/John Brayl/Documents/GitHub/TeamCus/reseebo_app/build/jdk-sockets"'
  & 'C:\src\flutter\bin\flutter.bat' build apk --debug --no-pub --target integration_test/paddle_engine_probe_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Probe build failed; do not install.' }
} finally {
  [Environment]::SetEnvironmentVariable('ORG_GRADLE_PROJECT_reseeboVerification', $paddlePriorVerification, 'Process')
  [Environment]::SetEnvironmentVariable('JAVA_TOOL_OPTIONS', $paddlePriorJavaOptions, 'Process')
}

# Inspect separately, then copy the printed SHA-256 into paddleExpectedHash.
$paddleApk = Join-Path $PWD 'build\app\outputs\flutter-apk\app-debug.apk'
Get-FileHash -Algorithm SHA256 -LiteralPath $paddleApk
& $paddleAapt dump badging $paddleApk
# Set paddleExpectedHash to this independently inspected APK's exact hash.
& $paddlePython scripts/run_paddle_probe.py --apk $paddleApk --sha256 $paddleExpectedHash
if ($LASTEXITCODE -ne 0) { throw 'APK guard rejected the new build; stop here.' }
```

## Connected receipt inference

Record the phone identity, installed Reseebo packages and networking state.
Confirm the serial says `device` and the hardware is Samsung SM-A576B. Record
ordinary-package absence if it has not been restored; do not claim preservation
of the earlier removed installation. These reads must be repeated after runs.

```powershell
& $paddleAdb devices -l
& $paddleAdb -s $paddleSerial shell getprop ro.product.model
& $paddleAdb -s $paddleSerial shell getprop ro.build.version.sdk
& $paddleAdb -s $paddleSerial shell getconf PAGE_SIZE
& $paddleAdb -s $paddleSerial shell pm list packages --user 0 com.reseebo.reseebo
& $paddleAdb -s $paddleSerial shell settings get global wifi_on
& $paddleAdb -s $paddleSerial shell settings get global mobile_data
& $paddleAdb -s $paddleSerial shell settings get global airplane_mode_on
```

Public receipt photos are optional developer test inputs, not app assets.
If the ignored `build\paddle-truth-samples` folder is absent, prepare it on the
host while the host has internet. The observer checks the two exact image hashes
against committed independent truth and refuses changed inputs. This download
script is never called by the app; copyright/source details stay in its manifest.

```powershell
& $paddlePython scripts/download_receipt_samples.py --output build/paddle-truth-samples
& $paddlePython scripts/observe_paddle_probe.py --apk $paddleApk --sha256 $paddleExpectedHash --output build/paddle-probe-user-connected --receipt-samples build/paddle-truth-samples
if ($LASTEXITCODE -ne 0) { Write-Host 'Probe failed: preserve the log; both engines stay disabled.' }
& $paddleAdb -s $paddleSerial shell pm list packages --user 0 com.reseebo.reseebo
```

Observer fixture copies use run-as only for the exact verification cache. It
captures complete result JSON, red coordinate overlays and sampled process PSS.
On an evidence error, it stops/waits only its owned child process tree. Flutter
drive normally stops/uninstalls **the verification package** at completion; the
guard ensures this cleanup cannot target the ordinary package.

Inspect the saved overlays against the two original photos. Report each parsed
supplier/date/total and each associated item quantity/gross-price match or
disagreement. `lexicalPresence` is a whole-text check, not row association.
Keep unresolved values and parser warnings. Report cold run 0 and warm runs
1/2, sampled PSS maxima, crashes/OOM/errors and the exact APK/model/runtime/parser
identities. The controlled generated fixture alone is not receipt acceptance.

## Fresh offline first launch and restart evidence

Record the existing Wi-Fi, mobile-data and airplane settings before changing
anything. Manually disconnect the phone from internet in Quick Settings: turn
on airplane mode and turn Wi-Fi off. Keep USB connected for the local driver.
Take a screenshot of the disconnected state and rerun the three settings reads;
Wi-Fi and mobile-data must be off. Also record `dumpsys connectivity` so a
remaining connected transport is visible. Host internet is not phone internet.

Confirm no verification package remains after the connected run. If it remains,
first repeat the exact APK guard above, then remove **only** that verification
installation manually to establish a fresh install:

```powershell
& $paddlePython scripts/run_paddle_probe.py --apk $paddleApk --sha256 $paddleExpectedHash
if ($LASTEXITCODE -ne 0) { throw 'Guard rejected the APK; stop here.' }
& $paddleAdb -s $paddleSerial uninstall --user 0 com.reseebo.reseebo.verification
& $paddleAdb -s $paddleSerial shell pm list packages --user 0 com.reseebo.reseebo
& $paddleAdb -s $paddleSerial shell settings get global wifi_on
& $paddleAdb -s $paddleSerial shell settings get global mobile_data
& $paddleAdb -s $paddleSerial shell settings get global airplane_mode_on
& $paddleAdb -s $paddleSerial shell dumpsys connectivity
```

Run the same immutable observer while disconnected, saving separate evidence.
Repeat after the first run completes to exercise a new native process. Each
driver cleanup/fresh install is a fresh-process test; it does not prove retained
receipt data. The models must load without application downloads in both runs.
The observer performs no networking changes; restore the manually recorded
settings after these commands, including when a run fails.

```powershell
& $paddlePython scripts/observe_paddle_probe.py --apk $paddleApk --sha256 $paddleExpectedHash --output build/paddle-probe-user-offline-first --receipt-samples build/paddle-truth-samples
& $paddleAdb -s $paddleSerial shell pm list packages --user 0 com.reseebo.reseebo
& $paddlePython scripts/observe_paddle_probe.py --apk $paddleApk --sha256 $paddleExpectedHash --output build/paddle-probe-user-offline-restart --receipt-samples build/paddle-truth-samples
& $paddleAdb -s $paddleSerial shell pm list packages --user 0 com.reseebo.reseebo
```

Receipt persistence needs a separate completed-app check after the owner restores
that app themselves. With phone internet disconnected, import through ML Kit,
save a Needs review receipt with original photos, fully close the app and reopen
it. Verify saved edits, originals, ordering and review status still exist; then
review/confirm eligible fields and check the ledger after another restart.
Capture screenshots and any failure. Keep the native Paddle evidence separate
from this storage/UI acceptance. Paddle choices stay disabled throughout this
handoff; changing flags requires reviewed physical evidence, not merely a
successful install or a generated-text test.
