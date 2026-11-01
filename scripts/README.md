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

All are re-runnable. `sign_ipa.sh` re-signs every Mach-O in the bundle and embeds the profile;
`install_device.sh` retries installs and can uninstall a bundle id first.
