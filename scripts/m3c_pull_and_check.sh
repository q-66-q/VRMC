#!/bin/bash
# M3c post-run triage: pull the decisive device logs/files and print the lines that decide the
# black-immersive question (root cause EV-0093: drawn-drawable depth clear must be 1.0).
#
# Usage:
#   DEVICE=<udid> OUTDIR=/tmp/vrmc-m3c scripts/m3c_pull_and_check.sh      # pull from D1 + analyse
#   scripts/m3c_pull_and_check.sh --from <dir>                           # analyse an existing pull
#
# Exit: 0 = triage lines printed, no hard regression detected; 2 = depthZero=1 or no presented frame.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTDIR="${OUTDIR:-/tmp/vrmc-m3c}"
DEVICE="${DEVICE:-${VRMC_DEVICE_UDID:-}}"
FROM=""
if [ "${1:-}" = "--from" ]; then FROM="${2:?--from needs a directory}"; OUTDIR="$FROM"; fi
mkdir -p "$OUTDIR"

if [ -z "$FROM" ]; then
  echo "[m3c] pulling Documents from $DEVICE into $OUTDIR"
  for f in vrmc-shell.log vrmc-compositor.log latestlog.txt \
           vrmc-drawable-L.raw vrmc-drawable-R.raw vrmc-drawable-L.raw.meta vrmc-drawable-R.raw.meta; do
    xcrun devicectl device copy from --device "$DEVICE" \
      --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc \
      --source "Documents/$f" --destination "$OUTDIR/$f" >/dev/null 2>&1 || true
  done
fi

COMP="$OUTDIR/vrmc-compositor.log"
SHELLLOG="$OUTDIR/vrmc-shell.log"
fail=0

echo "== compositor diagnostics (last session) =="
grep -E 'diagnostics: reprojMode' "$COMP" 2>/dev/null | tail -2 || echo "  (no diagnostics line)"

echo "== first presented frame / layer state / frame lines =="
grep -E 'first presented frame|drawable topology' "$COMP" 2>/dev/null | tail -4 || true
grep -E 'frame [0-9]+ eyes=' "$COMP" 2>/dev/null | tail -2 | sed 's/^/  /' || true

echo "== drawable readback (what was drawn) =="
grep -E 'drawable proof' "$COMP" 2>/dev/null | tail -2 | sed 's/^/  /' || echo "  (no drawable proof — clear-probe mode or no presented frame)"
if [ -f "$OUTDIR/vrmc-drawable-L.raw.meta" ]; then
  echo -n "  meta: "; cat "$OUTDIR/vrmc-drawable-L.raw.meta"; echo
fi

echo "== immersive scene activation / parking (shell) =="
grep -E 'STATE immersive=' "$SHELLLOG" 2>/dev/null | tail -3 | sed 's/^/  /' || true
grep -E 'VRMCCompositorRunning|window parked|window re-parked|NO-FRAME|willResignActive|VRMCImmersiveEnded' "$SHELLLOG" 2>/dev/null | tail -6 | sed 's/^/  /' || true

echo "== verdict =="
if grep -q 'depthZero=1' "$COMP" 2>/dev/null; then
  echo "  REGRESSION: depthZero=1 (EV-0093 root cause re-enabled via vrmc-depth-zero.flag)"; fail=1
elif grep -q 'depthZero=0' "$COMP" 2>/dev/null; then
  echo "  OK: depthZero=0 (drawable depth clear 1.0, EV-0093 fix active)"
else
  echo "  WARN: cannot read depthZero from the diagnostics line"
fi
if grep -q 'first presented frame' "$COMP" 2>/dev/null; then
  echo "  OK: compositor presented at least one frame this log"
else
  echo "  WARN: no 'first presented frame' in the pulled compositor log (check the immersive open)"; fail=1
fi
if grep -q 'CPSceneSessionRoleImmersiveSpaceApplication:fgActive' "$SHELLLOG" 2>/dev/null; then
  echo "  OK: immersive scene was foreground-active while logging"
elif grep -q 'CPSceneSessionRoleImmersiveSpaceApplication' "$SHELLLOG" 2>/dev/null; then
  echo "  WARN: immersive scene seen but not foreground-active in the sampled STATE lines"
else
  echo "  WARN: no immersive-scene activation logged (manual Enter VR not tapped / space not open?)"
fi


echo "== provider eye textures (game run only) =="
grep -E 'provider eye textures|provider tex L|provider tex R|eye frame sync' "$COMP" 2>/dev/null | tail -4 | sed 's/^/  /' || true

echo "== window parking effectiveness =="
if grep -q 'window parked after first presented frame' "$SHELLLOG" 2>/dev/null; then
  grep -E 'window parked after first presented frame|window re-parked' "$SHELLLOG" 2>/dev/null | tail -2 | sed 's/^/  /'
  if grep -E 'window parked after first presented frame.*alpha=0.00' "$SHELLLOG" 2>/dev/null | grep -q 'hidden=false'; then
    echo "  NOTE: alpha-only parking (isHidden not set); if the operator still saw a floating window, A/B with vrmc-hide-windows.flag"
  fi
else
  echo "  (windows not parked — selftest/manual mode leaves them visible by design)"
fi

echo "== mode / sampling =="
grep -E 'shading mode=|TEST PATTERN state|diagnostics:' "$COMP" 2>/dev/null | tail -3 | sed 's/^/  /' || true

echo "[m3c] logs in $OUTDIR"
exit $fail