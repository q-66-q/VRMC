# Streaming, Timing, and Transport Specification

**Status:** Design baseline (M0/M1).
**Related:** ADR-0002, ADR-0004, ADR-0005, `protocol/PROTOCOL.md`.

This document describes the media pipeline end to end. The wire format is in
`protocol/PROTOCOL.md`; this file explains why each stage exists and how it is measured.

---

## 1. Pipeline overview

```text
Vivecraft DUAL mirror (3840×1080, 90 Hz)
  │  Windows Graphics Capture (window client area)
  ▼
D3D11 texture (BGRA8) ──copy/convert──▶ NV12 (GPU)
  │
  ▼
NVENC HEVC (low-latency, CBR, no B-frames, IDR 1 s)
  │  access unit (Annex-B)
  ▼
fragmenter (≤1144 B payload) ──▶ UDP 48626 (AEAD)
  │
  ▼  Wi‑Fi 6E / LAN
client reassembly (jitter buffer) ──▶ VideoToolbox decode
  │
  ▼
CVPixelBuffer → CVMetalTextureCache → Metal eye textures
  │
  ▼
CompositorServices drawable + rotation-only reprojection ──▶ Vision Pro display

Hand/head ARKit (client, 90 Hz) ──▶ filter/predict ──▶ INTENT + skeleton (UDP 48627)
  ──▶ host clock map ──▶ prediction ──▶ shared memory ──▶ driver_vrmc ──▶ SteamVR
```

The PC is authoritative for simulation and frame production. The client is authoritative for
hand intent, head pose, and final presentation.

---

## 2. Capture

- **Source:** Vivecraft `MirrorMode.DUAL` in the game's main window. Left eye left half, right
  eye right half. `dualMirrorCrop = 0`, `dualMirrorSwap = false` (validated; can be flipped
  only if the config says so).
- **Window:** borderless, 3840×1080 client area, 90 Hz display mode, no DPI scaling. The host
  validates the client area after launch and rejects if it differs from `StreamConfig`.
- **API:** Windows Graphics Capture (`Windows.Graphics.Capture`) with a free-threaded frame
  pool of 3; copy the latest frame and release immediately. Do not block the game/render
  threads. Capture only the window, not the monitor, to avoid notifications/overlays.
- **Format:** BGRA8 → NV12 on GPU (video processor MFT or compute shader). Color: sRGB
  transfer; no HDR in v1. Record the actual color space; the client must not double-convert.
- **Frame identity:** host capture counter and `QueryPerformanceCounter` timestamp captured as
  close to `Present` as possible. `FRAME_META` carries the head pose used by Vivecraft for
  that frame (from the latest driver snapshot); if unavailable, mark `meta-missing`.
- **Window loss/resize:** stop sending new frames, keep the last for 500 ms, send
  `SESSION_STATE(degraded, capture_unavailable)`, retry discovery every 500 ms.
- **Capture failure modes:** exclusive fullscreen, minimized window, protected content, GPU
  device loss. The host logs a typed reason and surfaces it; never silently stream black.

**Measurement:** capture timestamp at frame arrival; encode submit timestamp; capture latency =
submit − arrival; p50/p95 per 10 s. Verify frame integrity with a known asymmetric test
pattern (left bar red, right bar blue) and a moving counter in both halves.

---

## 3. Encoding

Baseline: NVIDIA NVENC HEVC Main, 8-bit, 4:2:0, 3840×1080, 90 fps, ~90 Mbps CBR, IDR every
1 s, infinite GOP with forced IDR on request, no B-frames, no lookahead, zero reorder delay,
low-latency tune, slice/tile settings for packet loss resilience if supported.

Fallback: H.264 high profile, ~60 Mbps, same low-latency settings. H.264 is the compatibility
codec when HEVC decode fails.

Encoder rules:

- Never queue more than 2 frames; drop oldest and request IDR if the GPU is behind.
- On encoder error, recreate once; request IDR; if it fails again, degrade codec/resolution.
- Include VPS/SPS/PPS before every IDR and as `config` flags on the first fragments.
- Output Annex-B with 4-byte start codes. The fragmenter must not split a NAL header across
  packets? It may split anywhere, but the first fragment should include the start code so the
  decoder can identify the access unit. The client reassembles the whole access unit before
  decoding.
- Bitrate adapts to NACK/loss/RTT via `SET_QUALITY` and host ABR; never change resolution
  without a new `STREAM_CONFIG` and client acknowledgement.

**Measurement:** NVENC submit→output p50/p95; GPU utilization; bitrate; frame size; IDR rate.
Budget: p95 ≤15 ms at 90 Hz.

---

## 4. Fragmentation and reliability

- Max datagram 1200 bytes; header 40; AEAD tag 16; payload ≤1144.
- Fragment each access unit into `ceil(size/1144)` fragments, max 1024. Frame max 8 MiB.
- `FRAME_META` is sent twice before the fragments; video fragments follow in order. Packet
  sequence increases per datagram; frame ID per access unit.
- Client buffers per frame. On incomplete after 50 ms, NACK missing fragments once; after
  150 ms, drop and request IDR. Keep at most 4 incomplete frames / 8 MiB.
- Host NACK retransmits from a 250 ms / 8-frame ring; if unavailable, force IDR. Retransmits
  have `retransmit` flag and do not change frame IDs.
- Duplicates are ignored. A frame with a gap or missing keyframe triggers decoder reset + IDR.
- Jitter buffer target = 1 frame; max 3. Under pressure, drop oldest undecoded frames, never
  the newest complete one. Decode and render are decoupled: the renderer always uses the newest
  decoded frame.

**Measurement:** packets sent/lost, NACKs, IDR requests, incomplete frame drops, reassembly
latency, jitter buffer depth. Budget: ≤1% dropped video frames on N1; recovery ≤500 ms.

---

## 5. Clock synchronisation

- Use monotonic clocks on both sides. Convert `mach_continuous_time`/`clock_gettime_nsec_np`
  and `QueryPerformanceCounter` to ns.
- Four-timestamp exchange on the control channel every 1 s:
  `t0` client send, `t1` host receive, `t2` host send, `t3` client receive.
  `offset = ((t1−t0)+(t2−t3))/2` (host − client), `rtt = (t3−t0)−(t2−t1)`.
- Keep a 64-sample ring; use median offset and a robust linear fit for drift. Reject samples
  with RTT > 4× median or offset jumps > 20 ms; re-sync after reconnection.
- Report offset, RTT, uncertainty, sample count. Prediction/reprojection use the best estimate
  and clamp; on uncertainty >15 ms, reduce prediction and flag degraded.
- Frame timestamps are host-clock; hand/head timestamps are client-clock. Convert at the
  boundary, retain raw values in telemetry for audit.

**Measurement:** S-11 soak on N1/N2/N4; offset error vs a wired reference if available;
uncertainty; drift over 30 min. Budget: |offset error| ≤2 ms on N1, ≤5 ms on N2.

---

## 6. Prediction and late latching

- **Client hand/head:** one-euro filter; velocity estimated over ≥2 samples; predict to
  `hostDriverTime + uplinkEstimate` with a constant-velocity/angular-velocity model. Clamp
  horizon to 50 ms; scale by confidence; decay to zero on loss.
- **Host:** map client timestamp to host time; reject stale (>250 ms) samples; apply the newest
  INTENT; driver extrapolates pose by ≤30 ms to its update time; buttons are latched for at
  least one driver frame.
- **Client render:** decode frame N; at present time, take the newest decoded frame and its
  capture head pose; reproject rotation from capture to predicted present head pose; present
  per-eye. Do not wait for a newer frame if it would miss the compositor deadline.
- **Gestures:** evaluated on sensor samples; press/release timestamped; never re-evaluated on
  arrival at the host. A press that occurred before a frame is valid for that frame's action.
- **Frame metadata loss:** use last capture pose; mark `meta_missing`; reprojection still
  occurs with a bounded error, and the issue is visible in telemetry.

**Measurement:** replay recorded poses against ground truth (prediction error ≤2 cm/3° at
50 ms), and camera M2P. Budget: view M2P p50 ≤50 ms, p95 ≤70 ms.

---

## 7. Rendering and reprojection

- CompositorServices `LayerRenderer` with dedicated layout, color `rgba16Float`, depth optional
  for UI (video is full-screen). Foveation disabled initially.
- For each eye: sample the eye half of the SBS texture. Map screen NDC → present eye ray via
  inverse present projection → rotate by `qDelta = qPresentHead * qCaptureHead⁻¹` → capture
  projection → UV. Clamp UV to the eye rect; never sample across halves.
- `qCaptureHead` comes from `FRAME_META`; `qPresentHead` from the ARKit/world anchor at
  present time (or the drawable view transform). If either is invalid, use identity delta.
- Translation is not reprojected in v1 (ADR-0005). Show a diagnostic when head translation
  since capture exceeds 0.15 m; this is a known limitation.
- Color: decode to a color-managed texture; convert sRGB→linear for `rgba16Float` if needed;
  test with a gradient and skin tones. Avoid double gamma.
- Eye order/flip: config + runtime validation; an asymmetric test pattern must show left/right
  correctly on device. No vertical flip.
- UI overlays (status, latency, tracking) are rendered in-headset as a separate Metal pass or
  SwiftUI attachment; they must not be captured back into the stream.

**Measurement:** frame time p50/p95, GPU utilization, dropped presents, reprojection delta
angle, visual test patterns. Budget: 11.1 ms at 90 Hz.

---

## 8. Audio (v1.1, not acceptance-blocking)

- WASAPI loopback capture on the PC; Opus 48 kHz stereo, 10 ms frames, ~128 kbps; timestamps
  aligned to video capture; UDP type 3 with its own sequence and jitter buffer.
- Client: AudioToolbox/AVAudioEngine decode and render; target ≤80 ms audio latency; mute on
  link loss. Do not let audio block video or input.
- If implemented before v1.1, it must pass sync tests (clap/visual marker) and not violate
  bandwidth/latency budgets.

---

## 9. Failure handling summary

| Failure | Detection | Action | Recovery |
| --- | --- | --- | --- |
| Capture window lost | WGC event/validation | Stop new frames, hold 500 ms, state degraded | Rediscover every 500 ms |
| Encoder stall | queue depth/time | Drop oldest, recreate, IDR | Resume; if repeated, degrade codec |
| Packet loss | gap/NACK | NACK once, hold last frame, IDR after 150 ms | Resume on complete keyframe |
| Media silence >250 ms | host/client timer | Freeze last frame, release input, overlay | Handshake/reconnect, IDR |
| Clock sync lost | no pong 3× | Continue with last offset, flag degraded | Re-sync, rate-limited |
| Decoder error | VideoToolbox error | Reset decoder, request IDR | Resume |
| Hand tracking lost | ARKit state/stale | Release all, ghost, mark invalid | 3 good samples |
| SteamVR restart | driver/IPC health | Release inputs, invalid poses | Re-register/restart profile |
| Host crash | socket/control loss | Overlay, retry backoff | Restart host, re-handshake |

All state transitions are timestamped and counted in telemetry. No failure may leave a button,
stick, or trigger asserted.

---

## 10. Budgets and measurement plan

See `VERIFY.md` §5 for the authoritative table. Instrumentation:

- **Client:** `FramePipeline` records sample, send, receive, decode start/end, present; ring
  buffers for p50/p95; CSV export with session metadata; UI overlay with fps/latency/queue.
- **Host:** capture/encode timestamps, queue depth, bitrate, packets/NACKs, driver update age;
  JSONL log with redacted session ID.
- **Camera:** 240 fps video of the Vision Pro display and a physical hand/marker; use a
  full-screen flash or a moving edge triggered by a known gesture; count frames. Instrumented
  telemetry alone is `PARTIAL` for M2P.
- **Analysis:** `tools/diagnostics/latency_report.py` computes percentiles and stage budgets
  from the CSV; results go into `docs/performance/PERF_REPORT.md` and `VERIFY.md` MT-09.

Baseline assumptions (must be measured): game/mirror 11.1 ms, capture 2–6 ms, encode 4–8 ms,
network 2–10 ms, decode 3–8 ms, compositor 11.1 ms. A stage exceeding its budget is optimized
before adding features; if the total target is missed, document the limitation and a mitigation
or waiver per AC-4.6.

---

## 11. Quality and degradation policy

- Start at configured resolution/bitrate; monitor decode/render/encode time and NACK rate.
- If p95 frame time > 90% budget for 2 s: reduce bitrate 20%; if still bad, reduce render
  scale or fps (with user-visible notification); never drop input.
- If tracking quality degrades: reduce prediction, show ghost hands, keep session.
- If thermal pressure: cap fps at 72, reduce resolution one step, notify; restore when cool.
- Degradation is observable (HUD), reversible, and logged with the reason. No silent quality
  switches.

---

## 12. Security and privacy of media

- Media/input are AEAD-encrypted in production; no plaintext fallback in release builds.
- Keys are per-session, derived after pairing; no keys or raw frames in logs.
- Telemetry contains counts/timings, not pixels/joints. Diagnostics require explicit user
  action and are redacted.
- The host binds to the selected interface; discovery can be disabled. Pairing is rate-limited.
- A compromised host can display arbitrary video and inject input; pair only with a trusted PC.
  The client shows the host name and requires explicit confirmation on first connect.
