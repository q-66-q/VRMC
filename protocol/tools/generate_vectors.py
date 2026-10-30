#!/usr/bin/env python3
"""Generate and verify VRMC protocol conformance vectors.

The Python reference codec is authoritative. Swift and C++ tests consume these files
(and must re-encode them byte-for-byte).
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "protocol" / "tools"))
import reference_codec as rc  # noqa: E402

VECTOR_DIR = ROOT / "protocol" / "vectors"


def encode_hello() -> bytes:
    return rc.encode_hello(b"\x01" * 16)


def encode_welcome() -> bytes:
    return rc.encode_welcome(0x1234, "conformance-host")


def encode_config() -> bytes:
    return rc.encode_stream_config(0x1234, 1280, 720, fps=30, bitrate_kbps=8000)


def encode_meta() -> bytes:
    return rc.encode_frame_meta(
        42, client_head_timestamp_ns=777,
        capture_head=(0.1, 1.6, -0.2), orientation=(0, 0, 0, 1),
        flags=1, source_frame=9,
    )


def encode_intent() -> bytes:
    w = rc.Writer()
    w.u8(3)
    w.u8(1)
    w.u8(2)
    w.u16(0)
    w.u32(77)
    w.vec3(0.1, 1.2, -0.3)
    w.quat(0, 0, 0, 1)
    w.vec3(0.0, 0.0, 0.0)
    w.vec3(0.0, 0.0, 0.0)
    w.f32(0.75); w.f32(0.25)
    w.f32(0.5); w.f32(-0.25); w.f32(0.0); w.f32(0.0)
    w.u32(0x205); w.u32(0)
    payload = bytes(w.data)
    return rc.encode_media_header(
        rc.INPUT, len(payload), 0x1234, 0, 7, 999, 0, 1, 16
    ) + payload


def encode_video() -> bytes:
    payload = b"\x00\x00\x00\x01\x09\xf0" + b"VRMC-test-frame" * 8
    return rc.encode_media_header(
        rc.VIDEO, len(payload), 0x1234, 42, 7, 999, 0, 1, 16 | 1
    ) + payload


VECTORS = {
    "hello.bin": encode_hello,
    "welcome.bin": encode_welcome,
    "stream_config.bin": encode_config,
    "frame_meta.bin": encode_meta,
    "intent.bin": encode_intent,
    "video_fragment.bin": encode_video,
}


def main() -> int:
    VECTOR_DIR.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for name, encoder in VECTORS.items():
        data = encoder()
        (VECTOR_DIR / name).write_bytes(data)
        manifest[name] = {
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "hex": data.hex(),
        }
        print(f"{name}: {len(data)} bytes {hashlib.sha256(data).hexdigest()[:16]}")
    (VECTOR_DIR / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
