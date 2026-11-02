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
#
# Usage: provider/tests/run_tests.sh
# Env:   PROVIDER_OUT (default /tmp/vrmc-provider-build), LWJGL_JAR (auto-detected for the smoke test)
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

if [ "$FAILED" != "0" ]; then
  echo; echo "[provider-tests] FAILED"
  exit 1
fi
echo; echo "[provider-tests] ALL PASS"
