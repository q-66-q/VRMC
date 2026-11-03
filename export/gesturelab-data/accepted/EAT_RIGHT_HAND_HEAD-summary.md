# Accepted dataset: EAT_RIGHT_HAND_HEAD

- Canonical file: `gesturelab-EAT_RIGHT_HAND_HEAD-20261102-180404.jsonl`
- Duration: 30.85 s, 455 samples; right hand 386/455 tracked; left 180/455; head 455/455.
- Right-wrist→head distance: min/p05/p10/p25/p50/p75/p95 = 0.187/0.218/0.227/0.247/0.283/0.434/0.734 m.
- Frames within 0.28 m: **181**; within 0.30 m: 216.
- Near-head events (enter <0.28 m, leave >0.35 m): **11**, durations 0.22–6.04 s.
- Verdict: valid eat/drink approach data. Starting detector: right hand enters ~0.28 m of head and is
  held (250 ms latch) while the held item is edible/drinkable; leave >0.35 m or release stops it.
  Use the narrower 0.22–0.25 m region for a stronger trigger once in-game context is available.
