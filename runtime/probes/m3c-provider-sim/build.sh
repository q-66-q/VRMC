#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"        # repo root (runtime/probes/m3c-provider-sim -> root)
OUT="${OUT:-/tmp/vrmc-fake-provider/libvrmc_bridge.dylib}"
SDK=$(xcrun --sdk xrsimulator --show-sdk-path)
mkdir -p "$(dirname "$OUT")"
xcrun --sdk xrsimulator clang -target arm64-apple-xros-simulator -isysroot "$SDK" \
  -dynamiclib -fobjc-arc -O1 -I "$ROOT/bridge/abi" \
  -framework Foundation -framework Metal \
  -o "$OUT" "$HERE/fake_provider.m"
echo "[fake-provider] built $OUT"
file "$OUT"