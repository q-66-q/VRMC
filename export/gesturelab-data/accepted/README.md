# Accepted Gesture Lab datasets (2026-11-02)

All recordings are local (gitignored raw JSONL) under this directory; each has a tracked summary.
These establish starting thresholds only; in-game device A/B is still required.

| Action | Duration | Events | Key measurements / starting rule |
|---|---|---|---|
| MENU_RIGHT_PINCH | 31.23 s | 42 pinches | pinch p05/p50/p95=0.006/0.083/0.148 m; 0.030 on / 0.045 off |
| ESCAPE_LEFT_FIST | 31.18 s | 24 | left fist curl p05/p50/p95=0.298/0.905/0.983; 0.55 threshold |
| WALK_BOTH_FISTS | 30.97 s | ~25 cycles | both fists 75%; wrist-to-head z corr −0.73, z range 0.79/0.65 m, ~0.8 Hz |
| JUMP_HEAD | 80.03 s | 29 rises | head rise 0.11–0.30 m; upward velocity p95 1.51 m/s |
| SNEAK_HEAD | 31.00 s | 5 drops | head drop 0.10–0.25 m; max speed 1.66 m/s (held-crouch heavy) |
| TELEPORT_LEFT_PINCH | 31.09 + 38.97 s | 16 | left pinch holds 0.05–4.56 s; press=aim, release=commit |
| ATTACK_RIGHT_SWING | 31.41 s | ~28 | right speed p95 2.97 m/s; accel p95 21.4 m/s²; one-handed |
| EAT_RIGHT_HAND_HEAD | 30.85 s | 11 | wrist→head 0.187–0.28 m core; 250 ms latch; stop >0.35 m |
| BOW_BOTH_FISTS | 46.66 s | 16 draws | separation 0.16–1.05 m; release when back hand opens |
| PLACE_RIGHT_PINCH | 59.19 s | 72 short | <0.35 s taps (mostly 0.11–0.22 s); 0.030/0.045 |
| BREAK_RIGHT_PINCH_HOLD | 31.11 s | 7 holds | 1.21–10.44 s holds; same pinch thresholds |
| INVENTORY_BOTH_FISTS | 31.14 s | 24 taps | both-fist taps 0.06–0.28 s; hand sep 0.26–0.44 m |
| HOTBAR_RIGHT_TAP | 30.94 s | 22 taps | right index fingertip speed p95 1.28 m/s; taps 0.05–0.22 s |
| CLIMB_ALTERNATE | 31.09 s | ~15 | alternating fist/height cycles; left-right height zero crossings 31 |

## Next

Implement the production M7 gesture engine behind a mode switch, with host fuzz/invariant tests, then
device A/B against the current M4 mappings. Thresholds above are provisional.
