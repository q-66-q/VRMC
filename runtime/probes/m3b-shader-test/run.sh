#!/bin/bash
# M3b compositor reprojection shader unit test (macOS Metal).
# Validates that the exact VRMCCompositor.mm shader compiles on Metal, that the fragment uniforms
# (invProjection / viewToDevice / sourceTangents / misc) match the CPU-side math, and that the
# reprojection/conversion branches produce the expected pixels for the EV-0086 device frustum.
# Evidence: EV-0087 (code/build/static validation - NOT device evidence).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT=${OUT:-/tmp/vrmc-shader-test}
mkdir -p "$OUT"
python3 "$ROOT/runtime/probes/m3b-shader-test/extract_shader.py" "$OUT/shadercopy.metal"
# The harness reads the shader from this fixed path; keep it stable.
cp "$OUT/shadercopy.metal" /tmp/vrmc-testshader.metal
clang++ -fobjc-arc -O1 -std=c++17 -o "$OUT/shadertest" \
  "$ROOT/runtime/probes/m3b-shader-test/main.mm" -framework Metal -framework Foundation
"$OUT/shadertest"
