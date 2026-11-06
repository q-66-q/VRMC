# VRMC current status & handoff (development build)

Updated: 2026-11-03 (host time; M7 data-driven accuracy iteration EV-0237; device A/B pending).
Authority remains [`VERIFY.md`](../../VERIFY.md) and the per-round evidence bundles; this page is a
navigation summary.

## Current installed build (D1)

- App: path-independent tree sha256 `2388965a1908f9630f80f77e4f5b8fc4b44ddddf58175452613182faabd375f3`
  (`/tmp/VRMC-native-releaseinput.app`, 169 signed Mach-O, deep/strict verify PASS)
- Packaged release-app provider: `a109ae5661fd726b445ed083e3cce3c00b651fe5dd89154daf501a85ec19de58`
  (92,516 bytes, two-build reproducible; M6 package integrity PASS via `scripts/m6_device_integrity.sh`).
  The D1 `mods/` provider has since been updated by the M7 pushes. **EV-0238**: the EV-0237 provider
  `d2c8a8d9…` (120,666 bytes) was pushed and round-trip/integrity verified on D1; the pre-push installed
  jar was `cf3ef0a0…` (110,857 bytes, a previous unrecorded push). App launch for the operator A/B was
  **NOT RUN** at push time (`devicectl` app launch failed with "Failed to allocate RSD device"); gesture
  behaviour is unverified and the operator session remains the acceptance gate.
- Development package: `/tmp/VRMC-dev-release.zip` bytes=206,538,366 sha256
  `4d9141f05a8993a0c5242534df4ff102aaefe6fffd7ae555bf82c06dd9e3d2af`; verifier PASS; not a final release.
- D1 is available and the latest build has now **launched successfully and been played** (EV-0212):
  immersive/hands/input active, no exceptions, 12,199 presented frames, p50 8.34 ms/p95 9.24 ms,
  clean provider teardown. It was **locked/not launched** earlier; full device acceptance remains pending.

## Milestones

| Milestone | State |
|---|---|
| M1 environment/toolchain | CLOSED (EV-0043/0044/0052/0057) |
| M2 JVM/Minecraft/immersive bootstrap | CLOSED (EV-0094) |
| M3 presentation/stereo | DEVICE PASS (EV-0093/0094); M3c extras host/build PASS |
| M4 hands input | W1 device PASS (EV-0096); W2–W5 host PASS; device tuning/AC-4 NOT RUN |
| M5 settings/comfort/diagnostics | **PASS (operator-attested prior session, EV-0258)**; M6 AC/K NOT RUN |
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
200k pose fuzz, 100k smoother fuzz, 500k gaze fuzz, 100k JSON fuzz, 100k settings fuzz — 0 violations;
release check PASS; package verifier/freshness PASS; release-ready host gates PASS (acceptance NOT READY).

## M7 simplified gesture engine (EV-0228 → EV-0237)

- Pure-Java `VisionM7Gesture` + VisionVR dispatch; default `gesture.mode=m7`, fallback `m4`.
- **2026-11-03 (EV-0237): data-driven accuracy iteration.** All 14 Gesture Lab datasets were analysed
  by two independent scripts/reports, replayed through the real engine (90 Hz + raw) and scored by an
  independent evaluator. The engine now uses fitted thresholds/hysteresis, head-frame geometry, item/
  climb game context, windowed speeds and a dt-corrected head baseline. Host: 73 synthetic checks +
  200k-frame fuzz ALL PASS; literal replay gate **20/24 rows (baseline 12/24)**, context suppression
  9/9. Residual literal rows and root-cause analysis: `M7_ACCURACY_ITERATION.md`.
- **The EV-0237 provider was NOT pushed to D1**: the installed device provider remains the EV-0236 jar,
  so no device behaviour is claimed for the new engine. Device A/B is the remaining acceptance gate
  (`M7_PLAN.md`).
- Rollback path prepared (`gesture.mode=m4` in tune, read back); **step 0 playability NOT RUN**.
- 2026-11-02 EV-0236: menu/inventory false triggers (inventory once, menu/hotbar glitches, pinches too
  sensitive) addressed with pinch debounce/arming, GUI close via onClose, menu/hotbar suppression and a
  head-ray cursor; device retest was still pending when EV-0237 landed.
- 2026-11-02: first M7 GUI-cursor build crashed on launch (runtime-missing WindowExtension method);
  fixed in EV-0235. Hand-tracking dropouts remain an ARKit/visibility issue.
- **Device A/B NOT RUN**; GUI eye-hover/drag remain known gaps (climb now has runtime context).

## First successful device session (EV-0212)

- Operator launched and played; no exceptions in latestlog.
- Both hands tracked, input healthy, player present, display views live.
- 12,199 compositor frames (flat mode, eyes=1, anchor=1), 0 frames without drawable/encoder.
- Frame stats: p50 8.34 ms, p95 9.24 ms, missed90 3/3586.
- Clean `destroy-complete` with no teardown exception; thermal nominal.
- Full H1–H10/AC/K checklist is still not recorded; this is a smoke/partial device PASS, not final acceptance.

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
- A lite app variant with JRE pruning is an experimental K6 option (app ~246 MB vs ~584 MB) but is
  **not installed/default** until device launch is validated.
- Development package is not a release manifest sign-off.

## 2026-11-05 latest M7 mapping (EV-0249)

- Movement: left thumb-index pinch hold + move left hand (analog free-move); both-fist swing no longer moves.
- GUI: right pinch = left mouse button; hold = long press/drag; release lifts.
- Head-ray cursor offset 8% down.
- Teleport shares left pinch, suppressed while moving; dedicated teleport gesture still needed.
- Provider `a337481f…` pushed/verified; device movement/cursor/GUI retest pending.

- 2026-11-05 EV-0250: M7 movement made player-relative (HMD horizontal basis) after operator observed
  world-absolute forward; provider `85d18f61…` pushed/verified. Device retest pending.

- 2026-11-05 EV-0251: movement failure root-caused to same-pinch teleport + lateral neutral offset +
  right-axis sign. Fixed and provider `90a724fc…` pushed; device movement retest pending. Teleport is
  temporarily unbound from the left pinch.

- 2026-11-05 EV-0253: **M7 movement device PASS** (left pinch player-relative stick; no teleport override). Other M7 actions/M5/M6 device gates remain.

- 2026-11-05 EV-0256: **M7 short-pinch attack/place/use + hold-break + hotbar stability device PASS.** Teleport remains unbound; bow/eat/climb and M5/M6 device gates remain.

- 2026-11-05 EV-0257: **M7 core scope device PASS**; teleport descoped by operator. Remaining: M5/M6 acceptance and hand-tracking dropout metrics.

- 2026-11-05 EV-0258: M5 loop recorded as **operator-attested PASS** (tested previously; current-build re-run waived). M6 AC/K remains.
