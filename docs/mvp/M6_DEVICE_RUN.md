# M6 device acceptance runbook (D1; all device gates NOT RUN yet)

Purpose: execute AC-1…AC-6 and K1…K6 on hardware, record evidence in VERIFY, and drive
`scripts/m6_acceptance_report.sh --require-pass` to READY. Host/build evidence never satisfies a gate.

## Preconditions

- Current build installed; run `scripts/m6_device_integrity.sh` (installed VRMC version + provider sha256).
- `scripts/m6_device_diagnostics_pull.sh` works read-only (baseline snapshot).
- StikDebug JIT available; hand-tracking permission granted; operator read `M4_CONTROLS.md` and
  `M5_DEVICE_RUN.md`.
- Host-side release check PASS (`scripts/m6_release_check.sh`).

## AC gates

| Gate | Procedure | Evidence to record |
|---|---|---|
| AC-1 fresh install → world, native, no PC | Uninstall/reinstall; StikDebug JIT; play; join/create world; no streaming/PC | build identity, diagnostics bundle, operator notes, clean launch log |
| AC-2 stereo/head alignment | Look at near/far geometry; head translations/rotations; both eyes no swap/flip | 2-3 diagnostics runs + operator confirmation; note IPD/eye values |
| AC-3 hands only | Disable controllers; every core action from hands | AC-4 checklist output |
| AC-4 P0 actions + no stuck hands | Run `M4_CONTROLS.md` P0 list: menu, move/turn/teleport/jump/sneak, attack/use, bow, inventory/hotbar, climb, recenter; wave hands in/out of view | per-action pass/fail, stuck-hand stress notes, `vrmc-status.json` snapshots |
| AC-5 soak | `DEVICE_UDID=… SOAK_SECONDS=3600 scripts/m6_soak_harness.sh --device`; 20 cold launches, 10 world loads | harness artifacts; every run must have `destroy-complete`; no watchdog kills |
| AC-6 legal/source | Confirm no Minecraft/Vivecraft binaries; `SOURCE_OFFER.md`, licenses/notices, manifest source_commit; legal sign-off | signed checklist/notes |

## K gates

| Gate | Procedure | Evidence |
|---|---|---|
| K1 timing | D1 timing runs (`DT-14`): start/stop, frame times | timing table |
| K2 90 Hz pacing | Play with `[VRMC-M5] diag` at 30 s; record p50/p95/missed90 (+launcher provider line) | diag log windows + status JSON |
| K3 latency rig | 240 fps rig: motion-to-photon / input-to-action | rig results |
| K4 soak | AC-5 artifact set | soak output + shutdown journals |
| K5 thermal | Long session; thermal log/state file; `performance.thermalResponse` A/B | `vrmc-thermal.log`, state file, diag |
| K6 install size | `scripts/m6_install_metrics.sh` host + device app info/storage measurement | metrics output + device storage note |

## Commands

```
scripts/m6_device_integrity.sh
scripts/m6_device_diagnostics_pull.sh /tmp/vrmc-device-diag
DEVICE_UDID=<udid> SOAK_SECONDS=3600 scripts/m6_soak_harness.sh --device
scripts/m6_acceptance_report.sh --require-pass
```

## After the operator checklist

```
scripts/m6_import_device_checklist.sh                 # pulls checklist JSON from the app container
scripts/m6_import_device_checklist.sh --require-no-fail
```

Writes `export/device-acceptance-report.md` and `export/device-acceptance-status.txt` for VERIFY.

## Evidence rules

- One current build identity for all runs; record app tree sha256 + provider jar sha256.
- Attach logs/bundles/screenshots (if available) under `evidence/EV-…/`, mark status honestly.
- Any crash without `destroy-complete` is an AC-5/K4 failure until explained.
- Update `M6_ACCEPTANCE.md`, `M5_ACCEPTANCE.md`, VERIFY, dashboard and acceptance report after each run.
