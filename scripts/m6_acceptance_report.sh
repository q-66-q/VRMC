#!/bin/bash
# M6/M5 acceptance readiness report (host documentation gate).
#
# Parses the acceptance matrices in docs/mvp/M5_ACCEPTANCE.md (H1..H10) and
# docs/mvp/M6_ACCEPTANCE.md (AC-1..AC-6, K1..K6) and prints the current status + counts.
# This is a reporting gate only: it does NOT turn host evidence into device PASS.
#
# Usage: scripts/m6_acceptance_report.sh [--require-pass]
#   --require-pass  exit 1 unless every listed row has an explicit PASS status
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$(mktemp -t vrmc-acceptance.XXXXXX)}"
REQUIRE=0
for arg in "$@"; do
  case "$arg" in
    --require-pass) REQUIRE=1 ;;
    *) echo "[acceptance] unknown argument: $arg" >&2; exit 2 ;;
  esac
done
{
  echo "# VRMC acceptance readiness report"
  echo "# generated: $(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "# source: docs/mvp/M5_ACCEPTANCE.md, docs/mvp/M6_ACCEPTANCE.md"
  echo
  for f in "$ROOT/docs/mvp/M5_ACCEPTANCE.md" "$ROOT/docs/mvp/M6_ACCEPTANCE.md"; do
    [ -f "$f" ] || continue
    echo "## $(basename "$f")"
    grep -E '^\| *\*?\*?(H[0-9]+|AC-[0-9]+|K[0-9]+)' "$f" | \
      sed -E 's/^\| *\*?\*?([^|*]+)\*?\*? *\|.*\| *([^|]+) *\|[[:space:]]*$/\1 :: \2/' | \
      while IFS= read -r row; do
        id="${row%% :: *}"
        status="${row##* :: }"
        printf '%-6s %s\n' "$id" "$status"
      done
    echo
  done
} > "$OUT"
PASS=$(grep -c -E ':: *`?PASS`? *$' "$OUT" || true)
NOTRUN=$(grep -c -E 'NOT RUN' "$OUT" || true)
PARTIAL=$(grep -c -E 'PARTIAL' "$OUT" || true)
TOTAL=$(grep -c -E '^(H[0-9]+|AC-[0-9]+|K[0-9]+) ' "$OUT" || true)
{
  echo "## summary"
  echo "rows=$TOTAL pass=$PASS partial=$PARTIAL not-run=$NOTRUN"
} >> "$OUT"
cat "$OUT"
if [ "$REQUIRE" = "1" ]; then
  # Every row must contain an explicit PASS (partial/host-pass does NOT satisfy a device gate).
  if grep -E '^(H[0-9]+|AC-[0-9]+|K[0-9]+) ' "$OUT" | grep -qv 'PASS'; then
    echo "[acceptance] RESULT: NOT READY ($PASS/$TOTAL rows explicit PASS)" >&2
    exit 1
  fi
  echo "[acceptance] RESULT: READY ($PASS/$TOTAL rows explicit PASS)"
else
  echo "[acceptance] RESULT: report only (use --require-pass for the release gate)"
fi
