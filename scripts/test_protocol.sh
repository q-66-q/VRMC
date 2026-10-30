#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import hashlib, sys
from pathlib import Path
sys.path.insert(0, str(Path('protocol/tools')))
import reference_codec as rc

manifest = __import__('json').loads(Path('protocol/vectors/manifest.json').read_text())
for name, entry in manifest.items():
    data = Path('protocol/vectors', name).read_bytes()
    assert len(data) == entry['size'], name
    assert hashlib.sha256(data).hexdigest() == entry['sha256'], name

header, payload = rc.parse_control((Path('protocol/vectors/hello.bin')).read_bytes())
hello = rc.decode_hello(payload)
assert header['type'] == rc.HELLO and hello['auth_mode'] == 3

header, payload = rc.parse_control((Path('protocol/vectors/welcome.bin')).read_bytes())
assert header['type'] == rc.WELCOME

header, payload = rc.parse_control((Path('protocol/vectors/stream_config.bin')).read_bytes())
assert header['type'] == rc.STREAM_CONFIG
reader = rc.Reader(payload)
assert reader.u16() == 1
assert reader.u16() == 1280 and reader.u16() == 720

header, payload = rc.parse_media((Path('protocol/vectors/frame_meta.bin')).read_bytes())
assert header['type'] == rc.FRAME_META
reader = rc.Reader(payload)
assert reader.u32() == 42
reader.vec3()
reader.quat()
assert reader.u32() == 1
assert reader.u64() == 9
assert reader.u64() == 777

header, _ = rc.parse_media((Path('protocol/vectors/video_fragment.bin')).read_bytes())
assert header['type'] == rc.VIDEO and (header['flags'] & 1)

header, payload = rc.parse_media((Path('protocol/vectors/intent.bin')).read_bytes())
intent = rc.decode_intent(payload)
assert intent['hand'] == 1 and abs(intent['trigger'] - 0.75) < 1e-6
print('protocol vectors verified')
PY
echo "Protocol conformance vectors OK"
