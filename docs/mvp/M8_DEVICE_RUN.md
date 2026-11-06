# M8 device verification runbook (D1)

**Status:** tooling ready; **device run NOT RUN** (D1 unavailable during implementation).
**Plan/acceptance:** [M8_PLAN.md](M8_PLAN.md) §5/§7. **Evidence:** record a new EV id in
[`VERIFY.md`](../../VERIFY.md) §6; this page is the operator procedure, not evidence.

M8 is the foveated 4K/120 rendering pipeline:

- the shell configures the CompositorServices layer with **foveation enabled** (when the layer
  supports it) and **maxRenderQuality = 1.0** (the highest the device supports; the drawable is then
  allocated at the 4K-class per-eye logical size);
- the compositor logs the rasterization-rate-map geometry and the **measured display cadence** and
  publishes the display's logical per-eye size/size state to the provider;
- the provider renders its stereo eye targets at **logical size × adaptive eyeScale** (auto default)
  instead of the old fixed 1024×1024, and resizes with hysteresis;
- **120 Hz is measured and targeted, not requested**: there is no public CompositorServices
  refresh-rate selector; the layer forbids frame repetition and the compositor reports the cadence the
  system actually presents at (`render feedback: displayHz=…`).

## 1. What you need

1. The M8 build: a **staged device-candidate app** plus the matching M8 provider jar. The last host-built
   candidate (D1 unavailable at build time, so **not yet installed/tested**) is recorded in
   [`export/m8-device-candidate.txt`](../../export/m8-device-candidate.txt):
   - app: `/tmp/VRMC-native-m8.app` — tree sha256 `aea4bd4f…`, signed, deep/strict verify PASS,
     contains the M8 shell framework + M8 bridge dylib (render-settings symbols verified);
   - provider jar: `cd80b753…` / 136,067 B (two-build reproducible), matching the M8 provider code.
   If the candidate is missing, rebuild with `scripts/build_shell.sh` (device), `MODE=device
   scripts/build_bridge.sh`, then `scripts/stage_native_app.sh <framework> <bridge dylib>` (see
   `export/m8-device-candidate.txt` for the exact invocation) and build the provider jar with
   `scripts/build_provider.sh`.
2. D1 unlocked, awake and reachable over the paired development connection
   (`xcrun devicectl list devices` must show `Apple Vision Pro … available`).
3. JIT enabled for the app in StikDebug (as in the normal launch procedure).
4. The existing instance with Vivecraft 26.2-1.3.15 + the VRMC provider jar in
   `Documents/instances/default/mods/`.

## 2. First run (defaults)

1. Install/stage the build:
   ```bash
   DEVICE=<udid> scripts/install_device.sh /tmp/VRMC-native-m8.app dev.vrmc.vrmc
   DEVICE=<udid> scripts/push_provider_jar.sh /tmp/vrmc-provider-build/vrmc-provider.jar
   ```
2. Launch the app (StikDebug JIT, then the app), let the launcher boot Minecraft, create/load a world
   and enter the immersive space.
3. Play for **3–5 minutes** and include:
   - a title/menu screen visit,
   - walking/turning and distant geometry (look at the horizon),
   - one menu/inventory open/close.
4. Quit via Minecraft's own **Quit Game** so the provider writes `destroy-complete`.
5. Pull and classify in one command:
   ```bash
   scripts/m8_device_check.sh
   # or analyse an existing pull: scripts/m8_device_check.sh --from /tmp/vrmc-m8-device
   ```
   Exit codes: 0 PASS (A6–A9), 2 PARTIAL (e.g. 90 Hz or no foveation), 3 NOT RUN (old build/logs
   missing), 4 FAIL (hard regression), 5 device unavailable/pull failed.

## 3. What the tool checks

| Row | Requirement | Log lines |
|---|---|---|
| A6 | Foveation actually active: layer configured `foveation=1`, rate-map geometry present, display geometry `rateMaps>0` | `layer configuration … foveation=1`, `foveation rate map view …`, `display geometry: …` |
| A7 | 4K-class per-eye display path + provider eye targets follow it: logical per-eye ≥ 3200×2800, provider render settings + ≥1 resize, sane resize count, final target ≥ the old 1024 baseline | compositor `display geometry` / `render feedback published`, provider `[VRMC-M8] render settings:`, `[VRMC-M8] eye target resize #…`, `[VRMC-M8] render state …` |
| A8 | Measured display cadence: 120 Hz PASS (≥117 Hz, repeats ≤20 %), else PARTIAL with the actual Hz | `render feedback: displayHz=… repeats=…` |
| A9 | Pacing/regressions: no render-feedback publication failures, no command-buffer failures, provider p95 within 1.5× the measured cadence budget | `[VRMC-M5] diag: … p95Ms=… missedTarget=… targetHz=…` |

**Required operator statement for full evidence:** whether the image looked **less blurry/jagged**
than the pre-M8 build (the old build upscaled 1024² into ~1888×1792), and whether 90→120 Hz felt
smooth. A/PASS visual statement + A6–A9 PASS is the M8 device acceptance.

## 4. Tuning / A-B if a row is PARTIAL

Files (push with `devicectl device copy to`, relaunch as noted):

| Knob | Where | Values | Applies |
|---|---|---|---|
| `vrmc-eye-scale.txt` | game dir (`Documents/instances/default/`) | `auto` (default), or a number 0.25–1.0 | live, re-read every ~600 frames |
| `vrmc-render-quality.txt` | `Documents/` (compositor) | `auto` or 0.0–1.0 (pins runtime quality) | next compositor start (relaunch) |
| `vrmc-max-render-quality.txt` | `Documents/` (shell) | 0.05–1.0 (memory upper bound) | next immersive open |
| `vrmc-foveation-off.flag` | `Documents/` (shell) | A/B: uniform rasterization (one-way on device: an app-data reset or `vrmc-clear-diagnostics.flag` restores foveation) | next immersive open |

One command for all of the above (no relaunch required for eye scale):

```bash
scripts/push_m8_render_config.sh --eye-scale 0.5            # live tuning
scripts/push_m8_render_config.sh --runtime-quality auto      # next launch
scripts/push_m8_render_config.sh --max-quality 0.75          # next immersive open
scripts/push_m8_render_config.sh --print --eye-scale auto    # offline preview
scripts/push_m8_render_config.sh --self-test                 # offline validation
```

When a knob is set back to its default, prefer the explicit value (`--max-quality default`,
`--runtime-quality default`, `--eye-scale auto`) because devicectl cannot delete files.

Interpretation:

- **A6 NOT RUN / FAIL:** if the shell log says `supportsFoveation=false` the runtime does not expose
  foveation (check you are on the M8 build; the simulator cannot). If it says `supportsFoveation=true`
  but `foveation=false`, remove `vrmc-foveation-off.flag`.
- **A7 PARTIAL:** the logical size is the device's max-quality per-eye size; if it is below 4K-class,
  check `maxRenderQuality=1.00` in the shell/compositor logs (the shell only sets it when the layer
  reports a usable default render quality; a runtime reporting `NaN` keeps the system default).
  If provider resize lines are missing, the provider did not receive the new channel
  (check the bridge dylib/provider jar are the M8 pair) or the game was never in a world long enough
  (resize waits for world-stable frames by design).
- **A8 PARTIAL at 90 Hz:** the system chose 90 Hz for this session (cadence is system-selected). Try
  reducing render cost so the app has 120 Hz headroom: set `vrmc-eye-scale.txt=0.5` (or lower) and/or
  `vrmc-render-quality.txt=0.75`, then re-run. Record the achieved cadence either way — do **not**
  claim 120 Hz without `displayHz≈120` in the log.
- **A9 PARTIAL/FAIL:** if `render feedback publish FAILED`/command-buffer failures appear, record the
  session as FAIL and keep the logs (they are hashed as evidence). If only p95 is over budget, lower
  the eye scale and re-run.
- **Resize hitch:** the first resize rebuilds every render target. If it is objectionable, pin
  `vrmc-eye-scale.txt` to a fixed value so no resizes happen.

## 5. Evidence to record

1. Run `scripts/m8_device_check.sh` and keep `/tmp/vrmc-m8-device/` (logs are copied there).
2. Record a new `EV-xxxx` in `VERIFY.md` §6 with:
   - A6–A9 statuses + the exact log lines,
   - measured `displayHz`, repeats, logical per-eye size, final provider eye target, resize count,
   - the operator visual statement (blur/jaggies/comfort),
   - the artifact paths (push them through `scripts/log_evidence.sh` for hashing).
3. Update the M8 dashboard row in `VERIFY.md` §7 and `docs/mvp/M8_PLAN.md` §4 (M8.5) when the device
   run results are recorded.

## 6. Rollback

Delete the override files above (defaults = M8 feature path). To reproduce the pre-M8 rendering cost
profile: `vrmc-foveation-off.flag` + `vrmc-render-quality.txt=0.5` + `vrmc-max-render-quality.txt=0.5`
+ `vrmc-eye-scale.txt=0.25`.
