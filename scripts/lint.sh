#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if command -v swiftformat >/dev/null 2>&1; then
  (cd client && swiftformat --lint Sources Tests)
else
  echo "swiftformat not installed; skipping Swift format lint"
fi
if command -v swiftlint >/dev/null 2>&1; then
  (cd client && swiftlint lint --quiet)
else
  echo "swiftlint not installed; skipping Swift lint"
fi
if command -v clang-format >/dev/null 2>&1; then
  find bridge -name '*.cpp' -o -name '*.hpp' | while read -r file; do
    clang-format --dry-run --Werror "$file" || exit 1
  done
else
  echo "clang-format not installed; skipping C++ format lint"
fi
./scripts/check_docs.sh
