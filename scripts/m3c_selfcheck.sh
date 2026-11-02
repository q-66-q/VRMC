#!/bin/bash
# One-command M3c self-check (operator-independent).
#
# Runs the host/simulator checks that guard the immersive presentation work:
#   1. depth-clear regression guard (EV-0093 root cause)
#   2. display-view frustum math
#   3. shell framework build (device target)
#   4. provider + bridge builds
#   5. bridge host test suite (stub/sync/TSan/layout/MoltenVK-Metal probe)
#   6. provider-sampling simulator harness (flat path + GPU timeline sync + stereo pattern + parking A/B + re-entry)
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

step "1/6 depth-clear regression"
run "DepthClearRegressionTest" "$ROOT/scripts/tests/DepthClearRegressionTest.sh"

step "2/6 display-view frustum math"
run "DisplayViewsTest" "$ROOT/scripts/test_display_views.sh"

step "3/6 shell framework build (device)"
run "build_shell(device)" bash -c "cd '$ROOT/runtime/native-shell' && xcodebuild -project VRMCShell.xcodeproj -scheme VRMCShell -configuration Debug -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/vrmc-shell-selfcheck build > /tmp/vrmc-selfcheck-shell-build.log 2>&1 && grep -q 'BUILD SUCCEEDED' /tmp/vrmc-selfcheck-shell-build.log"

step "4/6 provider + bridge builds"
run "build_provider" bash -c "cd '$ROOT' && scripts/build_provider.sh >/dev/null"
if [ "$FAST" = "1" ]; then
  run "build_bridge(device)" bash -c "cd '$ROOT' && MODE=device scripts/build_bridge.sh >/dev/null"
else
  run "build_bridge(both)" bash -c "cd '$ROOT' && MODE=both scripts/build_bridge.sh >/dev/null"
fi

step "5/6 bridge host suite"
if [ "$FAST" = "1" ]; then
  echo "[selfcheck] skip (--fast)"
else
  run "bridge_host_tests" bash -c "cd '$ROOT' && bridge/tests/run_tests.sh > /tmp/vrmc-selfcheck-bridge-tests.log 2>&1; rc=\$?; tail -3 /tmp/vrmc-selfcheck-bridge-tests.log; exit \$rc"
fi

step "6/6 provider-sampling simulator harness"
if [ "$FAST" = "1" ]; then
  echo "[selfcheck] skip (--fast)"
else
  # Retry once: the first simulator launch after a full shell build can race CoreSimulator service startup.
  run "provider-sim (six scenarios)" bash -c "ok=1; for i in 1 2; do '$ROOT/runtime/probes/m3c-provider-sim/run.sh' > /tmp/vrmc-selfcheck-provider-sim.log 2>&1 && { ok=0; break; }; sleep 5; done; tail -4 /tmp/vrmc-selfcheck-provider-sim.log; exit \$ok"
fi

echo
if [ "$fail" != "0" ]; then
  echo "[selfcheck] RESULT: FAIL"
  exit 1
fi
echo "[selfcheck] RESULT: PASS (host + simulator checks; device/headset evidence is separate)"