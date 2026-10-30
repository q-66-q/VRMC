# Tools

- `mock_host/mock_host.py` — dependency-free protocol-v1 mock host: serves a generated H.264
  SBS test pattern, answers clock pings, logs controller INTENT packets. Used by the simulator
  E2E demo. Not a Vivecraft bridge and not acceptance evidence.
- `mock_host/fixtures/stereo_test.h264` — generated test pattern (our content; no game assets).
- `diagnostics/latency_report.py` — compute stage percentiles from telemetry CSV.

Generate the fixture if missing:

```bash
ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'testsrc2=size=640x720:rate=30:duration=4' \
  -f lavfi -i 'testsrc2=size=640x720:rate=30:duration=4' \
  -filter_complex '[1:v]hue=h=120[r];[0:v][r]hstack=inputs=2' \
  -t 4 -c:v libx264 -preset ultrafast -tune zerolatency -g 30 \
  -x264-params aud=1 -pix_fmt yuv420p -f h264 tools/mock_host/fixtures/stereo_test.h264 -y
```
