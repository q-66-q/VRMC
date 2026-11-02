# M4 → M6 offline product roadmap (operator unavailable)

Status: **ACTIVE WORKING PLAN** (2026-11-01, goal round 1). D1 device testing is temporarily
unavailable, so everything below is implemented/verified at the host/simulator/build level and every
device-only claim stays `NOT RUN` in VERIFY. This file is the ordering for the remaining product work;
it does not override AGENT.md/VERIFY.md evidence rules.

## M4 — hands input (remaining)

Current: W1 PASS on device (EV-0096); W2 smooth hands (EV-0097 host), shutdown hardening (EV-0097
host), gaze tracking areas (EV-0098 host build/tests; runtime/device NOT RUN).

1. **W3 locomotion + core actions (HOST PASS, EV-0099; device pending):** middle-finger pinch gesture family (thumb–middle) as a
   conflict-free chord alongside the existing thumb–index pinch:
   - left middle-pinch hold -> analog free-move virtual stick derived from the left wrist relative to
     the head (forward/strafe), written to `vivecraft.key.freeMoveStrafe`;
   - right middle-pinch hold -> sneak (`key.sneak`), right middle-pinch tap -> jump (`key.jump`);
   - left middle-pinch tap/double-tap -> snap turn left/right (`vivecraft.key.rotateLeft/Right`);
   - hotbar next/previous via right/left middle-pinch double-taps (`vivecraft.key.hotbarNext/Prev`);
   - all thresholds/deadzones configurable in `vrmc-input-tune.properties`; host tests cover gesture
     edges, movement axis math, no-stuck-input on loss, and action-set gating.
2. **W4 full P0 coverage (PARTIAL host PASS, EV-0100 + EV-0106):** hotbar slots, scroll, radial menu, on-screen keyboard/chat, swap/drop,
   two-hand bow/climb chord semantics, visible hands/held item (visual polish).
3. **W5 device acceptance:** ARKit real-hands P0 checklist (AC-4), tracking-loss/occlusion matrix,
   seated/standing parity, gesture tuning from device logs. Device-only.
4. **W6 shutdown/quit/re-entry:** verify EV-0097/EV-0096 fixes on D1 after the stale-immersive/beeps
   fix (commit 3c5d57c).

## M5 — gameplay loop + comfort + diagnostics

Status: first slice HOST/BUILD PASS (EV-0101: opt-in runtime/comfort/performance settings, provider
diagnostics, shell thermal monitor) + recenter safety chord HOST PASS (EV-0103) + launcher settings panel BUILD PASS (EV-0104) + world-scale/height settings & command channel HOST PASS (EV-0105) + diagnostics export BUILD PASS (EV-0107). Details in `docs/mvp/M5_PLAN.md`.

1. **Comfort settings** applied from a game-dir `vrmc-comfort.properties` (logged at startup):
   seated/seated-free-move/seated-aim, world-rotation increment (snap angle), vignette intensity (where
   Vivecraft exposes it), movement speed multiplier; no silent settings changes on existing installs.
2. **Recenter / height / world scale:** launcher- or gesture-triggered VR recenter; runtime height
   calibration from ARKit head pose; values logged and persisted.
3. **Performance presets:** quality/balanced/performance presets for render distance, simulation
   distance, graphics mode, frame-rate limit/VSync (MC options), + VR settings (render scale, foveation
   is off by hardware requirement); documented defaults and measurement logging.
4. **Diagnostics:** provider periodic stats (frame pace, player pose, GUI state, gesture state), shell
   thermal/low-power logger (`ProcessInfo.thermalState`), frame-graph/export path in the launcher log;
   no telemetry by default (AC-6 privacy).
5. **Gameplay loop:** verify H1–H10 on device; host-test every pure-Java helper.

## M6 — hardening + acceptance

Status: IN PROGRESS offline (EV-0102/EV-0108): shutdown journal, soak/release harnesses, privacy/acceptance matrix, crash guard + release check host PASS; device gates NOT RUN. Scope in `docs/mvp/M6_PLAN.md`.

1. **Stability:** clean shutdown/restart, crash log capture/safe restart, 60-min soak + 20-launch /
   10-load harness, watchdog-kill detection.
2. **Performance acceptance:** 90 Hz target / 45 fps floor, thermal step-down, K1–K6 measurements
   (needs D1 + latency rig; document gaps rather than invent numbers).
3. **Release:** version/pins manifest, signed build reproducibility, third-party notices/GPL source
   gate, no Minecraft binaries, privacy manifest.
4. **Acceptance:** AC-1…AC-6 matrix, AC-4 hands-only checklist, evidence/waiver table, final
   VERIFY §10 sign-off.

## Evidence rules while D1 is unavailable

- Host/simulator/build evidence is recorded as `PARTIAL` with explicit limitations; never `PASS` for a
  device gate.
- Any new device capability ships behind a flag and fails safe (gaze: `vrmc-gaze.flag`; comfort/
  performance config files default to today's behaviour).
- Keep one-command host checks: `provider/tests/run_tests.sh`, `bridge/tests/run_tests.sh`,
  `scripts/m3c_selfcheck.sh`, `scripts/m4_input_selfcheck.sh`; add new checks to those suites.
