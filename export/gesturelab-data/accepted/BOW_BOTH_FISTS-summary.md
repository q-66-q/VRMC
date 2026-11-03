# Accepted dataset: BOW_BOTH_FISTS

- Canonical file: `gesturelab-BOW_BOTH_FISTS-20261102-180604.jsonl`
- Duration: 46.66 s, 819 samples; both hands mostly tracked (left 695, right 758), head 819/819.
- Left/right wrist separation: min/p05/p50/p95/max = 0.156/0.224/0.502/0.727/1.049 m.
- 16 separation cycles crossing 0.55 m (draw/release cycles); peak 1.049 m.
- Fist curl: left p50=0.349 (front bow hand stays closed), right p50=0.479 with p95=0.983
  (back string hand opens on release).
- Both fists closed in 216/636 paired frames (~34%); that is expected because the release hand opens.
- Verdict: valid bow data. Starting detector: both hands start fists, front/back separation grows >0.55 m,
  release when the back hand opens; suppress walk while bow context is active.
