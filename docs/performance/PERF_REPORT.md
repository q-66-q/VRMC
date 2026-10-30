# Performance and Latency Report

**Status:** Simulator pipeline evidence only; hardware acceptance NOT RUN.
**Author:** Media/verification workstream.
**Build:** see `VERIFY.md` EV entries.

> This report must not be cited as proof of the 90 Hz/50 ms acceptance targets. Those require
> D1 + P1 + N1 and the MT-09 procedure. The simulator uses a 1280×720 30 fps mock stream.

## 1. Environment

| Item | Value |
| --- | --- |
| Client | visionOS 27 simulator (VRMC-VP) on macOS 27.0.1, Xcode 27.1 |
| Host | Python mock host on the same Mac (localhost) |
| Video | H.264 Constrained Baseline, 1280×720 SBS, 30 fps, ~8 Mbps target |
| Input | Synthetic hands @ ~90 Hz, synthetic head |
| Device | None (simulator) |
| Network | Loopback (not representative of Wi-Fi) |

## 2. Functional pipeline result

- Client connected to mock host via TCP control, received WELCOME/AUTH_OK/STREAM_CONFIG/
  START_STREAM (insecure development mode).
- Decoded H.264 frames into Metal textures; CompositorServices presented a full-screen stereo
  view at the simulator's frame cadence.
- Synthetic INTENT packets arrived at the mock host; pinch/fist/locomotion/menu states were
  visible in logs.
- A screenshot of the immersive test pattern was captured (`artifacts/demo/simulator.png` when
  running `scripts/demo_simulator.sh`).

## 3. Measurements (simulator, indicative only)

| Metric | Observed | Notes |
| --- | --- | --- |
| Mock stream fps | 30 | Config; not a device capability |
| Client frames decoded | ~150/150 in a run | No drops in the final local run after mock IDR handling |
| Client reported "latency p50" | ~2–5 ms | Loopback + host/client clock domains; **not M2P** |
| Decode + render | Not separately instrumented yet | AT-TELEM work in progress |
| GPU/CPU | Not measured | Simulator Metal is not Vision Pro |
| Thermal | N/A | Simulator |

The UI "latency p50" is a network/queue estimate derived from host frame timestamps and the
clock estimate; it is not motion-to-photon and must not be used for AC-4.

## 4. Required hardware measurements (pending)

Run MT-09/MT-10 on D1/P1/N1 and fill:

| Stage | p50 | p95 | p99 | Budget | Result |
| --- | --- | --- | --- | --- | --- |
| Game render + DUAL mirror | | | | 11.1 ms | NOT RUN |
| WGC capture/copy | | | | ≤6 ms | NOT RUN |
| NVENC submit→output | | | | ≤15 ms p95 | NOT RUN |
| Network one-way | | | | ≤8/20/40 ms | NOT RUN |
| Decode | | | | ≤8 ms | NOT RUN |
| Compositor/scan-out | | | | 11.1 ms | NOT RUN |
| View M2P (instrumented) | | | | P50 ≤50, P95 ≤70 ms | NOT RUN |
| View M2P (240 fps camera) | | | | same | NOT RUN |
| Action-to-feedback | | | | P50 ≤150, P95 ≤250 ms | NOT RUN |
| Dropped video frames | | | | ≤1% N1 | NOT RUN |
| Bitrate | | | | 70–100 Mbps | NOT RUN |
| Encode GPU | | | | ≤15% RTX 4070 | NOT RUN |
| Client GPU | | | | ≤70% frame | NOT RUN |

## 5. Optimization backlog (ordered by expected impact)

1. Measure and, if needed, replace WGC copy/format conversion with GPU NV12 shader.
2. Tune NVENC (preset/tuning/slices/rate control) and verify Annex-B/IDR behavior.
3. Reduce client decode→Metal copies (CVPixelBuffer/IOSurface direct).
4. Validate reprojection quality/latency with a 240 fps camera; add depth only if justified.
5. ABR policy: bitrate first, then resolution/fps; keep input unaffected.
6. Thermal policy for 30+ minute sessions; target 72 fps fallback.

## 6. Raw data

Add links to telemetry CSV, analysis output, and camera video here when MT-09 runs. The
analysis script is planned at `tools/diagnostics/latency_report.py`; do not hand-edit numbers
without raw files.
