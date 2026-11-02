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

## Still to implement (M5 completion)

- Recenter / height / world-scale actions and persistence.
- Launcher-facing settings UI for the same values (file editing is the interim path).
- Quality preset application review on device (render distance vs. 90 Hz floor), thermal soak.
- H1–H10 gameplay acceptance matrix (device).

## Verification

Host: `provider/tests/run_tests.sh` (m5-settings 18 checks). Shell: `scripts/build_shell.sh`.
Device: `NOT RUN` (needs D1). See VERIFY EV-0101.
