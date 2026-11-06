#!/bin/bash
# M8 quality ladder host probe (macOS Apple Silicon; no device, no CompositorServices).
#
# Quantifies the compositor's upscale trade: a 1920x1080 procedural reference is box-downsampled to
# several "game eye-target" sizes, then upscaled back with the compositor's flat shader and with the
# fovea-weighted sharp shader at the auto strength the compositor would choose. PSNR and edge acutance
# vs the reference produce the settings ladder used to reason about blur/jaggedness on device.
#
# Usage: runtime/probes/m8-quality-ladder/run.sh
# Exit: 0 PASS, 1 FAIL, 2 SKIP (no Metal device).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-/tmp/vrmc-m8-quality-ladder}"
mkdir -p "$OUT"
SDK=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang++)
echo "[m8-quality-ladder] building probe (macOS host Metal)"
"$CC" -fobjc-arc -O1 -isysroot "$SDK" -framework Foundation -framework Metal \
  -o "$OUT/quality_ladder" "$HERE/quality_ladder.mm" || { echo "[m8-quality-ladder] BUILD FAILED"; exit 1; }
"$OUT/quality_ladder" | tee "$OUT/ladder.log"
rc=${PIPESTATUS[0]}
echo "[m8-quality-ladder] log: $OUT/ladder.log"
exit "$rc"
