# Accepted dataset: ESCAPE_LEFT_FIST

- Canonical file: `gesturelab-ESCAPE_LEFT_FIST-20261102-174228.jsonl`
- Source recording: `gesturelab-MENU_RIGHT_PINCH-20261102-174228.jsonl` (picker stayed on the default label;
  relabelled with `label=ESCAPE_LEFT_FIST`, `sourceLabel=MENU_RIGHT_PINCH`, `relabeled=true`).
- Duration: 31.18 s, 561 samples, no sampling gaps above 0.14 s.
- Left hand tracked 561/561; right hand 349/561 (resting/out of view part of the time).
- Left fist curl ratio (new metric, mean tip→knuckle / wrist→knuckle):
  p05=0.298, p50=0.905, p95=0.983, min=0.205.
- Left fist frames <0.55: **146**; detected left-fist events (0.55 on / 0.75 off): **24**,
  durations mostly 0.22–0.61 s.
- Right fist: 0 frames <0.55 (correct: the action was left-handed).
- Verdict: valid data for Escape = left-fist tap.
