# Gesture Lab analysis

files=5 samples=3129 unparsed=0 labels=5

| label | samples | left tracked | right tracked | pinch p05/p50/p95 | pinch<0.03 | pinch events | left fist p50 | right fist p50 | right speed p95 | right wrist→head p50 | head y range |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ESCAPE_LEFT_FIST | 561 | 561 | 349 | 0.021/0.075/1.000 | 63 | 1 | 0.90 | 0.92 | 0.43 | 0.667 | 0.045 |
| JUMP_HEAD | 923 | 529 | 806 | 0.027/0.046/1.000 | 86 | 19 | 0.92 | 0.89 | 4.89 | 0.724 | 0.752 |
| MENU_RIGHT_PINCH | 563 | 179 | 563 | 0.006/0.083/0.148 | 112 | 42 | 0.72 | 0.67 | 0.57 | 0.397 | 0.095 |
| SNEAK_HEAD | 524 | 326 | 459 | 0.027/0.039/1.000 | 59 | 12 | 0.85 | 0.84 | 4.10 | 0.638 | 0.731 |
| WALK_BOTH_FISTS | 558 | 544 | 507 | 0.026/0.033/1.000 | 137 | 27 | 0.36 | 0.35 | 3.40 | 0.581 | 0.150 |

## Suggested starting thresholds (host hints only)

- ESCAPE_LEFT_FIST: left fist frames <0.55=146/561; right fist frames <0.55=0/349; left p50=0.90, right p50=0.92. Use closed frames with both-hands-visible to set fist on/off hysteresis.
- JUMP_HEAD: head y range=0.752 m; compare idle baseline before latching.
- MENU_RIGHT_PINCH: 112 closed frames (<0.030 m), 42 pinch events; p05=0.006 p25=0.047 p50=0.083 p95=0.148 m. Current 0.030 on / 0.045 off is consistent if the open-hand p25 stays above 0.045.
- SNEAK_HEAD: head y range=0.731 m; compare idle baseline before latching.
- WALK_BOTH_FISTS: left fist frames <0.55=499/544; right fist frames <0.55=457/507; left p50=0.36, right p50=0.35. Use closed frames with both-hands-visible to set fist on/off hysteresis.
- WALK_BOTH_FISTS: right wrist speed p95=3.40 m/s; use for attack/walk separation after checking falsing.

Device validation is still required; do not treat these as accepted thresholds.
