# Accepted dataset: MENU_RIGHT_PINCH

- Canonical file: `gesturelab-MENU_RIGHT_PINCH-20261102-173326.jsonl`
- Source recording: `gesturelab-IDLE-20261102-173326.jsonl` (operator omitted the label picker; it was relabelled
  with `label=MENU_RIGHT_PINCH`, `sourceLabel=IDLE`, `relabeled=true`).
- Duration: 31.23 s, 563 samples at ~18 Hz.
- Right hand tracked: 563/563 samples. Left hand tracked: 179/563 (not needed for menu pinch).
- Pinch distance percentiles (m): p05=0.006, p25=0.047, p50=0.083, p95=0.148, min=0.002.
- Closed frames <0.030 m: 112; detected pinch events with 0.030 on / 0.045 off: **42**.
- Event durations: mostly 0.11–0.34 s (normal menu click cadence, ~1.35 events/s).
- Live classifier independently labelled the closed frames `RIGHT_PINCH`.
- Starting threshold implied: on=0.030 m / off=0.045 m (consistent with this data; device A/B still required).
- Verdict: valid data for the menu right-pinch action.
