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
| AC-1 | Fresh install → world, natively on AVP, no PC/streaming | `PARTIAL` | M1 CLOSED (EV-0043/0044/0052/0057); native immersive path EV-0094. Re-verify after M4/M5 changes and on a clean install for release. |
| AC-2 | Stereo correct, no eye swap/flip; head tracking aligned | `PARTIAL` | EV-0094 operator-confirmed stereo alignment + head tracking; M3-W5/W6 90 Hz/soak still NOT RUN. |
| AC-3 | Immersive input from hands (no controller fallback) | `PARTIAL` | W1 device PASS (EV-0096); W2–W4 host PASS (EV-0097–EV-0101); full AC-4 hands checklist NOT RUN. |
| AC-4 | Every P0 action reachable from hands; no stuck input | `NOT RUN` | Guesture slices host-tested; real-hands P0 checklist, gesture tuning, no-stuck stress on D1 required. |
| AC-5 | 60-min session, 20 cold launches, 10 world loads, no watchdog kills | `NOT RUN` | `scripts/m6_soak_harness.sh` prepared (dry-run PASS); device run required. |
| AC-6 | No Minecraft binaries; ownership/EULA; GPL source; notices complete | `PARTIAL` | THIRD_PARTY_NOTICES/licensing present; release manifest script prepared; final source-publication/EULA gate needs release review. |

## Budgets (K gates)

| ID | Target | Status | Evidence / gap |
|---|---|---|---|
| K1 | Launcher ≤10 s; launch → in-world ≤90 s | `NOT RUN` | needs D1 timing runs (`DT-14`). |
| K2 | 90 Hz target; ≥72 fps default; 45 fps floor behavior | `NOT RUN` | M5 presets/diagnostics implemented; device pacing trace required. |
| K3 | Rotational M2P P50 ≤50 ms / P95 ≤65 ms | `NOT RUN` | 240 fps latency rig protocol + rig availability still required. |
| K4 | 60-min/20-launch/10-load stability | `NOT RUN` | M6 soak harness + shutdown journal; device run required. |
| K5 | Thermal step-down predictable, 45 fps floor | `NOT RUN` | shell thermal monitor implemented (EV-0101); device thermal soak required. |
| K6 | Install ≤3.5 GB, first install ≤30 min | `NOT RUN` | release manifest records app/bundle size; needs device install measurement. |

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
