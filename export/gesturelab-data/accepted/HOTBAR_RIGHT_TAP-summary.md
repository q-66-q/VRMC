# Accepted dataset: HOTBAR_RIGHT_TAP

- Canonical file: `gesturelab-HOTBAR_RIGHT_TAP-20261102-193317.jsonl`
- Duration: 30.94 s, 558 samples; right hand 558/558 tracked; left 519.
- The tap is a **finger tap**, not a wrist flick: wrist speed stays low (max 0.65 m/s) but the right
  index fingertip moves sharply:
  - index-tip speed p50/p90/p95/p99/max = 0.27/0.75/1.28/2.66/3.76 m/s
  - index-tip acceleration p95 ≈ 20.8 m/s², max 62.6 m/s²
- **22 index-finger tap events** at >1.2 m/s (reset <0.5), durations **0.05–0.22 s**.
- Verdict: valid hotbar-tap dataset. Production rule: quick right index-fingertip tap (short spike,
  no pinch/fist hold, no full-hand swing) selects the next hotbar slot; double tap cycles back.
  Must be suppressed while walking/bow/GUI.
