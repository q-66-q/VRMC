#!/bin/bash
# Regression guard for the M3c black-immersive root cause (EV-0093):
# The CompositorServices drawable depth attachment MUST be cleared to 1.0 (near) by default.
# Clearing to 0.0 (reverse-Z far) made visionOS 27.2 present the whole layer black on D1 even though
# the colour texture was bright and the command buffer completed (A/B device evidence in EV-0093).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/runtime/native-shell/Sources/VRMCCompositor.mm"
fail() { echo "[depth-clear-test] FAIL: $*" >&2; exit 1; }
[ -f "$SRC" ] || fail "compositor source not found: $SRC"
grep -q 'rp.depthAttachment.clearDepth = depthZero ? 0.0 : 1.0' "$SRC" \
  || fail "default drawable depth clear is not 1.0 (EV-0093 regression)"
grep -q 'vrmc-depth-zero.flag' "$SRC" \
  || fail "the vrmc-depth-zero.flag A/B escape hatch is missing"
grep -q 'ROOT CAUSE (EV-0093)' "$SRC" \
  || fail "the EV-0093 root-cause comment is missing"
# The known-good M3A probe (EV-0074) must keep clearing depth to 1.0 as the reference.
grep -q 'rp.depthAttachment.clearDepth = 1.0;' "$ROOT/runtime/probes/m3a-immersive/Sources/ProbeRenderer.mm" \
  || fail "M3A probe reference depth clear is not 1.0"
echo "[depth-clear-test] PASS: default depth clear 1.0 + vrmc-depth-zero A/B + probe reference 1.0"
