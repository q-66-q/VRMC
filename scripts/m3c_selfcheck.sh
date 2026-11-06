#!/bin/bash
# One-command self-check (operator-independent): immersive presentation AND immersive input.
#
# Runs the host/simulator checks that guard the M3c presentation work and the M4-W1 input path:
#   1. depth-clear regression guard (EV-0093 root cause)
#   2. display-view frustum math
#   3. shell framework build (device target)
#   4. provider + bridge builds
#   5. bridge host test suite (stub/sync/TSan/layout/MoltenVK-Metal probe)
#   6. provider-sampling simulator harness (flat path + GPU timeline sync + stereo pattern + parking A/B + re-entry)
#   7. M4 immersive-input self-check (ABI v3 input bridge + gestures + cross-language fixture + simulator input scenario)
#
# Usage: scripts/m3c_selfcheck.sh [--fast]
#   --fast skips the bridge Metal host probe / full bridge suite and the simulator harness, and runs the
#          M4 input self-check in its fast mode; the default runs everything.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAST=0
[ "${1:-}" = "--fast" ] && FAST=1
fail=0
step() { echo; echo "===== $* ====="; }
run() { local name="$1"; shift; if "$@"; then echo "[selfcheck] PASS: $name"; else echo "[selfcheck] FAIL: $name"; fail=1; fi; }

step "1/7 depth-clear regression"
run "DepthClearRegressionTest" "$ROOT/scripts/tests/DepthClearRegressionTest.sh"

step "1b/7 M8 device-check classifier (host)"
run "M8DeviceCheckTest" "$ROOT/scripts/tests/M8DeviceCheckTest.sh"

step "1c/7 M8 foveation host probe (real Metal rasterization rate map)"
if "$ROOT/runtime/probes/m8-foveation/run.sh" > /tmp/vrmc-selfcheck-foveation-probe.log 2>&1; then
  echo "[selfcheck] PASS: M8FoveationProbe"
else
  rc=$?
  if [ "$rc" = "2" ]; then
    echo "[selfcheck] SKIP: M8FoveationProbe (no Metal / rasterization rate map support)"
  else
    echo "[selfcheck] FAIL: M8FoveationProbe"; fail=1
  fi
fi

step "1d/7 M8 quality-ladder host probe (upscale PSNR/acutance ladder)"
if "$ROOT/runtime/probes/m8-quality-ladder/run.sh" > /tmp/vrmc-selfcheck-quality-ladder.log 2>&1; then
  echo "[selfcheck] PASS: M8QualityLadder"
else
  rc=$?
  if [ "$rc" = "2" ]; then
    echo "[selfcheck] SKIP: M8QualityLadder (no Metal device)"
  else
    echo "[selfcheck] FAIL: M8QualityLadder"; fail=1
  fi
fi

step "1e/7 M8 device-session flow rehearsal (host data, no device)"
if "$ROOT/scripts/tests/M8DeviceFlowTest.sh" > /tmp/vrmc-selfcheck-m8-flow.log 2>&1; then
  echo "[selfcheck] PASS: M8DeviceFlowTest"
else
  echo "[selfcheck] FAIL: M8DeviceFlowTest"; tail -20 /tmp/vrmc-selfcheck-m8-flow.log; fail=1
fi

step "2/7 display-view frustum math"
run "DisplayViewsTest" "$ROOT/scripts/test_display_views.sh"

step "3/7 shell framework build (device)"
run "build_shell(device)" bash -c "cd '$ROOT/runtime/native-shell' && xcodebuild -project VRMCShell.xcodeproj -scheme VRMCShell -configuration Debug -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/vrmc-shell-selfcheck build > /tmp/vrmc-selfcheck-shell-build.log 2>&1 && grep -q 'BUILD SUCCEEDED' /tmp/vrmc-selfcheck-shell-build.log"

step "4/7 provider + bridge builds"
run "build_provider" bash -c "cd '$ROOT' && scripts/build_provider.sh >/dev/null"
if [ "$FAST" = "1" ]; then
  run "build_bridge(device)" bash -c "cd '$ROOT' && MODE=device scripts/build_bridge.sh >/dev/null"
else
  run "build_bridge(both)" bash -c "cd '$ROOT' && MODE=both scripts/build_bridge.sh >/dev/null"
fi

step "5/7 bridge host suite"
if [ "$FAST" = "1" ]; then
  echo "[selfcheck] skip (--fast)"
else
  run "bridge_host_tests" bash -c "cd '$ROOT' && bridge/tests/run_tests.sh > /tmp/vrmc-selfcheck-bridge-tests.log 2>&1; rc=\$?; tail -3 /tmp/vrmc-selfcheck-bridge-tests.log; exit \$rc"
fi

step "6/7 provider-sampling simulator harness"
if [ "$FAST" = "1" ]; then
  echo "[selfcheck] skip (--fast)"
else
  # Retry once: the first simulator launch after a full shell build can race CoreSimulator service startup.
  run "provider-sim (presentation scenarios; env-limited ones skip)" bash -c "ok=1; for i in 1 2; do '$ROOT/runtime/probes/m3c-provider-sim/run.sh' > /tmp/vrmc-selfcheck-provider-sim.log 2>&1 && { ok=0; break; }; sleep 5; done; tail -4 /tmp/vrmc-selfcheck-provider-sim.log; exit \$ok"
fi

step "7/7 M4 immersive-input self-check"
if [ "$FAST" = "1" ]; then
  run "m4_input_selfcheck(fast)" "$ROOT/scripts/m4_input_selfcheck.sh" --fast
else
  run "m4_input_selfcheck" "$ROOT/scripts/m4_input_selfcheck.sh"
fi

echo
if [ "$fail" != "0" ]; then
  echo "[selfcheck] RESULT: FAIL"
  exit 1
fi
echo "[selfcheck] RESULT: PASS (host + simulator checks; device/headset evidence is separate)"
