#!/bin/bash
# End-to-end rehearsal of the M8 device-session command flow on HOST data (no device).
#
# The future D1 session runs exactly these orchestration commands:
#   scripts/m8_device_session.sh prepare --dry-run        (artifact validation + planned commands)
#   scripts/m8_device_session.sh collect --report         (classifier + report from a pull)
#   scripts/m8_device_report.sh --from <pull>             (report/evidence scaffold)
#   scripts/m8_device_package.sh --check                  (durable package still matches the manifest)
#
# This test generates synthetic pulls with scripts/tests/M8DeviceCheckTest.sh (PASS and 90 Hz PARTIAL)
# and runs the same wrappers over them, so a regression in the operator flow fails here instead of on
# the headset. TEST DATA only.
#
# Usage: scripts/tests/M8DeviceFlowTest.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="${TMPDIR:-/tmp}/vrmc-m8-device-check-test"
REPORT_DEFAULT="$ROOT/export/m8-device-session-report.md"
fail=0
checks=0
check() { # check <name> <ok:0/1> [detail]
  local name="$1" ok="$2" detail="${3:-}"
  checks=$((checks + 1))
  if [ "$ok" = "0" ]; then echo "[m8-flow-test] PASS: $name"; else echo "[m8-flow-test] FAIL: $name $detail"; fail=1; fi
}

# ---- 1. generate synthetic pulls (PASS + 90 Hz PARTIAL) --------------------------------------
if "$ROOT/scripts/tests/M8DeviceCheckTest.sh" > /tmp/vrmc-m8-flow-classifier.log 2>&1; then
  check "classifier test provides fixtures" 0
else
  check "classifier test provides fixtures" 1 "(see /tmp/vrmc-m8-flow-classifier.log)"
  echo "[m8-flow-test] RESULT: FAIL"; exit 1
fi
PASS_PULL="$T/pass"
HZ90_PULL="$T/hz90"
[ -d "$PASS_PULL" ] && [ -d "$HZ90_PULL" ] && check "fixture pulls exist" 0 || check "fixture pulls exist" 1

# ---- 2. session collect --report on the PASS pull --------------------------------------------
if RM_BEFORE=1 && [ -f "$REPORT_DEFAULT" ]; then cp -f "$REPORT_DEFAULT" /tmp/vrmc-m8-flow-report-before.md; rm -f "$REPORT_DEFAULT"; fi
"$ROOT/scripts/m8_device_session.sh" --from "$PASS_PULL" collect --report > /tmp/vrmc-m8-flow-collect.log 2>&1
RC=$?
check "collect --report preserves PASS exit code (0)" "$([ "$RC" = "0" ] && echo 0 || echo 1)" "rc=$RC"
if [ -f "$REPORT_DEFAULT" ]; then
  check "collect --report wrote the default report" 0
  sections=$(grep -cE 'A6-A9 classifier output|Build identity|Frame trace|Operator visual statement' "$REPORT_DEFAULT")
  check "default report has all four sections" "$([ "$sections" -ge 4 ] && echo 0 || echo 1)" "sections=$sections"
  grep -q 'RESULT: PASS (A6-A9)' "$REPORT_DEFAULT" && check "report carries the PASS verdict" 0 || check "report carries the PASS verdict" 1
  cp -f "$REPORT_DEFAULT" /tmp/vrmc-m8-flow-report-pass.md
  rm -f "$REPORT_DEFAULT"
else
  check "collect --report wrote the default report" 1 "(missing $REPORT_DEFAULT)"
fi

# ---- 3. report on the 90 Hz PARTIAL pull with an operator note ------------------------------
"$ROOT/scripts/m8_device_report.sh" --from "$HZ90_PULL" --out /tmp/vrmc-m8-flow-report-hz90.md \
  --operator-note "TEST NOTE: image acceptable, no halos" > /tmp/vrmc-m8-flow-report-hz90.log 2>&1
check "report on 90 Hz pull succeeds" "$([ $? = 0 ] && echo 0 || echo 1)"
grep -q 'RESULT: PARTIAL' /tmp/vrmc-m8-flow-report-hz90.md 2>/dev/null \
  && check "90 Hz report carries PARTIAL" 0 || check "90 Hz report carries PARTIAL" 1
grep -q 'TEST NOTE: image acceptable, no halos' /tmp/vrmc-m8-flow-report-hz90.md 2>/dev/null \
  && check "operator note embedded" 0 || check "operator note embedded" 1

# ---- 4. prepare --dry-run (skips cleanly when no staged candidate is present) ----------------
if [ -d /tmp/VRMC-native-m8.app ] && [ -f /tmp/vrmc-provider-build/vrmc-provider.jar ]; then
  "$ROOT/scripts/m8_device_session.sh" prepare --dry-run > /tmp/vrmc-m8-flow-prepare.log 2>&1
  check "prepare --dry-run validates the staged candidate" "$([ $? = 0 ] && echo 0 || echo 1)"
  grep -q 'DRY-RUN: DEVICE=' /tmp/vrmc-m8-flow-prepare.log 2>/dev/null \
    && check "prepare --dry-run prints the install command" 0 || check "prepare --dry-run prints the install command" 1
else
  echo "[m8-flow-test] SKIP: prepare --dry-run (no staged /tmp candidate on this host)"
fi

# ---- 5. durable package check ----------------------------------------------------------------
if [ -d /tmp/VRMC-native-m8.app ] && [ -f /tmp/vrmc-provider-build/vrmc-provider.jar ]; then
  "$ROOT/scripts/m8_device_package.sh" --check > /tmp/vrmc-m8-flow-package.log 2>&1
  check "package --check matches the candidate manifest" "$([ $? = 0 ] && echo 0 || echo 1)"
else
  echo "[m8-flow-test] SKIP: package --check (no staged candidate)"
fi

echo "[m8-flow-test] $checks checks, fail=$fail"
if [ "$fail" = "0" ]; then echo "[m8-flow-test] RESULT: PASS"; exit 0; fi
echo "[m8-flow-test] RESULT: FAIL"; exit 1
