#!/bin/bash
# M6: fail release readiness if the imported device acceptance checklist contains a FAIL row.
# Missing checklist/report is a SKIP (device acceptance not run yet), not a pass.
# Usage: scripts/m6_check_device_checklist.sh [STATUS_FILE]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="${1:-$ROOT/export/device-acceptance-status.txt}"
if [ ! -f "$FILE" ]; then
  echo "[device-checklist] SKIP no imported checklist at $FILE (device acceptance NOT RUN)"
  exit 0
fi
FAILS=$(grep -E '=FAIL$' "$FILE" || true)
NOTRUN=$(grep -c -E '=NOT RUN$' "$FILE" || true)
PARTIAL=$(grep -c -E '=PARTIAL$' "$FILE" || true)
PASS=$(grep -c -E '=PASS$' "$FILE" || true)
echo "[device-checklist] rows=$(grep -c . "$FILE" || true) PASS=$PASS PARTIAL=$PARTIAL NOT RUN=$NOTRUN"
if [ -n "$FAILS" ]; then
  echo "[device-checklist] FAIL rows:" >&2
  printf '%s\n' "$FAILS" >&2
  echo "[device-checklist] RESULT: FAIL (fix device issues before release)" >&2
  exit 1
fi
if [ "$NOTRUN" != "0" ] || [ "$PARTIAL" != "0" ]; then
  echo "[device-checklist] RESULT: INCOMPLETE (NOT RUN/PARTIAL rows present; acceptance matrices remain authoritative)"
  exit 2
fi
echo "[device-checklist] RESULT: PASS (all imported rows PASS; acceptance matrices remains authoritative)"
