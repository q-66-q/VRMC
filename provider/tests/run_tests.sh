#!/bin/bash
# Host tests for the VRMC provider (no device).
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
# Pure-Java mode: when the provider jar cannot be built because the game classpath (Minecraft 26.2
# client jar, Vivecraft classes, JOML/Mixin/ASM/SLF4J) is absent from this host, the suite compiles the
# provider sources that do not import game libraries and runs every test that needs only those. Steps
# needing game classes print an explicit SKIP and the run ends "PURE-JAVA PASS", never "ALL PASS".
# VRMC_REQUIRE_GAME_CP=1 turns the missing classpath back into a hard failure (release gates).
#
# Usage: provider/tests/run_tests.sh
# Env:   PROVIDER_OUT (default /tmp/vrmc-provider-build), LWJGL_JAR (auto-detected for the smoke test),
#        VRMC_INPUT_FIXTURE / VRMC_INPUT_FIXTURE_FRAMES (optional cross-language fixture),
#        VRMC_REQUIRE_GAME_CP=1 (no pure-Java fallback)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROVIDER_OUT="${PROVIDER_OUT:-/tmp/vrmc-provider-build}"
SRC="$ROOT/provider/src/main/java/dev/vrmc/provider"
TESTS="$ROOT/provider/tests/dev/vrmc/provider"
T="${TMPDIR:-/tmp}/vrmc-provider-tests"
rm -rf "$T"
mkdir -p "$T"
JAVAC=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javac
JAVA=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/java
[ -x "$JAVAC" ] || { JAVAC=$(command -v javac || true); JAVA=$(command -v java || true); }
[ -x "$JAVAC" ] && [ -x "$JAVA" ] || { echo "[provider-tests] ERROR: no JDK 25 found" >&2; exit 1; }

FAILED=0
PURE_MODE=0
SKIPPED_GAME_STEPS=()
step() { echo; echo "=== $1 ==="; }
fail() { echo "[provider-tests] $1: FAIL"; FAILED=1; }
skip_game() { echo "[provider-tests] $1: SKIP (pure-Java mode: needs game classes)"; SKIPPED_GAME_STEPS+=("$1"); }

# run_check <classpath> <label> <main-class> <pass-marker> <pass-description> [summary-regex]
# Runs one Java test main, requires <pass-marker> in its output, prints the summary line(s) on PASS
# and the whole log on FAIL.
run_check() {
  local cp="$1" label="$2" cls="$3" marker="$4" desc="$5" summary="${6:-}"
  local log="$T/$label.log"
  if "$JAVA" -cp "$cp" "$cls" > "$log" 2>&1 && grep -qF -- "$marker" "$log"; then
    echo "[provider-tests] $label: PASS ($desc)"
    if [ -n "$summary" ]; then grep -E -- "$summary" "$log" || true; fi
  else
    cat "$log"; fail "$label"
  fi
}

# Provider sources that import game/runtime libraries; everything else compiles with a bare JDK.
GAME_IMPORT_RE='^import (net\.minecraft|org\.vivecraft|org\.spongepowered|org\.joml|com\.mojang|net\.fabricmc|org\.lwjgl|org\.slf4j)'

# --- build the provider jar (also gives us the compile classpath) ----------------------------
step "build-provider"
if OUT_DIR="$PROVIDER_OUT" "$ROOT/scripts/build_provider.sh" > "$T/build.log" 2>&1; then
  grep -E '^\[provider\] (compiled|jar:|size:|sha256:)' "$T/build.log"
  echo "[provider-tests] build-provider: PASS"
  CLASSES="$PROVIDER_OUT/classes"
  CP="$(cat "$PROVIDER_OUT/classpath.txt")"
elif [ "${VRMC_REQUIRE_GAME_CP:-0}" != "1" ] \
     && grep -qE '\[provider\] ERROR: .*(not found|missing).*(set [A-Z_]+_JAR|run: cd Vivecraft)' "$T/build.log"; then
  grep '\[provider\] ERROR' "$T/build.log"
  echo "[provider-tests] build-provider: SKIP (game classpath unavailable on this host)"
  echo "[provider-tests] *** PURE-JAVA MODE: game-dependent steps will be skipped (VRMC_REQUIRE_GAME_CP=1 to fail instead) ***"
  PURE_MODE=1
  SKIPPED_GAME_STEPS+=("build-provider")
  CLASSES="$T/pureclasses"
  mkdir -p "$CLASSES"
  PURE_SOURCES=()
  while IFS= read -r -d '' f; do
    grep -qE "$GAME_IMPORT_RE" "$f" || PURE_SOURCES+=("$f")
  done < <(find "$ROOT/provider/src/main/java" -name '*.java' -print0 | sort -z)
  if ! "$JAVAC" -d "$CLASSES" "${PURE_SOURCES[@]}" > "$T/pure-build.log" 2>&1; then
    cat "$T/pure-build.log"; fail "pure-build"
    echo "[provider-tests] FAILED"; exit 1
  fi
  echo "[provider-tests] pure-build: PASS (${#PURE_SOURCES[@]} provider sources without game imports)"
  CP="$CLASSES"
else
  cat "$T/build.log"
  fail "build-provider"
  echo "[provider-tests] FAILED"
  exit 1
fi

# --- 1. flag parsing (pure Java, no game classes) --------------------------------------------
step "flag-test"
mkdir -p "$T/flagclasses"
"$JAVAC" -d "$T/flagclasses" "$SRC/GpuSyncFlags.java" "$ROOT/provider/tests/GpuSyncFlagsTest.java" \
  || fail "flag-test-compile"
if "$JAVA" -cp "$T/flagclasses" GpuSyncFlagsTest; then
  echo "[provider-tests] flag-test: PASS"
else
  fail "flag-test"
fi

# --- 2. enable/fallback contract (game classes present, no live device) ----------------------
step "fallback-test"
if [ "$PURE_MODE" = "1" ]; then
  skip_game "fallback-test"
else
  mkdir -p "$T/fbclasses"
  "$JAVAC" -cp "$CP:$CLASSES" -d "$T/fbclasses" "$TESTS/GpuEyeSyncFallbackTest.java" || fail "fallback-test-compile"
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
fi

# --- 3. VkReflect reflection plumbing --------------------------------------------------------
step "vkreflect-smoke"
# LWJGL 3.4.1 (same version the game ships): core jar + macOS natives (loaded from the classpath jar)
# + Vulkan struct classes. Used ONLY for the reflection smoke test; the provider jar stays LWJGL-free.
LWJGL_CP="${LWJGL_CP:-}"
if [ -z "$LWJGL_CP" ]; then
  GC="$HOME/.gradle/caches/modules-2"
  LJ_CORE=$(find "$GC" -path '*org.lwjgl/lwjgl/3.4.1*' -name 'lwjgl-3.4.1.jar' -not -name '*sources*' 2>/dev/null | head -1 || true)
  LJ_NAT=$(find "$GC" -path '*org.lwjgl/lwjgl/3.4.1*' -name 'lwjgl-3.4.1-natives-macos-arm64.jar' -not -name '*sources*' 2>/dev/null | head -1 || true)
  LJ_VK=$(find "$GC" -path '*org.lwjgl/lwjgl-vulkan/3.4.1*' -name 'lwjgl-vulkan-3.4.1.jar' -not -name '*sources*' 2>/dev/null | head -1 || true)
  [ -n "$LJ_CORE" ] && [ -n "$LJ_VK" ] && LWJGL_CP="$LJ_CORE:$LJ_VK${LJ_NAT:+:$LJ_NAT}"
fi
mkdir -p "$T/smokeclasses"
"$JAVAC" -cp "$CP:$CLASSES${LWJGL_CP:+:$LWJGL_CP}" -d "$T/smokeclasses" \
  "$TESTS/VkReflectSmokeTest.java" || fail "vkreflect-compile"
# 3a. without LWJGL: must fail closed (this is the provider-jar compile classpath). VkReflect is pure
#     reflection, so this also runs in pure-Java mode.
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
if [ "$PURE_MODE" = "1" ]; then
  skip_game "vulkan-host-test"
elif [ -n "$LWJGL_CP" ] && [ -f "$MVK_LIB" ]; then
  mkdir -p "$T/vkclasses"
  if "$JAVAC" -cp "$CP:$CLASSES:$LWJGL_CP" -d "$T/vkclasses" "$TESTS/GpuSyncVulkanHostTest.java" \
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
RC="$T/renderclasses"
mkdir -p "$RC"
if "$JAVAC" -d "$RC" \
     "$SRC/bridge/VrmcBridge.java" \
     "$SRC/VisionFrameStats.java" \
     "$SRC/VisionRenderSettings.java" \
     "$SRC/VisionContentGovernor.java" \
     "$SRC/VisionTargetGuardrail.java" \
     "$SRC/VisionWorldSupersample.java" \
     "$SRC/VisionTrace.java" \
     "$TESTS/VisionRenderSettingsTest.java" \
     "$TESTS/VisionFrameStatsTest.java" \
     "$TESTS/VisionTargetCadenceTest.java" \
     "$TESTS/VisionContentGovernorTest.java" \
     "$TESTS/VisionTargetGuardrailTest.java" \
     "$TESTS/VisionWorldSupersampleTest.java" \
     "$TESTS/VisionTraceTest.java" \
     "$TESTS/VisionRenderSettingsFixtureTest.java" \
     "$TESTS/VisionRenderSettingsFuzzTest.java"; then
  P=dev.vrmc.provider
  run_check "$RC" m8-render $P.VisionRenderSettingsTest "[m8-render-test] PASS" \
    "render feedback layout/parse + eye-target scale policy" "\[m8-render-test\] [0-9]+ checks"
  run_check "$RC" m8-frame-stats $P.VisionFrameStatsTest "[m5-frame-stats-test] PASS" \
    "90 Hz default + 120 Hz target-interval scoring" "\[m5-frame-stats-test\] [0-9]+ checks"
  run_check "$RC" m8-target-cadence $P.VisionTargetCadenceTest "[m8-target-test] PASS" \
    "auto|90..120 Hz knob + frame-budget intervals" "\[m8-target-test\] [0-9]+ checks"
  run_check "$RC" m8-content-first $P.VisionContentGovernorTest "[m8-content-first-test] PASS" \
    "render/sim reduction policy before resolution" "\[m8-content-first-test\] [0-9]+ checks"
  run_check "$RC" m8-target-guardrail $P.VisionTargetGuardrailTest "[m8-target-guardrail-test] PASS" \
    "unreachable target-cadence auto-revert policy" "\[m8-target-guardrail-test\] [0-9]+ checks"
  run_check "$RC" m8-world-supersample $P.VisionWorldSupersampleTest "[m8-supersample-test] PASS" \
    "off|1.0..2.0 knob, sqrt-axis mapping, bounded dimensions" "\[m8-supersample-test\] [0-9]+ checks"
  run_check "$RC" m8-frame-trace $P.VisionTraceTest "[m8-trace-test] PASS" \
    "per-window CSV schema/formatting + non-finite handling" "\[m8-trace-test\] [0-9]+ checks"
else
  fail "m8-render-compile"
fi

# --- 5. M8 render-feedback ABI: C struct -> Java parser cross-language fixture -----------------
step "m8-render-settings-fixture"
CC_FIXTURE=$(xcrun --sdk macosx --find clang 2>/dev/null || command -v clang || true)
CC_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
if [ -n "$CC_FIXTURE" ] && [ -x "$CC_FIXTURE" ]; then
  if "$CC_FIXTURE" -O2 -isysroot "$CC_SDK" -I "$ROOT/bridge/abi" \
       "$ROOT/bridge/tests/make_render_settings_fixture.c" -o "$T/make_render_settings_fixture" \
       > "$T/m8-rs-fixture-build.log" 2>&1; then
    if "$T/make_render_settings_fixture" "$T/render_settings_fixture.bin" \
         > "$T/m8-rs-fixture-gen.log" 2>&1; then
      RS_SIZE=$(wc -c < "$T/render_settings_fixture.bin" | tr -d ' ')
      RS_SHA=$(shasum -a 256 "$T/render_settings_fixture.bin" | awk '{print $1}')
      echo "[provider-tests] m8-render-settings-fixture: bytes=$RS_SIZE sha256=$RS_SHA"
      if "$JAVA" -cp "$RC" dev.vrmc.provider.VisionRenderSettingsFixtureTest \
           "$T/render_settings_fixture.bin" > "$T/m8-rs-fixture.log" 2>&1 \
         && grep -q "\[m8-rs-fixture-test\] PASS" "$T/m8-rs-fixture.log"; then
        echo "[provider-tests] m8-render-settings-fixture: PASS (C vrmc_render_settings -> Java parse contract, 3 cases)"
        grep -E "\[m8-rs-fixture-test\] [0-9]+ checks" "$T/m8-rs-fixture.log"
        run_check "$RC" m8-render-settings-fuzz dev.vrmc.provider.VisionRenderSettingsFuzzTest \
          "[m8-rs-fuzz-test] PASS" "arbitrary/mutated payloads never throw or leak" "\[m8-rs-fuzz-test\] cases="
      else
        cat "$T/m8-rs-fixture.log"; fail "m8-rs-fixture-java"
      fi
    else
      cat "$T/m8-rs-fixture-gen.log"; fail "m8-rs-fixture-generate"
    fi
  else
    cat "$T/m8-rs-fixture-build.log"; fail "m8-rs-fixture-build"
  fi
else
  echo "[provider-tests] m8-render-settings-fixture: SKIP (no host C compiler)"
fi

# --- 6. M4-W1 immersive input: layout + gesture engine + pose (+ cross-language fixture) ---------
step "m4-input-tests"
M4_DIR="$T/m4classes"
mkdir -p "$M4_DIR"
M4_CP="$CP:$CLASSES:$M4_DIR"
# Tests whose subjects (hand pose, smoother, gaze math, locomotion) are built on JOML/game types.
GAME_TESTS=(VisionHandPoseTest VisionPoseSmootherTest VisionGazeMathTest VisionLocomotionTest
            VisionHandPoseFuzzTest VisionPoseSmootherFuzzTest VisionGazeMathFuzzTest)
M4_TESTS=(VisionInputLayoutTest VisionInputTest VisionHandPoseTest VisionPoseSmootherTest
          VisionGazeMathTest VisionMiddleGestureTest VisionLocomotionTest VisionSwipeGestureTest
          VisionRuntimeSettingsTest VisionCommandFileTest VisionFrameStatsTest VisionInputFuzzTest
          VisionHotbarWheelTest VisionRingChordTest VisionThermalStateTest VisionStatusJsonTest
          VisionHandPoseFuzzTest VisionPoseSmootherFuzzTest VisionStatusJsonFuzzTest
          VisionRuntimeSettingsFuzzTest VisionGazeMathFuzzTest VisionHandCalibrationTest
          VisionLogFormatTest VisionM7GestureTest VisionM7GestureFuzzTest TestJson VisionInputFixtureTest)
is_game_test() { local t; for t in "${GAME_TESTS[@]}"; do [ "$t" = "$1" ] && return 0; done; return 1; }
M4_SOURCES=()
for t in "${M4_TESTS[@]}"; do
  if [ "$PURE_MODE" = "1" ] && is_game_test "$t"; then continue; fi
  M4_SOURCES+=("$TESTS/$t.java")
done
# m4_check <label> <TestClass> <pass-marker> <description> [summary-regex]
m4_check() {
  if [ "$PURE_MODE" = "1" ] && is_game_test "$2"; then skip_game "$1"; return; fi
  run_check "$M4_CP" "$1" "dev.vrmc.provider.$2" "$3" "$4" "${5:-}"
}
if "$JAVAC" -cp "$CP:$CLASSES" -d "$M4_DIR" "${M4_SOURCES[@]}"; then
  m4_check m4-layout VisionInputLayoutTest "PASS" "ABI v3 sizes/offsets + documented-offset round-trip"
  m4_check m4-gestures VisionInputTest "[m4-input-test] PASS" \
    "hysteresis/arming/taps/stale/action-sets/bindings" "\[m4-input-test\] [0-9]+ checks"
  m4_check m4-pose VisionHandPoseTest "[m4-pose-test] PASS" \
    "R*(0,0,-1)=aim, orthonormal basis, gaze fallback" "\[m4-pose-test\] [0-9]+ checks"
  m4_check m4-smoother VisionPoseSmootherTest "[m4-smoother-test] PASS" \
    "One-Euro damping/convergence, angle slerp, reset, passthrough" "\[m4-smoother-test\] [0-9]+ checks"
  m4_check m4-gaze VisionGazeMathTest "[m4-gaze-test] PASS" \
    "tile->NDC->eye-ray->GUI-plane geometry" "\[m4-gaze-test\] [0-9]+ checks"
  m4_check m4-middle VisionMiddleGestureTest "[m4-middle-test] PASS" \
    "middle pinch hysteresis/tap/double-tap/bindings/loss" "\[m4-middle-test\] [0-9]+ checks"
  m4_check m4-locomotion VisionLocomotionTest "[m4-locomotion-test] PASS" \
    "middle-pinch virtual stick axes/deadzone" "\[m4-locomotion-test\] [0-9]+ checks"
  m4_check m4-swipe VisionSwipeGestureTest "[m4-swipe-test] PASS" \
    "opt-in open-hand swipe directions/cooldown" "\[m4-swipe-test\] [0-9]+ checks"
  m4_check m5-settings VisionRuntimeSettingsTest "[m5-settings-test] PASS" \
    "vrmc-runtime.properties parser: opt-in, presets, invalid warnings" "\[m5-settings-test\] [0-9]+ checks"
  m4_check m5-command VisionCommandFileTest "[m5-command-test] PASS" \
    "command take/validate/result contract" "\[m5-command-test\] [0-9]+ checks"
  m4_check m5-frame-stats VisionFrameStatsTest "[m5-frame-stats-test] PASS" \
    "rolling poll P50/P95/max, 90 Hz missed-frame count" "\[m5-frame-stats-test\] [0-9]+ checks"
  m4_check m4-fuzz VisionInputFuzzTest "[m4-fuzz-test] PASS" \
    "random frames; untracked/stale release + W4 safety invariants" "\[m4-fuzz-test\] frames="
  m4_check m4-hotbar-wheel VisionHotbarWheelTest "[m4-hotbar-wheel-test] PASS" \
    "ring-chord slot mapping/deadzone/clamp" "\[m4-hotbar-wheel-test\] [0-9]+ checks"
  m4_check m4-ring-chord VisionRingChordTest "[m4-ring-chord-test] PASS" \
    "both-hand ring pinch hysteresis/loss/opt-out" "\[m4-ring-chord-test\] [0-9]+ checks"
  m4_check m7-gesture VisionM7GestureTest "[m7-gesture-test] PASS" \
    "synthetic mapping/thresholds/priorities/context/release" "\[m7-gesture-test\] [0-9]+ checks"
  m4_check m7-fuzz VisionM7GestureFuzzTest "[m7-fuzz-test] PASS" \
    "random frames: no stuck hand actions, releaseAll complete" "\[m7-fuzz-test\] frames="
  m4_check m4-log-format VisionLogFormatTest "[m4-log-format-test] PASS" \
    "startup locomotion printf types/no exception" "\[m4-log-format-test\] [0-9]+ checks"
  m4_check m4-hand-calibration VisionHandCalibrationTest "[m4-hand-calibration-test] PASS" \
    "phases/suggestions/report/NaN safety" "\[m4-hand-calibration-test\] [0-9]+ checks"
  m4_check m4-gaze-fuzz VisionGazeMathFuzzTest "[m4-gaze-fuzz-test] PASS" \
    "500k invalid tile/ray/plane cases null-or-in-range" "\[m4-gaze-fuzz-test\] cases="
  m4_check m5-settings-fuzz VisionRuntimeSettingsFuzzTest "[m5-settings-fuzz-test] PASS" \
    "100k arbitrary runtime maps within bounds" "\[m5-settings-fuzz-test\] cases="
  m4_check m5-status-json-fuzz VisionStatusJsonFuzzTest "[m5-status-json-fuzz-test] PASS" \
    "100k arbitrary strings/non-finite numbers" "\[m5-status-json-fuzz-test\] cases="
  m4_check m4-smoother-fuzz VisionPoseSmootherFuzzTest "[m4-smoother-fuzz-test] PASS" \
    "100k random poses/timestamps finite+orthonormal" "\[m4-smoother-fuzz-test\] cases="
  m4_check m4-pose-fuzz VisionHandPoseFuzzTest "[m4-pose-fuzz-test] PASS" \
    "200k random/degenerate pose cases finite+orthonormal" "\[m4-pose-fuzz-test\] cases=[0-9]+"
  m4_check m5-status-json VisionStatusJsonTest "[m5-status-json-test] PASS" \
    "strict JSON validity/escapes/EV-0144 regression" "\[m5-status-json-test\] [0-9]+ checks"
  m4_check m5-thermal VisionThermalStateTest "[m5-thermal-test] PASS" \
    "shell thermal state reader/advisory" "\[m5-thermal-test\] [0-9]+ checks"
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
if [ "$PURE_MODE" = "1" ]; then
  echo; echo "[provider-tests] PURE-JAVA PASS (${#SKIPPED_GAME_STEPS[@]} game-dependent steps skipped: ${SKIPPED_GAME_STEPS[*]})"
  echo "[provider-tests] not a full run: provide the game classpath (see scripts/build_provider.sh) for ALL PASS"
  exit 0
fi
echo; echo "[provider-tests] ALL PASS"
