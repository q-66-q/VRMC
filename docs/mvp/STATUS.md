# VRMC current status & handoff (development build)

Updated: 2026-11-05 (host time; M8 foveated 4K/120 rendering implemented — host/simulator verified,
device verification NOT RUN; M7 M6 release-ready evidence unchanged).
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
| M8 foveated 4K/120 rendering | **host/simulator PASS** (foveation + max render quality layer config, render-feedback bridge channel, adaptive provider eye targets, resize-safety + frame-cadence diagnostics); **device tooling ready** (`scripts/m8_device_check.sh` + [M8_DEVICE_RUN.md](M8_DEVICE_RUN.md)); **device NOT RUN** — [M8_PLAN.md](M8_PLAN.md) |

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

- 2026-11-05 EV-0260: operator accepted reduced 10-min soak as PASS; relaunches not product defects. EV-0261: bow works with open hands held apart; menu-hand gray box shifted onto the hand. Provider `fac54efa…` pushed.

- 2026-11-05 EV-0263: bow visual orientation remains wrong (parallel); accepted as non-blocking known bug per operator. Bow draw/fire works.

- 2026-11-05 EV-0264: acceptance consolidation — AC-2/AC-3/AC-4/K1/K2 PASS (operator + device logs), AC-5/K4 waived PASS, M5 all PASS. Remaining PARTIAL: AC-1 clean install, AC-6 legal, K3 latency rig, K5 thermal step-down, K6 cold install time.

- 2026-11-05 EV-0265: cold uninstall/reinstall done for AC-1 (23.66 s, app data empty); AC-6 operator sign-off + host legal checks PASS; K6 PASS. AC-1 first-run/world pending; package otherwise release-ready at 21/22.

- 2026-11-05 EV-0266: **AC-1 device PASS** on fresh install (world session, 21 mods, clean destroy-complete, p50 8.34/p95 9.21, missed90=0). Caveat: fresh install required manual Vivecraft/provider jar installation; launcher auto-provisioning is a known gap. Acceptance now 22/22.

- 2026-11-05 EV-0266: **RELEASE READY** development package (22/22 acceptance). zip `0fa384d9…` 206,567,700 bytes; app `a4663e16…`, provider `4e92b306…`. Caveats: K3 waived; fresh install needs manual Vivecraft/provider restore; bow visual known bug.

- 2026-11-05 EV-0267: device application cleaned for handoff — app uninstalled/reinstalled; `Documents` and `tmp` containers empty (0 files); only system `Library/Caches`+`Preferences` remain. Test worlds, accounts, mods/provider, crash reports, tuning/status/config/logs removed. Release package/evidence remain outside the app.

- 2026-11-05 EV-0268: **M8 foveated 4K/120 rendering implemented (host/simulator)**. Root cause of
  the operator's "resolution too low + jaggedness": the provider rendered a fixed **1024x1024** eye
  target into a ~1888x1792 per-eye drawable (~1.84x upscale), and the layer had foveation disabled at
  the default render quality. M8: the shell requests foveation when the layer supports it, sets
  `maxRenderQuality=1.0` (default) and the compositor starts its runtime quality there; the compositor
  logs foveation/rate-map geometry, measures display cadence and publishes a new 68-byte
  `vrmc_render_settings` native-shared payload; the provider sizes its stereo eye targets from the
  display's logical per-eye size with an adaptive `eyeScale` (auto default, file/JVM knob) and resizes
  with hysteresis. "4K in both eyes" is now the display-path target (max render quality + foveation);
  "120 Hz" is measured/targeted (`minimumFrameRepeatCount=0`, `displayHz=` log) because there is no
  public CompositorServices refresh-rate selector. Engine-side foveation is deferred
  (MoltenVK 1.4.3 has no `VK_KHR_fragment_shading_rate`). Bridge/provider host suites PASS; simulator
  `render` scenario PASS (plumbing only). **Device A6–A9 NOT RUN (D1 unavailable).**

- 2026-11-05 EV-0269: **M8 round 2 — resize-safe provider eye targets + device verification tooling.**
  Provider eye-target resizes are gated to a stable state (menu room, or a loaded level stable for
  ≥120 frames; 240-frame rate limit) so the render-target rebuild never lands in world loading; the
  auto eye-scale takes 0.10 steps under strong headroom; frame stats track `missed90` and
  `missedTarget` (measured cadence) separately, and the periodic diag/render-state lines carry
  `targetHz/displayHz/foveation/rateMaps/logical/eyeTarget/scale/resizes`. Added
  `scripts/m8_device_check.sh` (+python analyser and a host test for PASS/90 Hz/old-build/FAIL) and
  `docs/mvp/M8_DEVICE_RUN.md` so the next D1 session yields A6–A9 in one command. Host/sim ALL PASS
  (provider suite m8-render 49 checks; classifier 4/4 outcomes; M3c fast self-check; simulator suite
  flat/sync/hidepark/nopark/pattern/input/render PASS). **Device A6–A9 still NOT RUN (D1
  unavailable)** — no 4K-class/foveation/120 Hz device claim yet.

- 2026-11-05 EV-0270: **M8 foveation rendering-model host probe (real Metal rate map) PASS.** Added
  `runtime/probes/m8-foveation/run.sh`: the compositor's full-screen `vmain`+`fmain_flat` sampling
  math is rendered into a real macOS `MTLRasterizationRateMap` pass (0.5 periphery / 1.0 centre;
  1920×1080 logical → 1488×848 physical). The logical centre maps exactly to the pattern's white
  centre cross and the logical upper-left quarter to the red quadrant (NDC→UV stays logical under
  variable rate); the physical-size-viewport negative control corrupts the foveal centre, proving the
  screen-size viewport convention the compositor uses. 6/6 checks, wired into `scripts/m3c_selfcheck.sh`.
  Host Metal only — device eye-tracked foveation/optics/cadence (A6–A9) remain NOT RUN. The rendering
  model was cross-checked against Apple VRR docs, the public *Drawing Graphics on Apple Vision*
  article and Qt's visionOS qrhimetal rate-map viewport fix (M8_PLAN §8).

- 2026-11-05 EV-0271: **M8 device candidate staged and verified (host).** Built the M8 device shell
  framework + M8 device bridge (render-settings symbols) and staged a signed app
  `/tmp/VRMC-native-m8.app` (tree `aea4bd4f…`, `codesign --verify --deep --strict` PASS, 169 Mach-O +
  6 frameworks, profile provisions D1) with the matching provider jar `cd80b753…` (136,067 B,
  two-build reproducible). Added `scripts/push_m8_render_config.sh` (offline self-test + `--print`
  preview PASS) and `export/m8-device-candidate.txt` with install/tuning/rollback commands. D1 install
  attempt fails with `CoreDeviceError 4016` (device unavailable) → **device install/A6–A9 NOT RUN**;
  the candidate is ready to install when the headset is reachable.

- 2026-11-05 EV-0272: **M8 host Fabric harness PASS (host GL).** Added `scripts/m8_host_harness.sh`
  and [M8_HOST_HARNESS.md](M8_HOST_HARNESS.md): the real M8 provider runs inside a real Minecraft 26.2 +
  Fabric + Vivecraft desktop client while a host test bridge dylib feeds fake 3660×3200 / foveation=1 /
  120 Hz display geometry through the real native-shared channel. The provider starts at 1024×1024 with
  no feedback, then resizes its stereo eye targets **1024×1024 → 1832×1600** through Vivecraft's
  `Reinit Render` path and ramps the auto eye scale (0.60 → 2200×1928, 0.70 → 2568×2248) at the
  240-frame cadence with **0 M8 exceptions**. This de-risks the provider part of device row A7 (host
  desktop GL, fabricated feedback, menu room only — **not** device/Vulkan/optics evidence).

- 2026-11-05 EV-0273: **M8.6 foveated sharpening for sub-native 4K/120 rendering (host Metal + sim
  PASS).** When the provider renders below the display's logical per-eye size (the normal 120 Hz case),
  the compositor's flat sampling pass now applies a CAS-lite, fovea-weighted 5-tap sharpening pass
  (`fmain_flat_sharp`, auto strength from the upscale ratio capped 0.45, anti-halo clamp, periphery
  tapered) controlled live by `Documents/vrmc-sharpening.txt` (`auto`/`off`/fixed) and reported as
  `sharpen=` in the cadence summary. Host Metal probe on a 4× upscale: edge acutance **1.17×**, mean
  absolute change 0.0158 (bounded), centre gain **1.27×** vs corner **1.00×** (foveal taper) — 10/10
  checks. Simulator `render` scenario PASS with the real sharpening pipeline active (47 publications;
  known pattern unchanged). Push script gained `--sharpening` (21 self-test checks); self-check PASS;
  **device candidate rebuilt and signed** (tree `53184ffe…`, framework `b1f48c2f…`, provider
  `cd80b753…`). **Device A6–A9 still NOT RUN (D1 unavailable)**; device halo/comfort judgement remains.

- 2026-11-05 EV-0274: **One-command M8 device session + sharpening knob A/B (host/simulator).**
  Added `scripts/m8_device_session.sh`: `prepare` validates the staged candidate (codesign
  deep/strict + app-tree/provider hashes against `export/m8-device-candidate.txt`), installs the app,
  pushes the matching provider jar and prints the operator checklist; `collect` pulls and classifies
  A6–A9 (A6 foveation/rate maps, A7 4K-class logical size + provider targets, A8 measured cadence,
  A9 pacing). Tested: `--dry-run` validates `53184ffe…`/`cd80b753…` and prints the exact commands;
  unavailable D1 → clear exit 5; `--from` pull classifies correctly. The simulator render scenario
  gained `SHARPEN=<off|auto|0.05..1.0>`: `off` → no sharpening / `sharpen=0.00`; `0.30` → fixed
  strength 0.30 / `sharpen=0.30`; both scenarios PASS with the known pattern unchanged. The remaining
  work is the D1 session itself — now one command each way.

- 2026-11-05 EV-0275: **M8 diagnostics status render summary + device-check fallback (host PASS).**
  `vrmc-status.json` now carries the M8 renderer/display state (`render`: eye target, display logical
  size, drawable, foveation, rate maps, measured display Hz, eye scale auto/fixed, resize count, valid)
  alongside the existing frame p50/p95/missed counters. The A6–A9 classifier uses this as a fallback
  when compositor/provider logs have rotated away, and prints it in the report; the synthetic
  classifier test now covers a status-only pull that classifies **PASS**. Provider suite ALL PASS
  (status JSON strict/fuzz updated; jar `89a5910f…`, 136,399 B, two-build reproducible); M3c fast
  self-check PASS. **Device A6–A9 still NOT RUN**; candidate manifest provider hash updated.

- 2026-11-05 EV-0276: **M8 resize texture-lifetime safety (host PASS).** The provider now clears the
  shared eye frame immediately before each eye-target rebuild, closing the only unsafe window that
  M8's dynamic resizes introduced (the compositor could otherwise acquire the old eye VkImages between
  `destroyBuffers` and the next submit; it already retains in-flight textures). Real Minecraft host
  Fabric harness: resize #1 `1024x1024 -> 1832x1600` and #2 `-> 2200x1928`, each preceded by the
  `cleared the shared eye frame before the eye-target rebuild` line, **0 M8 exceptions**; provider
  suite ALL PASS; provider jar `e9a08c52…` (136,579 B, two-build reproducible). The compositor may show
  its fallback pattern for one or two frames per resize — documented in M8_DEVICE_RUN with the
  fixed-eye-scale rollback. **Device A6–A9 still NOT RUN (D1 unavailable).**

- 2026-11-05 EV-0277: **Compositor resize grace (simulator PASS).** When the provider clears the
  shared eye frame before an eye-target rebuild, the compositor now keeps the last sampled
  `MTLTexture` pair retained and reuses it for up to 30 frames (one stale frame), instead of flashing
  the procedural test pattern for the 1–2 frames of every dynamic resize; longer gaps fall back to the
  pattern and log the grace expiry, and recovery is logged when eyes return. New simulator `eyedrop`
  scenario (provider withholds the eye frame for 60 acquires, then resumes with a bumped generation):
  reuse → expiry → recovery ordered, compositor survived, final known pattern PASS; `render`
  regression PASS. The device candidate was rebuilt with the new framework (tree `6773acf1…`,
  framework `d53e148a…`, provider `e9a08c52…`, codesign PASS). **Device A6–A9 still NOT RUN.**

- 2026-11-05 EV-0278: **M8 target-cadence override — pursue 120 Hz explicitly (host PASS).** New
  game-dir knob `vrmc-target-hz.txt` (`auto` default, or 60..120 Hz, re-read live): the auto
  eye-scale policy now aims at the configured frame deadline (e.g. 8.33 ms for 120 Hz) instead of only
  the cadence the compositor measured (90/96/100/120 chosen by the system), so the provider can keep
  frames inside the shorter deadline and the system may promote the display. The achieved rate is still
  measured and reported (compositor `displayHz`), never assumed; the target is logged, in render state
  and in `vrmc-status.json`, and the device checker reports it without using it for classification.
  Verified with 27 new provider checks, `--target-hz` in the push script (30 self-test checks), and a
  real Minecraft Fabric harness run with `TARGET_HZ=100` (`target cadence: 100 Hz (file)…`, resize
  path unaffected); provider jar `144d47a7…` (137,501 B, two-build reproducible). **Device A6–A9 still
  NOT RUN.**
