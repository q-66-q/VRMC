# M5 acceptance matrix — gameplay loop, comfort, diagnostics

Authority: [`VERIFY.md`](../../VERIFY.md). Every status is evidence-based; host/build work is **not** a
device PASS. D1 is currently unavailable, so all device rows are `NOT RUN`.

| ID | Requirement | Implementation in current build | Status |
|---|---|---|---|
| H1 | Title/menu/continue/new world | Launcher -> JIT game -> GUI pointer via right pinch; menu entry via left fist tap; automatic immersive open | `PARTIAL` (device W1 PASS EV-0096; current build needs re-check) |
| H2 | Free move, snap/smooth turn, teleport, jump, sneak | Left middle-pinch virtual stick; turn angle picker 0/15/30/45/90; left pinch teleport (suppressed during use/bow); right middle tap jump; right middle hold sneak | `HOST PASS` (EV-0099), device `NOT RUN` |
| H3 | Seated and standing modes | Runtime settings + launcher toggles; provider falls back correctly in seated | `HOST PASS`, device `NOT RUN` |
| H4 | Break/place/attack/use/eat/entity interact | Right pinch attack/click; right fist hold use/bow; contextual VR interact bindings | device `PARTIAL` (W1) / current build `NOT RUN` |
| H5 | Inventory, hotbar, crafting, chests, drag/drop | Both-fist tap inventory; ring-pinch hotbar wheel 1–9; optional swipes hotbar ±/swap/drop; GUI pointer | `HOST PASS`, device `NOT RUN` |
| H6 | Pause/options/death/respawn | Left fist tap menu; GUI pointer; no dedicated respawn gesture (GUI) | device `PARTIAL`, current build `NOT RUN` |
| H7 | Visible hands/held item | Provider hands drive controller poses; optional `hands.componentMode=joints` for fingertip tip component | `HOST PASS` math only, device appearance `NOT RUN` |
| H8 | Bow | Right fist hold = continuous use (draw/fire); teleport suppressed while held | host `PASS`, device `NOT RUN` |
| H9 | Climbing | Both-hand pinch grab; both-middle pinch tap = climb jump | host `PASS`, device `NOT RUN` |
| H10 | Save/reload/settings persistence | Minecraft saves; VRMC settings files; shutdown journal | host/docs PASS, device `NOT RUN` |

## Comfort/diagnostics

| Item | Status |
|---|---|
| Seated/free-move/aim settings | host PASS, device NOT RUN |
| Smooth/snap turn angle (0/15/30/45/90) | host/build PASS (EV-0127), device NOT RUN |
| Teleport + bow/use suppression | host PASS (EV-0121/0125) |
| Recenter (both-middle double-tap) | host PASS (EV-0103) |
| Comfort vignette | build PASS (EV-0122), device appearance NOT RUN |
| Frame pacing/diag telemetry | host PASS (EV-0110), device measurements NOT RUN |
| Thermal/low-power logging | build PASS (EV-0101), device NOT RUN |
| Diagnostics export (logs/crash/status) | build PASS (EV-0107/0121), device share UI NOT RUN |
| Controls help/reference | host PASS (EV-0124) |

## Exit criteria (M5)

1. All H1–H10 rows have device evidence (or written waiver) from a single current build.
2. Comfort settings exercised on D1: standing, seated, turn angles, teleport, recenter, vignette.
3. At least one diagnostics export captured and reviewed after a real session.
4. No open P0 defects from the gameplay session; frame pacing/thermal results recorded for M6 K2/K5.
