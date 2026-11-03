# Accepted dataset: JUMP_HEAD

- Canonical file: `gesturelab-JUMP_HEAD-20261102-175006.jsonl`
- Duration: 80.03 s, 923 samples; head tracked 923/923; full 4×4 head transform per sample.
- Head Y: min/p05/p50/p95/max = 1.057 / 1.285 / 1.460 / 1.650 / 1.809 m.
- Adaptive-baseline excursions >0.08 m: **29 head-rise events**; peak amplitudes **0.11–0.30 m**;
  durations mostly 0.27–0.95 s (one long 3.95 s stay).
- Upward head velocity: p95 ≈ 1.51 m/s, max ≈ 2.36 m/s.
- Hand tracking is not required for this action; left/right were partially visible.
- Verdict: valid data for head-rise jump. Starting detector: baseline EMA (τ≈2 s), require head rise
  >0.08 m with upward velocity >0.25 m/s, release when within 0.03 m of baseline for 300 ms.
- The game also keeps Minecraft auto-jump enabled by default for one-block steps.
