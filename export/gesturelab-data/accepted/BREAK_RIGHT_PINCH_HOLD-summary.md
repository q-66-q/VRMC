# Accepted dataset: BREAK_RIGHT_PINCH_HOLD

- Canonical file: `gesturelab-BREAK_RIGHT_PINCH_HOLD-20261102-192842.jsonl`
- Duration: 31.11 s, 588 samples; right hand 588/588 tracked; left 578.
- Right pinch distance: min/p05/p25/p50/p95 = 0.001/0.004/0.008/0.010/0.127 m.
- 470/588 frames below 0.030 m.
- **7 held-pinch events** with durations **1.21 / 2.24 / 1.49 / 1.98 / 4.33 / 3.36 / 10.44 s**
  (all ≥0.35 s; no short taps in this recording).
- Verdict: valid block-break hold data. Starting split: right pinch <0.35 s = place/select;
  held ≥0.35 s = break/mine. The 10.44 s event can be clamped/segmented in the production engine but
  is useful for long-hold stability.
