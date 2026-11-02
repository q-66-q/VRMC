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

| `m3c_selfcheck.sh` | `scripts/m3c_selfcheck.sh [--fast]` — one-command M3c host/simulator self-check (depth regression, display-views, provider+bridge builds, bridge suite, provider-sampling harness) |

All are re-runnable. `sign_ipa.sh` re-signs every Mach-O in the bundle and embeds the profile;
`install_device.sh` retries installs and can uninstall a bundle id first.