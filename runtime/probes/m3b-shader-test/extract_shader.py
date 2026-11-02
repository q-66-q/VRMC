#!/usr/bin/env python3
"""Extract the Metal shader source embedded in runtime/native-shell/Sources/VRMCCompositor.mm.

Used by the M3b shader unit test (runtime/probes/m3b-shader-test) so the test always compiles the
exact shader that ships in the compositor, with no duplicated copy that can drift.
"""
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]
SRC = REPO / "runtime" / "native-shell" / "Sources" / "VRMCCompositor.mm"
OUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/vrmc-testshader.metal")

source = SRC.read_text()
start = source.index("static NSString *const kShaderSource =")
lines = source[start:].split("\n")
out = []
for line in lines[1:]:
    match = re.search(r'"((?:[^"\\]|\\.)*)"', line)
    if match:
        out.append(match.group(1).encode().decode("unicode_escape"))
    if line.strip().endswith('";'):
        break
OUT.write_text("\n".join(out))
print(f"extracted {len(out)} lines -> {OUT}")
