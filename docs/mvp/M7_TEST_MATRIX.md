# M7 synthetic test matrix (host)

`provider/tests/dev/vrmc/provider/VisionM7GestureTest.java` — **40 checks**, all PASS on host.
These are synthetic joint/head sequences; they are not device evidence. The original 23 checks are
listed first (1–23), then the adjacent-priority/boundary checks added for the device A/B review.

## Full check list and adjacent-priority mapping

| # | Check name | Class | Adjacent-priority relation |
|---|---|---|---|
| 1 | short pinch not place while held | place/break | place only on release; held = break |
| 2 | short right pinch releases place | place/break | short place |
| 3 | short right pinch does not break | place/break | short/held separation |
| 4 | held right pinch breaks | place/break | break |
| 5 | held right pinch does not place | place/break | short/held separation |
| 6 | left fist tap fires menu | menu | left fist path |
| 7 | both-fist tap fires inventory | inventory | base both-fist tap |
| 8 | both-fist tap does not walk | inventory/walk | **inventory tap + both fists ≠ walk** |
| 9 | alternating both-fist swing starts walk | walk | walk |
| 10 | walk forward analog > 0 | walk | walk output |
| 11 | head rise fires jump | jump | head path |
| 12 | head drop latches sneak | sneak | head path |
| 13 | index-finger tap fires hotbar next | hotbar | tap path |
| 14 | wide both fists = bow draw | bow | bow path |
| 15 | right hand near head = eat | eat | eat path |
| 16 | GUI right pinch fires click | GUI | GUI click |
| 17 | GUI suppresses world place | GUI/place | GUI priority over world place |
| 18 | GUI left fist taps menu/escape | GUI/menu | GUI escape |
| 19 | GUI + both fists suppresses inventory | GUI/inventory | **GUI + both fists → no inventory** |
| 20 | GUI + both fists suppresses walk | GUI/walk | GUI priority over walk |
| 21 | bow + both fists suppresses inventory | bow/inventory | **bow drawing + both fists → no inventory** |
| 22 | bow + both fists suppresses walk | bow/walk | bow priority over walk |
| 23 | bow release fires | bow | release edge |
| 24 | climb + both fists suppresses inventory | climb/inventory | **climb + both fists → no inventory** |
| 25 | climb + both fists suppresses walk | climb/walk | climb priority over walk |
| 26 | walk + both fists suppresses inventory | walk/inventory | **walk + both fists → no inventory** |
| 27 | inventory tap does not start walk | inventory/walk | **inventory tap → no walk** |
| 28 | pinch 349 ms releases place | boundary | 349 ms = place |
| 29 | pinch 349 ms is short | boundary | 349 ms not break |
| 30 | pinch 351 ms is break | boundary | 351 ms = break |
| 31 | pinch 351 ms does not place | boundary | 351 ms not place |
| 32 | pinch 350 ms is break | boundary | 350 ms boundary = break |
| 33 | pinch 350 ms does not place | boundary | 350 ms not place |
| 34 | fast wrist swing attacks | attack/hotbar | swing → attack |
| 35 | attack swing does not cycle hotbar | attack/hotbar | **hotbar tap ≠ attack swing** |
| 36 | seated suppresses walk | seated | seated safety |
| 37 | seated suppresses teleport | seated | seated safety |
| 38 | release clears menu | release | loss-of-input release |
| 39 | release clears inventory | release | loss-of-input release |
| 40 | release clears break | release | loss-of-input release |

## Requested adjacent-priority pairs

| Pair | Checks |
|---|---|
| GUI open + both fists ⇒ no inventory | 19 (also 17, 20) |
| Bow drawing + both fists ⇒ no inventory | 21 (also 22, 23) |
| Climb + both fists ⇒ no inventory | 24 (also 25) |
| Walk + both fists ⇒ no inventory | 26 (also 9, 10) |
| Inventory tap + both fists ⇒ no walk | 8, 27 |
| Place (short) vs break (held) boundary 0.35 s | 1–5, 28–33 |
| Hotbar tap vs attack swing | 34, 35 (also 13, 16) |

## Checks added after the review

- 20, 22, 25 (GUI/bow/climb priority over walk)
- 23 (bow release edge)
- 29 (349 ms not break)
- 30, 31 (351 ms boundary)
- 34, 35 (attack vs hotbar)
- 19, 21, 24, 26, 27 (explicit adjacent-priority pairs)
- 28/32/33 already existed as boundary checks but are listed here with the full pair.

No engine rewrite was required; the added tests exposed two previous-state ordering bugs (bow/climb
inventory suppression) which were fixed before the matrix was rerun.
