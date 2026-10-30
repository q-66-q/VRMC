#!/usr/bin/env python3
"""VRMC mock host for simulator/M1 end-to-end testing.

It speaks the insecure development variant of protocol v1, serves a generated H.264 SBS
test pattern over UDP, answers clock pings, and logs the controller intents it receives.
It is not the real Vivecraft bridge and is never evidence for device/latency acceptance.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import socket
import struct
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "protocol" / "tools"))
import reference_codec as rc  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "stereo_test.h264"
LOG_LOCK = threading.Lock()


def log(message: str) -> None:
    print(f"[mock-host] {message}", flush=True)


def now_ns() -> int:
    return time.monotonic_ns()


class MockHost:
    def __init__(self, host: str, control_port: int, media_port: int, input_port: int,
                 fps: int, log_file: Path | None) -> None:
        self.host = host
        self.control_port = control_port
        self.media_port = media_port
        self.input_port = input_port
        self.fps = fps
        self.log_file = log_file
        self.session_id = random.getrandbits(32) or 1
        self.client_udp: tuple[str, int] | None = None
        self.client_udp_lock = threading.Lock()
        self.control_conn: socket.socket | None = None
        self.control_lock = threading.Lock()
        self.control_sequence = 1
        self.media_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.media_socket.bind((host, media_port))
        self.input_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.input_socket.bind((host, input_port))
        self.sequence = 0
        self.frame_id = 1
        self.meta_sequence = 1
        self.last_fragments: dict[int, list[bytes]] = {}
        self.units = rc.access_units(FIXTURE.read_bytes())
        self.force_idr = False
        log(f"loaded {len(self.units)} access units from {FIXTURE.name}")
        self.stop = threading.Event()

    def run(self) -> None:
        self._start_udp()
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((self.host, self.control_port))
        server.listen(1)
        log(f"control listening on {self.host}:{self.control_port}; UDP input {self.input_port}; media {self.media_port}")
        try:
            while not self.stop.is_set():
                conn, address = server.accept()
                log(f"client connected from {address[0]}:{address[1]}")
                self.control_conn = conn
                self.client_udp = None
                try:
                    self._handle_control(conn)
                except Exception as exc:  # noqa: BLE001
                    log(f"control session ended: {exc}")
                finally:
                    with self.control_lock:
                        self.control_conn = None
                    try:
                        conn.close()
                    except OSError:
                        pass
        finally:
            server.close()
            self.stop.set()
            self.media_socket.close()
            self.input_socket.close()

    def _start_udp(self) -> None:
        threading.Thread(target=self._input_loop, daemon=True).start()
        threading.Thread(target=self._video_loop, daemon=True).start()

    def _send_control(self, data: bytes) -> None:
        with self.control_lock:
            conn = self.control_conn
            if conn is None:
                return
            conn.sendall(data)

    def _handle_control(self, conn: socket.socket) -> None:
        buffer = bytearray()
        while not self.stop.is_set():
            chunk = conn.recv(65536)
            if not chunk:
                return
            buffer += chunk
            while len(buffer) >= rc.CONTROL_HEADER_SIZE:
                try:
                    header, payload = rc.parse_control(bytes(buffer))
                except Exception:
                    break
                total = rc.CONTROL_HEADER_SIZE + header["payload_len"]
                if len(buffer) < total:
                    break
                del buffer[:total]
                self._on_control(header, payload)

    def _on_control(self, header: dict, payload: bytes) -> None:
        msg_type = header["type"]
        if msg_type == rc.HELLO:
            hello = rc.decode_hello(payload)
            log(f"HELLO from {hello['client_platform']} version {hello['client_version']} auth={hello['auth_mode']}")
            self._send_control(rc.encode_welcome(self.session_id))
            self._send_control(rc.encode_auth_ok(self.session_id))
            self._send_control(rc.encode_stream_config(self.session_id, fps=self.fps))
            self._send_control(rc.encode_start_stream(self.session_id, self.frame_id))
            log("sent WELCOME/AUTH_OK/STREAM_CONFIG/START_STREAM (insecure dev)")
        elif msg_type == rc.CLOCK_PING:
            t0, ping_id = rc.decode_clock_ping(payload)
            t1 = now_ns()
            t2 = now_ns()
            self._send_control(rc.encode_clock_pong(self.session_id, t0, t1, t2, ping_id))
        elif msg_type == rc.SESSION_STATE:
            state = rc.decode_session_state(payload)
            log(f"SESSION_STATE phase={state['phase']} reason={state['reason']} detail={state['detail']!r}")
        elif msg_type == rc.KEYFRAME_REQUEST:
            log("KEYFRAME_REQUEST (mock will keyframe at next IDR)")
        elif msg_type == rc.DISCONNECT:
            log("client disconnected")
            self.stop.set()
        else:
            log(f"control type 0x{msg_type:02x} payload={len(payload)}")

    def _input_loop(self) -> None:
        count = 0
        while not self.stop.is_set():
            try:
                data, address = self.input_socket.recvfrom(65535)
            except OSError:
                return
            with self.client_udp_lock:
                if self.client_udp != address:
                    self.client_udp = address
                    log(f"client UDP port learned: {address[0]}:{address[1]}")
            try:
                header, payload = rc.parse_media(data)
            except Exception:  # noqa: BLE001
                continue
            if header["type"] == rc.INPUT:
                subtype = payload[0]
                if subtype == 3:
                    intent = rc.decode_intent(payload)
                    count += 1
                    if count <= 5 or count % 90 == 0:
                        log(
                            f"INTENT hand={intent['hand']} trigger={intent['trigger']:.2f} "
                            f"grip={intent['grip']:.2f} stick=({intent['stick'][0]:.2f},{intent['stick'][1]:.2f}) "
                            f"buttons=0x{intent['buttons']:03x} quality={intent['quality']}"
                        )
                    if self.log_file is not None:
                        with LOG_LOCK:
                            with self.log_file.open("a", encoding="utf-8") as handle:
                                handle.write(json.dumps(intent) + "\n")
                elif subtype == 1 and count % 180 == 0:
                    head = rc.decode_head(payload)
                    log(f"HEAD quality={head['quality']} pos={head['position']}")
            elif header["type"] == rc.KEEPALIVE:
                pass
            elif header["type"] == rc.NACK:
                log(f"NACK {len(payload)} bytes; retransmit is not required on localhost")
            elif header["type"] == rc.IDR_REQUEST:
                self.force_idr = True
                log("IDR_REQUEST received; forcing keyframe")

    def _video_loop(self) -> None:
        interval = 1.0 / max(self.fps, 1)
        last = 0.0
        index = 0
        while not self.stop.is_set():
            with self.client_udp_lock:
                client = self.client_udp
            if client is None:
                time.sleep(0.05)
                continue
            now = time.monotonic()
            if now - last < interval:
                time.sleep(min(interval - (now - last), 0.02))
                continue
            last = now
            if self.force_idr:
                for offset in range(len(self.units)):
                    candidate = self.units[(index + offset) % len(self.units)]
                    if rc.is_keyframe(candidate):
                        index += offset
                        break
                self.force_idr = False
            access_unit = self.units[index % len(self.units)]
            index += 1
            keyframe = rc.is_keyframe(access_unit)
            frame_id = self.frame_id
            self.frame_id += 1
            timestamp = now_ns()
            meta = rc.encode_frame_meta(frame_id)
            # meta uses session 0; that is accepted by the client as a wildcard. Use the
            # session for stricter hosts by patching the two bytes is unnecessary here.
            self.media_socket.sendto(meta, client)
            self.media_socket.sendto(meta, client)
            fragments = [access_unit[i:i + rc.MAX_MEDIA_PAYLOAD]
                         for i in range(0, len(access_unit), rc.MAX_MEDIA_PAYLOAD)]
            self.last_fragments[frame_id] = fragments
            if len(self.last_fragments) > 8:
                self.last_fragments.pop(min(self.last_fragments), None)
            flags = 16 | (1 if keyframe else 0) | (2 if index == 1 else 0)
            for frag_index, fragment in enumerate(fragments):
                header = rc.encode_media_header(
                    rc.VIDEO, len(fragment), self.session_id, frame_id, self.sequence,
                    timestamp, frag_index, len(fragments), flags
                )
                self.sequence += 1
                self.media_socket.sendto(header + fragment, client)
            if index % self.fps == 0:
                log(f"sent frame {frame_id} key={keyframe} fragments={len(fragments)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--control-port", type=int, default=48625)
    parser.add_argument("--media-port", type=int, default=48626)
    parser.add_argument("--input-port", type=int, default=48627)
    parser.add_argument("--log-file", type=Path, default=None)
    args = parser.parse_args()
    if not FIXTURE.exists():
        log(f"missing fixture {FIXTURE}; run tools/mock_host/generate_fixture.sh")
        return 2
    host = MockHost(args.host, args.control_port, args.media_port, args.input_port, args.fps, args.log_file)
    try:
        host.run()
    except KeyboardInterrupt:
        host.stop.set()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
