#!/bin/bash
# M5/M6 guard: every vrmc-status.json field the launcher reads must be written by the provider builder.
# Prevents silent status/UI drift after JSON-builder refactors.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SHELL_SRC="runtime/native-shell/Sources/Shell.swift"
BUILDER="provider/src/main/java/dev/vrmc/provider/VisionStatusJson.java"
[ -f "$SHELL_SRC" ] || { echo "[status-fields] ERROR: $SHELL_SRC missing" >&2; exit 2; }
[ -f "$BUILDER" ] || { echo "[status-fields] ERROR: $BUILDER missing" >&2; exit 2; }
FIELDS=$(grep -oE 'obj\["[A-Za-z0-9]+"\]' "$SHELL_SRC" | sed -E 's/obj\["([A-Za-z0-9]+)"\]/\1/' | LC_ALL=C sort -u)
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
