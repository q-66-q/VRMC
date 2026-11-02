#!/bin/bash
# M5/M6 guard: every VRMC settings key the launcher writes must be recognized by provider source.
# Prevents silent UI/provider key drift (the reload-input regression class).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SHELL_SRC="runtime/native-shell/Sources/Shell.swift"
[ -f "$SHELL_SRC" ] || { echo "[settings-keys] ERROR: $SHELL_SRC missing" >&2; exit 2; }
KEYS=$(grep -oE '"(comfort|performance|diagnostics|pinch|fist|middle|ring|swipe|hotbar|move|tracking|hands)\.[A-Za-z0-9.]+"' "$SHELL_SRC" \
       | tr -d '"' | LC_ALL=C sort -u)
fail=0
count=0
for key in $KEYS; do
  count=$((count + 1))
  if grep -RqF "\"$key\"" provider/src/main/java; then
    echo "[settings-keys] OK   $key"
  else
    echo "[settings-keys] FAIL launcher writes '$key' but provider source never reads it"
    fail=1
  fi
done
echo "[settings-keys] checked=$count"
if [ "$fail" != "0" ]; then echo "[settings-keys] RESULT: FAIL" >&2; exit 1; fi
echo "[settings-keys] RESULT: PASS (launcher settings keys all recognized by provider)"
