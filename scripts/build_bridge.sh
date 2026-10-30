#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:---core}"
case "$MODE" in
  --core)
    cmake -S bridge -B build/bridge-core -DCMAKE_BUILD_TYPE=Debug
    cmake --build build/bridge-core -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    ctest --test-dir build/bridge-core -C Debug --output-on-failure
    ;;
  *)
    echo "usage: $0 [--core]" >&2
    exit 2
    ;;
esac
