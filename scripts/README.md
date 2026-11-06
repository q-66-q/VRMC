# Device/build helper scripts (Sprint-1 T2)

One usage line: set the environment (`DEVICE=<udid>`, and where relevant `BUNDLE_ID`, `TEAM_ID`, `IDENTITY`,
`XCENT`, `PROFILE`, `STIKDEBUG_BUNDLE_ID`, `AMETHYST_BUNDLE_ID`, `OUTDIR`, `DRY_RUN=1`) and run the script.

| Script | One-line usage |
|---|---|
| `sign_ipa.sh` | `BUNDLE_ID=... TEAM_ID=... IDENTITY=... XCENT=... PROFILE=... scripts/sign_ipa.sh App.app` |
| `install_device.sh` | `DEVICE=<udid> scripts/install_device.sh App.app [bundle-id-to-uninstall]` (add `DRY_RUN=1` to preview) |
| `push_jit_script.sh` | `DEVICE=<udid> scripts/push_jit_script.sh runtime/jit/amethyst.js` |
| `set_mc_options.sh` | `DEVICE=<udid> scripts/set_mc_options.sh` |
| `capture_device_logs.sh` | `DEVICE=<udid> OUTDIR=/tmp/vrmc-logs scripts/capture_device_logs.sh` |
| `build_provider.sh` | `scripts/build_provider.sh` — javac 25 + `jar` for the provider mod (no Gradle; classpath auto-resolved from Gradle caches + the Vivecraft tree); prints jar + sha256 |
| `build_bridge.sh` | `scripts/build_bridge.sh` — `MODE=device\|host\|both` (default device): clang cross-build + `vtool` visionOS retag; verifies platform/symbols |
| `stage_native_app.sh` | `scripts/stage_native_app.sh <VRMCShell.framework> [libvrmc_bridge.dylib]` — copy the EV-0086 app bundle, swap framework/dylib, embed profile, re-sign 169 Mach-O, `codesign --verify --deep --strict`; never installs (`DRY_RUN=1` preview) |
| `push_provider_jar.sh` | `scripts/push_provider_jar.sh [jar]` — `devicectl device copy to` the app data container `Documents/instances/default/mods/vrmc-provider.jar` + sha256 round-trip |

| `tests/DepthClearRegressionTest.sh` | `scripts/tests/DepthClearRegressionTest.sh` — regression guard for the M3c black-immersive root cause (EV-0093): default drawn-drawable depth clear must be 1.0, `vrmc-depth-zero.flag` A/B present, M3A probe reference 1.0 |
| `m3c_pull_and_check.sh` | `DEVICE=<udid> scripts/m3c_pull_and_check.sh` — pull the decisive M3c device logs/readbacks and print depthZero / scene-activation / first-presented-frame / parking triage (`--from <dir>` analyses an existing pull) |
| `m8_device_session.sh` | `scripts/m8_device_session.sh prepare|collect|all [--dry-run] [--from <dir>]` — one-command M8 device session: validate the staged candidate hashes/codesign, install the app, push the matching provider jar, print the operator checklist (prepare), then pull + classify A6-A9 (collect; wraps m8_device_check.sh). Exit 0 ok / 2 local artifact error / 5 device unavailable / classifier 0-4 |
| `m8_device_check.sh` | `DEVICE=<udid> scripts/m8_device_check.sh` — pull the M8 device logs and classify A6–A9 (foveation/rate maps, 4K-class logical size + provider eye targets, measured 90/120 Hz cadence + sharpening state, pacing): exit 0 PASS / 2 PARTIAL / 3 NOT RUN / 4 FAIL / 5 device unavailable; falls back to the `vrmc-status.json` render/pacing summary when logs rotated; `--from <dir>` analyses an existing pull or simulator case. Runbook: `docs/mvp/M8_DEVICE_RUN.md` |
| `tests/M8DeviceCheckTest.sh` | `scripts/tests/M8DeviceCheckTest.sh` — host test for the M8 classifier (synthetic PASS/90 Hz/old-build/FAIL log pulls; no device) |
| `runtime/probes/m8-foveation/run.sh` | `runtime/probes/m8-foveation/run.sh` — host Metal probe: the compositor's full-screen flat sampling math in a real variable-rasterization-rate (foveated) pass on macOS Apple Silicon (logical UV mapping + screen-size viewport convention) **and** the M8.6 foveated-sharpening upscale metrics (edge acutance, anti-halo bound, foveal weighting); 10 checks (exit 0 PASS / 1 FAIL / 2 SKIP) |
| `m8_host_harness.sh` | `VIVECRAFT_REF=<tree> [TARGET_HZ=… CONTENT_FIRST=on|off DISPLAY_HZ=…] scripts/m8_host_harness.sh [--timeout s]` — host Fabric harness: real Minecraft+Vivecraft client with the M8 provider, fake 3660×3200 display feedback through the real bridge; asserts the provider resizes its eye targets (1024×1024 → 1832×1600) and stays stable, and honours the M8 knobs (target cadence, content-first, simulated display cadence with guardrail revert) (host GL only; runbook docs/mvp/M8_HOST_HARNESS.md) |
| `push_m8_render_config.sh` | `DEVICE=<udid> scripts/push_m8_render_config.sh --eye-scale auto|0.25..1.0 --target-hz auto|60..120 --sharpening auto|off|0.05..1.0 --runtime-quality default|auto|0..1 --max-quality default|0.05..1.0 --content-first on|off --foveation-off` — push M8 rendering knobs to the app data container (`--print`/`DRY_RUN=1` preview, `--self-test` offline validation, 34 checks); see docs/mvp/M8_DEVICE_RUN.md §4 |

| `m3c_selfcheck.sh` | `scripts/m3c_selfcheck.sh [--fast]` — one-command M3c host/simulator self-check (depth regression, display-views, provider+bridge builds, bridge suite, provider-sampling harness) |

All are re-runnable. `sign_ipa.sh` re-signs every Mach-O in the bundle and embeds the profile;
`install_device.sh` retries installs and can uninstall a bundle id first.