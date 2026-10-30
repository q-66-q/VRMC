#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ID="${1:---help}"
NOTE="${2:-}"
if [[ "$ID" == "--help" || -z "$NOTE" ]]; then
  echo "usage: $0 EV-0001 'what was tested'" >&2
  exit 2
fi
DIR="evidence/$ID"
mkdir -p "$DIR"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo none)"
DIRTY="no"
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then DIRTY="yes"; fi
cat > "$DIR/manifest.json" <<EOF
{
  "id": "$ID",
  "date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "commit": "$COMMIT",
  "dirty": "$DIRTY",
  "host": "$(hostname)",
  "note": "$NOTE"
}
EOF
echo "Evidence manifest: $DIR/manifest.json"
echo "Attach logs/screenshots under $DIR (do not include secrets or raw hand data)."
