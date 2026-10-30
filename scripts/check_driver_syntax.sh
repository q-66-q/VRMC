#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OPENVR_DIR="${OPENVR_DIR:-build/openvr}"
if [[ ! -f "$OPENVR_DIR/headers/openvr_driver.h" ]]; then
  mkdir -p "$(dirname "$OPENVR_DIR")"
  git clone --depth 1 --branch v2.15.6 https://github.com/ValveSoftware/openvr.git "$OPENVR_DIR"
fi
clang++ -std=c++20 -fsyntax-only \
  -I"$OPENVR_DIR/headers" -Ibridge/core/include \
  bridge/driver/src/driver.cpp
echo "driver source syntax OK (OpenVR v2.15.6; not a Windows/SteamVR runtime test)"
