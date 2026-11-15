#!/bin/bash
# Host GPU check of the immersive compositor's runtime Metal shaders (no headset needed).
#
# The compositor compiles its shaders from source at runtime on the device, so a shader error would
# only surface on the headset. This extracts the exact kShaderBody string from
# runtime/native-shell/Sources/VRMCCompositor.mm, compiles it with this Mac's Metal runtime compiler,
# and renders an aliased edge through the 1.3.5 path (native-resolution FXAA pre-pass + upscale and
# sharpen) vs the old upscale paths, measuring the stair-step amplitude (edge-position std dev).
# PASS = shaders compile and the new path has a smaller stair-step than both old paths.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/vrmc-shader-check.XXXXXX")"
trap 'rm -rf "$T"' EXIT
python3 - "$ROOT/runtime/native-shell/Sources/VRMCCompositor.mm" \
  "$ROOT/scripts/tests/compositor_shader_check.mm.in" "$T/check.mm" <<'PY'
import sys
src = open(sys.argv[1]).read()
a = src.index('static NSString *const kShaderBody =')
b = src.index('";\n', a) + 3
open(sys.argv[3], 'w').write(open(sys.argv[2]).read().replace('@@SHADER@@', src[a:b]))
PY
clang++ -fobjc-arc -framework Foundation -framework Metal "$T/check.mm" -o "$T/check"
"$T/check"
