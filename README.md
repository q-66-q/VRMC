# VRMC — Minecraft VR on Apple Vision Pro

VRMC runs **Minecraft: Java Edition 26.2 + Fabric + the real Vivecraft mod natively on Apple
Vision Pro**, with head-tracked stereo and ARKit hand-tracked input. There is no PC and no
streaming.

This is a **development/sideload** project, not an App Store submission.

## Current status

- **M7 hand-input mapping: device PASS**
- **M5/M6 acceptance: 22/22 rows PASS** ([`docs/mvp/M6_ACCEPTANCE.md`](docs/mvp/M6_ACCEPTANCE.md))
- **Release gate: RELEASE READY** (`scripts/m6_release_ready.sh --zip …`)
- **M8 foveated 4K/120 rendering: host+simulator PASS; DEVICE PARTIAL 2026-11-07 (foveation + 4K-class per eye + sharpening/colour/boat PASS; 90 Hz platform cap, 120 Hz not attainable for custom immersive rendering)** —
  [`docs/mvp/M8_PLAN.md`](docs/mvp/M8_PLAN.md). The hashes/package below describe the **last
  release-ready build (pre-M8)**; the M8 provider jar (`2cc9626a…`, 144,529 B, reproducible) and the
  rendering pipeline have no device acceptance yet. Device verification is a one-command classify:
  `scripts/m8_device_check.sh` (runbook [`docs/mvp/M8_DEVICE_RUN.md`](docs/mvp/M8_DEVICE_RUN.md)).
  The compositor's foveation sampling path is validated on host Metal against a real rasterization
  rate map plus its M8.6 foveated-sharpening upscale metrics and the combined foveated-drawable +
  sharpening pass ([probe](runtime/probes/m8-foveation/README.md)), by a cross-language render-feedback ABI
  fixture (C struct -> Java parser), by a 120k-case payload fuzz test and classifier robustness cases, and by
  an upscale quality ladder
  ([probe](runtime/probes/m8-quality-ladder/README.md): PSNR/acutance per eye-target scale), with a generated
  device tuning guide ([`M8_TUNING.md`](docs/mvp/M8_TUNING.md): budgets + A/B commands),
  and the provider's display-feedback → eye-target resize path is validated in a real Minecraft client
  ([host Fabric harness](docs/mvp/M8_HOST_HARNESS.md)), including the resize texture-lifetime safety
  and the compositor's resize grace (no test-pattern flash during an eye-target rebuild; simulator
  `eyedrop` scenario), and the provider can be aimed at 120 Hz explicitly (`vrmc-target-hz.txt`,
  live; achieved rate still measured) with an opt-in content-first governor that keeps the 4K-class eye
  target by cutting scene cost first (`vrmc-content-first.txt`) and a startup super-sampling knob for
  jagged edges (`vrmc-world-supersample.txt`, SSAA — Minecraft 26.2 has no MSAA); a signed M8 device
  candidate is staged and ready to install
  ([`export/m8-device-candidate.txt`](export/m8-device-candidate.txt)), and a durable handoff package
  (app + provider jar + checksums, `scripts/m8_device_package.sh`) plus
  [`M8_DEVICE_HANDOFF.md`](docs/mvp/M8_DEVICE_HANDOFF.md) capture everything needed to finish on the
  headset; the next device session is one command each way (`scripts/m8_device_session.sh prepare` /
  `collect --report`), with device eye-tracked foveation and cadence still unverified.
- Current provider: `4e92b3067c1bb67ba1d00ce35d70bbb3cf14d83faa3a7b6ba23fd20a755d5351`
  (127,258 bytes)
- Current app tree: `a4663e16b8dc57d16c67ccd72be770f15f2846dc0fdb3c913fa5203283ba7bfb`
- Current development package:
  `sha256 0fa384d9a40e1a3b001799d6d3b376ddb1de67a09d4b201abaa99236a45ca764`,
  206,567,700 bytes. See [`export/release-package-dev.txt`](export/release-package-dev.txt).

Evidence authority: [`VERIFY.md`](VERIFY.md). Navigation summary:
[`docs/mvp/STATUS.md`](docs/mvp/STATUS.md).

## What works

### Interaction (M7)

- **Look/head ray** drives the IDE cursor; cursor sits slightly below view centre for bottom-row
  selection.
- **Short right pinch** — GUI left-click; in world: attack an entity, or place/use on a block.
- **Hold right pinch (≥350 ms)** — break/mine; release stops.
- **Left pinch hold + move left hand** — player-relative movement (forward/back + strafe).
- **Left fist tap** — open/close menu.
- **Both-fist tap** — inventory; **right pinch** picks up/places stacks.
- **Right-hand swing** — alternate attack.
- **Head rise/lower** — jump/sneak.
- **Hotbar** — touch the rendered bar with the right index fingertip; air index tap fallback.
- **Both hands apart (bow held)** — draw; release by opening the back fist or bringing hands
  together to fire.
- **Right hand near head** — eat/drink; alternating closed hands — climb.

Teleport was **descoped** by the operator. Bow draw/fire works, but the bow **visual orientation**
is a known non-blocking bug (it renders parallel to the hand; see EV-0263).

### Runtime

- Native visionOS shell + CompositorServices immersive presentation
- On-device JVM with JIT (StikDebug), Minecraft 26.2, Fabric, Vivecraft
- LGPL VRMC provider mod (M7 gesture engine + Vivecraft integration)
- ABI v3 bridge: hand tracking, eye handoff, display views, immersive input
- Crash guard, clean-shutdown journal, diagnostics bundle, comfort/settings/acceptance checklist

## Stack

| Component | Version |
|---|---|
| Minecraft Java | 26.2 |
| Java runtime | 25.0.4 (bundled) |
| Fabric loader | 0.20.1 on the tested instance (pin in [`versions.env`](versions.env)) |
| Vivecraft | 26.2-1.3.15 |
| visionOS | 27.x |

Pins are in [`versions.env`](versions.env). Third-party reference sources and vendor build trees
are intentionally not committed.

## Install / run

VRMC is a sideloaded development app. A provisioning profile that matches the target Apple Vision
Pro is required; the app must be signed for that device.

1. Install the app (or unpack the development package).
2. Open **StikDebug**, enable JIT for the app, then launch VRMC.
3. The launcher creates the Minecraft/Fabric instance. On every start the shell **auto-provisions**
   `Documents/instances/default/mods/` (`runtime/native-shell/Sources/ModProvisioner.swift`):
   - **VRMC provider** — installed from the app bundle (`<app>/vrmc/vrmc-provider.jar`, embedded by
     `scripts/stage_native_app.sh`) when missing, and upgraded when the app ships a newer one. A jar
     you pushed yourself (`scripts/push_provider_jar.sh`) is never overwritten; create
     `Documents/vrmc-provider-reset.flag` to force the bundled jar back.
   - **Vivecraft** is **not redistributed**. Download `vivecraft-26.2-1.3.15-fabric.jar` from the
     Vivecraft project and save it to *On My Apple Vision Pro › VRMC* in the Files app (or AirDrop it).
     It is moved into `mods/` only if its sha256 matches the pin in [`versions.env`](versions.env):
     `e63aeed1a6b36a55fc38c7633acbbac2cdf8b46f546382c6a2cd9348440b58bb`; anything else is rejected
     and left in place.
   - The launcher's **Mods** panel shows the result (ready / action needed, duplicate-jar warnings)
     with a *Re-check mods* button; the diagnostics export includes the same lines.
4. Manual fallback (builds staged without an embedded provider, or the pre-provisioning app): copy
   both jars into `Documents/instances/default/mods/` yourself.
5. Launch the Fabric instance, create/load a world, and enter immersive mode.

The installed app on D1 is currently in a **clean, freshly-installed state** (no account, worlds,
mods, logs or test data).

## Build / test

The repository contains source, docs, scripts and release metadata. Third-party reference trees,
vendor builds and staged app artifacts were removed to keep the repo clean; restore/fetch those
external inputs before rebuilding.

Device and signing scripts read your device UDID, team ID and signing identity from
`scripts/local.env` (git-ignored): `cp scripts/local.env.example scripts/local.env` and fill it in, or
export `VRMC_DEVICE_UDID` / `VRMC_TEAM_ID` / `VRMC_SIGN_IDENTITY`. XcodeGen projects take the team from
`VRMC_TEAM_ID`.

```bash
scripts/build_provider.sh              # provider mod jar
scripts/build_shell.sh                 # native visionOS shell
scripts/build_bridge.sh                # ABI v3 bridge
provider/tests/run_tests.sh            # host provider suite (pure-Java subset if no MC jar)
runtime/native-shell/tests/run_tests.sh  # shell host suite (mod provisioning policy + pin guard)
scripts/m6_release_check.sh            # release/licensing/source checks
scripts/m6_release_ready.sh --zip …    # full host + acceptance gate
```

Host tests are **not** device evidence. Device-only claims are recorded in
[`VERIFY.md`](VERIFY.md).

## Repository layout

| Path | Purpose |
|---|---|
| [`AGENT.md`](AGENT.md) | Operating manual, architecture, milestone rules |
| [`VERIFY.md`](VERIFY.md) | Requirements, test suites, evidence log |
| [`docs/mvp/`](docs/mvp/) | MVP plans, acceptance, device runbooks |
| [`provider/`](provider/) | LGPL-3.0 Vivecraft companion mod + M7 gesture engine |
| [`runtime/`](runtime/) | visionOS shell, CompositorServices compositor, probes |
| [`bridge/`](bridge/) | Native VR bridge (ABI v3) |
| [`scripts/`](scripts/) | Build, test, release and diagnostics tooling |
| [`assets/`](assets/) | Branding and Vulkan headers |
| [`export/`](export/) | Tracked summaries, release metadata, acceptance readiness |
| [`evidence/`](evidence/) | Local acceptance evidence bundles referenced by `VERIFY.md` |

## Known issues

- **M8 rendering is not device-verified yet:** foveation is requested when the layer supports it and
  the display path is configured for maximum render quality; the provider sizes its eye targets from
  the compositor's logical display feedback (adaptive scale). Whether a session presents at 120 Hz is
  measured on device (`displayHz=` in `vrmc-compositor.log`), not claimed. Engine-side foveation is
  deferred because the shipped MoltenVK has no `VK_KHR_fragment_shading_rate`; see
  [`docs/mvp/M8_PLAN.md`](docs/mvp/M8_PLAN.md).
- Bow visual model orientation (parallel to hand) — accepted non-blocking bug.
- Launcher auto-provisioning (bundled provider + hash-verified Vivecraft import) is **host-tested
  only** (`runtime/native-shell/tests/run_tests.sh`, visionOS build PASS); the fresh-install flow on
  D1 has not been re-run with it yet. Vivecraft still has to be downloaded by the user.
- Hand tracking can drop when hands are outside the ARKit camera view; actions release safely.
- K3 latency-rig gate and the full 60-minute soak were explicitly waived/covered by a reduced
  10-minute operator-accepted soak.
- This is a development/sideload package, not App Store distribution.

## Licensing

- VRMC application code: **GPL-3.0** ([`LICENSE`](LICENSE)), derived from Amethyst.
- `provider/`: **LGPL-3.0** ([`provider/LICENSE`](provider/LICENSE)), distributed as a separate,
  replaceable artifact with source.
- Minecraft is proprietary; users must own it. No Minecraft binaries or assets are distributed.
- Vivecraft is installed by the user and used unmodified.
- See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md),
  [`SOURCE_OFFER.md`](SOURCE_OFFER.md) and [`PRIVACY.md`](PRIVACY.md).

## Safety

VR can cause discomfort. VRMC provides comfort settings (vignette, snap/smooth turn, seated mode)
and keeps exit/recenter reachable. VRMC is not affiliated with Mojang, Microsoft, Vivecraft, Valve,
Sony, or Apple.
