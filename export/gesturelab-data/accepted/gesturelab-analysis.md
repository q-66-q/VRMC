# Gesture Lab analysis

files=9 samples=5358 unparsed=0 labels=8

| label | samples | L tracked | R tracked | L pinch p05/p50/p95 | L events | R pinch p05/p50/p95 | R events | L fist p50 | R fist p50 | R speed p95 | R wrist→head p50 | head y range |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ATTACK_RIGHT_SWING | 520 | 25 | 503 | 0.022/0.050/0.080 | 2 | 0.016/0.048/0.090 | 31 | 0.66 | 0.45 | 3.31 | 0.475 | 0.052 |
| EAT_RIGHT_HAND_HEAD | 455 | 180 | 386 | 0.034/0.048/0.064 | 2 | 0.016/0.042/1.000 | 29 | 0.56 | 0.63 | 2.15 | 0.283 | 0.030 |
| ESCAPE_LEFT_FIST | 561 | 561 | 349 | 0.038/0.101/0.148 | 4 | 0.021/0.075/1.000 | 1 | 0.90 | 0.92 | 0.43 | 0.667 | 0.045 |
| JUMP_HEAD | 923 | 529 | 806 | 0.035/0.053/0.095 | 5 | 0.027/0.046/1.000 | 19 | 0.92 | 0.89 | 4.89 | 0.724 | 0.752 |
| MENU_RIGHT_PINCH | 563 | 179 | 563 | 0.032/0.075/0.088 | 0 | 0.006/0.083/0.148 | 42 | 0.72 | 0.67 | 0.57 | 0.397 | 0.095 |
| SNEAK_HEAD | 524 | 326 | 459 | 0.025/0.040/0.054 | 9 | 0.027/0.039/1.000 | 12 | 0.85 | 0.84 | 4.10 | 0.638 | 0.731 |
| TELEPORT_LEFT_PINCH | 1254 | 1113 | 994 | 0.006/0.040/0.162 | 16 | 0.032/0.052/1.000 | 8 | 0.59 | 0.90 | 1.28 | 0.782 | 0.117 |
| WALK_BOTH_FISTS | 558 | 544 | 507 | 0.026/0.036/0.048 | 3 | 0.026/0.033/1.000 | 27 | 0.36 | 0.35 | 3.40 | 0.581 | 0.150 |

## Suggested starting thresholds (host hints only)

- ATTACK_RIGHT_SWING: right wrist speed p95=3.31 m/s; use for attack/walk separation after checking falsing.
- eat proximity: right wrist→head p50=0.283 m, p95=0.734 m; start latch ~0.28 m and require food context.
- ESCAPE_LEFT_FIST: left fist frames <0.55=146/561; right fist frames <0.55=0/349; left p50=0.90, right p50=0.92. Use closed frames with both-hands-visible to set fist on/off hysteresis.
- JUMP_HEAD: head y range=0.752 m; compare idle baseline before latching.
- MENU_RIGHT_PINCH: 112 closed frames (<0.030 m), 42 pinch events; p05=0.006 p25=0.047 p50=0.083 p95=0.148 m. Current 0.030 on / 0.045 off is consistent if the open-hand p25 stays above 0.045.
- SNEAK_HEAD: head y range=0.731 m; compare idle baseline before latching.
- TELEPORT_LEFT_PINCH: left pinch events=16; p05=0.006 p50=0.040 p95=0.162 m. Left pinch hold should start teleport-aim; release commits.
- WALK_BOTH_FISTS: left fist frames <0.55=499/544; right fist frames <0.55=457/507; left p50=0.36, right p50=0.35. Use closed frames with both-hands-visible to set fist on/off hysteresis.
- WALK_BOTH_FISTS: right wrist speed p95=3.40 m/s; use for attack/walk separation after checking falsing.

Device validation is still required; do not treat these as accepted thresholds.
