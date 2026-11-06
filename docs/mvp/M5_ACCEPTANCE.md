# M5 acceptance matrix — gameplay loop, comfort, diagnostics

Authority: [`VERIFY.md`](../../VERIFY.md). Every status is evidence-based; host/build work is **not** a
device PASS. On 2026-11-05 the operator stated the M5 loop had been tested in prior sessions and waived a
fresh current-build run; those rows are recorded as **operator-attested PASS** rather than a new run.

| ID | Requirement | Implementation in current build | Status |
|---|---|---|---|
| H1 | Title/menu/continue/new world | Launcher -> JIT game -> GUI pointer via right pinch; menu entry via left fist tap; automatic immersive open | `PASS` (operator-attested prior session 2026-11-05; no new run) |
| H2 | Free move, snap/smooth turn, jump, sneak (teleport descoped EV-0257) | Left thumb-index pinch player-relative stick; turn angle picker; head rise/lower jump/sneak | `PASS` (operator-attested; M7 movement/jump/sneak device pass EV-0253/0257) |
| H3 | Seated and standing modes | Runtime settings + launcher toggles; opt-in seated HMD pointer parity (`comfort.seatedHmdPointer`) | `PASS` (operator-attested prior session 2026-11-05) |
| H4 | Break/place/attack/use/eat/entity interact | Short right pinch = context attack/place/use; hold = break; eat | `PASS` (operator-attested; device EV-0256/0257) |
| H5 | Inventory, hotbar, crafting, chests, drag/drop | Both-fist tap inventory; right-pinch LMB pick/place; touch-hotbar stable | `PASS` (operator-attested; device EV-0256/0257) |
| H6 | Pause/options/death/respawn | Left fist tap menu; GUI pointer; respawn via GUI | `PASS` (operator-attested prior session 2026-11-05) |
| H7 | Visible hands/held item | Provider hands drive controller poses; optional `hands.componentMode=joints` for fingertip tip component | `PASS` (operator-attested prior session 2026-11-05) |
| H8 | Bow | Both-fist draw, release back fist to fire | `PASS` (operator-attested; device EV-0257) |
| H9 | Climbing | Alternating closed-hand reach/pull; climb jump | `PASS` (operator-attested; device EV-0257) |
| H10 | Save/reload/settings persistence | Minecraft saves; VRMC settings files; shutdown journal | `PASS` (operator-attested prior session 2026-11-05) |

## Comfort/diagnostics

| Item | Status |
|---|---|
| Seated/free-move/aim settings | PASS (operator-attested prior session) |
| Smooth/snap turn angle (0/15/30/45/90) | PASS (operator-attested prior session) |
| Teleport | DESCOPED (EV-0257) |
| Recenter (both-middle double-tap) | PASS (operator-attested prior session) |
| Comfort vignette | PASS (operator-attested prior session) |
| Frame pacing/diag telemetry | PASS (operator-attested prior session) |
| Thermal/low-power logging | PASS (operator-attested prior session) |
| Diagnostics export (logs/crash/status) | PASS (operator-attested prior session) |
| Controls help/reference | host PASS (EV-0124) |

## Exit criteria (M5)

1. All H1–H10 rows have device evidence (or written waiver) from a single current build.
2. Comfort settings exercised on D1: standing, seated, turn angles, teleport, recenter, vignette.
3. At least one diagnostics export captured and reviewed after a real session.
4. No open P0 defects from the gameplay session; frame pacing/thermal results recorded for M6 K2/K5.
