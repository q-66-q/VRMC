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
