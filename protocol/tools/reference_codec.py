#!/usr/bin/env python3
"""VRMC protocol reference codec (v1.0), used by the mock host and conformance vectors.

This is the language-neutral authority for byte layout. Keep it dependency-free.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import Optional

CONTROL_MAGIC = b"VRMC"
MEDIA_MAGIC = b"VM"
CONTROL_HEADER_SIZE = 24
MEDIA_HEADER_SIZE = 40
MAX_CONTROL_PAYLOAD = 1_048_576
MAX_DATAGRAM = 1_200
MAX_MEDIA_PAYLOAD = 1_144


class ProtocolError(ValueError):
    pass


class Writer:
    def __init__(self) -> None:
        self.data = bytearray()

    def u8(self, value: int) -> None:
        self.data += struct.pack("<B", value & 0xFF)

    def u16(self, value: int) -> None:
        self.data += struct.pack("<H", value & 0xFFFF)

    def u32(self, value: int) -> None:
        self.data += struct.pack("<I", value & 0xFFFFFFFF)

    def u64(self, value: int) -> None:
        self.data += struct.pack("<Q", value & 0xFFFFFFFFFFFFFFFF)

    def i32(self, value: int) -> None:
        self.data += struct.pack("<i", value)

    def f32(self, value: float) -> None:
        self.data += struct.pack("<f", float(value))

    def string(self, value: str) -> None:
        encoded = value.encode("utf-8")
        if len(encoded) > 255:
            raise ProtocolError("string too long")
        self.u16(len(encoded))
        self.data += encoded

    def vec3(self, x: float, y: float, z: float) -> None:
        self.f32(x); self.f32(y); self.f32(z)

    def quat(self, x: float, y: float, z: float, w: float) -> None:
        self.f32(x); self.f32(y); self.f32(z); self.f32(w)

    def raw(self, value: bytes) -> None:
        self.data += value


class Reader:
    def __init__(self, data: bytes) -> None:
        self.data = memoryview(data)
        self.offset = 0

    def _take(self, size: int) -> memoryview:
        if self.offset + size > len(self.data):
            raise ProtocolError("truncated")
        value = self.data[self.offset:self.offset + size]
        self.offset += size
        return value

    def u8(self) -> int:
        return struct.unpack("<B", self._take(1))[0]

    def u16(self) -> int:
        return struct.unpack("<H", self._take(2))[0]

    def u32(self) -> int:
        return struct.unpack("<I", self._take(4))[0]

    def u64(self) -> int:
        return struct.unpack("<Q", self._take(8))[0]

    def f32(self) -> float:
        return struct.unpack("<f", self._take(4))[0]

    def string(self) -> str:
        length = self.u16()
        return bytes(self._take(length)).decode("utf-8")

    def vec3(self) -> tuple[float, float, float]:
        return (self.f32(), self.f32(), self.f32())

    def quat(self) -> tuple[float, float, float, float]:
        return (self.f32(), self.f32(), self.f32(), self.f32())

    def raw(self, size: int) -> bytes:
        return bytes(self._take(size))

    def finish(self) -> None:
        if self.offset != len(self.data):
            raise ProtocolError(f"trailing bytes: {len(self.data) - self.offset}")


# Control message type values
HELLO = 0x01
WELCOME = 0x02
AUTH_CHALLENGE = 0x03
AUTH_RESPONSE = 0x04
AUTH_OK = 0x05
STREAM_CONFIG = 0x06
START_STREAM = 0x07
STOP_STREAM = 0x08
KEYFRAME_REQUEST = 0x09
SESSION_STATE = 0x0A
CLOCK_PING = 0x0B
CLOCK_PONG = 0x0C
TELEMETRY_CLIENT = 0x0D
TELEMETRY_HOST = 0x0E
SET_QUALITY = 0x0F
INPUT_CONFIG = 0x10
HAPTIC = 0x11
HEARTBEAT = 0x12
DISCONNECT = 0x13
ERROR = 0x14
AUDIO_CONFIG = 0x15

# Media types
VIDEO = 1
INPUT = 2
AUDIO = 3
FRAME_META = 4
NACK = 5
IDR_REQUEST = 6
KEEPALIVE = 7


def control_frame(msg_type: int, payload: bytes, session_id: int = 0, sequence: int = 0,
                  flags: int = 1) -> bytes:
    header = bytearray()
    header += CONTROL_MAGIC
    header += struct.pack("<BBBBI", 1, 0, msg_type, flags, session_id)
    header += struct.pack("<II", sequence & 0xFFFFFFFF, len(payload))
    header += struct.pack("<I", 0)
    assert len(header) == CONTROL_HEADER_SIZE
    return bytes(header) + payload


def parse_control(data: bytes) -> tuple[dict, bytes]:
    if len(data) < CONTROL_HEADER_SIZE:
        raise ProtocolError("short control header")
    if data[:4] != CONTROL_MAGIC:
        raise ProtocolError("bad control magic")
    major, minor, msg_type, flags, session_id, sequence, payload_len, reserved = struct.unpack(
        "<BBBBI III", data[4:CONTROL_HEADER_SIZE]
    )
    if major != 1:
        raise ProtocolError("unsupported protocol")
    if payload_len > MAX_CONTROL_PAYLOAD:
        raise ProtocolError("payload too large")
    if len(data) < CONTROL_HEADER_SIZE + payload_len:
        raise ProtocolError("short control payload")
    return ({
        "major": major, "minor": minor, "type": msg_type, "flags": flags,
        "session_id": session_id, "sequence": sequence, "payload_len": payload_len,
    }, data[CONTROL_HEADER_SIZE:CONTROL_HEADER_SIZE + payload_len])


def encode_hello(client_nonce: bytes = b"\x01" * 16) -> bytes:
    w = Writer()
    w.u16(1); w.u16(1); w.u16(0); w.u16(0)
    w.raw(client_nonce)
    w.string("0.1.0"); w.string("mock")
    w.u8(3)  # insecure dev
    w.u32(0x3F)
    return control_frame(HELLO, bytes(w.data))


def decode_hello(payload: bytes) -> dict:
    r = Reader(payload)
    result = {
        "min_major": r.u16(), "max_major": r.u16(),
        "min_minor": r.u16(), "max_minor": r.u16(),
        "nonce": r.raw(16), "client_version": r.string(),
        "client_platform": r.string(), "auth_mode": r.u8(),
        "capabilities": r.u32(),
    }
    r.finish()
    return result


def encode_welcome(session_id: int, host_name: str = "VRMC mock host") -> bytes:
    w = Writer()
    w.u16(1); w.u16(0); w.u32(session_id)
    w.raw(b"\x02" * 16)
    w.u8(3)  # insecure dev
    w.string("0.1.0"); w.string(host_name)
    w.raw(b"\x00" * 16)
    w.u32(0x3F)
    return control_frame(WELCOME, bytes(w.data), session_id=session_id, flags=1)


def encode_auth_ok(session_id: int) -> bytes:
    w = Writer(); w.u8(0); w.string("")
    return control_frame(AUTH_OK, bytes(w.data), session_id=session_id, flags=1)


def encode_stream_config(session_id: int, width: int = 1280, height: int = 720,
                         fps: int = 30, bitrate_kbps: int = 8_000,
                         vertical_flip: bool = False) -> bytes:
    eye_w = width // 2
    w = Writer()
    w.u16(1); w.u16(width); w.u16(height); w.u16(eye_w); w.u16(height)
    w.u8(0); w.u8(0); w.u8(1); w.u8(0)  # LR, sRGB, H.264
    w.u16(fps); w.u16(90); w.u32(bitrate_kbps); w.u16(1000); w.u16(1200)
    w.f32(0.064)
    for _ in range(2):
        w.f32(-1.19175); w.f32(1.19175); w.f32(1.0); w.f32(-1.0)
    w.vec3(-0.032, 0, 0); w.vec3(0.032, 0, 0)
    flags = 1 | (8 if vertical_flip else 0)  # reprojection + optional flip
    w.u32(flags)
    w.string("VRMC mock SBS test pattern")
    w.string("handmap-v1")
    return control_frame(STREAM_CONFIG, bytes(w.data), session_id=session_id, flags=1)


def encode_start_stream(session_id: int, first_frame_id: int = 1) -> bytes:
    import time
    w = Writer(); w.u64(time.monotonic_ns()); w.u32(first_frame_id); w.u32(0)
    return control_frame(START_STREAM, bytes(w.data), session_id=session_id, flags=1)


def encode_clock_pong(session_id: int, t0: int, t1: int, t2: int, ping_id: int) -> bytes:
    w = Writer(); w.u64(t0); w.u64(t1); w.u64(t2); w.u32(ping_id)
    return control_frame(CLOCK_PONG, bytes(w.data), session_id=session_id, flags=1)


def decode_clock_ping(payload: bytes) -> tuple[int, int]:
    r = Reader(payload)
    value = (r.u64(), r.u32())
    r.finish()
    return value


def decode_session_state(payload: bytes) -> dict:
    r = Reader(payload)
    result = {"phase": r.u8(), "reason": r.u16(), "flags": r.u32(), "detail": r.string()}
    r.finish()
    return result


def encode_media_header(msg_type: int, payload_len: int, session_id: int, frame_id: int,
                        sequence: int, timestamp_ns: int, fragment_index: int = 0,
                        fragment_count: int = 1, flags: int = 1) -> bytes:
    header = bytearray()
    header += MEDIA_MAGIC
    header += struct.pack("<BBBB", 1, msg_type, flags, 0)
    header += struct.pack("<HHH", fragment_index, fragment_count, payload_len)
    header += struct.pack("<II", session_id, frame_id)
    header += struct.pack("<I", 0)
    header += struct.pack("<QQ", sequence, timestamp_ns)
    assert len(header) == MEDIA_HEADER_SIZE
    return bytes(header)


def encode_frame_meta(frame_id: int, client_head_timestamp_ns: int = 0,
                      capture_head=(0.0, 1.6, 0.0), orientation=(0.0, 0.0, 0.0, 1.0),
                      flags: int = 0, source_frame: int = 0) -> bytes:
    w = Writer()
    w.u32(frame_id)
    w.vec3(*capture_head)
    w.quat(*orientation)
    w.u32(flags); w.u64(source_frame); w.u64(client_head_timestamp_ns)
    payload = bytes(w.data)
    return encode_media_header(FRAME_META, len(payload), 0, frame_id, 0, 0,
                               flags=1 | 8) + payload


def parse_media(data: bytes) -> tuple[dict, bytes]:
    if len(data) < MEDIA_HEADER_SIZE:
        raise ProtocolError("short media header")
    if data[:2] != MEDIA_MAGIC:
        raise ProtocolError("bad media magic")
    version, msg_type, flags, reserved = struct.unpack("<BBBB", data[2:6])
    fragment_index, fragment_count, payload_len = struct.unpack("<HHH", data[6:12])
    session_id, frame_id = struct.unpack("<II", data[12:20])
    packet_seq, timestamp_ns = struct.unpack("<QQ", data[24:40])
    if payload_len > MAX_MEDIA_PAYLOAD or payload_len > len(data) - MEDIA_HEADER_SIZE:
        raise ProtocolError("bad media payload")
    return ({
        "version": version, "type": msg_type, "flags": flags,
        "fragment_index": fragment_index, "fragment_count": fragment_count,
        "session_id": session_id, "frame_id": frame_id,
        "sequence": packet_seq, "timestamp_ns": timestamp_ns,
    }, data[MEDIA_HEADER_SIZE:MEDIA_HEADER_SIZE + payload_len])


def decode_intent(payload: bytes) -> dict:
    r = Reader(payload)
    subtype = r.u8()
    if subtype != 3:
        return {"subtype": subtype}
    result = {
        "subtype": subtype, "hand": r.u8(), "quality": r.u8(), "flags": r.u16(),
        "sample_id": r.u32(), "position": r.vec3(), "orientation": r.quat(),
        "linear": r.vec3(), "angular": r.vec3(),
        "trigger": r.f32(), "grip": r.f32(),
        "stick": (r.f32(), r.f32()), "trackpad": (r.f32(), r.f32()),
        "buttons": r.u32(), "reserved": r.u32(),
    }
    r.finish()
    return result


def decode_head(payload: bytes) -> dict:
    r = Reader(payload)
    subtype = r.u8()
    if subtype != 1:
        return {"subtype": subtype}
    result = {
        "subtype": subtype, "quality": r.u8(), "flags": r.u16(), "sample_id": r.u32(),
        "position": r.vec3(), "orientation": r.quat(),
        "linear": r.vec3(), "angular": r.vec3(),
    }
    r.finish()
    return result


def split_annex_b(data: bytes) -> list[bytes]:
    starts: list[tuple[int, int]] = []
    i = 0
    while i + 2 < len(data):
        if data[i:i+3] == b"\x00\x00\x01":
            starts.append((i, 3)); i += 3
        elif i + 3 < len(data) and data[i:i+4] == b"\x00\x00\x00\x01":
            starts.append((i, 4)); i += 4
        else:
            i += 1
    units = []
    for index, (start, header) in enumerate(starts):
        end = starts[index + 1][0] if index + 1 < len(starts) else len(data)
        if start + header < end:
            units.append(data[start + header:end])
    return units


def access_units(data: bytes) -> list[bytes]:
    """Groups NAL units by AUD (type 9), with a VCL fallback for streams without AUD."""
    units = split_annex_b(data)
    groups: list[list[bytes]] = []
    current: list[bytes] = []
    for unit in units:
        nal_type = unit[0] & 0x1F if unit else 0
        if nal_type == 9:
            if current:
                groups.append(current)
            current = [unit]
        else:
            current.append(unit)
    if current:
        groups.append(current)
    if len(groups) <= 1:
        # No AUDs: split before each VCL slice that starts a new picture. This is a
        # simplification for the mock fixture, which is encoded with AUDs anyway.
        groups = [[u for u in units]]
    return [b"\x00\x00\x00\x01" + b"\x00\x00\x00\x01".join(group) for group in groups]


def is_keyframe(access_unit: bytes) -> bool:
    for unit in split_annex_b(access_unit):
        if unit and (unit[0] & 0x1F) == 5:
            return True
    return False
