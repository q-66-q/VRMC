# M6 plan — hardening + acceptance

Status: **IN PROGRESS (offline groundwork)** — EV-0102: shutdown journal, soak/release harnesses, privacy + acceptance matrix; EV-0108: crash guard/safe mode + release readiness check. Host/build PASS; device gates remain `NOT RUN` while D1 is unavailable. See `docs/mvp/M6_ACCEPTANCE.md`.

## Scope (AGENT §7 M6: AC-1…AC-6 + K gates evidenced)

- **Stability:** clean shutdown/restart, crash-log capture + safe restart, repeated launches/world
  loads, watchdog-kill detection, 60-minute soak.
- **Performance/thermal acceptance:** K1 boot/launch, K2 frame rate (90 Hz target / ≥72 fps default,
  45 fps floor), K3 rotational latency protocol, K4 60-min/20-launch/10-load, K5 thermal step-down,
  K6 footprint. K3 requires the 240 fps rig protocol; document gaps rather than inventing numbers.
- **Release:** signed-build reproducibility, version/pins manifest, third-party notices/GPL source
  publication gate, no Minecraft binaries in git, privacy manifest, install-size budget.
- **Acceptance:** AC-1…AC-6 matrix with evidence/waiver table, hands-only AC-4 checklist, final
  VERIFY §10 sign-off.

## Implemented offline (EV-0102/EV-0108)

- Append-only `vrmc-shutdown.log`, `scripts/m6_soak_harness.sh`, `scripts/m6_release_manifest.sh`.
- Crash guard: startup evaluates the last shutdown journal event; two consecutive unclean sessions
  enable safe mode (automatic immersive open suppressed, manual Enter VR available, launcher can clear).
- `scripts/m6_release_check.sh`: host readiness gate for licenses/notices/privacy/source dirs/no tracked
  Minecraft binaries/usage strings/manifest fields (PASS).

## Release workflow (EV-0119)

- `scripts/m6_release_check.sh` PASS on a clean tree.
- `scripts/m6_release_manifest.sh` generated a clean manifest (`dirty_tree=no`, pins/hashes/licensing).
- `scripts/m6_package_release.sh` produced a development sideload package
  (`/tmp/VRMC-dev-release.zip`, sha256 `d583608d…`, 206,308,244 bytes) with app + provider +
  licenses/notices/privacy/README/versions.env + manifest + INSTALL.txt.
- **Not final release:** AC-1..AC-6/K gates and VERIFY sign-off still NOT RUN; final package must be
  rebuilt from the release commit with device evidence.

## Install metrics + device runbook (EV-0150)

- `scripts/m6_install_metrics.sh` reports host app-bundle bytes/files/Mach-O count, provider bytes/hash,
  package bytes/hash (K6 groundwork); snapshot in `export/install-metrics-dev.txt`.
- `docs/mvp/M6_DEVICE_RUN.md` is the AC-1…AC-6/K1…K6 execution procedure, evidence rules, and command
  list; device install size remains a device gate.
- `scripts/m6_acceptance_report.sh --require-pass` remains the release gate; it is currently NOT READY.

## Soak harness hardening (EV-0149)

- Pulls the real Minecraft log (`Documents/instances/default/logs/latest.log`) in addition to the legacy
  path, plus `vrmc-heartbeat.txt` and `vrmc-status.json` each poll.
- Marker scan adds OOM/watchdog strings; `REQUIRE_CLEAN_SHUTDOWN=1` (default) fails the soak when the
  shutdown journal lacks `destroy-complete` (AC-5 clean teardown), with an explicit override for probes.
- `scripts/m6_release_check.sh` now runs `m6_soak_harness.sh --dry-run` and reports it. Host checks PASS;
  device soak NOT RUN.

## Source offer + refreshed package (EV-0143)

- `SOURCE_OFFER.md`: GPLv3 app/launcher/compositor + LGPLv3 separately-replaceable provider correspondence,
  release-manifest source commit/versions pins, rebuild instructions, 3-year written offer, explicit
  no-Minecraft/Vivecraft redistribution.
- Release check requires it; the development package includes it plus M4/M5/M6 docs.
- Clean-tree refresh: release check PASS, manifest `dirty_tree=no`, package
  `/tmp/VRMC-dev-release.zip` bytes=206,440,226 sha256 `7cfc1433…`; device provider integrity PASS.
- Acceptance gate still **NOT READY**; this is a development sideload package, not final release.

## Acceptance readiness report (EV-0139)

- `scripts/m6_acceptance_report.sh` parses M5/M6 acceptance matrices, prints per-row status and counts,
  and `--require-pass` is the release gate (all rows explicit PASS).
- Current snapshot in `export/acceptance-readiness.txt`: **NOT READY** (device AC/K/H gates NOT RUN;
  host-pass/partial rows excluded from PASS).
- Release check remains host readiness only; the acceptance report is the explicit device gate.

## Device diagnostics pull (EV-0137)

- `scripts/m6_device_diagnostics_pull.sh [OUT_DIR]` copies local VRMC logs/status/config out of the
  installed app data container (read-only; no launch/unlock) and writes SHA256SUMS.
- Current D1 snapshot: provider integrity PASS; `Documents/vrmc-shell.log` absent => the latest build has
  not been launched since install. The two old pulled logs (22:17/22:28 device time) show a clean
  `game stopping` -> `VRMCImmersiveEnded` sequence from an earlier session, no crash markers.

## Device provider-integrity check (EV-0136)

- `scripts/m6_device_integrity.sh` reads the installed app data container (read-only), copies the
  provider jar out, compares SHA256 with the locally built jar, and prints the installed VRMC version.
- Requires no launch/unlock; behavior/acceptance gates remain separate.
- Current D1: **PASS** — provider `4602605f…` (85,957 bytes) matches; VRMC 1.2.0 installed.

## Consolidated host regression (EV-0188)

- Shell build, provider suite (all fuzz), bridge suite incl. TSan, M4 selfcheck --fast, release check,
  package verifier/freshness and device integrity: all PASS.
- Release-ready host gates PASS; acceptance 0/22 explicit PASS → NOT READY. Device AC/K/H gates NOT RUN.

## K6 JRE-pruning experiment (EV-0205)

- `stage_native_app.sh` accepts `VRMC_KEEP_JRE=<major>` to prune other bundled `java-*-openjdk`
  runtimes before signing; default unchanged (keeps all).
- Read-only device JRE probe (EV-0207): device `Documents/java_runtimes` empty; selected profile
  `fabric-loader-0.20.1-26.2`; crash log shows OpenJDK 25.0.4 loaded from app-bundled
  `java_runtimes/java-25-openjdk` — strongest available indication that pruning 8/17/21 is safe, but a
  lite launch is still required.
- Experimental lite staging (not installed): app 245,747,712 bytes vs 583,630,848 current, 72 vs 169
  Mach-O, deep/strict codesign PASS; clean measurement package 89,919,699 bytes sha256 `db3f6a48…`,
  verifier PASS (EV-0206). **Device launch behavior NOT validated**; do not use as default until D1
  confirms the launcher does not select a pruned bundled runtime.

## Checklist FAIL release gate (EV-0204)

- `scripts/m6_check_device_checklist.sh` consumes `export/device-acceptance-status.txt`: missing SKIP,
  FAIL exit1, NOT RUN/PARTIAL exit2, all PASS exit0.
- `m6_release_ready.sh` runs it before the acceptance gate; FAIL blocks host readiness, incomplete is a
  note. Host fixtures pass; fixture-generated export artifacts were removed; device checklist NOT RUN.

## Checklist importer (EV-0203)

- `scripts/m6_import_device_checklist.sh [--input PATH] [--require-no-fail]` imports the in-headset
  checklist JSON into `export/device-acceptance-report.md` and machine status lines; validates statuses
  and can fail on FAIL. Device pull is read-only; host fixtures cover normal/FAIL/bogus/missing.
- An argument-loop hang (missing shift) was found and fixed during host testing. Actual device pull NOT RUN.

## Refreshed package for checklist-summary build (EV-0201)

- Package refreshed to app `a4663e16…` + provider `4587b5d2…`: bytes=206,538,366 sha256
  `4d9141f05a8993a0c5242534df4ff102aaefe6fffd7ae555bf82c06dd9e3d2af`; freshness/verifier/release-ready
  host gates PASS; acceptance NOT READY; metrics + STATUS.md refreshed.

## Acceptance checklist UI (EV-0198)

- Launcher checklist (+ diagnostics export) captures H1–H10/AC-1..6 outcomes on device without typing;
  persisted to `Documents/vrmc-acceptance-checklist.json`. Build/install PASS; device interaction NOT RUN.

## Round-100 package refresh (EV-0197)

- Package refreshed to app `cf231fc7…` + provider `4587b5d2…`: bytes=206,493,046 sha256
  `7e9e608ce8f5f53a857fff8bd87f1ba46cf39be9ce0aeebe34b333303bbe68bd`; freshness/verifier/release-ready
  host gates PASS; acceptance NOT READY; metrics + STATUS.md refreshed.

## Refreshed package for targeted-reset build (EV-0194)

- Package refreshed to app `f1ae3749…` + provider `50cd776b…`: bytes=206,486,820 sha256
  `efe71843f71e669e4e6164fab39c8cafcf144fb6d75917006918121f3b737cf5`; freshness/verifier/release-ready
  host gates PASS; acceptance NOT READY; metrics + STATUS.md refreshed.

## Refreshed package for calibration-apply build (EV-0192)

- Package refreshed to app `595982a2…` + provider `50cd776b…`: bytes=206,483,529 sha256
  `4e1d99823e79c3aa813b0cf3aad1ff0a3aade1f811f6d662b85643e0c87c9ef5`; freshness/verifier/release-ready
  host gates PASS; acceptance NOT READY; metrics + STATUS.md refreshed.

## Refreshed package for calibration build (EV-0191)

- Package refreshed to app `b0680cac…` + provider `18029045…`: bytes=206,479,055 sha256
  `9540a8a947a2f360742b7c7f958474b975eab2132da74e944d2792aa8287a7ac`; freshness/verifier/release-ready
  host gates PASS; acceptance NOT READY; metrics + STATUS.md refreshed.

## Release gate default app freshness (EV-0187)

- `m6_release_ready.sh` defaults `RELEASE_APP_BUNDLE` from `export/latest-build-identity.txt`'s staged app
  path, so package freshness checks both app and provider hashes without explicit overrides.
- Current match app `2388965a…`/provider `a109ae56…`; host gates PASS; acceptance NOT READY.

## Refreshed package for auto-sprint build (EV-0185)

- Package refreshed to app `2388965a…` + provider `a109ae56…`: bytes=206,471,014 sha256
  `bc497dfe140db8433bffa532cfffa2e84488de0fcaf8ef11d2daba9189d2ebbd`; freshness/verifier/release-ready
  host gates PASS; acceptance NOT READY; metrics + STATUS.md refreshed.

## Refreshed package for auto-status build (EV-0183)

- Package refreshed to app `2939c509…` + provider `702e7193…`: bytes=206,470,666 sha256
  `f6a687ace74facb3e266f4a858fb0618d55b032f46750c70f7f010f711c843c0`; freshness/verifier/release-ready
  host gates PASS; acceptance NOT READY; metrics refreshed.

## Status/handoff document (EV-0181)

- `docs/mvp/STATUS.md` summarizes the current installed build identity, milestone states, feature
  inventory, host verification commands/results, remaining device-only procedures and known risks;
  linked from README.
- Documentation only; device AC/K/H gates remain NOT RUN.

## Stale-package guard (EV-0180)

- `scripts/m6_check_release_current.sh` compares a package's embedded manifest app/provider hashes with
  the current local builds; `m6_release_ready.sh` runs it before package verification.
- Current package app `2939c509…`/provider `5379fe2c…` match → PASS; host gates PASS; acceptance NOT READY.

## Refreshed package for restore build (EV-0179)

- Package refreshed to app `2939c509…` + provider `5379fe2c…`: bytes=206,470,289 sha256
  `20ffc04d980001124a9585f9511047b3a7f17bedc62b9482003486d6298ce648`; verifier/release-ready host
  gates PASS; acceptance NOT READY; metrics refreshed.

## Refreshed package/metrics for climb build (EV-0177)

- Package refreshed to app `90c83c0d…` + provider `1d36487e…`: bytes=206,468,279 sha256
  `9720b6527c5276b2ec25aa897ad9171e2799fbbbc5c2a05cf1383c0ce34abc2f`; verifier/release-ready host
  gates PASS; acceptance NOT READY.
- Install metrics refreshed: app 583,630,848 bytes / 485 files / 169 Mach-O; provider 91,427 bytes.

## Refreshed package/metrics for bow build (EV-0175)

- Package refreshed to app `6e4b7c5e…` + provider `47713964…`: bytes=206,462,210 sha256
  `8a82159e54eb5bf0abafc507301b2575cc5738c96efae98aa52280e970f4efcd`; verifier/release-ready host
  gates PASS; acceptance NOT READY.
- Install metrics refreshed: app 583,630,848 bytes / 485 files / 169 Mach-O; provider 91,130 bytes.

## Status-field parity guard (EV-0173)

- `scripts/check_status_fields.sh` extracts the 11 `obj["..."]` fields the launcher reads and requires
  `VisionStatusJson` to write each; release check runs it and reports PASS.
- Prevents launcher/provider status-field drift. Device gates NOT RUN.

## Settings-key parity guard (EV-0172)

- `scripts/check_settings_keys.sh` extracts every runtime/input key literal the launcher writes (31 keys)
  and requires provider source recognition; release check runs it and reports PASS.
- Prevents silent UI/provider drift (the reload-input regression class). Device gates NOT RUN.

## Refreshed package + gate verification (EV-0171)

- Clean-tree release check/reproducibility PASS; package refreshed to bytes=206,459,555 sha256
  `6e99d8e994571ba75d134f5e95d14a903fd4b30df0dc3b75d86626c2110f819c` (app `d1d68596…`,
  provider `bad3d955…`); package verifier PASS; release-ready gate host/package/device-integrity PASS,
  acceptance NOT READY (expected until device acceptance).

## Single-command release gate (EV-0165)

- `scripts/m6_release_ready.sh [--zip PATH] [--report-only] [--skip-device]` aggregates: host release
  check, package verifier, read-only device provider integrity, and the acceptance `--require-pass` gate.
- Current expected result: host/package/device-integrity PASS; acceptance 0/22 explicit PASS →
  **NOT RELEASE READY**, exit 1. Use `--report-only` for informational runs.

## Package verifier PASS (EV-0164)

- App tree hash is now bundle-relative/path-independent: `d1d685968dbc19f728b2279fa3ac23b87862ecf79913b6108b8718e4c83a1269`;
  manifest regenerated with it.
- Package rebuilt: bytes=206,459,032 sha256 `46b14b6a870b02185d9835682ec256162e13329b01303ba4a895aa4afabc081a`;
  `m6_verify_release_package.sh` PASS (entries, app/provider hashes vs manifest, dirty_tree=no).
- Older app hashes used absolute paths and are not comparable. Device gates NOT RUN.


- `scripts/app_tree_sha256.sh` hashes file sha256s with bundle-relative paths, so the app identity does
  not depend on staging path; the release manifest now uses it.
- `scripts/m6_verify_release_package.sh ZIP` unpacks a package and verifies required entries, the
  embedded manifest's provider/app hashes, and dirty_tree; prints zip size/sha.
- Hash method note: app-bundle hashes recorded before EV-0164 used absolute paths and are not comparable
  to the new path-independent digest.

## Extreme stress run (EV-0163)

- Provider input fuzz at **1,000,000** frames: 0 violations (6.0 s).
- Full bridge suite including **TSan** builds: ALL PASS; concurrent sync (200k publishes × 4 readers),
  tracking/display views (500k writes/reads) and input (500k publishes × 4 readers, millions of reads)
  with no torn state.
- Host-only stress evidence; device AC/K gates NOT RUN.

## Acceptance report parser fix (EV-0161)

- M6 acceptance rows were parsed from the evidence/gap cell; the report now reads the status cell for
  AC/K rows and strips backticks for M5 H rows. Current accurate summary: rows=22, explicit-pass=0,
  not-run=17, partial=7; `--require-pass` remains NOT READY. Device gates NOT RUN.

## Refreshed package to latest app (EV-0160)

- Clean-tree release check PASS + reproducibility PASS.
- Package refreshed to app `a046bab6…` + provider `fcd1df76…`: bytes=206,458,384 sha256
  `4f89d0d690e266ac961a1c06bf37e058994c53183347ae984b41fedc0a36c696`; manifest `dirty_tree=no`;
  export manifest/package metadata updated.
- Development sideload package only; acceptance NOT READY.

## Release check proves reproducibility (EV-0156)

- `scripts/m6_release_check.sh` now runs `scripts/m6_reproducibility_check.sh` (two independent provider
  builds) and reports the provider sha256; a mismatch fails host readiness.
- Current release check PASS with provider `fcd1df76…`; device acceptance remains separate/NOT READY.

## Refreshed package with reproducible provider (EV-0155)

- `scripts/m6_reproducibility_check.sh` PASS: two builds both `fcd1df76…` (90,619 bytes).
- Clean-tree release check PASS; package refreshed to bytes=206,459,027 sha256
  `3b3fa4feaa9ca2eeb80bff6d504dff89940a98664772597366530f0b2ac1aa03` with app `0aebb806…` +
  provider `fcd1df76…`; manifest `dirty_tree=no`; metadata refreshed.
- Development sideload package only; acceptance NOT READY.

## Reproducibility check (EV-0155)

- `scripts/m6_reproducibility_check.sh` builds the provider twice from the same source and compares
  sha256/bytes (requires the normal host toolchain/deps; does not touch `/tmp/vrmc-current` or device).
- Used as the standing release-integrity check for the fixed-timestamp jar.

## Reproducible provider jar (EV-0154)

- `build_provider.sh` packages with fixed entry timestamps (`jar --date`, override `REPRO_TIMESTAMP`)
  instead of wall-clock stamps: identical source/JDK/payload now yields an identical sha256.
- Two independent builds: `fcd1df76…` (90,619 bytes) both; provider suite PASS; jar pushed and device
  integrity PASS.
- Release manifest/package metadata must be regenerated to the new stable provider hash.

## Async heartbeat write (EV-0153)

- Heartbeat throttling stays on the frame thread (≤1 Hz), but the atomic file write is dispatched to a
  utility QoS background queue: no synchronous watchdog filesystem I/O on the render thread.
- Dropped final queued write on abrupt process death is harmless (watchdog reports stale heartbeat).
- Shell/app build/install PASS; device runtime performance NOT RUN.

## Heartbeat watchdog (EV-0132)

- Compositor rewrites `Documents/vrmc-heartbeat.txt` at most 1 Hz while frames loop (generation, frame,
  presented, drawables, layer state).
- Shell checks every 5 s while immersive+presenting; >20 s stale logs a single WATCHDOG warning and sets
  launcher status; recovery is logged; the heartbeat is included in diagnostics export. No auto-kill.
- Build/install PASS; device hang behavior NOT RUN.

## Concurrency hardening (EV-0116)

- `bridge/tests/bridge_shared_test.c` stress-tests the additive native-shared channels (display views,
  gaze mailbox, tracking override, game-stopping) with a writer/reader pair under normal build and
  ThreadSanitizer; full bridge suite PASS.

## Safety fuzzing (EV-0115)

- `VisionInputFuzzTest` (20k deterministic random frames) exercises tracking-loss/malformed/stale
  invariants and found/fixed a both-hand chord pulse that could outlive a lost hand.
- Full provider suite PASS; device real-hands no-stuck verification still required.

## Offline groundwork to add

1. `scripts/soak_harness.sh`: device-only repeat launch/world/quit loop with log capture + crash
   detection (can be dry-run on host until D1 is available).
2. Provider/shell clean-shutdown checkpoints and a documented `vrmc-shutdown.log`.
3. Release manifest script: hashes/pins/build identity from the accepted app tree.
4. NOTICE/licensing/privacy files and README release section.
5. M6 acceptance matrix skeleton linked to existing EV entries, all device rows `NOT RUN`.

## Known open defects to close before M6 exit

- Full AC-4 hands checklist (locomotion/actions/comfort) not run.
- Provider GPU-timeline sync device run (flag-gated, host PASS).
- M3-W5/W6 90 Hz pacing/thermal soak.
- Any shutdown/teardown regression after EV-0097/EV-0100 changes needs D1 confirmation.
