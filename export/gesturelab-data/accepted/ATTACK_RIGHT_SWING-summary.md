# Accepted dataset: ATTACK_RIGHT_SWING

- Canonical file: `gesturelab-ATTACK_RIGHT_SWING-20261102-180152.jsonl`
- Duration: 31.41 s, 520 samples; right hand tracked 503/520; left hand only 25/520
  (a one-handed action, useful separation from walk which needs both hands).
- Right-wrist speed: p50=1.30, p90=2.57, p95=2.97, p99=3.81, max=4.75 m/s.
- Right-wrist acceleration: p50=5.85, p90=16.88, p95=21.39, p99=28.07, max=50.61 m/s².
- 228 frames >1.4 m/s; 186 frames >8 m/s²; ~28 speed-run swing events.
- Fist curl p50=0.45 (hand loose/partly curled during swings; attack should still be gated by
  one-hand/speed/acceleration and not by the walk both-fist condition).
- Verdict: valid one-handed attack-swing data. Starting detector: right-wrist speed >1.4 m/s or
  acceleration >8 m/s², not both-fist, GUI closed, not bow/eat/climb.
