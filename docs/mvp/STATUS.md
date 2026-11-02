# VRMC current status & handoff (development build)

Updated: 2026-11-02 (host time). Authority remains [`VERIFY.md`](../../VERIFY.md) and the per-round
evidence bundles; this page is a navigation summary.

## Current installed build (D1)

- App: path-independent tree sha256 `2388965a1908f9630f80f77e4f5b8fc4b44ddddf58175452613182faabd375f3`
  (`/tmp/VRMC-native-sprint.app`, 169 signed Mach-O, deep/strict verify PASS)
- Provider: `a109ae5661fd726b445ed083e3cce3c00b651fe5dd89154daf501a85ec19de58` (92,516 bytes),
  reproducible (two-build check) and **device integrity PASS** via `scripts/m6_device_integrity.sh`
- Development package: `/tmp/VRMC-dev-release.zip` bytes=206,479,055 sha256
  `9540a8a947a2f360742b7c7f958474b975eab2132da74e944d2792aa8287a7ac`; verifier PASS; not a final release.
- D1 is currently **locked**; latest build has not been launched since install. All behavior/acceptance
  gates remain **NOT RUN**.

## Milestones

| Milestone | State |
|---|---|
| M1 environment/toolchain | CLOSED (EV-0043/0044/0052/0057) |
| M2 JVM/Minecraft/immersive bootstrap | CLOSED (EV-0094) |
| M3 presentation/stereo | DEVICE PASS (EV-0093/0094); M3c extras host/build PASS |
| M4 hands input | W1 device PASS (EV-0096); W2–W5 host PASS; device tuning/AC-4 NOT RUN |
| M5 settings/comfort/diagnostics | host/build PASS; device acceptance NOT RUN |
| M6 hardening/release | host hardening/release gates PASS; device AC/K gates NOT RUN |

## Implemented feature summary

- Hands-only immersive input: pinch/fist families, middle-pinch locomotion, snap turn, jump/sneak,
  radial, climb jump, direct hotbar wheel, use-hold/bow, climb, recenter, teleport + interaction.
- Safety: release-on-tracking-loss/stale, no stuck actions, both-fist/use/attack/teleport conflict
  priorities, pause/reload, tracking-dropout pose hold, tuning validation.
- Comfort/settings: seated/free-move/HMD pointer, turn angles, world scale, height, presets, render/
  simulation distance, frame limit, VSync, vignette, adaptive framerate, thermal response/reduction and
  explicit restore, recenter/height commands, live input reload.
- Diagnostics: status JSON (tracking, hands, pacing, thermal, bow, climb, input tuning), in-game
  controls help, launcher recent-diagnostics/status, capped support bundle, heartbeat watchdog,
  crash guard/safe mode, thermal state, device provider-integrity and diagnostics pull.
- Release engineering: reproducible provider jar, path-independent app hash, clean manifest/package,
  package verifier, stale-package guard, settings/status parity guards, acceptance gate, single command
  `scripts/m6_release_ready.sh`.

## Verification commands (host)

```
scripts/build_shell.sh
provider/tests/run_tests.sh
bridge/tests/run_tests.sh
scripts/m6_release_check.sh
scripts/m6_acceptance_report.sh --require-pass   # currently NOT READY (device gates)
scripts/m6_release_ready.sh --zip /tmp/VRMC-dev-release.zip   # currently NOT RELEASE READY
```

Latest host results: provider suite ALL PASS; bridge suite incl. TSan ALL PASS; 1M-frame input fuzz,
200k pose fuzz, 100k smoother fuzz, 100k JSON fuzz, 100k settings fuzz — 0 violations; release check
PASS; package verifier/freshness PASS.

## What remains (device only, D1)

1. `M5_DEVICE_RUN.md` — gameplay/comfort/diagnostics loop.
2. `M6_DEVICE_RUN.md` — AC-1…AC-6 / K1…K6 (soak, timing, latency, thermal, install size).
3. Tune real-hand thresholds/feel, visible-hands/held-item appearance, two-hand bow/climb.
4. Record evidence in VERIFY; run `scripts/m6_acceptance_report.sh --require-pass` until READY, then
   rebuild the final package from the release commit and re-run the release gate.

## Known risks

- Latest build is **unlaunched**; presentation/input regression risk can only be excluded on D1.
- Simulator currently backgrounds the app immediately before compositor logs, so it is not evidence.
- `hands.componentMode=joints` remains experimental/opt-in (device visual result unknown).
- Development package is not a release manifest sign-off.
