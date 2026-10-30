#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== Swift tests =="
(cd client && swift test)

echo "== Bridge core tests =="
./scripts/build_bridge.sh --core

echo "== Protocol vectors =="
./scripts/test_protocol.sh

echo "== Docs checks =="
./scripts/check_docs.sh

echo "ALL LOCAL TESTS PASSED"
