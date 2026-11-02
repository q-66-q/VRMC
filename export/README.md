# VRMC — native immersive integration — **RESOLVED** (M3c visual acceptance PASS)

**Date:** 2026-11-01
**Status:** **RESOLVED.** The black-immersive blocker is closed and on-device visual acceptance passed:
stereo/alignment pattern and a live JIT game render in the immersive space with stereo aligned and head
tracking active (EV-0094, operator-confirmed). Root cause of the black immersion: the M3b drawable depth
clear had been changed from 1.0 to 0.0, which visionOS 27.2 presents as a black immersive layer (EV-0093).

## Acceptance evidence (EV-0094)

- Manual immersive: operator confirmed the eye-distinct stereo pattern (fusion cross, per-eye tint,
  checker border); drawable readback L mean luma 110.4 / R luma 110.4, centre ~171, nonBlack 4096/4096.
- JIT game run: `VRMCGameStarted 05:04:02 UTC` -> auto `openImmersiveSpace result=opened 05:04:17` ->
  first presented frame -> `VRMCCompositorRunning`; windows parked `alpha=0.00`; `depthZero=0`;
  `mode=flat`; provider eye textures live (mean luma 46 -> 35 -> 109 -> 156 as MenuWorlds world59
  rendered); display views applied exactly (e.g. `Lpos=(-0.0328,-0.0265,-0.0347)`
  `Rpos=(0.0316,-0.0246,-0.0347)`, `ipd 0.0645`); drawable proof luma 35 -> 118 -> 129; first command
  buffer completed; no failures; tracking frames present.
- Operator: “the game launched successfully! the eyesight is aligned and it shows the game properly in
  immersive!”
- Session ended by operator at 05:04:34 UTC (headset off/crown) after confirming the view.

## Root cause of the black immersive (EV-0093)

M3b changed the CompositorServices drawable **depth clear** to 0.0 (interpreting “0 = infinitely far”
in isolation). On visionOS 27.2 that makes the whole immersive layer present black even though the colour
drawable is bright and the command buffer completes. Controls: known-good M3a probe (depth 1.0) displays;
minimal-window/deprecated-API/pure-SwiftUI builds with depth 0.0 are black; same build with depth 1.0
shows bright content. Fix: default depth clear **1.0**, `vrmc-depth-zero.flag` A/B, and
`scripts/tests/DepthClearRegressionTest.sh` PASS.

## Alignment/position fix (macstream reference, EV-0088/EV-0090)

Per macstream `VERIFY.md` Phase 8 root causes 3+4:
- eye matrices are **head-relative** (`cp_view_get_transform`) and rendered by the provider on
  `hmdPoseLeftEye`/`hmdPoseRightEye`;
- the provider renders the headset's **asymmetric per-eye FOV** (`cp_view_get_tangents`) with cached
  projection invalidation (`lastFarClip`/`lastReverseFarClip = NaN`);
- display views are published per-eye interleaved (`L t@0, L m@16, R t@80, R m@96, ipd@160`; a
  grouped-vs-interleaved JNI bug that corrupted the left eye was fixed in EV-0090, with a layout test);
- compositor uses flat 1:1 eye-texture mapping once display views are applied.

## What works now on D1

- Native launcher UI -> Play -> JIT game
- Auto-open immersive space; game window content parked (alpha 0) and chrome hidden
- Live Minecraft rendered in the immersive space with **stereo aligned** and **head tracking active**
- No command-buffer failures; provider eye textures and drawable both non-black

## Remaining work (not part of this closure)

- M4 input (hands) — needed to actually play
- Window chrome on/off behaviour polish
- Background -> foreground re-entry device check
- Provider GPU-timeline sync device run (flag-gated, host PASS)
- M3-W5/W6: 90 Hz pacing/thermal, 10-minute soak, acceptance

## Evidence / logs in this folder

- `evidence/EV-0090.md` … `evidence/EV-0094.md` — layout fix, M3c plan/root cause/acceptance
- `logs/ev0094/` — step1 pattern + game-live compositor/shell/latestlog, drawable metas, triage,
  operator reports
- `logs/` (older) — M3b/EV-0086 reproduction evidence, retained as history
- Runbook: `docs/mvp/M3C_DEVICE_RUN.md`; flag reference: `docs/mvp/M3C_FLAGS.md`


---

Older M3b-era evidence (EV-0086 black reproduction, display-view first runs) is retained in
`logs/` and the repository history; it is superseded by the EV-0093/EV-0094 closure above.
