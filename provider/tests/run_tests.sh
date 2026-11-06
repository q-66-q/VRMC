#!/bin/bash
# Host tests for the provider-side GPU eye-frame sync (no device).
#
#   1. flag test          - GpuSyncFlags: off by default, flag file / -Dvrmc.gpuSync semantics
#   2. fallback test      - GpuEyeSync.tryEnable: never throws; requested-but-unavailable returns null
#                           after one warning; flag absent returns null silently
#   3. VkReflect smoke    - reflection plumbing used on device: with LWJGL the create-info structs and
#                           constants resolve; without LWJGL it fails closed with UnavailableException
#                           (the exact "reflection reaches nothing" fallback path)
#   4. provider build     - scripts/build_provider.sh (jar + sha256, exit 0) with the new sources
#   5. M4 immersive input - ABI v3 layout constants, gesture engine (hysteresis/arming/taps/stale/
#                           action-set gating/binding table), hand-pose math, and the optional
#                           cross-language fixture produced by bridge/tests/make_input_fixture.c
#                           (VRMC_INPUT_FIXTURE, plus the VRMC_INPUT_FIXTURE_FRAMES timeline sidecar).
#                           Unset fixture = explicit SKIP; set-but-missing = FAIL.
#
# Usage: provider/tests/run_tests.sh
# Env:   PROVIDER_OUT (default /tmp/vrmc-provider-build), LWJGL_JAR (auto-detected for the smoke test),
#        VRMC_INPUT_FIXTURE / VRMC_INPUT_FIXTURE_FRAMES (optional cross-language fixture)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROVIDER_OUT="${PROVIDER_OUT:-/tmp/vrmc-provider-build}"
T="${TMPDIR:-/tmp}/vrmc-provider-tests"
rm -rf "$T"
mkdir -p "$T"
JAVAC=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javac
JAVA=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/java
[ -x "$JAVAC" ] || { JAVAC=$(command -v javac || true); JAVA=$(command -v java || true); }
[ -x "$JAVAC" ] && [ -x "$JAVA" ] || { echo "[provider-tests] ERROR: no JDK 25 found" >&2; exit 1; }

FAILED=0
step() { echo; echo "=== $1 ==="; }
fail() { echo "[provider-tests] $1: FAIL"; FAILED=1; }

# --- build the provider jar (also gives us the compile classpath) ----------------------------
step "build-provider"
if ! OUT_DIR="$PROVIDER_OUT" "$ROOT/scripts/build_provider.sh" > "$T/build.log" 2>&1; then
  cat "$T/build.log"
  fail "build-provider"
  echo "[provider-tests] FAILED"
  exit 1
fi
grep -E '^\[provider\] (compiled|jar:|size:|sha256:)' "$T/build.log"
echo "[provider-tests] build-provider: PASS"
CLASSES="$PROVIDER_OUT/classes"
CP="$(cat "$PROVIDER_OUT/classpath.txt")"

# --- 1. flag parsing (pure Java, no game classes) --------------------------------------------
step "flag-test"
mkdir -p "$T/flagclasses"
"$JAVAC" -d "$T/flagclasses" "$ROOT/provider/src/main/java/dev/vrmc/provider/GpuSyncFlags.java" \
  "$ROOT/provider/tests/GpuSyncFlagsTest.java" || fail "flag-test-compile"
if "$JAVA" -cp "$T/flagclasses" GpuSyncFlagsTest; then
  echo "[provider-tests] flag-test: PASS"
else
  fail "flag-test"
fi

# --- 2. enable/fallback contract (game classes present, no live device) ----------------------
step "fallback-test"
mkdir -p "$T/fbclasses"
"$JAVAC" -cp "$CP:$CLASSES" -d "$T/fbclasses" \
  "$ROOT/provider/tests/dev/vrmc/provider/GpuEyeSyncFallbackTest.java" || fail "fallback-test-compile"
FB_CP="$CP:$CLASSES:$T/fbclasses"
EMPTY_DIR="$T/empty-game-dir"
FLAG_DIR="$T/flagged-game-dir"
mkdir -p "$EMPTY_DIR" "$FLAG_DIR"
: > "$FLAG_DIR/vrmc-gpu-sync.flag"
if "$JAVA" -cp "$FB_CP" dev.vrmc.provider.GpuEyeSyncFallbackTest "$EMPTY_DIR" > "$T/fallback-off.log" 2>&1 \
   && grep -q "PASS (off by default)" "$T/fallback-off.log"; then
  echo "[provider-tests] fallback-off: PASS (no flag -> null, silent)"
else
  cat "$T/fallback-off.log"; fail "fallback-off"
fi
if "$JAVA" -cp "$FB_CP" dev.vrmc.provider.GpuEyeSyncFallbackTest "$FLAG_DIR" > "$T/fallback-flag.log" 2>&1 \
   && grep -q "PASS (graceful fallback)" "$T/fallback-flag.log" \
   && grep -q "WARNING" "$T/fallback-flag.log" \
   && grep -q "falling back to unsynchronized" "$T/fallback-flag.log"; then
  echo "[provider-tests] fallback-flagfile: PASS (requested, one warning, safe null)"
  grep "WARNING" "$T/fallback-flag.log" | head -2
else
  cat "$T/fallback-flag.log"; fail "fallback-flagfile"
fi
if "$JAVA" -Dvrmc.gpuSync=1 -cp "$FB_CP" dev.vrmc.provider.GpuEyeSyncFallbackTest "$EMPTY_DIR" > "$T/fallback-prop.log" 2>&1 \
   && grep -q "PASS (graceful fallback)" "$T/fallback-prop.log"; then
  echo "[provider-tests] fallback-property: PASS (-Dvrmc.gpuSync=1 requested, safe null)"
else
  cat "$T/fallback-prop.log"; fail "fallback-property"
fi

# --- 3. VkReflect reflection plumbing --------------------------------------------------------
step "vkreflect-smoke"
# LWJGL 3.4.1 (same version the game ships): core jar + macOS natives (loaded from the classpath jar)
# + Vulkan struct classes. Used ONLY for the reflection smoke test; the provider jar stays LWJGL-free.
LWJGL_CP="${LWJGL_CP:-}"
if [ -z "$LWJGL_CP" ]; then
  GC="$HOME/.gradle/caches/modules-2"
  LJ_CORE=$(find "$GC" -path '*org.lwjgl/lwjgl/3.4.1*' -name 'lwjgl-3.4.1.jar' -not -name '*sources*' 2>/dev/null | head -1)
  LJ_NAT=$(find "$GC" -path '*org.lwjgl/lwjgl/3.4.1*' -name 'lwjgl-3.4.1-natives-macos-arm64.jar' -not -name '*sources*' 2>/dev/null | head -1)
  LJ_VK=$(find "$GC" -path '*org.lwjgl/lwjgl-vulkan/3.4.1*' -name 'lwjgl-vulkan-3.4.1.jar' -not -name '*sources*' 2>/dev/null | head -1)
  [ -n "$LJ_CORE" ] && [ -n "$LJ_VK" ] && LWJGL_CP="$LJ_CORE:$LJ_VK${LJ_NAT:+:$LJ_NAT}"
fi
mkdir -p "$T/smokeclasses"
"$JAVAC" -cp "$CP:$CLASSES${LWJGL_CP:+:$LWJGL_CP}" -d "$T/smokeclasses" \
  "$ROOT/provider/tests/dev/vrmc/provider/VkReflectSmokeTest.java" || fail "vkreflect-compile"
# 3a. without LWJGL: must fail closed (this is the provider-jar compile classpath).
if "$JAVA" -cp "$CP:$CLASSES:$T/smokeclasses" dev.vrmc.provider.VkReflectSmokeTest > "$T/smoke-nolwjgl.log" 2>&1 \
   && grep -q "PASS (graceful UnavailableException)" "$T/smoke-nolwjgl.log"; then
  echo "[provider-tests] vkreflect-without-lwjgl: PASS (fails closed as designed)"
  grep "expected fail-closed" "$T/smoke-nolwjgl.log" | head -1
else
  cat "$T/smoke-nolwjgl.log"; fail "vkreflect-without-lwjgl"
fi
# 3b. with LWJGL: structs/constants resolve (the plumbing used on device).
if [ -n "$LWJGL_CP" ]; then
  if "$JAVA" -cp "$CP:$CLASSES:$T/smokeclasses:$LWJGL_CP" \
       dev.vrmc.provider.VkReflectSmokeTest --expect-lwjgl > "$T/smoke-lwjgl.log" 2>&1 \
     && grep -q "PASS (reflection plumbing live)" "$T/smoke-lwjgl.log"; then
    echo "[provider-tests] vkreflect-with-lwjgl: PASS"
    grep "smokeTest:" "$T/smoke-lwjgl.log" | head -1
  else
    cat "$T/smoke-lwjgl.log"; fail "vkreflect-with-lwjgl"
  fi
else
  echo "[provider-tests] vkreflect-with-lwjgl: SKIP (no LWJGL 3.4.1 jars found; set LWJGL_CP)"
fi

# --- 4. Real MoltenVK (macOS host): reflective vkCreateSemaphore + export path ------------------
step "vulkan-host-test"
MVK_LIB="${MVK_LIB:-/tmp/vrmc-host-mvk/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib}"
if [ -n "$LWJGL_CP" ] && [ -f "$MVK_LIB" ]; then
  mkdir -p "$T/vkclasses"
  if "$JAVAC" -cp "$CP:$CLASSES:$LWJGL_CP" -d "$T/vkclasses" \
       "$ROOT/provider/tests/dev/vrmc/provider/GpuSyncVulkanHostTest.java" \
     && "$JAVA" -Dorg.lwjgl.vulkan.libname="$MVK_LIB" \
          -cp "$CP:$CLASSES:$T/vkclasses:$LWJGL_CP" \
          dev.vrmc.provider.GpuSyncVulkanHostTest > "$T/vulkan-host.log" 2>&1 \
     && grep -q "PASS (real MoltenVK: semaphore create + event export)" "$T/vulkan-host.log"; then
    echo "[provider-tests] vulkan-host-test: PASS"
    grep -E "exportable timeline|deallocate|destroySemaphore" "$T/vulkan-host.log" | head -3
  else
    tail -20 "$T/vulkan-host.log" 2>/dev/null || true
    fail "vulkan-host-test"
  fi
else
  echo "[provider-tests] vulkan-host-test: SKIP (needs LWJGL 3.4.1 + MoltenVK macOS SDK; see MVK_LIB)"
fi

# --- 4b. M8 render feedback + eye-target policy (pure Java, no game classes) ---------------------
step "m8-render-test"
mkdir -p "$T/renderclasses"
if "$JAVAC" -d "$T/renderclasses" \
     "$ROOT/provider/src/main/java/dev/vrmc/provider/bridge/VrmcBridge.java" \
     "$ROOT/provider/src/main/java/dev/vrmc/provider/VisionFrameStats.java" \
     "$ROOT/provider/src/main/java/dev/vrmc/provider/VisionRenderSettings.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionRenderSettingsTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionFrameStatsTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionTargetCadenceTest.java" \
     "$ROOT/provider/src/main/java/dev/vrmc/provider/VisionContentGovernor.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionContentGovernorTest.java" \
     "$ROOT/provider/src/main/java/dev/vrmc/provider/VisionTargetGuardrail.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionTargetGuardrailTest.java" \
     "$ROOT/provider/src/main/java/dev/vrmc/provider/VisionWorldSupersample.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionWorldSupersampleTest.java"; then
  if "$JAVA" -cp "$T/renderclasses" dev.vrmc.provider.VisionRenderSettingsTest > "$T/m8-render.log" 2>&1 \
     && grep -q "\[m8-render-test\] PASS" "$T/m8-render.log"; then
    echo "[provider-tests] m8-render: PASS (render feedback layout/parse + eye-target scale policy)"
    grep -E "\[m8-render-test\] [0-9]+ checks" "$T/m8-render.log"
  else
    cat "$T/m8-render.log"; fail "m8-render"
  fi
  if "$JAVA" -cp "$T/renderclasses" dev.vrmc.provider.VisionFrameStatsTest > "$T/m8-frame.log" 2>&1 \
     && grep -q "\[m5-frame-stats-test\] PASS" "$T/m8-frame.log"; then
    echo "[provider-tests] m8-frame-stats: PASS (90 Hz default + 120 Hz target-interval scoring)"
    grep -E "\[m5-frame-stats-test\] [0-9]+ checks" "$T/m8-frame.log"
  else
    cat "$T/m8-frame.log"; fail "m8-frame-stats"
  fi
  if "$JAVA" -cp "$T/renderclasses" dev.vrmc.provider.VisionTargetCadenceTest > "$T/m8-target.log" 2>&1 \
     && grep -q "\[m8-target-test\] PASS" "$T/m8-target.log"; then
    echo "[provider-tests] m8-target-cadence: PASS (auto|90..120 Hz knob + frame-budget intervals)"
    grep -E "\[m8-target-test\] [0-9]+ checks" "$T/m8-target.log"
  else
    cat "$T/m8-target.log"; fail "m8-target-cadence"
  fi
  if "$JAVA" -cp "$T/renderclasses" dev.vrmc.provider.VisionContentGovernorTest > "$T/m8-content.log" 2>&1 \
     && grep -q "\[m8-content-first-test\] PASS" "$T/m8-content.log"; then
    echo "[provider-tests] m8-content-first: PASS (render/sim reduction policy before resolution)"
    grep -E "\[m8-content-first-test\] [0-9]+ checks" "$T/m8-content.log"
  else
    cat "$T/m8-content.log"; fail "m8-content-first"
  fi
  if "$JAVA" -cp "$T/renderclasses" dev.vrmc.provider.VisionTargetGuardrailTest > "$T/m8-guardrail.log" 2>&1 \
     && grep -q "\[m8-target-guardrail-test\] PASS" "$T/m8-guardrail.log"; then
    echo "[provider-tests] m8-target-guardrail: PASS (unreachable target-cadence auto-revert policy)"
    grep -E "\[m8-target-guardrail-test\] [0-9]+ checks" "$T/m8-guardrail.log"
  else
    cat "$T/m8-guardrail.log"; fail "m8-target-guardrail"
  fi
  if "$JAVA" -cp "$T/renderclasses" dev.vrmc.provider.VisionWorldSupersampleTest > "$T/m8-supersample.log" 2>&1 \
     && grep -q "\[m8-supersample-test\] PASS" "$T/m8-supersample.log"; then
    echo "[provider-tests] m8-world-supersample: PASS (off|1.0..2.0 knob, sqrt-axis mapping, bounded dimensions)"
    grep -E "\[m8-supersample-test\] [0-9]+ checks" "$T/m8-supersample.log"
  else
    cat "$T/m8-supersample.log"; fail "m8-world-supersample"
  fi
else
  fail "m8-render-compile"
fi

# --- 5. M4-W1 immersive input: layout + gesture engine + pose (+ cross-language fixture) ---------
step "m4-input-tests"
mkdir -p "$T/m4classes"
M4_CP="$CP:$CLASSES:$T/m4classes"
if "$JAVAC" -cp "$CP:$CLASSES" -d "$T/m4classes" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionInputLayoutTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionInputTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionHandPoseTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionPoseSmootherTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionGazeMathTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionMiddleGestureTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionLocomotionTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionSwipeGestureTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionRuntimeSettingsTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionCommandFileTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionFrameStatsTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionInputFuzzTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionHotbarWheelTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionRingChordTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionThermalStateTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionStatusJsonTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionHandPoseFuzzTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionPoseSmootherFuzzTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionStatusJsonFuzzTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionRuntimeSettingsFuzzTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionGazeMathFuzzTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionHandCalibrationTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionLogFormatTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionM7GestureTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionM7GestureFuzzTest.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/TestJson.java" \
     "$ROOT/provider/tests/dev/vrmc/provider/VisionInputFixtureTest.java"; then
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionInputLayoutTest > "$T/m4-layout.log" 2>&1 \
     && grep -q "PASS" "$T/m4-layout.log"; then
    echo "[provider-tests] m4-layout: PASS (ABI v3 sizes/offsets + documented-offset round-trip)"
  else
    cat "$T/m4-layout.log"; fail "m4-layout"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionInputTest > "$T/m4-input.log" 2>&1 \
     && grep -q "\[m4-input-test\] PASS" "$T/m4-input.log"; then
    echo "[provider-tests] m4-gestures: PASS (hysteresis/arming/taps/stale/action-sets/bindings)"
    grep -E "\[m4-input-test\] [0-9]+ checks" "$T/m4-input.log"
  else
    cat "$T/m4-input.log"; fail "m4-gestures"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionHandPoseTest > "$T/m4-pose.log" 2>&1 \
     && grep -q "\[m4-pose-test\] PASS" "$T/m4-pose.log"; then
    echo "[provider-tests] m4-pose: PASS (R*(0,0,-1)=aim, orthonormal basis, gaze fallback)"
    grep -E "\[m4-pose-test\] [0-9]+ checks" "$T/m4-pose.log"
  else
    cat "$T/m4-pose.log"; fail "m4-pose"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionPoseSmootherTest > "$T/m4-smoother.log" 2>&1 \
     && grep -q "\[m4-smoother-test\] PASS" "$T/m4-smoother.log"; then
    echo "[provider-tests] m4-smoother: PASS (One-Euro damping/convergence, angle slerp, reset, passthrough)"
    grep -E "\[m4-smoother-test\] [0-9]+ checks" "$T/m4-smoother.log"
  else
    cat "$T/m4-smoother.log"; fail "m4-smoother"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionGazeMathTest > "$T/m4-gaze.log" 2>&1 \
     && grep -q "\[m4-gaze-test\] PASS" "$T/m4-gaze.log"; then
    echo "[provider-tests] m4-gaze: PASS (tile->NDC->eye-ray->GUI-plane geometry)"
    grep -E "\[m4-gaze-test\] [0-9]+ checks" "$T/m4-gaze.log"
  else
    cat "$T/m4-gaze.log"; fail "m4-gaze"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionMiddleGestureTest > "$T/m4-middle.log" 2>&1 \
     && grep -q "\[m4-middle-test\] PASS" "$T/m4-middle.log"; then
    echo "[provider-tests] m4-middle: PASS (middle pinch hysteresis/tap/double-tap/bindings/loss)"
    grep -E "\[m4-middle-test\] [0-9]+ checks" "$T/m4-middle.log"
  else
    cat "$T/m4-middle.log"; fail "m4-middle"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionLocomotionTest > "$T/m4-locomotion.log" 2>&1 \
     && grep -q "\[m4-locomotion-test\] PASS" "$T/m4-locomotion.log"; then
    echo "[provider-tests] m4-locomotion: PASS (middle-pinch virtual stick axes/deadzone)"
    grep -E "\[m4-locomotion-test\] [0-9]+ checks" "$T/m4-locomotion.log"
  else
    cat "$T/m4-locomotion.log"; fail "m4-locomotion"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionSwipeGestureTest > "$T/m4-swipe.log" 2>&1 \
     && grep -q "\[m4-swipe-test\] PASS" "$T/m4-swipe.log"; then
    echo "[provider-tests] m4-swipe: PASS (opt-in open-hand swipe directions/cooldown)"
    grep -E "\[m4-swipe-test\] [0-9]+ checks" "$T/m4-swipe.log"
  else
    cat "$T/m4-swipe.log"; fail "m4-swipe"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionRuntimeSettingsTest > "$T/m5-settings.log" 2>&1 \
     && grep -q "\[m5-settings-test\] PASS" "$T/m5-settings.log"; then
    echo "[provider-tests] m5-settings: PASS (vrmc-runtime.properties parser: opt-in, presets, invalid warnings)"
    grep -E "\[m5-settings-test\] [0-9]+ checks" "$T/m5-settings.log"
  else
    cat "$T/m5-settings.log"; fail "m5-settings"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionCommandFileTest > "$T/m5-command.log" 2>&1 \
     && grep -q "\[m5-command-test\] PASS" "$T/m5-command.log"; then
    echo "[provider-tests] m5-command: PASS (command take/validate/result contract)"
    grep -E "\[m5-command-test\] [0-9]+ checks" "$T/m5-command.log"
  else
    cat "$T/m5-command.log"; fail "m5-command"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionFrameStatsTest > "$T/m5-frame.log" 2>&1 \
     && grep -q "\[m5-frame-stats-test\] PASS" "$T/m5-frame.log"; then
    echo "[provider-tests] m5-frame-stats: PASS (rolling poll P50/P95/max, 90 Hz missed-frame count)"
    grep -E "\[m5-frame-stats-test\] [0-9]+ checks" "$T/m5-frame.log"
  else
    cat "$T/m5-frame.log"; fail "m5-frame-stats"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionInputFuzzTest > "$T/m4-fuzz.log" 2>&1 \
     && grep -q "\[m4-fuzz-test\] PASS" "$T/m4-fuzz.log"; then
    echo "[provider-tests] m4-fuzz: PASS (random frames; untracked/stale release + W4 safety invariants)"
    grep -E "\[m4-fuzz-test\] frames=" "$T/m4-fuzz.log"
  else
    cat "$T/m4-fuzz.log"; fail "m4-fuzz"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionHotbarWheelTest > "$T/m4-hotbar.log" 2>&1 \
     && grep -q "\[m4-hotbar-wheel-test\] PASS" "$T/m4-hotbar.log"; then
    echo "[provider-tests] m4-hotbar-wheel: PASS (ring-chord slot mapping/deadzone/clamp)"
    grep -E "\[m4-hotbar-wheel-test\] [0-9]+ checks" "$T/m4-hotbar.log"
  else
    cat "$T/m4-hotbar.log"; fail "m4-hotbar-wheel"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionRingChordTest > "$T/m4-ring.log" 2>&1 \
     && grep -q "\[m4-ring-chord-test\] PASS" "$T/m4-ring.log"; then
    echo "[provider-tests] m4-ring-chord: PASS (both-hand ring pinch hysteresis/loss/opt-out)"
    grep -E "\[m4-ring-chord-test\] [0-9]+ checks" "$T/m4-ring.log"
  else
    cat "$T/m4-ring.log"; fail "m4-ring-chord"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionM7GestureTest > "$T/m7-gesture.log" 2>&1 \
     && grep -q "\[m7-gesture-test\] PASS" "$T/m7-gesture.log"; then
    echo "[provider-tests] m7-gesture: PASS (synthetic mapping/thresholds/priorities/context/release)"
    grep -E "\[m7-gesture-test\] [0-9]+ checks" "$T/m7-gesture.log"
  else
    cat "$T/m7-gesture.log"; fail "m7-gesture"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionM7GestureFuzzTest > "$T/m7-fuzz.log" 2>&1 \
     && grep -q "\[m7-fuzz-test\] PASS" "$T/m7-fuzz.log"; then
    echo "[provider-tests] m7-fuzz: PASS (random frames: no stuck hand actions, releaseAll complete)"
    grep -E "\[m7-fuzz-test\] frames=" "$T/m7-fuzz.log"
  else
    cat "$T/m7-fuzz.log"; fail "m7-fuzz"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionLogFormatTest > "$T/m4-log-format.log" 2>&1 \
     && grep -q "\[m4-log-format-test\] PASS" "$T/m4-log-format.log"; then
    echo "[provider-tests] m4-log-format: PASS (startup locomotion printf types/no exception)"
    grep -E "\[m4-log-format-test\] [0-9]+ checks" "$T/m4-log-format.log"
  else
    cat "$T/m4-log-format.log"; fail "m4-log-format"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionHandCalibrationTest > "$T/m4-hand-calibration.log" 2>&1 \
     && grep -q "\[m4-hand-calibration-test\] PASS" "$T/m4-hand-calibration.log"; then
    echo "[provider-tests] m4-hand-calibration: PASS (phases/suggestions/report/NaN safety)"
    grep -E "\[m4-hand-calibration-test\] [0-9]+ checks" "$T/m4-hand-calibration.log"
  else
    cat "$T/m4-hand-calibration.log"; fail "m4-hand-calibration"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionGazeMathFuzzTest > "$T/m4-gaze-fuzz.log" 2>&1 \
     && grep -q "\[m4-gaze-fuzz-test\] PASS" "$T/m4-gaze-fuzz.log"; then
    echo "[provider-tests] m4-gaze-fuzz: PASS (500k invalid tile/ray/plane cases null-or-in-range)"
    grep -E "\[m4-gaze-fuzz-test\] cases=" "$T/m4-gaze-fuzz.log"
  else
    cat "$T/m4-gaze-fuzz.log"; fail "m4-gaze-fuzz"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionRuntimeSettingsFuzzTest > "$T/m5-settings-fuzz.log" 2>&1 \
     && grep -q "\[m5-settings-fuzz-test\] PASS" "$T/m5-settings-fuzz.log"; then
    echo "[provider-tests] m5-settings-fuzz: PASS (100k arbitrary runtime maps within bounds)"
    grep -E "\[m5-settings-fuzz-test\] cases=" "$T/m5-settings-fuzz.log"
  else
    cat "$T/m5-settings-fuzz.log"; fail "m5-settings-fuzz"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionStatusJsonFuzzTest > "$T/m5-status-json-fuzz.log" 2>&1 \
     && grep -q "\[m5-status-json-fuzz-test\] PASS" "$T/m5-status-json-fuzz.log"; then
    echo "[provider-tests] m5-status-json-fuzz: PASS (100k arbitrary strings/non-finite numbers)"
    grep -E "\[m5-status-json-fuzz-test\] cases=" "$T/m5-status-json-fuzz.log"
  else
    cat "$T/m5-status-json-fuzz.log"; fail "m5-status-json-fuzz"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionPoseSmootherFuzzTest > "$T/m4-smoother-fuzz.log" 2>&1 \
     && grep -q "\[m4-smoother-fuzz-test\] PASS" "$T/m4-smoother-fuzz.log"; then
    echo "[provider-tests] m4-smoother-fuzz: PASS (100k random poses/timestamps finite+orthonormal)"
    grep -E "\[m4-smoother-fuzz-test\] cases=" "$T/m4-smoother-fuzz.log"
  else
    cat "$T/m4-smoother-fuzz.log"; fail "m4-smoother-fuzz"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionHandPoseFuzzTest > "$T/m4-pose-fuzz.log" 2>&1 \
     && grep -q "\[m4-pose-fuzz-test\] PASS" "$T/m4-pose-fuzz.log"; then
    echo "[provider-tests] m4-pose-fuzz: PASS (200k random/degenerate pose cases finite+orthonormal)"
    grep -E "\[m4-pose-fuzz-test\] cases=[0-9]+" "$T/m4-pose-fuzz.log"
  else
    cat "$T/m4-pose-fuzz.log"; fail "m4-pose-fuzz"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionStatusJsonTest > "$T/m5-status-json.log" 2>&1 \
     && grep -q "\[m5-status-json-test\] PASS" "$T/m5-status-json.log"; then
    echo "[provider-tests] m5-status-json: PASS (strict JSON validity/escapes/EV-0144 regression)"
    grep -E "\[m5-status-json-test\] [0-9]+ checks" "$T/m5-status-json.log"
  else
    cat "$T/m5-status-json.log"; fail "m5-status-json"
  fi
  if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionThermalStateTest > "$T/m5-thermal.log" 2>&1 \
     && grep -q "\[m5-thermal-test\] PASS" "$T/m5-thermal.log"; then
    echo "[provider-tests] m5-thermal: PASS (shell thermal state reader/advisory)"
    grep -E "\[m5-thermal-test\] [0-9]+ checks" "$T/m5-thermal.log"
  else
    cat "$T/m5-thermal.log"; fail "m5-thermal"
  fi
  # Cross-language fixture: set-but-missing must FAIL; unset is an explicit SKIP (never silent).
  FIXTURE="${VRMC_INPUT_FIXTURE:-}"
  if [ -z "$FIXTURE" ]; then
    echo "[provider-tests] m4-fixture: SKIP (VRMC_INPUT_FIXTURE unset; run bridge/tests/make_input_fixture.c)"
  elif [ ! -f "$FIXTURE" ]; then
    echo "[provider-tests] m4-fixture: FAIL (VRMC_INPUT_FIXTURE is set but the file is missing: $FIXTURE)"
    fail "m4-fixture"
  else
    FRAMES="${VRMC_INPUT_FIXTURE_FRAMES:-}"
    if [ -z "$FRAMES" ] && [ -f "$FIXTURE.frames" ]; then FRAMES="$FIXTURE.frames"; fi
    if [ -n "$FRAMES" ]; then export VRMC_INPUT_FIXTURE_FRAMES="$FRAMES"; fi
    if "$JAVA" -cp "$M4_CP" dev.vrmc.provider.VisionInputFixtureTest > "$T/m4-fixture.log" 2>&1 \
       && grep -q "\[m4-fixture-test\] PASS" "$T/m4-fixture.log"; then
      grep -E "\[m4-fixture-test\] (PASS|SKIP|[0-9]+ checks)" "$T/m4-fixture.log"
      echo "[provider-tests] m4-fixture: PASS (C -> Java 752-byte contract + timeline replay)"
    else
      cat "$T/m4-fixture.log"; fail "m4-fixture"
    fi
  fi
else
  fail "m4-input-compile"
fi

if [ "$FAILED" != "0" ]; then
  echo; echo "[provider-tests] FAILED"
  exit 1
fi
echo; echo "[provider-tests] ALL PASS"