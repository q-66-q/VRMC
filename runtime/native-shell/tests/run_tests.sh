#!/bin/bash
# Host tests for the visionOS shell's platform-independent logic (no device, no simulator).
#
#   1. provisioning - ModProvisioner policy: provider install/upgrade/user-managed/reset, Vivecraft
#                     hash-verified import (Documents + Inbox), rejection, duplicate-jar warnings,
#                     manifest parsing. Compiled for macOS from the same source the shell ships.
#   2. pins         - scripts/check_provisioning_pins.sh (Swift built-in pin == versions.env).
#
# Usage: runtime/native-shell/tests/run_tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SHELL_DIR="$ROOT/runtime/native-shell"
T="${TMPDIR:-/tmp}/vrmc-shell-tests"
rm -rf "$T"
mkdir -p "$T"
FAILED=0
fail() { echo "[shell-tests] $1: FAIL"; FAILED=1; }

echo "=== provisioning ==="
SWIFTC=$(xcrun --sdk macosx --find swiftc 2>/dev/null || command -v swiftc || true)
if [ -z "$SWIFTC" ]; then
  fail "provisioning (no swiftc)"
elif "$SWIFTC" -O -parse-as-library -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
       "$SHELL_DIR/Sources/ModProvisioner.swift" "$SHELL_DIR/tests/ModProvisionerTests.swift" \
       -o "$T/provisioning-tests" > "$T/provisioning-build.log" 2>&1; then
  if "$T/provisioning-tests" > "$T/provisioning.log" 2>&1 && grep -q "\[provisioning-test\] PASS" "$T/provisioning.log"; then
    grep -E "\[provisioning-test\] [0-9]+ checks" "$T/provisioning.log"
    echo "[shell-tests] provisioning: PASS"
  else
    cat "$T/provisioning.log"; fail "provisioning"
  fi
else
  cat "$T/provisioning-build.log"; fail "provisioning-build"
fi

echo; echo "=== pins ==="
if "$ROOT/scripts/check_provisioning_pins.sh"; then
  echo "[shell-tests] pins: PASS"
else
  fail "pins"
fi

if [ "$FAILED" != "0" ]; then
  echo; echo "[shell-tests] FAILED"; exit 1
fi
echo; echo "[shell-tests] ALL PASS"
