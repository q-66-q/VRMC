# M1 acceptance matrix — launcher shell + install + flat MC boot

Status as of **2026-11-01**. This is the single view of the M1 acceptance criteria from
`M1_PLAN.md` §2, the workstreams, and the remaining gaps. Every PASS points at an EV; gaps are explicit.

## Acceptance criteria

| # | Criterion | Status | Evidence / gap |
|---|---|---|---|
| 1 | Fresh install → launch MC 26.2 → create/enter a world entirely from the app UI | **PASS** | Fresh `dev.vrmc.vrmc` container reached the world with app-side provisioning (EV-0043). Note: the world preset (flat) was not separately recorded — confirm on the next clean install. |
| 2 | 30 minutes stable in-world, clean exit, save preserved on relaunch | **PASS** | Soak PASS: 1805 s continuous, no game crash/watchdog, thermal `serious` (EV-0044); clean save/quit and save-reload verified (EV-0052). |
| 3 | No manual host steps after install (JRE, LWJGL, options, JIT script provisioned by the app or documented one-tap UI) | **PASS** | Bundled JREs selected internally, options forced app-side, no Mac-side pushes (EV-0037/EV-0043). StikDebug script assignment is the documented on-device step. |
| 4 | JIT readiness UX: detect no-JIT, guide through StikDebug, retry cleanly | **PASS** | Explicit TXM alert + `[JIT] preflight` logging (EV-0050); no-JIT flow verified on D1, game continues after JIT is enabled (EV-0051). |
| 5 | Crash/log capture: MC log stored and retrievable; crash produces an in-app report | **PASS** | Logs/crash reports retrievable via repo scripts (EV-0039); launcher `Send logs` and in-game **Log output** overlay with *Share latestlog.txt* confirmed in source/installed binary (EV-0053); MC crash screen/report remains the in-app crash path. |
| 6 | Input usable for flat-world movement/look (keyboard/controller at minimum; mouse issue triaged) | **PARTIAL** | Grab/relative mouse path active, rotation smooth (EV-0047); 30-minute play session used keyboard+mouse (EV-0044). Cursor visibility is a visionOS pointer-lock limitation accepted as cosmetic (EV-0047). **Gap:** keyboard/controller defaults not explicitly validated. |
| 7 | GPL-3.0 compliance: corresponding source + build instructions published for the distributed build | **PASS (in-repo source offer)** | Base-tree provenance hash, VRMC patch, build script and third-party license table are now in `docs/legal/SOURCE_OFFER.md` (plus ADR-0006/0008 and EV-0049). Residual: publish the same offer wherever the binary is distributed (release page). |

## Workstreams (M1_PLAN §3)

| ID | Workstream | Status | Notes |
|---|---|---|---|
| W1 | Our app shell | **DONE (icon/first-run build pending install)** | Build-from-source (ADR-0008); branded app (EV-0042/0043); reproducible script (EV-0049/EV-0055); VRMC icon + first-run checklist built/signed (EV-0054) — install pending device wake. |
| W2 | Runtime provisioning | **PASS** | Bundled JRE 8/17/21/25 + LWJGL 3.3.3/3.4.1 + MoltenVK inside the app; fresh container used internal Java 25 with no Mac pushes (EV-0043). |
| W3 | JIT readiness | **DONE** | Upstream wait-gate retained; explicit TXM instructions + preflight logging (EV-0050); no-JIT flow verified (EV-0051). |
| W4 | MC install + boot | **PASS** | Fresh container: account + MC 26.2 install + world reached from app UI (EV-0043). Flat preset note above. |
| W5 | Input | **CLOSED (with accepted cosmetic)** | Rotation smooth via grab/relative path (EV-0047); cursor visible is a visionOS pointer-lock limitation, accepted by the user. Keyboard/controller defaults tabled. |
| W6 | Observability | **DONE** | Logs/crash reports retrievable with repo scripts (EV-0039); in-app Send logs / Log output share path confirmed (EV-0053). |
| W7 | Stability | **DONE** | 30-min soak PASS (EV-0044); save/relaunch integrity PASS (EV-0052); thermal `serious` recorded; FPS baseline still a nice-to-have. |

## Next actions

1. **W3 verification (device):** launch VRMC without enabling JIT first → confirm the explicit alert /
   StikDebug flow and that the game resumes after JIT is enabled.
2. **W7 save/relaunch (device):** play, quit MC cleanly, relaunch and confirm the saved world loads.
3. **W6:** add an in-app "Share logs / crash report" entry (W6 acceptance).
4. **W1:** custom app icon + first-run welcome/checklist screen.
5. **GPL:** produce the source-offer artifact (source tree reference + patch + build instructions) for
   distribution.
