# Accepted dataset: SNEAK_HEAD

- Canonical file: `gesturelab-SNEAK_HEAD-20261102-175427.jsonl`
- Duration: 31.00 s, 524 samples; head tracked 524/524; full 4×4 head transform per sample.
- Head Y: min/p05/p50/p95/max = 0.779 / 0.822 / 0.956 / 1.492 / 1.509 m.
- Adaptive-baseline downward excursions >0.10 m: **5 events**; depths **0.10–0.25 m**; several long holds
  (two ~4.9 s holds, plus 0.33/2.56/1.33 s returns). Max head speed 1.66 m/s.
- Hand tracking is not required; left/right were partially visible.
- Verdict: valid data for headset-lower sneak. Starting detector: baseline EMA (τ≈2 s), require
  head drop >0.10 m sustained ~350 ms, release when within 0.05 m of baseline for 250 ms.
- The long holds mean this dataset over-represents held crouch vs repeated taps, but still gives the
  displacement/velocity range; a second sneak pass can be added later for more transitions.
