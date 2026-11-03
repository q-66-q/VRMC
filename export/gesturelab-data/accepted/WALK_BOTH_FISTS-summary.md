# Accepted dataset: WALK_BOTH_FISTS

- Canonical file: `gesturelab-WALK_BOTH_FISTS-20261102-174725.jsonl`
- Source recording: `gesturelab-MENU_RIGHT_PINCH-20261102-174725.jsonl` (picker stayed on the default
  label; relabelled with `label=WALK_BOTH_FISTS`, `sourceLabel=MENU_RIGHT_PINCH`, `relabeled=true`).
- Duration: 30.97 s, 558 samples. Left tracked 544/558; right 507/558; head 558/558.
- Both hands closed as fists in **420/558** samples (~75%); left fist curl p50=0.359, right p50=0.348;
  open-hand p95=0.65/0.74. The samples outside the both-fist region are transitions.
- Arm swing (wrist relative to head): left/right z-range 0.788/0.645 m; left/right z
  correlation **−0.73** (opposite phase); ~51/53 zero crossings over 31 s (~25 alternating cycles,
  ≈0.8 Hz). x correlation −0.46, y −0.49.
- Headset position moved during the session: head x range 0.279 m, y range 0.150 m, z range 1.969 m
  (the operator walked around the room); full 4×4 head transforms are in every sample.
- Verdict: valid data for walk/run = both fists + alternating arm swing; relative-to-head arm z swing is
  the strongest separator. Device A/B still required.
