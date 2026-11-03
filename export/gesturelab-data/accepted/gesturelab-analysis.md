# Gesture Lab analysis

files=1 samples=563 unparsed=0 labels=1

| label | samples | left tracked | right tracked | pinch p05/p50/p95 | pinch<0.03 | pinch events | right fist p50 | right speed p95 | right wrist→head p50 | head y range |
|---|---|---|---|---|---|---|---|---|---|---|
| MENU_RIGHT_PINCH | 563 | 179 | 563 | 0.006/0.083/0.148 | 112 | 42 | 0.60 | 0.57 | 0.397 | 0.095 |

## Suggested starting thresholds (host hints only)

- MENU_RIGHT_PINCH: 112 closed frames (<0.030 m), 42 pinch events; p05=0.006 p25=0.047 p50=0.083 p95=0.148 m. Current 0.030 on / 0.045 off is consistent if the open-hand p25 stays above 0.045.

Device validation is still required; do not treat these as accepted thresholds.
