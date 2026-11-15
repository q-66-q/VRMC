#!/bin/bash
# Host checks for the visionOS shell (no device, no simulator).
#
#   pins - scripts/check_provisioning_pins.sh: the Vivecraft version / file name / SHA-256 that
#          SetupManager (Sources/ShellSetup.swift) installs must equal versions.env.
#
# Usage: runtime/native-shell/tests/run_tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FAILED=0

echo "=== pins ==="
if "$ROOT/scripts/check_provisioning_pins.sh"; then
  echo "[shell-tests] pins: PASS"
else
  echo "[shell-tests] pins: FAIL"; FAILED=1
fi

if [ "$FAILED" != "0" ]; then
  echo; echo "[shell-tests] FAILED"; exit 1
fi
echo; echo "[shell-tests] ALL PASS"
