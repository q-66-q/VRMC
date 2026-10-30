#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="${1:---help}"
if [[ "$VERSION" == "--help" ]]; then echo "usage: $0 1.0.0" >&2; exit 2; fi
OUT="artifacts/$VERSION"
mkdir -p "$OUT"
./scripts/test_all.sh
./scripts/build_client.sh --device >/dev/null || echo "WARNING: device build failed (signing/toolchain)"
cp THIRD_PARTY_NOTICES.md LICENSE "$OUT/"
if [[ -d build/client/Build/Products/Release-xros/VRMC.app ]]; then
  ditto -c -k --keepParent build/client/Build/Products/Release-xros/VRMC.app "$OUT/VRMC-$VERSION-xros.zip"
fi
if [[ -d build/bridge-windows/bin/win64 ]]; then
  (cd build/bridge-windows/bin/win64 && zip -r "$ROOT/$OUT/VRMC-$VERSION-win64.zip" .)
fi
(cd "$OUT" && shasum -a 256 * > SHA256SUMS)
echo "Release artifacts: $OUT"
echo "Complete VERIFY.md §10 before tagging this as a release."
