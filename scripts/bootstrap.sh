#!/bin/bash
# bootstrap.sh — M0 prerequisites check and local scaffolding.
# Does not download game or mod binaries. Safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "VRMC bootstrap"
echo "  root: $ROOT"
echo ""

mkdir -p "$ROOT/evidence" "$ROOT/vendor" "$ROOT/artifacts"
echo "Local directories ready: evidence/ vendor/ artifacts/ (all git-ignored)"
echo ""

if ! "$ROOT/scripts/check_versions.sh"; then
  echo ""
  echo "Environment check failed. Fix the FAIL lines above before starting a spike." >&2
  exit 1
fi

echo ""
echo "Next steps (M0):"
echo "  1. S1: reference JVM + JIT probe on the paired Vision Pro  — docs/mvp/SPIKES.md §S1"
echo "  2. S2: MC 26.2 Vulkan via MoltenVK boot probe               — docs/mvp/SPIKES.md §S2"
echo "  3. S3: Mixin injection-point evidence (decompiled 26.2-1.3.15 jar)"
echo "  4. Record each result with scripts/log_evidence.sh; never mark PASS without an EV entry."
