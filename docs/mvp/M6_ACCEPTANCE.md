# M6 acceptance matrix (skeleton)

Authority: [`VERIFY.md`](../../VERIFY.md). This matrix is a navigation/checklist layer; every row's
actual status comes from VERIFY evidence. **Device rows remain `NOT RUN` while D1 is unavailable.**

## Automated readiness report

`scripts/m6_acceptance_report.sh` parses this matrix plus `M5_ACCEPTANCE.md` and prints per-row status +
counts; `--require-pass` exits non-zero unless every row has an explicit PASS. The current snapshot is
stored in `export/acceptance-readiness.txt` and is **NOT READY** (device gates NOT RUN). Host/partial
evidence never counts as a device PASS.

## MVP acceptance criteria

| ID | Criterion | Status | Evidence / gap |
|---|---|---|---|
| AC-1 | Fresh install → world, natively on AVP, no PC/streaming | `PARTIAL` | M1 CLOSED (EV-0043/0044/0052/0057); native immersive path EV-0094. Current build launched and was played on D1 (EV-0212), but clean-install/world-load sequence and full checklist remain. |
| AC-2 | Stereo correct, no eye swap/flip; head tracking aligned | `PASS` | Operator-confirmed stereo alignment + head tracking (EV-0094); display path unchanged through current provider. `ipd=0.0645`, displayViews applied continuously in EV-0256/0261 sessions. |
| AC-3 | Immersive input from hands (no controller fallback) | `PASS` | All M7 core actions device-passed using hands only (EV-0253/0256/0257): menu, movement, inventory, attack/place/use/break, hotbar, jump/sneak, bow, eat, climb. |
| AC-4 | Every P0 action reachable from hands; no stuck input | `PASS` | Operator device pass for all P0 hand actions (EV-0256/0257); 200k-frame M7 fuzz + release-input panic path host PASS. |
| AC-5 | 60-min session, 20 cold launches, 10 world loads, no watchdog kills | `PASS` | Operator accepted a **reduced 10-min soak** as sufficient (2026-11-05) and stated the observed relaunches were not product defects. Full duration/launch matrix waived. Harness now enforces fresh one-init/final-destroy for future runs. |
| AC-6 | No Minecraft binaries; ownership/EULA; GPL source; notices complete | `PARTIAL` | THIRD_PARTY_NOTICES/licensing present; `SOURCE_OFFER.md` (GPL/LGPL corresponding-source offer, no Minecraft/Vivecraft redistribution) added; release manifest script prepared; final legal review/sign-off still required. |

## Budgets (K gates)

| ID | Target | Status | Evidence / gap |
|---|---|---|---|
| K1 | Launcher ≤10 s; launch → in-world ≤90 s | `PASS` | Observed 2026-11-06 07:00:14 launcher host → 07:00:20 game started → 07:00:36 immersive presented (22 s to immersive; well under 90 s). Launcher-process-to-window time not separately instrumented. |
| K2 | 90 Hz target; ≥72 fps default; 45 fps floor behavior | `PASS` | Repeated device diag windows: poll 119.8-119.9 Hz, p50 8.27-8.36 ms, p95 9.15-9.33 ms, missed90=0 (EV-0257 session). |
| K3 | Rotational M2P P50 ≤50 ms / P95 ≤65 ms | `NOT RUN` | 240 fps latency rig protocol + rig availability still required. |
| K4 | 60-min/20-launch/10-load stability | `PASS` | Same operator-accepted reduced 10-min soak (EV-0260); full-duration waiver. |
| K5 | Thermal step-down predictable, 45 fps floor | `PARTIAL` | Thermal state observed `fair` during the 10-min soak; no forced step-down/frame-floor event was captured. |
| K6 | Install ≤3.5 GB, first install ≤30 min | `PARTIAL` | App tree ~583.6 MB (well under 3.5 GB); device cold-install duration not instrumented. |

## Stability / hardening

| Item | Status | Notes |
|---|---|---|
| Clean shutdown (no JVM SIGSEGV) | `CODE (device NOT RUN)` | EV-0097 teardown hardening; `vrmc-shutdown.log` now records init/destroy; verify on D1. |
| Stale immersive/beeps on game stop | `CODE (device NOT RUN)` | commit 3c5d57c; verify on D1. |
| Crash log capture + safe restart | `PARTIAL` | Minecraft/shell logs + shutdown journal; crash guard adds crash counting/safe mode and launcher warning (EV-0108). Device behavior NOT RUN. |
| Compositor hang detection | `PARTIAL (build PASS)` | Heartbeat + 20 s stale watchdog/status (EV-0132); device hang/recovery NOT RUN. |
| Release readiness check | `PARTIAL (host PASS)` | `scripts/m6_release_check.sh` PASS (licenses/notices/privacy/source dirs/no tracked MC binaries/usage strings/manifest fields); final clean-commit manifest + device acceptance still required. |
| Background → foreground re-entry | `PARTIAL` | M3c re-entry + simulator scenario; final device check open. |
| Release manifest / notices / privacy | `PARTIAL` | `scripts/m6_release_manifest.sh`, `THIRD_PARTY_NOTICES.md`, `PRIVACY.md`; sign-off pending. |

## Exit checklist

1. AC-1…AC-6 and K1…K6 demonstrated on D1 with recorded evidence (or written waiver).
2. No open P0 defects; shutdown/re-entry/soak runs clean.
3. Hands-only AC-4 checklist complete, comfort settings exercised (seated/snap/teleport).
4. Release manifest generated from a clean commit with all hashes/pins/notices; source publication gate met.
5. VERIFY §10 sign-off.
