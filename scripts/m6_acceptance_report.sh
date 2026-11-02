#!/bin/bash
# M6/M5 acceptance readiness report (host documentation gate).
#
# Parses the acceptance matrices:
#   docs/mvp/M5_ACCEPTANCE.md  -> H1..H10 (status is the LAST table cell)
#   docs/mvp/M6_ACCEPTANCE.md  -> AC-1..AC-6/K1..K6 (status is the SECOND-to-last cell;
#                                                     the last cell is evidence/gap)
# Prints per-row status + counts. This is a reporting gate only: host evidence never becomes a device PASS.
#
# Usage: scripts/m6_acceptance_report.sh [--require-pass]
#   --require-pass  exit 1 unless every listed row's status is an explicit PASS
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

trim_cell() { echo "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^\*\*//; s/\*\*$//; s/^`//; s/`$//'; }

{
  echo "# VRMC acceptance readiness report"
  echo "# generated: $(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "# source: docs/mvp/M5_ACCEPTANCE.md, docs/mvp/M6_ACCEPTANCE.md"
  echo
  echo "## M5_ACCEPTANCE.md (H1..H10)"
  awk -F'|' '/^\| *\*?\*?H[0-9]+/ {
        id=$2; status=$5;
        gsub(/^[ \t*`]+|[ \t*`]+$/, "", id);
        gsub(/^[ \t*`]+|[ \t*`]+$/, "", status);
        gsub(/`/, "", status);
        printf "%-6s %s\n", id, status;
      }' "$ROOT/docs/mvp/M5_ACCEPTANCE.md"
  echo
  echo "## M6_ACCEPTANCE.md (AC-1..AC-6, K1..K6)"
  awk -F'|' '/^\| *\*?\*?(AC-[0-9]+|K[0-9]+)/ {
        id=$2; status=$4;
        gsub(/^[ \t*`]+|[ \t*`]+$/, "", id);
        gsub(/^[ \t*`]+|[ \t*`]+$/, "", status);
        printf "%-6s %s\n", id, status;
      }' "$ROOT/docs/mvp/M6_ACCEPTANCE.md"
  echo
} > "$OUT"
ROWS=$(grep -E '^(H[0-9]+|AC-[0-9]+|K[0-9]+) ' "$OUT" || true)
TOTAL=$(printf '%s\n' "$ROWS" | grep -c . || true)
PASS=$(printf '%s\n' "$ROWS" | grep -c -E ' PASS$' || true)
NOTRUN=$(printf '%s\n' "$ROWS" | grep -c 'NOT RUN' || true)
PARTIAL=$(printf '%s\n' "$ROWS" | grep -c 'PARTIAL' || true)
MIXED=$(printf '%s\n' "$ROWS" | grep 'PARTIAL' | grep -c 'NOT RUN' || true)
{
  echo "## summary"
  echo "rows=$TOTAL explicit-pass=$PASS not-run=$NOTRUN partial=$PARTIAL (partial rows that also say NOT RUN: $MIXED; categories overlap intentionally)"
  echo
  echo "## rows (machine-readable)"
  grep -E '^(H[0-9]+|AC-[0-9]+|K[0-9]+) ' "$OUT" | sed -E 's/^(H[0-9]+|AC-[0-9]+|K[0-9]+) +/id=\1 status=/'
} >> "$OUT"
cat "$OUT"
if [ "$REQUIRE" = "1" ]; then
  if printf '%s\n' "$ROWS" | grep -qv ' PASS$'; then
    echo "[acceptance] RESULT: NOT READY ($PASS/$TOTAL rows explicit PASS)" >&2
    exit 1
  fi
  echo "[acceptance] RESULT: READY ($PASS/$TOTAL rows explicit PASS)"
else
  echo "[acceptance] RESULT: report only (use --require-pass for the release gate)"
fi
