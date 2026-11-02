# M5 plan — gameplay loop + comfort + diagnostics

Status: **IN PROGRESS (offline)** — first slice implemented and host-verified: opt-in runtime/comfort/
performance settings (`VisionRuntimeSettings`, EV-0101) and provider periodic diagnostics + shell
thermal/low-power monitor. Device/gameplay verification is `NOT RUN` while D1 is unavailable.

## Scope (AGENT §7 M5: all H features pass)

- **Comfort:** seated/standing, seated free move/HMD aim, smooth vs snap rotation angle, recenter /
  height / world scale, comfort defaults that never silently change an existing install.
- **Performance:** quality/balanced/performance presets for render/simulation distance, frame-rate
  limit, VSync; frame pacing/thermal telemetry; 90 Hz target with documented 45 fps floor behavior.
- **Diagnostics:** provider periodic diagnostics (`[VRMC-M5] diag:`), shell thermal/low-power log
  (`vrmc-thermal.log`), launcher log export path; no telemetry leaves the device (AC-6).
- **Gameplay loop:** H1–H10 acceptance on device; host-test every pure-Java helper.

## First slice (EV-0101)

- `vrmc-runtime.properties` in the game directory, all keys optional; absent file = no changes:
  - `comfort.seated`, `comfort.seatedFreeMove`, `comfort.seatedUseHMD`,
    `comfort.worldRotationIncrement` (0 = smooth, >0 = snap degrees);
  - `performance.preset=performance|balanced|quality`, explicit overrides
    `performance.renderDistance` (2–32), `simulationDistance` (2–32), `framerateLimit` (30–260),
    `vsync`;
  - `diagnostics.periodSeconds` (5–3600, default 30).
- Strict validation: invalid/out-of-range values are logged as warnings and ignored (no silent
  clamping); preset expansion is logged via one summary line `[VRMC-M5] runtime settings: …`.
- Provider `[VRMC-M5] diag:` periodic line: poll Hz, frames, max poll gap, GUI screen, seated, hand
  tracking, display-view generation, tracked frames, player present.
- Shell `THERMAL` lines every 30 s + on thermal-state change, appended to `vrmc-thermal.log` and the
  shell log: thermal state, low-power mode, uptime, physical memory, immersive/presenting/app state.

## Recenter safety chord (EV-0103)

- Both-hand middle double-tap (120 ms window, 300 ms cooldown) → recenter; the chord cancels the
  per-hand middle-double-tap pulses so recenter cannot also trigger the right-hand radial or the
  left-hand snap-turn. `VisionVR` performs `snapRoomOriginToPlayerEntity(player,false,true)` and logs
  the action. Host tests PASS; device feel/comfort NOT RUN.

## Launcher settings panel (EV-0104)

- `VRControlOverlay` (launcher window) gains a collapsible **VRMC settings** panel: seated mode,
  seated free move, snap turn 45°/smooth, performance preset, render distance, frame limit.
- Loads/saves `Documents/instances/default/vrmc-runtime.properties`; preserves unrelated user keys,
  atomic write, shell log line on success/failure. Applied at the next game launch by the provider
  parser (EV-0101). Shell build PASS; device UI interaction NOT RUN.

## World scale / height / command channel (EV-0105)

- `comfort.worldScale` (0.1–5) and `comfort.manualHeight` (-1 = auto, or 1.0–2.2 m) are parsed and
  applied to Vivecraft settings at init.
- Local whitelisted command channel: the shell writes `vrmc-command.txt` in the game directory; the
  provider consumes at most one command every 500 ms and appends a result to
  `vrmc-command-result.txt`. Commands: `recenter`, `calibrate-height`, `reload-settings`, `diag`,
  `status`. Unknown commands are rejected and recorded (never executed).
- Launcher overlay buttons: **Recenter**, **Calibrate height**, **Reload settings**, **Diagnostics**.
  Device behavior/UI interaction NOT RUN.

## Diagnostics export (EV-0107)

- Provider writes `vrmc-status.json` (ABI, bridge, display views, tracked frames, seated/input/hand
  state, player present, runtime-settings summary) at init and on the `status` command.
- Launcher **Export diagnostics** button builds a capped local text bundle from shell/compositor/
  thermal/Minecraft logs, status, shutdown journal, command results and runtime settings; a ShareLink
  opens the system share sheet for manual save/AirDrop. No automatic upload or telemetry.
- Device share-sheet behavior NOT RUN.

## Still to implement (M5 completion)

- Recenter / height / world-scale actions and persistence.
- Quality preset application review on device (render distance vs. 90 Hz floor), thermal soak.
- H1–H10 gameplay acceptance matrix (device).

## Verification

Host: `provider/tests/run_tests.sh` (m5-settings 18 checks). Shell: `scripts/build_shell.sh`.
Device: `NOT RUN` (needs D1). See VERIFY EV-0101.
