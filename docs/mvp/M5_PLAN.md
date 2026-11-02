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

## Seated HMD pointer parity (EV-0129)

- Opt-in `comfort.seatedHmdPointer`: when seated with no tracked hand, the HMD-aim fallback pose may
  drive `controllerTracking`/the GUI cursor; gesture actions still require real hands. Default off
  preserves prior behavior. Launcher toggle added.
- m5-settings 23 checks, full provider suite PASS; app installed/provider pushed. Device seated
  behavior NOT RUN.

## W1 tuning sliders + input status (EV-0130)

- Launcher Input tuning adds **pinch on/off (mm)** and **fist on/off** sliders next to middle/ring/swipe/
  hotbar; saved to `vrmc-input-tune.properties` with off>on enforced and unrelated keys preserved;
  applies via Reload input or next launch.
- `VisionInput.tuningSummary()` is written into `vrmc-status.json` with `hotbarRange` for diagnostics.
- m4-input 172 checks, full provider suite PASS; app installed/provider pushed. Device tuning NOT RUN.

## Thermal pressure awareness (EV-0131)

- Shell thermal monitor writes game-dir `vrmc-thermal-state.txt` (state/lowPower/time).
- Provider `VisionThermalState` reads it; on `serious`/`critical` state change logs a warning and shows an
  action-bar advisory. Advisory only — no automatic setting changes; `thermalState` added to
  `vrmc-status.json`.
- m5-thermal 8 checks, full provider suite PASS; app installed/provider pushed. Device K5 thermal
  behavior NOT RUN.

## Thermal quality reduction (EV-0133)

- Opt-in `performance.thermalResponse=notify|reduce` (default notify) with launcher picker.
- On serious/critical thermal state with `reduce`, provider caps render/simulation distance to ≤8 and
  frame limit to ≤72 once per pressure episode; never auto-restores (user raises after cooling);
  logs/action-bar show the change; `thermalResponse` in status JSON.
- m5-settings 25 checks, full provider suite PASS; app installed/provider pushed. Device K5 thermal
  behavior NOT RUN.

## Provider hash + settings reset (EV-0134)

- Launcher status computes the provider jar's SHA256 (first 12 hex) or reports `MISSING`; the diagnostics
  bundle header includes the 32-hex prefix + path.
- **Reset VRMC settings** removes `vrmc-runtime.properties`, `vrmc-input-tune.properties` and
  `vrmc-vignette.flag` (game saves/logs/crash guard untouched) and reloads UI defaults.
- Build/install PASS; device UI NOT RUN.

## Adaptive framerate (EV-0135)

- Opt-in `performance.adaptiveFramerate` + launcher toggle (default off).
- After **two consecutive** over-budget diagnostic windows (p95 >16.7 ms or missed90 > max(2, frames/10)),
  the provider caps frame limit to ≤72 once, logs/action-bar, and reports adaptiveFramerate/Applied in
  status; no auto-restore. Pressure counter resets on a good window.
- m5-settings 27 checks, full provider suite PASS; app installed/provider pushed. Device K2 pacing
  behavior NOT RUN.

## Locomotion tuning sliders (EV-0138)

- Launcher Input tuning adds move forward/strafe scale (1–6), deadzone (0.02–0.40), originZ (−0.30–0.30)
  and snap-turn pulse (60–300 ms); saved as `move.*` keys beside the gesture thresholds (other keys
  preserved; reload-input/next launch).
- Shell/app build/install PASS; provider unchanged; device locomotion feel NOT RUN.

## Command-result feedback + Status button (EV-0140)

- Launcher refreshes the last `vrmc-command-result.txt` line and shows it as "Last result: …" under the
  command buttons; adds a **Status** button queueing the existing `status` command.
- Shell/app build/install PASS; provider unchanged; device UI NOT RUN.

## Tracking pose hold slider (EV-0142)

- Input tuning adds **Tracking-dropout pose hold** (0–1000 ms slider; provider clamps 0–2000) writing
  `tracking.holdLastPoseMs`; actions still release during dropouts.
- Build/install PASS; device visual/aim behavior NOT RUN.

## Status JSON fix + provider summary (EV-0144)

- Fixed invalid `vrmc-status.json` output (`adaptiveFramerateApplied` had a stray quote); the generator
  now emits valid JSON.
- Launcher parses status each refresh and shows a one-line provider summary
  (abi/bridge/tracked/hands/thermal/adaptive), empty on missing/invalid JSON.
- Full provider suite PASS; app installed/provider pushed + integrity PASS. No automated JSON-schema
  test; device UI NOT RUN.

## Testable status JSON builder (EV-0145)

- Extracted `VisionStatusJson` pure builder for `vrmc-status.json` (all fields, string escaping, finite
  numbers); `VisionVR` populates Data and writes atomically.
- `VisionStatusJsonTest` includes a strict-enough JSON parser and covers values/types, quote/backslash/
  control escapes and the EV-0144 trailing-quote regression (12 checks). Full provider suite PASS;
  provider pushed + integrity PASS. Actual file write against a live game remains untested; device
  behavior NOT RUN.

## Thermal poll throttle (EV-0146)

- `pollThermalState()` had read `vrmc-thermal-state.txt` **every frame**; now it is throttled to once per
  5 s (shell writes at thermal-change/30 s cadence), first poll immediate, advisory logic unchanged.
- Full provider suite PASS; provider pushed + integrity PASS. Device runtime performance NOT RUN.

## Allocation-free frame paths (EV-0147)

- Display-view eye transforms reuse a 16-float scratch array (no float[16] per eye per generation).
- `VisionLocomotion.axes(..., Vector2f dest)` is allocation-free; always overwrites (stale axes cleared
  on invalid input), used by `applyLocomotion`; out-param test added (m4-locomotion 9 checks).
- Full provider suite PASS; provider pushed + integrity PASS. Device runtime/GC performance NOT RUN.

## Frame pacing in status (EV-0148)

- `vrmc-status.json` adds `frameP50Ms`/`frameP95Ms`/`missed90Frames` from the last completed diagnostic
  window; the launcher provider summary shows **p95/missed90** next to ABI/bridge/hands/thermal/adaptive.
- Strict JSON test extended to 15 checks. App installed/provider pushed + integrity PASS; device K2
  pacing NOT RUN.

## reload-input completeness (EV-0151)

- Fixed: `reload-input` previously applied only gesture thresholds + hotbar range. It now also reloads
  smoothing, move origin/forward/strafe/deadzone/rotate-pulse, `tracking.holdLastPoseMs`,
  `hands.componentMode`, rebuilds pose smoothers, cancels an in-progress hotbar wheel, and reports the
  applied categories in the command result.
- Full provider suite PASS; provider pushed + integrity PASS. Device live-reload behavior NOT RUN.

## Fingertip component toggle (EV-0157)

- Launcher Input tuning adds an experimental `hands.componentMode=joints|identity` toggle; saved to
  `vrmc-input-tune.properties`, applied via Reload input/next launch (reload completeness EV-0151).
- Default identity preserves the device-accepted aim path. Build/install PASS; device visible-hands/
  held-item appearance NOT RUN.

## Reset confirmation (EV-0158)

- Destructive **Reset VRMC settings** now opens a confirmation dialog (Reset/Cancel) explaining that only
  runtime/input-tune/vignette files are removed and saves/logs/crash guard are kept.
- Shell/app build/install PASS; device dialog interaction NOT RUN.

## Diagnostics bundle completeness (EV-0159)

- Support bundle now also captures `vrmc-input-tune.properties`, `vrmc-thermal-state.txt`,
  `vrmc-vignette.flag` and the real Minecraft log `instances/default/logs/latest.log`, alongside
  shell/compositor/thermal/status/shutdown/command/heartbeat/settings/crash artifacts.
- Shell/app build/install PASS; device export/share UI NOT RUN.

## Status JSON fuzz (EV-0168)

- 100,000 random status documents with arbitrary strings (control chars, quotes, backslashes, BMP unicode,
  empty), random ints/bools and NaN/Inf/huge hotbarRange round-trip through a strict test parser with
  0 violations; shared `TestJson` parser. Status-json regression 15 checks PASS. Host only; device NOT RUN.

## Runtime-settings fuzz (EV-0169)

- 100,000 random settings maps with valid/unknown keys and empty/boolean/NaN/Infinity/huge/negative/random
  string values: no exceptions, applied values always within documented bounds.
- Full provider suite PASS. Host-only; device behavior NOT RUN.

## Command-file size cap (EV-0170)

- `VisionCommandFile.take` rejects local command files larger than **4096 bytes** before reading, deletes
  them and appends a `REJECTED oversized` result (no memory blow-up on the game thread).
- Host test covers rejection/consumption/result (m5-command 14 checks). Provider pushed + integrity PASS.
  Device behavior NOT RUN.

## Restore-performance command (EV-0178)

- Provider records original render/simulation distance and frame limit before thermal/adaptive caps; the
  new `restore-performance` command restores them once, clears applied flags/pressure counter, logs and
  shows an action-bar message (or `nothing to restore`). Launcher gains a Restore performance button.
- m5-command 15 checks; full provider suite PASS; app installed/provider pushed + integrity PASS.
  Device restore behavior NOT RUN.

## Auto status writes (EV-0182)

- Provider writes `vrmc-status.json` automatically on first update (non-null game directory) and after each
  completed diagnostic window; launcher/support diagnostics stay current without the explicit `status`
  command. No per-frame I/O added (~1 KB per 10–120 s window).
- Full provider suite PASS; provider pushed + integrity PASS. Device behavior NOT RUN.

## Auto-sprint settings (EV-0184)

- `comfort.autoSprint` (bool) and `comfort.autoSprintThreshold` (0.5–1.0, default 0.9) parsed/applied to
  Vivecraft's `autoSprint`/`autoSprintThreshold`; launcher toggle+slider. Parser 29 checks; key guard
  checked=33; app installed/provider pushed + integrity PASS. Device sprint feel NOT RUN.

## Guided hand calibration (EV-0190)

- Launcher **Calibrate hands** button runs the 9-second open/fist/pinch protocol and saves an advisory
  report; diagnostics bundle includes `vrmc-hand-calibration.txt`.
- Host tests/guards PASS; app installed/provider pushed + integrity PASS. Device calibration NOT RUN.

## Still to implement (M5 completion)

- Recenter / height / world-scale actions and persistence.
- Quality preset application review on device (render distance vs. 90 Hz floor), thermal soak.
- H1–H10 gameplay acceptance matrix (device).

## Verification

Host: `provider/tests/run_tests.sh` (m5-settings 18 checks). Shell: `scripts/build_shell.sh`.
Device: `NOT RUN` (needs D1). See VERIFY EV-0101.
