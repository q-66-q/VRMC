#!/bin/bash
# One-command M4-W1 immersive-input self-check (host + simulator; no headset, no device install).
#
# Proves the plumbing that makes the game controllable FROM the immersive scene:
#   1. bridge host tests (ABI v3 layout, input publish/acquire, release + TSan concurrency,
#      and the deterministic C->Java fixture generator)
#   2. provider build (ABI v3 input consumption + gesture engine + isEnabled mixin)
#   3. provider JVM tests incl. the cross-language fixture contract (exact 752-byte snapshot
#      produced by the C side, parsed by the Java side)
#   4. simulator input scenario: the REAL compositor runs in the visionOS simulator with the fake
#      provider bridge, synthetic hand input (Documents/vrmc-input-sim.flag) is published, and the
#      captured snapshot stream is asserted (tracking bits, pinch/fist cycles, release frames)
#
# Evidence classes: host + simulator only. This is NOT hands evidence and NOT device evidence.
# See docs/analysis/immersive-input.md and docs/mvp/M4_PLAN.md.
#
# Usage: scripts/m4_input_selfcheck.sh [--fast]
#   --fast skips the TSan bridge test and the simulator scenario (quick local loop).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT_DIR:-/tmp/vrmc-m4-input}"
FAST=0
[ "${1:-}" = "--fast" ] && FAST=1
mkdir -p "$OUT/logs"
fail=0
step() { echo; echo "===== $* ====="; }
pass() { echo "[m4-selfcheck] PASS: $1"; }
failed() { echo "[m4-selfcheck] FAIL: $1"; fail=1; }
run() { # run <name> <command...>
  local name="$1"; shift
  if "$@" > "$OUT/logs/$name.log" 2>&1; then
    tail -4 "$OUT/logs/$name.log"
    pass "$name"
  else
    tail -40 "$OUT/logs/$name.log"
    failed "$name (log: $OUT/logs/$name.log)"
  fi
}

echo "[m4-selfcheck] root=$ROOT out=$OUT fast=$FAST"

step "1/5 bridge host tests (ABI v3 input contract + TSan + build both)"
if [ "$FAST" = "1" ]; then
  run bridge-tests env OUT_DIR="$OUT/bridge-tests" bash -c "'$ROOT/bridge/tests/run_tests.sh' --skip-metal --skip-tsan"
else
  run bridge-tests env OUT_DIR="$OUT/bridge-tests" "$ROOT/bridge/tests/run_tests.sh" --skip-metal
fi

step "2/5 cross-language fixture (C vrmc_input_state -> raw 752-byte fixture)"
FIXTURE="$OUT/input_fixture.bin"
GEN="$OUT/make_input_fixture"
if clang -O2 -I "$ROOT/bridge/abi" "$ROOT/bridge/tests/make_input_fixture.c" "$ROOT/bridge/src/vrmc_stub.c" -lpthread -o "$GEN" > "$OUT/logs/fixture-build.log" 2>&1; then
  if "$GEN" "$FIXTURE" >> "$OUT/logs/fixture-run.log" 2>&1; then
    SIZE=$(wc -c < "$FIXTURE" | tr -d ' ')
    SHA=$(shasum -a 256 "$FIXTURE" | awk '{print $1}')
    FRAMES="$FIXTURE.frames"
    FSIZE=$( [ -f "$FRAMES" ] && wc -c < "$FRAMES" | tr -d ' ' || echo 0 )
    FSHA=$( [ -f "$FRAMES" ] && shasum -a 256 "$FRAMES" | awk '{print $1}' || echo none )
    echo "[m4-selfcheck] fixture path=$FIXTURE bytes=$SIZE sha256=$SHA"
    echo "[m4-selfcheck] fixture.frames path=$FRAMES bytes=$FSIZE sha256=$FSHA"
    if [ "$SIZE" = "752" ]; then pass "fixture-generate"; else failed "fixture-size ($SIZE != 752)"; fi
    if [ "$FSIZE" = "7520" ]; then pass "fixture-timeline-generate"; else failed "fixture.frames-size ($FSIZE != 7520)"; fi
    tail -12 "$OUT/logs/fixture-run.log"
  else
    tail -30 "$OUT/logs/fixture-run.log"; failed "fixture-run"
  fi
else
  tail -30 "$OUT/logs/fixture-build.log"; failed "fixture-build"
fi

step "3/5 provider build (ABI v3 input + gestures)"
run provider-build env OUT_DIR="$OUT/provider" "$ROOT/scripts/build_provider.sh"

step "4/5 provider JVM tests (+ cross-language fixture contract)"
if [ -f "$FIXTURE" ]; then
  run provider-tests env PROVIDER_OUT="$OUT/provider" VRMC_INPUT_FIXTURE="$FIXTURE" VRMC_INPUT_FIXTURE_FRAMES="$FIXTURE.frames" "$ROOT/provider/tests/run_tests.sh"
else
  failed "provider-tests (no fixture generated in step 2)"
fi

step "5/5 simulator input scenario (real compositor + synthetic hands)"
if [ "$FAST" = "1" ]; then
  echo "[m4-selfcheck] skip (--fast)"
else
  run provider-sim-input bash -c "cd '$ROOT/runtime/probes/m3c-provider-sim' && OUT='$OUT/provider-sim' ./run.sh input"
  if [ -f "$OUT/logs/provider-sim-input.log" ]; then
    grep -E 'scenario: input|\[provider-sim\]|INPUT-SIM|capture' "$OUT/logs/provider-sim-input.log" | tail -20 || true
  fi
fi

echo
echo "[m4-selfcheck] artifacts: $OUT/logs/ logs, $OUT/provider-sim/ simulator cases"
if [ "$fail" != "0" ]; then
  echo "[m4-selfcheck] RESULT: FAIL"
  exit 1
fi
echo "[m4-selfcheck] RESULT: PASS (host + simulator plumbing; hands and device are separate evidence)"
