#!/bin/bash
# M3c provider-sampling simulator test (two scenarios).
#
# Scenario "flat": the real compositor samples a fake provider's eye MTLTexture through the flat path
# (vrmc-reproj-off) and the drawn-drawable readback must match the known pattern (orientation + layout).
# Scenario "sync": same + the fake provider publishes a real MTLSharedEvent (sync.valid=1); the
# compositor must encode encodeWaitForEvent without blocking and still present the sampled pattern.
#
# This exercises the full real chain without JVM/JIT/headset: bridge symbol resolution, acquire path,
# sampling shader, drawable mapping/orientation, and the GPU-timeline wait wiring.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
SIM="${SIM:-F025E133-019D-4811-944F-F3C8226E14CB}"
OUT="${OUT:-/tmp/vrmc-provider-sim}"
APP="$OUT/VRMCProviderSim.app"
BUNDLE="dev.vrmc.providersim"
FULL="${FULL:-0}"   # 1 = rebuild framework/dylib; 0 = reuse $OUT/shell-dd + fake dylib if present

mkdir -p "$OUT"
if [ "$FULL" = "1" ] || [ ! -d "$OUT/shell-dd/Build/Products/Debug-xrsimulator/VRMCShell.framework" ]; then
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
run_case() {
  local name="$1" sync="$2" mode="${3:-provider}"
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
    python3 "$HERE/check.py" "$case_dir" --require-sync || overall=1
  else
    python3 "$HERE/check.py" "$case_dir" || overall=1
  fi
}

run_case flat 0
run_case sync 1
run_case pattern 0 pattern
if [ "$overall" != "0" ]; then echo "[provider-sim] OVERALL FAIL"; exit 1; fi
echo "[provider-sim] OVERALL PASS (flat sampling + GPU-timeline sync + test-pattern scenarios)"