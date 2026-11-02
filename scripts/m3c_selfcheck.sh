#!/bin/bash
# One-command M3c self-check (operator-independent).
#
# Runs the host/simulator checks that guard the immersive presentation work:
#   1. depth-clear regression guard (EV-0093 root cause)
#   2. display-view frustum math
#   3. provider + bridge builds
#   4. bridge host test suite (stub/sync/TSan/layout/MoltenVK-Metal probe)
#   5. provider-sampling simulator harness (flat path + GPU timeline sync + stereo pattern)
#
# Usage: scripts/m3c_selfcheck.sh [--fast]
#   --fast skips the bridge Metal host probe / full bridge suite and the simulator harness build cache is
#          reused; the default runs everything.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAST=0
[ "${1:-}" = "--fast" ] && FAST=1
fail=0
step() { echo; echo "===== $* ====="; }
run() { local name="$1"; shift; if "$@"; then echo "[selfcheck] PASS: $name"; else echo "[selfcheck] FAIL: $name"; fail=1; fi; }

step "1/5 depth-clear regression"
run "DepthClearRegressionTest" "$ROOT/scripts/tests/DepthClearRegressionTest.sh"

step "2/5 display-view frustum math"
run "DisplayViewsTest" "$ROOT/scripts/test_display_views.sh"

step "3/5 provider + bridge builds"
run "build_provider" bash -c "cd '$ROOT' && scripts/build_provider.sh >/dev/null"
if [ "$FAST" = "1" ]; then
  run "build_bridge(device)" bash -c "cd '$ROOT' && MODE=device scripts/build_bridge.sh >/dev/null"
else
  run "build_bridge(both)" bash -c "cd '$ROOT' && MODE=both scripts/build_bridge.sh >/dev/null"
fi

step "4/5 bridge host suite"
if [ "$FAST" = "1" ]; then
  echo "[selfcheck] skip (--fast)"
else
  run "bridge_host_tests" bash -c "cd '$ROOT' && bridge/tests/run_tests.sh 2>&1 | tail -3"
fi

step "5/5 provider-sampling simulator harness"
if [ "$FAST" = "1" ]; then
  echo "[selfcheck] skip (--fast)"
else
  run "provider-sim (flat + sync + pattern)" bash -c "'$ROOT/runtime/probes/m3c-provider-sim/run.sh' 2>&1 | tail -4"
fi

echo
if [ "$fail" != "0" ]; then
  echo "[selfcheck] RESULT: FAIL"
  exit 1
fi
echo "[selfcheck] RESULT: PASS (host + simulator checks; device/headset evidence is separate)"
