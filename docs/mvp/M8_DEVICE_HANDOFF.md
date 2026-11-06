# M8 device-session handoff

Current state of the foveated 4K/120 work and the exact steps to finish it on D1. Device acceptance
(A6–A9 + operator visual statement) is **NOT RUN** — D1 has been `unavailable` to `devicectl` for the
whole implementation window (last connection recorded hours before these runs).

## What is already proven (host / simulator only)

| Area | Evidence |
|---|---|
| Foveation sampling maths in a real variable-rate pass (host Metal) | EV-0270 |
| Provider display-feedback → eye-target resize in a real Minecraft client | EV-0272 |
| Fovea-weighted sharpening (4× upscale metrics: 1.17× acutance, bounded, foveal taper) | EV-0273 |
| Sharpening knob A/B in the real compositor (sim) | EV-0274 |
| Host Minecraft client: display-feedback, target-cadence, content-first, SSAA knobs | EV-0272, EV-0278, EV-0279, EV-0281 |
| Resize texture-lifetime safety + grace (no sampling of destroyed textures; no pattern flash) | EV-0276, EV-0277 |
| Status diagnostics + A6–A9 classifier incl. status-only fallback | EV-0275 |
| Target-cadence guardrail (unreachable 120 Hz auto-revert) + full host/sim self-check PASS | EV-0280 |
| Combined foveated drawable + sharpening under a real rate map | EV-0282 |
| Resize-failure containment + 120 s all-knobs soak (8 resizes, 0 M8 exceptions) | EV-0283 |
| Durable device package (app + jar + checksums, rebuildable) | EV-0284 |

Nothing above proves the device panels/optics, the achieved refresh rate, or that the operator finds
the image acceptable.

## Artifacts

- Durable package: `export/m8-device-package/` (app bundle + provider jar + manifest + checksums +
  README; zip: `export/m8-device-package.zip`). Built/validated by `scripts/m8_device_package.sh`.
- Candidate manifest (identity, install/tuning/rollback): `export/m8-device-candidate.txt`.
- After a session, `Documents/instances/default/vrmc-m8-trace.csv` (pulled by the checker) holds the
  one-row-per-window resolution/refresh history for the evidence bundle.
- Staged originals (volatile /tmp): `/tmp/VRMC-native-m8.app`,
  `/tmp/vrmc-provider-build/vrmc-provider.jar`.

## Finish procedure (one command each way)

```bash
# 1. validate + install + push provider jar, prints the operator checklist
APP="$PWD/export/m8-device-package/VRMC-native-m8.app" \
PROVIDER_JAR="$PWD/export/m8-device-package/vrmc-provider.jar" \
  scripts/m8_device_session.sh prepare

# 2. operator: StikDebug JIT → launch VRMC → Play → immersive → 3–5 min (menus + distant geometry)
#    optional live A/B while playing (macOS side):
#      scripts/push_m8_render_config.sh --target-hz 120
#      scripts/push_m8_render_config.sh --content-first on
#      scripts/push_m8_render_config.sh --sharpening off     # halo A/B
#    then Quit Game with the game's own quit.

# 3. pull + classify A6–A9
scripts/m8_device_session.sh collect
```

The collector writes `/tmp/vrmc-m8-device/` and exits 0 PASS / 2 PARTIAL / 3 NOT RUN / 4 FAIL.
A6 foveation/rate maps · A7 4K-class logical size + provider eye targets · A8 measured displayHz
(+ target-cadence source) · A9 pacing/regressions. If A6/A7/A8 pass, run the A/B above once with
`--world-supersample 1.44` (relaunch) for the jaggedness question.

## What to record

Add a new `EV-xxxx` row to `VERIFY.md` and a STATUS bullet with: app tree + provider jar hashes, the
A6–A9 rows and their exact log lines, the operator visual statement (blur/jaggedness/comfort at 90 vs
120 Hz, halo impression of sharpening), and any warnings (`[VRMC-M8][WARN]`). Then update
`docs/mvp/M8_PLAN.md` §5 and this handoff's status line.

## Known fallbacks / limitations

- Unreachable target cadence: provider auto-reverts to the measured display after 8 windows and logs
  `target cadence: N Hz unreachable … reverting to auto` — change `vrmc-target-hz.txt` to retry.
- Failed eye-target rebuild: provider logs `[VRMC-M8][WARN] eye-target rebuild failed …`, keeps the
  current target and disables auto eye scale; record as a regression and relaunch.
- `--world-supersample` (SSAA) is a pure pixel-cost trade, startup-only; use it when the goal is
  image quality at 90 Hz rather than 120 Hz.
- Host load differs from the device: host harness numbers are plumbing evidence, never device claims.
