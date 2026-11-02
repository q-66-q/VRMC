#!/bin/bash
# M6 reproducibility check: build the provider jar twice from the same source and compare sha256.
# Requires the same host toolchain/dependency caches as scripts/build_provider.sh; it does not touch
# the canonical /tmp/vrmc-current build or the device.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$(mktemp -d /tmp/vrmc-repro.XXXXXX)"
trap 'rm -rf "$BASE"' EXIT
echo "[repro] building provider twice under $BASE"
OUT_DIR="$BASE/a" PROVIDER_OUT="$BASE/a" "$ROOT/scripts/build_provider.sh" > "$BASE/a.log" 2>&1
OUT_DIR="$BASE/b" PROVIDER_OUT="$BASE/b" "$ROOT/scripts/build_provider.sh" > "$BASE/b.log" 2>&1
A=$(shasum -a 256 "$BASE/a/vrmc-provider.jar" | awk '{print $1}')
B=$(shasum -a 256 "$BASE/b/vrmc-provider.jar" | awk '{print $1}')
SA=$(stat -f%z "$BASE/a/vrmc-provider.jar")
SB=$(stat -f%z "$BASE/b/vrmc-provider.jar")
echo "[repro] build1 sha256=$A bytes=$SA"
echo "[repro] build2 sha256=$B bytes=$SB"
if [ "$A" = "$B" ] && [ "$SA" = "$SB" ]; then
  echo "[repro] RESULT: PASS (provider jar is byte-reproducible for this host toolchain)"
  echo "[repro] provider_sha256=$A provider_bytes=$SA"
  exit 0
fi
echo "[repro] RESULT: FAIL (provider jar differs between builds)" >&2
exit 1
