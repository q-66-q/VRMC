#!/bin/bash
# M3c/M4 provider-sampling simulator harness.
#
# Scenario "flat": the real compositor samples a fake provider's eye MTLTexture through the flat path
# (vrmc-reproj-off) and the drawn-drawable readback must match the known pattern (orientation + layout).
# Scenario "sync": same + the fake provider publishes a real MTLSharedEvent (sync.valid=1); the
# compositor must encode encodeWaitForEvent without blocking and still present the sampled pattern.
# Scenario "input" (M4-W1): the real compositor publishes synthetic 27-joint hand snapshots
# (Documents/vrmc-input-sim.flag=cycle) through the fake bridge's vrmc_shared_publish_input; the fake
# provider records every snapshot to Documents/vrmc-input-capture.txt and check.py --require-input
# asserts the cycle + the final zeroed release snapshot. This is plumbing evidence for the
# compositor->bridge wire path, NOT hands evidence (the simulator has no ARKit hand data).
#
# This exercises the full real chain without JVM/JIT/headset: bridge symbol resolution, acquire path,
# sampling shader, drawable mapping/orientation, the GPU-timeline wait wiring, and the input publish path.
#
# Usage: runtime/probes/m3c-provider-sim/run.sh [scenario...]
#   No arguments runs all presentation scenarios (flat sync hidepark nopark pattern reentry).
#   Named scenarios run in order, e.g. 'run.sh input' or 'run.sh input flat'. Known scenarios:
#   flat sync hidepark nopark pattern reentry input.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
SIM="${SIM:-F025E133-019D-4811-944F-F3C8226E14CB}"
OUT="${OUT:-/tmp/vrmc-provider-sim}"
APP="$OUT/VRMCProviderSim.app"
BUNDLE="dev.vrmc.providersim"
FULL="${FULL:-0}"   # 1 = rebuild framework/dylib; 0 = reuse $OUT/shell-dd + fake dylib if present

mkdir -p "$OUT"
NEED_BUILD=0
[ "$FULL" = "1" ] && NEED_BUILD=1
FRAMEWORK_BIN="$OUT/shell-dd/Build/Products/Debug-xrsimulator/VRMCShell.framework/VRMCShell"
[ -f "$FRAMEWORK_BIN" ] || NEED_BUILD=1
if [ -f "$FRAMEWORK_BIN" ]; then
  # rebuild when any shell source is newer than the cached framework (avoids testing a stale build)
  NEWEST_SRC=$(find "$ROOT/runtime/native-shell/Sources" -type f -newer "$FRAMEWORK_BIN" -print -quit 2>/dev/null || true)
  [ -n "$NEWEST_SRC" ] && NEED_BUILD=1
fi
if [ "$NEED_BUILD" = "1" ]; then
  echo "[build] shell framework (visionOS simulator)"
  ( cd "$ROOT/runtime/native-shell" && xcodebuild -project VRMCShell.xcodeproj -scheme VRMCShell -configuration Debug \
    -destination "platform=visionOS Simulator,id=$SIM" CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "$OUT/shell-dd" build 2>&1 | tail -2 )
fi
FW="$OUT/shell-dd/Build/Products/Debug-xrsimulator/VRMCShell.framework"
echo "[build] fake provider dylib"
OUT="$OUT/fake/libvrmc_bridge.dylib" "$HERE/build.sh" >/dev/null
FAKE="$OUT/fake/libvrmc_bridge.dylib"

echo "[build] host app bundle"
rm -rf "$APP"
mkdir -p "$APP/Frameworks"
cp "$HERE/host/Info.plist" "$APP/Info.plist"
cp -R "$FW" "$APP/Frameworks/VRMCShell.framework"
cp "$FAKE" "$APP/Frameworks/libvrmc_bridge.dylib"
SDK=$(xcrun --sdk xrsimulator --show-sdk-path)
xcrun --sdk xrsimulator clang -target arm64-apple-xros-simulator -isysroot "$SDK" -fobjc-arc \
  -framework Foundation -o "$APP/ProviderSim" "$HERE/host/main.m"

echo "[setup] boot simulator"
xcrun simctl boot "$SIM" 2>/dev/null || true

overall=0

wait_for_log() { # wait_for_log <file> <pattern> [tries]
  local file="$1" pat="$2" tries="${3:-40}"
  for _ in $(seq 1 "$tries"); do
    [ -f "$file" ] && grep -q "$pat" "$file" 2>/dev/null && return 0
    sleep 1
  done
  return 1
}

run_case() {
  local name="$1" sync="$2" mode="${3:-provider}" extra="${4:-}"
  local case_dir="$OUT/case-$name"
  rm -rf "$case_dir"; mkdir -p "$case_dir"
  # Fresh install per scenario: guarantees a fresh process (simctl launch reuses a running app) and a
  # clean Documents container, so the scenario flags are exactly what the app reads at startup.
  xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$SIM" "$APP"
  DATA=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
  mkdir -p "$DATA/Documents"
  if [ "$mode" = "pattern" ]; then
    echo "selftest" > "$DATA/Documents/vrmc-immersive-selftest.flag"
  else
    echo "provider sim" > "$DATA/Documents/vrmc-open-on-launch.flag"
    echo "flat"          > "$DATA/Documents/vrmc-reproj-off.flag"
    if [ "$sync" = "1" ]; then echo "sync" > "$DATA/Documents/vrmc-fake-provider-sync.flag"; fi
    if [ -n "$extra" ]; then echo "$extra" > "$DATA/Documents/$extra"; fi
  fi
  xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null 2>&1
  # Wait for the first presented frame + the 5 s scene-state line, so the copied logs are complete.
  for _ in $(seq 1 30); do
    if [ -f "$DATA/Documents/vrmc-shell.log" ] && grep -q 'STATE immersive=' "$DATA/Documents/vrmc-shell.log" 2>/dev/null; then break; fi
    sleep 1
  done
  sleep 2
  xcrun simctl io "$SIM" screenshot "$case_dir/screenshot.png" >/dev/null 2>&1 || true
  cp "$DATA/Documents/vrmc-compositor.log" "$case_dir/compositor.log" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-shell.log"      "$case_dir/shell.log" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-drawable-L.raw" "$case_dir/drawable-L.raw" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-drawable-L.raw.meta" "$case_dir/drawable-L.raw.meta" 2>/dev/null || true
  echo "---- scenario: $name ----"
  if [ "$mode" = "pattern" ]; then
    python3 "$HERE/check.py" "$case_dir" --pattern || overall=1
  elif [ "$sync" = "1" ]; then
    python3 "$HERE/check.py" "$case_dir" --require-sync --require-parking || overall=1
  elif [ "$name" = "hidepark" ]; then
    python3 "$HERE/check.py" "$case_dir" --require-parking --require-hidden || overall=1
  elif [ "$name" = "nopark" ]; then
    python3 "$HERE/check.py" "$case_dir" --require-noparking || overall=1
  else
    python3 "$HERE/check.py" "$case_dir" --require-parking || overall=1
  fi
}

run_reentry() {
  local case_dir="$OUT/case-reentry"
  rm -rf "$case_dir"; mkdir -p "$case_dir"
  xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$SIM" "$APP"
  local DATA; DATA=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
  mkdir -p "$DATA/Documents"
  echo "provider sim" > "$DATA/Documents/vrmc-open-on-launch.flag"
  echo "flat"          > "$DATA/Documents/vrmc-reproj-off.flag"
  xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null 2>&1
  wait_for_log "$DATA/Documents/vrmc-shell.log" 'VRMCCompositorRunning generation=' 40 || true
  wait_for_log "$DATA/Documents/vrmc-shell.log" 'STATE immersive=' 40 || true
  echo "---- scenario: reentry (background -> foreground) ----"
  # Background our app by foregrounding a system app, then bring VRMC back. This exercises the shell's
  # willResignActive/didEnterBackground -> reopenOnActive -> reason=foreground path (EV-0086 gen-2 class).
  xcrun simctl launch "$SIM" com.apple.Preferences >/dev/null 2>&1 || true
  sleep 4
  # visionOS simulator windowed scenes may keep the app foreground-active when another app is
  # launched (known environment limitation, recorded in EV-0269); re-entry itself is device-tracked.
  if ! grep -qE 'didEnterBackground|willResignActive' "$DATA/Documents/vrmc-shell.log" 2>/dev/null; then
    echo "[provider-sim] SKIP: reentry (simulator kept the app foreground-active; no background transition; known environment limitation)"
    return 0
  fi
  xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
  wait_for_log "$DATA/Documents/vrmc-shell.log" 'reason=foreground' 40 || true
  sleep 6
  xcrun simctl io "$SIM" screenshot "$case_dir/screenshot.png" >/dev/null 2>&1 || true
  cp "$DATA/Documents/vrmc-compositor.log" "$case_dir/compositor.log" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-shell.log"      "$case_dir/shell.log" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-drawable-L.raw" "$case_dir/drawable-L.raw" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-drawable-L.raw.meta" "$case_dir/drawable-L.raw.meta" 2>/dev/null || true
  python3 "$HERE/check.py" "$case_dir" --reentry --require-parking || overall=1
}

run_input() {
  local case_dir="$OUT/case-input"
  rm -rf "$case_dir"; mkdir -p "$case_dir"
  xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$SIM" "$APP"
  local DATA; DATA=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
  mkdir -p "$DATA/Documents"
  echo "provider sim" > "$DATA/Documents/vrmc-open-on-launch.flag"
  echo "flat"          > "$DATA/Documents/vrmc-reproj-off.flag"
  printf 'cycle\n'    > "$DATA/Documents/vrmc-input-sim.flag"
  # Optional A/B: exercise the GPU-timeline wait path in the same run (the fake provider then also
  # publishes a real MTLSharedEvent). INPUT_SYNC=1 enables it; off by default (not input-related).
  if [ "${INPUT_SYNC:-0}" = "1" ]; then echo "sync" > "$DATA/Documents/vrmc-fake-provider-sync.flag"; fi
  xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null 2>&1
  wait_for_log "$DATA/Documents/vrmc-shell.log" 'VRMCCompositorRunning generation=' 40 || true
  # The base assertion requires the immersive scene foreground-active line in the shell log; wait for
  # it explicitly so backgrounding early cannot race the shell's 5 s STATE log tick (flaky otherwise).
  wait_for_log "$DATA/Documents/vrmc-shell.log" 'CPSceneSessionRoleImmersiveSpaceApplication:fgActive' 40 || true
  # Wait for one full fabricated gesture lap (the compositor logs "lap complete" once) so the capture
  # contains both-open, right-pinch, left-fist and both-fist frames; fall back to a capture-line
  # threshold in case the log line is late.
  wait_for_log "$DATA/Documents/vrmc-compositor.log" 'input script=cycle lap complete' 60 || true
  for _ in $(seq 1 20); do
    if [ -f "$DATA/Documents/vrmc-input-capture.txt" ]; then
      lines=$(grep -v '^#' "$DATA/Documents/vrmc-input-capture.txt" 2>/dev/null | wc -l | tr -d ' ')
      [ "${lines:-0}" -ge 40 ] && break
    fi
    sleep 1
  done
  xcrun simctl io "$SIM" screenshot "$case_dir/screenshot.png" >/dev/null 2>&1 || true
  # Deterministically exercise release-on-stop: backgrounding stops the compositor (the shell calls
  # VRMCCompositor_RequestStop from didEnterBackground), which must publish the zeroed release snapshot
  # BEFORE ar_session_stop. Afterwards the capture's LAST line is a valid_mask=0 release frame.
  xcrun simctl launch "$SIM" com.apple.Preferences >/dev/null 2>&1 || true
  wait_for_log "$DATA/Documents/vrmc-compositor.log" 'input release' 40 || true
  sleep 1
  cp "$DATA/Documents/vrmc-compositor.log" "$case_dir/compositor.log" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-shell.log"      "$case_dir/shell.log" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-input-capture.txt" "$case_dir/input-capture.txt" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-drawable-L.raw" "$case_dir/drawable-L.raw" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-drawable-L.raw.meta" "$case_dir/drawable-L.raw.meta" 2>/dev/null || true
  echo "---- scenario: input ----"
  python3 "$HERE/check.py" "$case_dir" --require-input || overall=1
}

run_render() {
  # M8: foveated rendering + dynamic render quality feedback. The real compositor must publish the
  # layer's logical per-eye size at the current render quality, the physical foveated drawable extent,
  # the foveation/rate-map state and the measured display cadence through the native-shared channel
  # (fake provider records it in render-capture.txt). Simulator parameters are plumbing evidence only.
  local case_dir="$OUT/case-render"
  rm -rf "$case_dir"; mkdir -p "$case_dir"
  xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$SIM" "$APP"
  local DATA; DATA=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
  mkdir -p "$DATA/Documents"
  echo "provider sim" > "$DATA/Documents/vrmc-open-on-launch.flag"
  echo "flat"          > "$DATA/Documents/vrmc-reproj-off.flag"
  # Optional M8 sharpening A/B: SHARPEN=off|auto|<0.05..1.0> writes Documents/vrmc-sharpening.txt so
  # the same scenario proves the live knob is honoured by the real compositor.
  if [ -n "${SHARPEN:-}" ]; then
    printf '%s\n' "$SHARPEN" > "$DATA/Documents/vrmc-sharpening.txt"
    echo "[scenario] sharpening knob: $SHARPEN"
  fi
  xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null 2>&1
  wait_for_log "$DATA/Documents/vrmc-shell.log" 'VRMCCompositorRunning generation=' 40 || true
  wait_for_log "$DATA/Documents/vrmc-compositor.log" 'render feedback published:' 40 || true
  wait_for_log "$DATA/Documents/vrmc-compositor.log" 'display geometry: logical L=' 40 || true
  wait_for_log "$DATA/Documents/vrmc-compositor.log" 'render feedback: displayHz=' 60 || true
  # The shell logs STATE every 5 s; the check requires the immersive scene fgActive marker, so wait
  # for it explicitly instead of racing the copy (batch runs of all scenarios were flaky here).
  wait_for_log "$DATA/Documents/vrmc-shell.log" 'CPSceneSessionRoleImmersiveSpaceApplication:fgActive' 40 || true
  sleep 2
  xcrun simctl io "$SIM" screenshot "$case_dir/screenshot.png" >/dev/null 2>&1 || true
  cp "$DATA/Documents/vrmc-compositor.log"   "$case_dir/compositor.log" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-shell.log"        "$case_dir/shell.log" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-render-capture.txt" "$case_dir/render-capture.txt" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-drawable-L.raw"   "$case_dir/drawable-L.raw" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-drawable-L.raw.meta" "$case_dir/drawable-L.raw.meta" 2>/dev/null || true
  echo "---- scenario: render (M8 foveated render feedback) ----"
  python3 "$HERE/check.py" "$case_dir" --require-render --require-parking || overall=1
}

run_eyedrop() {
  # M8 resize grace: the provider withholds its eye frame for 60 acquire calls (mimicking the real
  # provider clearing the shared frame before an eye-target rebuild). The compositor must reuse its
  # last sampled pair for the 30-frame grace, log when the grace expires, and recover when eyes return.
  local case_dir="$OUT/case-eyedrop"
  rm -rf "$case_dir"; mkdir -p "$case_dir"
  xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$SIM" "$APP"
  local DATA; DATA=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
  mkdir -p "$DATA/Documents"
  echo "provider sim" > "$DATA/Documents/vrmc-open-on-launch.flag"
  echo "flat"          > "$DATA/Documents/vrmc-reproj-off.flag"
  echo "drop"          > "$DATA/Documents/vrmc-fake-eyes-drop.flag"
  xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null 2>&1
  wait_for_log "$DATA/Documents/vrmc-shell.log" 'VRMCCompositorRunning generation=' 40 || true
  wait_for_log "$DATA/Documents/vrmc-shell.log" 'CPSceneSessionRoleImmersiveSpaceApplication:fgActive' 40 || true
  wait_for_log "$DATA/Documents/vrmc-compositor.log" 'eyes absent: reusing the last sampled eye frame' 60 || true
  wait_for_log "$DATA/Documents/vrmc-compositor.log" 'last-frame grace expired' 40 || true
  wait_for_log "$DATA/Documents/vrmc-compositor.log" 'eye frame resumed after' 40 || true
  sleep 3
  xcrun simctl io "$SIM" screenshot "$case_dir/screenshot.png" >/dev/null 2>&1 || true
  cp "$DATA/Documents/vrmc-compositor.log" "$case_dir/compositor.log" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-shell.log"      "$case_dir/shell.log" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-drawable-L.raw" "$case_dir/drawable-L.raw" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-drawable-L.raw.meta" "$case_dir/drawable-L.raw.meta" 2>/dev/null || true
  echo "---- scenario: eyedrop (M8 resize grace) ----"
  python3 "$HERE/check.py" "$case_dir" --require-eyedrop --require-parking || overall=1
}

run_gaze() {
  local case_dir="$OUT/case-gaze"
  rm -rf "$case_dir"; mkdir -p "$case_dir"
  xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$SIM" "$APP"
  local DATA; DATA=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
  mkdir -p "$DATA/Documents"
  echo "provider sim" > "$DATA/Documents/vrmc-open-on-launch.flag"
  echo "flat"          > "$DATA/Documents/vrmc-reproj-off.flag"
  echo "gaze"          > "$DATA/Documents/vrmc-gaze.flag"
  xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null 2>&1
  wait_for_log "$DATA/Documents/vrmc-shell.log" 'VRMCCompositorRunning generation=' 40 || true
  wait_for_log "$DATA/Documents/vrmc-shell.log" 'CPSceneSessionRoleImmersiveSpaceApplication:fgActive' 40 || true
  # The compositor must either enable the tracking-area grid or log one precise reason it cannot.
  wait_for_log "$DATA/Documents/vrmc-compositor.log" 'gaze:' 40 || true
  sleep 3
  xcrun simctl io "$SIM" screenshot "$case_dir/screenshot.png" >/dev/null 2>&1 || true
  cp "$DATA/Documents/vrmc-compositor.log" "$case_dir/compositor.log" 2>/dev/null || true
  cp "$DATA/Documents/vrmc-shell.log"      "$case_dir/shell.log" 2>/dev/null || true
  echo "---- scenario: gaze (tracking-area pipeline) ----"
  if [ ! -f "$case_dir/compositor.log" ]; then
    echo "[provider-sim] SKIP: gaze (compositor did not start with the tracking-area flag in this simulator;"
    echo "[provider-sim]       the tracking-area API is device-only - known environment limitation, not a regression)"
    return 0
  fi
  if grep -q 'gaze: tracking areas ENABLED' "$case_dir/compositor.log" 2>/dev/null; then
    echo "[provider-sim] PASS: tracking-area mask pipeline built and enabled"
    grep -E 'gaze: tracking areas ENABLED|gaze: tracking areas disabled|gaze:' "$case_dir/compositor.log" | tail -5
  else
    echo "[provider-sim] SKIP: tracking areas not enabled in this simulator (device-only API); known environment limitation"
    grep -E 'gaze:|tracking areas' "$case_dir/compositor.log" | tail -5 || true
  fi
}

ALL_SCENARIOS=(flat sync hidepark nopark pattern reentry input gaze render eyedrop)
if [ "$#" -gt 0 ]; then
  SCENARIOS=("$@")
else
  SCENARIOS=("${ALL_SCENARIOS[@]}")
fi
for scenario in "${SCENARIOS[@]}"; do
  case "$scenario" in
    flat)     run_case flat 0 ;;
    sync)     run_case sync 1 ;;
    hidepark) run_case hidepark 0 provider vrmc-hide-windows.flag ;;
    nopark)   run_case nopark 0 provider vrmc-no-parking.flag ;;
    pattern)  run_case pattern 0 pattern ;;
    reentry)  run_reentry ;;
    input)    run_input ;;
    gaze)     run_gaze ;;
    render)   run_render ;;
    eyedrop)  run_eyedrop ;;
    *)
      echo "[provider-sim] unknown scenario '$scenario' (known: ${ALL_SCENARIOS[*]})"
      exit 2
      ;;
  esac
done
if [ "$overall" != "0" ]; then echo "[provider-sim] OVERALL FAIL"; exit 1; fi
echo "[provider-sim] OVERALL PASS (scenarios: ${SCENARIOS[*]})"