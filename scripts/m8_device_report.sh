#!/bin/bash
# Build a human-readable M8 device-session report (and optionally an evidence bundle) from a pull.
#
# The report embeds the A6-A9 classifier output, key compositor/provider/shell log lines, the per-window
# frame trace summary, the recorded build identity and a placeholder for the operator's visual statement.
# Works on a device pull or on an existing directory (e.g. a simulator/fixture pull) for testing.
#
# Usage:
#   scripts/m8_device_report.sh --from <pull-dir> [--out FILE] [--operator-note "..."]
#   scripts/m8_device_report.sh [--out FILE] [--operator-note "..."]        # pulls from D1 first
#
# Options/env:
#   --from DIR        analyse an existing pull directory (no device contact)
#   --out FILE        report path (default <repo>/export/m8-device-session-report.md; use /tmp to test)
#   --operator-note   operator visual statement for the report (blur/jaggedness/comfort at 90 vs 120)
#   --evidence        also create an evidence bundle (scripts/log_evidence.sh) for this session
#   DEVICE/BUNDLE/OUTDIR  forward to scripts/m8_device_check.sh for the pull
#
# Exit: 0 report written (even for PARTIAL/FAIL sessions) / 2 usage / 5 device pull failed.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FROM=""
OUT="$ROOT/export/m8-device-session-report.md"
OPERATOR_NOTE=""
EVIDENCE=0
DEVICE="${DEVICE:-${VRMC_DEVICE_UDID:-}}"
BUNDLE="${BUNDLE:-dev.vrmc.vrmc}"
OUTDIR="${OUTDIR:-/tmp/vrmc-m8-device}"
say() { echo "[m8-report] $*"; }
die() { echo "[m8-report] ERROR: $*" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --from) FROM="${2:?--from needs a directory}"; shift 2 ;;
    --out) OUT="${2:?--out needs a file}"; shift 2 ;;
    --operator-note) OPERATOR_NOTE="${2:?--operator-note needs text}"; shift 2 ;;
    --evidence) EVIDENCE=1; shift ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument '$1' (see --help)" ;;
  esac
done

CLASSIFIER_LOG="$(mktemp /tmp/vrmc-m8-classifier.XXXXXX)"
if [ -n "$FROM" ]; then
  [ -d "$FROM" ] || die "pull directory not found: $FROM"
  PULL="$FROM"
  "$ROOT/scripts/m8_device_check.sh" --from "$PULL" > "$CLASSIFIER_LOG" 2>&1
  RC=$?
else
  PULL="$OUTDIR"
  OUTDIR="$OUTDIR" DEVICE="$DEVICE" BUNDLE="$BUNDLE" "$ROOT/scripts/m8_device_check.sh" > "$CLASSIFIER_LOG" 2>&1
  RC=$?
  if [ "$RC" = "5" ] || [ ! -d "$PULL" ]; then
    cat "$CLASSIFIER_LOG"
    say "RESULT: NOT RUN (device pull failed: D1 unavailable or logs missing)"
    exit 5
  fi
fi
say "classifier exit=$RC (pull: $PULL)"
RESULT_LINE=$(grep -m1 'RESULT:' "$CLASSIFIER_LOG" | sed 's/^.*RESULT: /RESULT: /')
[ -n "$RESULT_LINE" ] || RESULT_LINE="RESULT: NOT RUN (no classifier verdict)"
case "$RC" in
  0) STATUS="PASS" ;;
  2) STATUS="PARTIAL" ;;
  4) STATUS="FAIL (hard regression)" ;;
  *) STATUS="NOT RUN" ;;
esac

MANIFEST="$ROOT/export/m8-device-candidate.txt"
app_tree=$(grep -m1 '^app_tree_sha256=' "$MANIFEST" 2>/dev/null | cut -d= -f2)
bundle=$(grep -m1 '^bundle_id=' "$MANIFEST" 2>/dev/null | cut -d= -f2)
version=$(grep -m1 '^version=' "$MANIFEST" 2>/dev/null | cut -d= -f2)
framework=$(grep -m1 '^framework_sha256=' "$MANIFEST" 2>/dev/null | cut -d= -f2)
provider=$(grep -m1 '^provider_jar_sha256=' "$MANIFEST" 2>/dev/null | cut -d= -f2)
provider_bytes=$(grep -m1 '^provider_jar_bytes=' "$MANIFEST" 2>/dev/null | cut -d= -f2)

grab() { # grab <file> <pattern> [max]
  local file="$1" pattern="$2" max="${3:-4}"
  [ -f "$PULL/$file" ] || return 0
  grep -E "$pattern" "$PULL/$file" 2>/dev/null | tail -n "$max" || true
}

{
  echo '# M8 device-session report'
  echo ''
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)  -  pull: $PULL"
  echo ''
  echo "Classifier: exit $RC - $RESULT_LINE"
  echo ''
  echo '## Build identity (recorded candidate)'
  echo ''
  echo '| item | value |'
  echo '|---|---|'
  echo "| bundle | ${bundle:-?} (version ${version:-?}) |"
  echo "| app tree sha256 | ${app_tree:-?} |"
  echo "| framework sha256 | ${framework:-?} |"
  echo "| provider jar sha256 | ${provider:-?} (${provider_bytes:-?} bytes) |"
  echo "| device | $DEVICE |"
  echo ''
  echo '## A6-A9 classifier output'
  echo ''
  sed 's/^/    /' "$CLASSIFIER_LOG"
  echo ''
  echo '## Key log lines'
  echo ''
  echo '    ### compositor'
  grab "vrmc-compositor.log" 'layer configuration|foveation rate map|display geometry|render feedback:' 8 | sed 's/^/    /'
  echo ''
  echo '    ### provider'
  grab "latestlog.txt" '\[VRMC-M8\] (render settings|eye target resize|target cadence|content governor|render state|trace)' 10 | sed 's/^/    /'
  echo ''
  echo '    ### shell'
  grab "vrmc-shell.log" 'layer config|onlaunch attempt.*openImmersiveSpace' 4 | sed 's/^/    /'
  echo ''
  echo '## Frame trace (vrmc-m8-trace.csv)'
  echo ''
  if [ -f "$PULL/vrmc-m8-trace.csv" ]; then
    echo "Rows: $(($(wc -l < "$PULL/vrmc-m8-trace.csv" 2>/dev/null || echo 1) - 1))"
    echo ''
    head -1 "$PULL/vrmc-m8-trace.csv" | sed 's/^/    /'
    tail -1 "$PULL/vrmc-m8-trace.csv" | sed 's/^/    /'
  else
    echo 'Not present in this pull (old build or trace disabled).'
  fi
  echo ''
  echo '## Operator visual statement'
  echo ''
  if [ -n "$OPERATOR_NOTE" ]; then
    echo "$OPERATOR_NOTE"
  else
    echo 'NOT PROVIDED. Record: image sharpness vs the pre-M8 build, jagged edges (SSAA/A-B), halo'
    echo 'impression of foveated sharpening, comfort at 90 vs 120 Hz, and whether 120 Hz was pursued.'
  fi
  echo ''
  echo '## Interpretation / next steps'
  echo ''
  case "$RC" in
    0) echo '- A6-A9 PASS: device acceptance pending the operator visual statement above.' ;;
    2) echo '- PARTIAL: inspect the failing row(s) above; tune with'
       echo '  scripts/push_m8_render_config.sh --target-hz/--eye-scale/--sharpening/--content-first,'
       echo '  and --world-supersample 1.44 (relaunch) for the jaggedness A/B.' ;;
    4) echo '- FAIL (hard regression): attach this pull to the evidence bundle and report it; check'
       echo '  [VRMC-M8][WARN] lines and the compositor/provider error markers above.' ;;
    *) echo '- NOT RUN: no M8 session evidence in this pull (old build/JIT/logs missing). Re-run the'
       echo '  session with the current candidate (see docs/mvp/M8_DEVICE_RUN.md).' ;;
  esac
  echo '- Evidence bundle: VERIFY.md section 6 + docs/mvp/M8_DEVICE_HANDOFF.md; include this report as an'
  echo "  artifact and pull the whole $PULL directory."
} > "$OUT"
say "report: $OUT"

if [ "$EVIDENCE" = "1" ]; then
  say 'creating evidence bundle ...'
  ARTIFACTS=()
  for name in vrmc-compositor.log vrmc-shell.log latestlog.txt vrmc-status.json vrmc-m8-trace.csv; do
    [ -f "$PULL/$name" ] && ARTIFACTS+=(--artifact "$PULL/$name")
  done
  ARTIFACTS+=(--artifact "$OUT" --artifact "$CLASSIFIER_LOG")
  "$ROOT/scripts/log_evidence.sh" \
    --title 'M8 device session (D1) A6-A9 + frame trace + operator report' \
    --status "$STATUS" \
    --device "D1 ($DEVICE)" \
    --procedure 'M8 device session on D1: prepare/install candidate + provider jar, JIT launch, immersive 3-5 min with M8 knobs, collect via scripts/m8_device_session.sh; classifier + report generated by scripts/m8_device_report.sh.' \
    --expected 'A6 foveation/rate maps active, A7 4K-class logical size + provider eye targets, A8 measured displayHz (120 Hz if achieved), A9 pacing/regressions; operator visual statement recorded in the report.' \
    --actual "$RESULT_LINE; report: $OUT; operator statement: ${OPERATOR_NOTE:-NOT PROVIDED}." \
    --notes "Generated from pull $PULL. Review the report before publishing; the operator statement is required for full acceptance." \
    "${ARTIFACTS[@]}" 2>&1 | tail -3
fi

say "DONE: $OUT"
