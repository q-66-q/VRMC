#!/bin/bash
# M8 foveation host probe: verifies the compositor's full-screen flat sampling pass renders correctly
# into a variable-rasterization-rate (foveated) target on real Metal, and that the render-pass viewport
# must be the rate map's logical screen size (the convention the compositor uses with the
# CompositorServices view viewport). macOS Apple Silicon only; no device, no CompositorServices.
#
# Usage: runtime/probes/m8-foveation/run.sh [--keep]
# Exit: 0 PASS, 1 FAIL, 2 SKIP (no Metal device or no rasterization rate map support).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-/tmp/vrmc-m8-foveation-probe}"
mkdir -p "$OUT"
SDK=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang++)
echo "[m8-foveation] building probe (macOS host Metal)"
"$CC" -fobjc-arc -O1 -isysroot "$SDK" -framework Foundation -framework Metal \
  -o "$OUT/host_probe" "$HERE/host_probe.mm" || { echo "[m8-foveation] BUILD FAILED"; exit 1; }
"$OUT/host_probe" | tee "$OUT/probe.log"
rc=${PIPESTATUS[0]}
echo "[m8-foveation] log: $OUT/probe.log"
exit "$rc"
