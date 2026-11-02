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

## Frame-pacing telemetry (EV-0110)

- `VisionFrameStats`: rolling provider-poll interval ring (900 samples); per diagnostic period reports
  mean/P50/P95/max ms and a documented `missed90` count (interval > 1.5 × 90 Hz = 16.67 ms); one sort
  per report, no per-frame allocation.
- `[VRMC-M5] diag:` now includes p50Ms/p95Ms/maxMs/missed90 alongside pollHz/maxGapMs.
- Device K2/K5 still need real measurements; poll intervals are a Java-side proxy, not GPU timestamps.

## Launcher panel extension (EV-0112)

- Launcher settings panel now also edits `comfort.worldScale` (0.80–1.50×), `comfort.manualHeight`
  (auto `-1`, manual 1.30–2.10 m) and `diagnostics.periodSeconds` (10–120 s), with the same
  load/clamp/preserve-other-keys/save behavior as EV-0104. Applied at the next game launch by the
  provider. Shell build PASS; device UI/comfort feel NOT RUN.

## Command feedback + live launcher status (EV-0114)

- Command/recenter completion shows a best-effort Minecraft action-bar message (`[VRMC] …`) via
  reflection (no annotation-class build dependency).
- Launcher overlay refreshes a compact 5 s status line from `vrmc-status.json` and `ProcessInfo`:
  bridge ready, display-view generation, hand L/R tracking, seated, thermal state, low-power mode.
- Latest build installed on D1 (app `46c80630…`, provider `39e9714a…`); behavior NOT RUN (device
  locked).

## Gesture toggles + reference (EV-0117)

- Launcher settings panel toggles **Middle-pinch gestures** (`middle.enabled`) and **Open-hand swipe
  gestures** (`swipe.enabled`), persisted to `vrmc-input-tune.properties` (separate from runtime
  settings, matching `VisionInput.loadInputTuning`); other keys preserved; applied next launch.
- Added a gesture cheat sheet covering pinch/fist/both-fist, middle-pinch family, and opt-in swipes.
- Updated app installed (tree `abc48c93…`, provider `d6de9469…`); device UI/gesture behavior NOT RUN.

## Live input reload (EV-0120)

- Command channel adds `reload-input`: the provider recreates `VisionInput` from the current game-dir
  `vrmc-input-tune.properties` (middle/ring/swipe toggles, thresholds, hotbar range) without a game
  restart, resets binding resolution and shows action-bar feedback.
- Launcher gains a **Reload input** button (queues the local command).
- Provider suite/shell builds PASS; latest app installed/provider pushed. Device behavior NOT RUN.

## Crash-log export (EV-0121)

- Diagnostics bundle now appends prior shell/compositor logs, `hs_err_pid*.log` and
  `crash-reports/*.txt` (first 6 extras, capped) to the fixed logs/status/settings sections.
- Local-only; device share UI NOT RUN.

## Comfort vignette (EV-0122)

- Compositor adds `fmain_flat_vignette`: when `Documents/vrmc-vignette.flag` exists, the flat-sampled
  image darkens toward the periphery by the file's strength (0–0.9; empty = 0.5). Centre untouched,
  test pattern unaffected; strength read once per immersive session and logged.
- Launcher settings: Comfort vignette toggle + 0.1–0.9 strength slider writes/removes the flag;
  applies at the next immersive open.
- Build/install PASS; runtime shader/appearance/comfort NOT RUN (device locked).

## Advanced input tuning UI (EV-0123)

- Launcher **Input tuning (advanced)** panel: middle-pinch and ring-pinch on/off thresholds (mm), swipe
  speed (m/s), hotbar range (m); saved to `vrmc-input-tune.properties` in metres with off > on enforced
  and unrelated keys preserved.
- Applies live with **Reload input** or at the next launch.
- Shell/app build/install PASS; device UI/tuning feel NOT RUN.

## In-game controls help (EV-0124)

- `controls` command sends a compact multi-line gesture reference to Minecraft chat (reflective, no
  annotation-class dependency); launcher Controls help button queues it.
- `docs/mvp/M4_CONTROLS.md` is the authoritative installed-build control reference.
- Device chat UX NOT RUN.

## Turn-angle picker + acceptance/runbook (EV-0127)

- Launcher **Turn** picker: Smooth / 15° / 30° / 45° / 90°, saved to `comfort.worldRotationIncrement`
  (replaces the fixed 45/smooth toggle; existing provider settings path).
- `docs/mvp/M5_ACCEPTANCE.md` (H1–H10 + comfort/diagnostics matrix, honest status, exit criteria) and
  `docs/mvp/M5_DEVICE_RUN.md` (step-by-step D1 procedure/evidence plan) published.
- Build/install PASS; device run NOT RUN.

## Diagnostics viewer + pacing warning (EV-0128)

- Launcher **Recent diagnostics** disclosure: capped tails of compositor/shell/latestlog/status, extracts
  `[VRMC-`/WARN/ERROR/FAIL/CRASH lines (last 8, monospaced, refresh); status line reports
  `providerJar=ok/MISSING`.
- Provider `[VRMC-M5] diag` emits an explicit WARN when p95 poll interval > 16.7 ms or missed90 exceeds
  max(2, frames/10).
- Build/install PASS; device UI/behavior NOT RUN; simulator remains unusable (immediate backgrounding).

## Still to implement (M5 completion)

- Recenter / height / world-scale actions and persistence.
- Quality preset application review on device (render distance vs. 90 Hz floor), thermal soak.
- H1–H10 gameplay acceptance matrix (device).

## Verification

Host: `provider/tests/run_tests.sh` (m5-settings 18 checks). Shell: `scripts/build_shell.sh`.
Device: `NOT RUN` (needs D1). See VERIFY EV-0101.
