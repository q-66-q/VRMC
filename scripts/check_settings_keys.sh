#!/bin/bash
# M5/M6 guard: every VRMC settings key the launcher writes must be recognized by provider source.
# Prevents silent UI/provider key drift (the reload-input regression class).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# The window UI moved from Shell.swift to ShellUI.swift in 1.3; scan every shell source so the
# guard keeps working across file splits instead of silently checking nothing.
SHELL_SRCS=(runtime/native-shell/Sources/*.swift)
[ "${#SHELL_SRCS[@]}" -gt 0 ] && [ -f "${SHELL_SRCS[0]}" ] || { echo "[settings-keys] ERROR: no runtime/native-shell/Sources/*.swift found" >&2; exit 2; }
# Settings keys are written through subscript dictionaries (values["comfort.seated"], tune["m7.pinch.on"]),
# so extract exactly those instead of guessing at quoted dotted strings.
KEYS=$(grep -hoE '(values|tune|settings|runtime)\["[A-Za-z0-9_.]+"\]' "${SHELL_SRCS[@]}" \
       | sed -E 's/^[A-Za-z]+\["([A-Za-z0-9_.]+)"\]$/\1/' | grep -v '^vrmc-' | LC_ALL=C sort -u)
if [ -z "$KEYS" ]; then
  echo "[settings-keys] FAIL: could not extract any settings keys from ${SHELL_SRCS[*]} (guard would be vacuous)" >&2
  exit 1
fi
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
