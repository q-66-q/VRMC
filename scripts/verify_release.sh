#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="${1:---help}"
[[ "$VERSION" == "--help" ]] && { echo "usage: $0 1.0.0" >&2; exit 2; }
OUT="artifacts/$VERSION"
[[ -d "$OUT" ]] || { echo "missing $OUT; run package_release.sh" >&2; exit 1; }
(cd "$OUT" && shasum -a 256 -c SHA256SUMS)
if grep -q "BLOCKED" VERIFY.md; then
  echo "RELEASE BLOCKED: VERIFY.md still has BLOCKED acceptance items." >&2
  grep -n "BLOCKED" VERIFY.md | head -20 >&2
  exit 1
fi
if grep -q "NOT RUN" VERIFY.md; then
  echo "RELEASE BLOCKED: VERIFY.md still has NOT RUN items." >&2
  exit 1
fi
echo "Release verification passed for $VERSION"
