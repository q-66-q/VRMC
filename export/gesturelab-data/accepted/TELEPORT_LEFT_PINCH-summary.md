# Accepted datasets: TELEPORT_LEFT_PINCH (2 samples)

- Files:
  - `gesturelab-TELEPORT_LEFT_PINCH-20261102-175641.jsonl` — 31.09 s, 551 samples, left tracked 484.
  - `gesturelab-TELEPORT_LEFT_PINCH-20261102-175731.jsonl` — 38.97 s, 703 samples, left tracked 629.
- Both have the correct label (no relabel needed).
- Left pinch distance:
  - sample 1: min/p05/p25/p50/p95 = 0.004/0.006/0.009/0.061/0.166 m; 214 frames <0.030; 8 events.
  - sample 2: min/p05/p25/p50/p95 = 0.002/0.006/0.010/0.017/0.156 m; 336 frames <0.030; 8 events.
- Combined 16 left-pinch events at 0.030 on / 0.045 off. Hold durations vary from quick taps
  (0.05/0.44–0.56 s) to aimed holds (1.5–4.56 s).
- Verdict: valid teleport-aim data. Starting behaviour: left pinch press starts aim; release commits;
  open hand/tracking loss cancels. Thresholds stay 0.030 on / 0.045 off.
