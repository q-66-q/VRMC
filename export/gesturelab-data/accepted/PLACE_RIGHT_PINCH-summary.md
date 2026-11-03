# Accepted dataset: PLACE_RIGHT_PINCH (short pinches)

- Canonical file: `gesturelab-PLACE_RIGHT_PINCH-20261102-183548.jsonl`
- Duration: 59.19 s, 1062 samples; right hand tracked 1055/1062; left 668; head 1062/1062.
- Right pinch distance: min/p05/p25/p50/p95/max = 0.002/0.007/0.015/0.067/0.154/0.168 m.
- 314 frames below 0.030 m; **76 pinch events** (0.030 on / 0.045 off).
- Event durations: **72 short events <0.35 s** (mostly 0.11–0.22 s) and 4 longer holds
  (4.06/3.39/0.63/0.61 s) that are outliers for the place action.
- Verdict: valid place/select short-pinch dataset. Under the updated rule, short pinch (<~0.35 s)
  places/selects; the four long holds belong to break semantics and are excluded from the place
  threshold fit. Dedicated `BREAK_RIGHT_PINCH_HOLD` data is next.
