#!/bin/bash
# M5/M6 guard: every vrmc-status.json field the launcher reads must be written by the provider builder.
# Prevents silent status/UI drift after JSON-builder refactors.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# The window UI moved from Shell.swift to ShellUI.swift in 1.3; scan every shell source so the
# guard keeps working across file splits instead of silently checking nothing.
SHELL_SRCS=(runtime/native-shell/Sources/*.swift)
BUILDER="provider/src/main/java/dev/vrmc/provider/VisionStatusJson.java"
[ "${#SHELL_SRCS[@]}" -gt 0 ] && [ -f "${SHELL_SRCS[0]}" ] || { echo "[status-fields] ERROR: no runtime/native-shell/Sources/*.swift found" >&2; exit 2; }
[ -f "$BUILDER" ] || { echo "[status-fields] ERROR: $BUILDER missing" >&2; exit 2; }
# Both the 1.2 obj["field"] and the 1.3 status["field"] read forms count.
FIELDS=$(grep -hoE '(obj|status)\["[A-Za-z0-9_]+"\]' "${SHELL_SRCS[@]}" \
         | sed -E 's/^[A-Za-z]+\["([A-Za-z0-9_]+)"\]$/\1/' | LC_ALL=C sort -u)
if [ -z "$FIELDS" ]; then
  echo "[status-fields] FAIL: could not extract any status fields from ${SHELL_SRCS[*]} (guard would be vacuous)" >&2
  exit 1
fi
fail=0; count=0
for field in $FIELDS; do
  count=$((count + 1))
  if grep -qF "\"$field\"" "$BUILDER"; then
    echo "[status-fields] OK   $field"
  else
    echo "[status-fields] FAIL launcher reads status field '$field' but VisionStatusJson never writes it"
    fail=1
  fi
done
echo "[status-fields] checked=$count"
if [ "$fail" != "0" ]; then echo "[status-fields] RESULT: FAIL" >&2; exit 1; fi
echo "[status-fields] RESULT: PASS (launcher status fields all written by provider)"
