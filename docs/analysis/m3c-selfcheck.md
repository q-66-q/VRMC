# M3c self-check log (2026-11-01, operator away) — build/install/host/simulator status

Purpose: record the operator-independent verification performed after the black-immersive root cause was
found (EV-0093), so the next device session starts from a known-good, reproducible build.

## Build and install identity

| Item | Value |
|---|---|
| Repo commit | `c72218d` (stereo/alignment pattern) on top of `3f9ab0d` (depth-clear fix/EV-0093) |
| Provider jar | `/tmp/vrmc-provider-build/vrmc-provider.jar` sha256 `8e7070221ccb56acb938eb0b67d02282ad2c88e046f5f1a2fde74521f46683da` (device copy verified) |
| Bridge dylib | `/tmp/vrmc-bridge-build/libvrmc_bridge.dylib` (device build; unsigned sha256 `38624e12…`) |
| Shell framework | device xros build, `BUILD SUCCEEDED`, staged framework sha256 `6edb3b949bc1b951…` (v12) |
| Staged app | `/tmp/VRMC-native-v12-stereo.app`; `codesign --verify --deep --strict: PASS`; installed on D1 as `VRMC-native-v12-stereo.app` |
| Installed bundle | `dev.vrmc.vrmc`, url `…/Application/06226F0B…/VRMC-native-v12-stereo.app/` |

## Host self-checks (all PASS)

| Check | Command | Result |
|---|---|---|
| Provider build | `scripts/build_provider.sh` | PASS — 4 classes, jar printed + sha256 |
| Bridge build (device+host) | `scripts/build_bridge.sh MODE=both` | PASS — platform 11 retag, symbol checks incl. new sync/acquire/display-view symbols |
| Shell build | `xcodebuild … -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO` | PASS |
| App staging/signing | `scripts/stage_native_app.sh` | PASS — 169 Mach-O signed, deep verify PASS |
| Display-view frustum test | `scripts/test_display_views.sh` | PASS |
| Depth-clear regression guard | `scripts/tests/DepthClearRegressionTest.sh` | PASS — default 1.0, `vrmc-depth-zero.flag` A/B, probe reference 1.0 |
| Bridge host suite | `bridge/tests/run_tests.sh` | ALL PASS — stub, sync, TSan, display-views layout, MoltenVK+Metal timeline probe |
| M3c triage script | `scripts/m3c_pull_and_check.sh --from …` | PASS on historical pulls |
| Simulator control | real `VRMCShell.framework` in a visionOS-simulator host | PASS — immersive scene `fgActive`, `layerState=2`, bright drawable proof, stereo pattern screenshot `/tmp/vrmc-sim-shots/stereo-pattern-sim.png` |

Simulator note: the simulator displayed correctly even with the old depth clear 0.0, which is exactly why
the device A/B (EV-0093) was required; the simulator remains non-evidence for this presentation path.

## Device state prepared for the next session (EV-0094)

- Installed: `VRMC-native-v12-stereo.app` = depth-clear fix (default 1.0) + array-API present path +
  scene-activation/layer-state logging + alpha-only first-frame parking with periodic re-park + 1.8 s
  willResignActive grace + manual **Enter VR** overlay + audible first-frame canary + eye-distinct
  stereo/alignment test pattern.
- Pending `Documents/vrmc-clear-diagnostics.flag` removes stale diagnostic flags on the next launch
  (`vrmc-clear-probe`, `vrmc-depth-near`, `vrmc-legacy-single-drawable`, `vrmc-immersive-selftest`, …).
- Game-dir flag `instances/default/vrmc-capture.flag` is present → provider writes eye-target PNGs for the
  game run (pull from `Documents/instances/default/vrmc-capture/`).
- `Documents/vrmc-drawable-dump.flag` could not be pushed (device connection dropped while asleep); retry
  when D1 reconnects. Composing the next-run instruction around the manual pattern + game run is unaffected.

## Next device session checklist (operator) — EV-0094

1. Unlock/wear D1; launch VRMC; tap **Enter VR**.
   - Expect: beep, window fades, bright stereo/alignment pattern (left warm/red, right green, white fusion
     cross, corner eye marker, checker border).
   - If black: pull logs via `scripts/m3c_pull_and_check.sh` (depthZero must be 0; scene fgActive).
   - If window remains over the view: A/B with `Documents/vrmc-hide-windows.flag`.
2. Game run: StikDebug → Assign script → Enable JIT → launch VRMC → Play.
   - Expect: menu world + GUI fills the FOV, head tracking; menus dark is content (check
     `drawable proof` luma and `vrmc-capture` PNGs); top green strip = flat sampling active.
   - Record whether the game window disappeared after the first presented frame (periodic re-park).
3. Stereo: if the fusion cross is doubled, report the offset direction; if the eyes are swapped, report
   which colour each eye sees (corner marker).
4. Pull logs + readbacks; record EV-0094; then continue with window chrome / re-entry / provider GPU sync.

## Open risks for the next run

- Menu world time-of-day: a night menu world is legitimately dark; judge with the drawable proof + eye PNGs,
  not only by eye.
- Window hiding on device: alpha-only parking may not fully hide the game window; `vrmc-hide-windows.flag`
  is the A/B (simulator says isHidden is lifecycle-safe; device early logs suggested possible scene
  deactivation — the willResignActive grace now protects against a transient).
- Stereo alignment depends on provider display-view application; logs will show the applied tangents/eye
  transforms and the compositor's published tangents.
- Provider GPU sync is still deferred (bridge API ready); unsynchronized readback can show L/R probe
  asymmetries but not a black layer.
