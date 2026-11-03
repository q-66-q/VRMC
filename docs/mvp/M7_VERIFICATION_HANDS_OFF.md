# M7 EV-0237 independent verification — hand-off report

Verifier: `verifier-m7` (independent checker; shared Team task `task-5`)
Date: 2026-11-03 07:21 HST. Workspace: `/Volumes/Untitled/Projects/VRMC`.
Tree state verified (FROZEN snapshot, 07:20:53): engine `VisionM7Gesture.java` sha256
`bfea1995f11908ed2be37d982b4c3cc4d652389a3c2cbf413cf235647b07ea20` (1293 lines, mtime 07:11:23);
`VisionVR.java` `b761600423e5f42608fd9fd2ecb2b0906fcf542aae5184d6f82214d76f994e08`;
`scripts/m7_eval_replay.py` `088bdde503983ca76352e2afcc6434623f9801d16560310a6965ccfe50d805df` (07:09:01);
`VERIFY.md` `910477cc095aff41863af30f92e54f082d62f320f4682364bfde6ca89fbffec6` (6066 lines);
`AGENT.md` `27a8113c56505847f6a75331dd162b8983683b4beaf0c0b242c5d8185dfc9c6b` (747 lines);
`M7_ACCURACY_ITERATION.md` `08c68a31…` (07:17:58), `M7_EVAL_REPLAY.md` `adaf12b8…` (07:17:21).

> Note: the tree moved slightly after the Lead's FROZEN ping — `M7_EVAL_REPLAY.md` (07:17:21) and
> `M7_ACCURACY_ITERATION.md` (07:17:58) were refreshed, and `export/m7-replay/eval.json` was re-run at
> 07:17:10. Engine/code/scripts/evidence were unchanged (07:09–07:13) and this report verifies the
> post-refresh snapshot. If anything changes after 07:21, re-run the commands in §2.

## 0. Re-verification after fixes (2026-11-03 07:30) — supersedes §1/§4 status

The Lead implemented the three required fixes from §4; this section is the post-fix re-check and the
current verdict. The remainder of this document is the pre-fix verification record and is kept for
traceability.

1. **Fix 1 — VERIFY §6 EV-0237 entry: VERIFIED.** `VERIFY.md` now has a full `### EV-0237` section at
   lines 5785–5813 (before `## 7. Status dashboard` at 5814), 29 lines with the same fields/format as
   the other §6 entries (date/commit/dirty/device/host/status, procedure, expected/actual, artifacts,
   verification paragraph citing this report, limitations). All **11 artifact references resolve and
   their 12-char sha256 prefixes match** the refreshed `evidence/EV-0237/` files, and the reference set
   is exactly the manifest's 11 artifacts. File is 6095 lines, header Next ID `EV-0238`; the EV-0237
   change-log row is still present at line 6095. Diff vs HEAD is now +609/−3 = the previous +580/−3
   content plus a pure 29-line insertion (no tail loss; last row still ends "Next ID `EV-0238`" and
   cites `d2c8a8d9…`/120,666 bytes).
2. **Fix 2 — identity file vs docs: VERIFIED.** `export/latest-build-identity.txt` is byte-identical to
   `git show HEAD:` content (sha256 `0e6ca5edd391…`; provider `b77897dd…`/109,829 B = installed
   EV-0236; no diff, not dirty). `STATUS.md` now separates the packaged M6 provider `a109ae56…` from the
   latest installed D1 provider `b77897dd…` (EV-0236) and explicitly calls `d2c8a8d9…` a host-only,
   not-pushed artifact; `M7_PLAN.md` now states evaluator-v2 primary 22/24 (the "being finalised"
   wording is gone). Grep shows no doc contradicts the identity file; `cf3ef0a0…` survives only in this
   report's historical §4 text.
3. **Fix 3 — evaluator robustness: VERIFIED.** Evaluator v2.1 self-check is **6/6 PASS**; the wrapper now
   runs `python3 scripts/m7_eval_replay.py --self-check` before evaluation (lines 67–69; `bash -n`
   clean). The zero-event-target defect is fixed: scoring datasets now come from the fixture source set
   (`is_fixture_source_dataset`, script line 2155) and the gate builders are defensive. Reproduction:
   with a BOW-silenced engine mutant (`FIST_ON=0.10`), the evaluator now reports a **clean FAIL** —
   literal 13/24, primary 14/24, explicit reasons "no replay events for target dataset(s):
   BOW_BOTH_FISTS…", **no traceback/KeyError**, exit 1. Normal gate numbers are unchanged: literal
   **20/24**, primary **22/24**, context **9/9**.
- Fresh post-fix re-runs (final tree): two builds → `d2c8a8d9…`/120,666 B; provider suite exit 0, ALL
  PASS (73 checks, 200k fuzz/0); wrapper exit 1 by design with SELF-CHECK 6/6, replays 07:28:08/09 >
  engine mtime 07:11:23 (no staleness warning); fresh `export/m7-replay/eval.json` is numerically
  identical to the refreshed `evidence/EV-0237/eval.json` (117b6325…; manifest 11/11 artifacts OK).
- **Commit-blocking list: EMPTY.** Remaining non-blocking notes: (a) public `VisionM7Gesture` constructor
  fallback (`VisionM7Gesture.java:377/379`) could invert thresholds if a future caller bypasses the
  VisionVR clamp; (b) engine class-javadoc priority order (`VisionM7Gesture.java:23`) is stale vs
  `M7_GESTURES.md` §4 (code is correct); (c) climb context does not cancel an already-active walk
  (≤1.2 s latency, no wrong action); (d) per-frame `buildSummary` String.format allocation is small but
  non-zero; (e) `closeM7Screen` now prefers `setScreen(null)` — device-path change with no device
  evidence (device A/B checklist); (f) minor doc naming: `M7_ACCURACY_ITERATION.md` says "Evaluator v2"
  while the final tooling is v2.1 (numbers unchanged), and the attack ground-truth window rule would
  still benefit from an explicit spec in `M7_EVAL_REPLAY.md`.
- Provenance: this addendum was added after the refreshed evidence snapshot. The bundle artifact
  `evidence/EV-0237/M7_VERIFICATION_HANDS_OFF.md` is the pre-addendum report (b7cee393…, the hash cited by
  VERIFY §6 and therefore self-consistent); if the bundle should carry this addendum, refresh that one
  artifact and its 12-char reference (optional, not verification-blocking).
- The NOT-device-evidence list in §6 is unchanged and still applies.

## 1. Verdict (pre-fix snapshot — see §0 for current verdict)

| Gate | Verdict |
|---|---|
| Code review (adversarial) | **PASS** — no blocking defect found; cleanup proven dead-code-only; minor observations in §3.6 |
| Provider suite (fresh) | **PASS** — exit 0, ALL PASS, m7-gesture **73 checks / 0 failed**, m7-fuzz **200,000 frames / 0 violations** |
| Replay gate (fresh) | **PASS as documented** — literal **20/24** (FAIL by design, exit 1), evaluator-v2 primary **22/24**, context **9/9**; residuals reproduced exactly; replay files fresh vs engine mtime |
| Metrics reproduction (own code) | **PASS with one flagged definitional delta** — 9/9 headline metric families match committed claims; attack windowed-peak count is GT-rule sensitive (29 vs literal-GT 31 = −6.5%, see §3.4) |
| Docs/evidence consistency | **PASS with exceptions** — numbers verified against `eval.json`, jar claims true; 2 commit-blocking and 3 minor inconsistencies in §4 |
| Hygiene | **PASS except the identity-file inconsistency** (part of §4); no raw JSONL/fixtures/replays/binaries staged or tracked |

**Commit status: 2 required fixes block commit** (VERIFY §6 EV-0237 entry; `export/latest-build-identity.txt`
reconciliation) **+ 1 recommended tooling fix** (evaluator crashes instead of gating when a target dataset
emits zero events — §4 fix 3). All claimed host metrics are true and independently reproduced.

## 2. Commands run and log paths

| Check | Command (all from repo root) | Log |
|---|---|---|
| Full provider suite | `PROVIDER_OUT=/tmp/verify-m7/final-provider provider/tests/run_tests.sh` | `/tmp/verify-m7/final-tests.log` (exit 0) |
| Two-build repro | `OUT_DIR=/tmp/verify-m7/final-a scripts/build_provider.sh`; same with `final-b` | `/tmp/verify-m7/final-build-a.log`, `-b.log` |
| Replay gate | `PROVIDER_OUT=/tmp/verify-m7/final-a scripts/m7_lab_replay.sh --skip-build` | `/tmp/verify-m7/final-replay.log` (exit 1 by design) |
| SKIP path | `LAB_DATA=/tmp/nonexistent scripts/m7_lab_replay.sh --skip-build` | inline: `[m7-replay] SKIP: no recordings at /tmp/nonexistent/accepted`, exit 0 |
| Independent metrics | own throwaway Python over raw JSONL | `/tmp/verify-m7/indep_metrics2.py`, `/tmp/verify-m7/attack_variants.py` |
| Engine safety probe | own Java class compiled against final classes | `/tmp/verify-m7/probe/HandSafetyProbe.java` → HAND-SAFETY-PROBE PASS |
| Cleanup equivalence | differential replay pre-cleanup classes vs final classes | `/tmp/verify-m7/old-*/events.jsonl` vs `new-*/events.jsonl` (0 diff lines) |
| Evidence manifest | own validator over `evidence/EV-0237/` | `/tmp/verify-m7/evidence_check.py` (9/9 artifact hashes OK) |
| VERIFY backfill | own validators | `/tmp/verify-m7/verify_md2.py` (110 artifact refs, 0 missing, 0 mismatched), shell check: 24/24 commit hashes exist |
| Gate-sensitivity mutants | copies of engine in /tmp, changed constant, real harness + evaluator | `/tmp/verify-m7/mutant*` (see §3.3) |

## 3. Findings per gate

### 3.1 Provider suite — PASS
Fresh run exit 0: `m7-gesture 73 checks, 0 failed`; `m7-fuzz frames=200000 violations=0`;
`[provider-tests] ALL PASS`; also m4-fuzz 20k/0, gaze 500k/0, settings/JSON/smoother/pose fuzz all pass.
Matches `evidence/EV-0237/provider-tests-final2.log` (only JVM heap addresses and my added
`SUITE_EXIT:0` line differ). 73 checks also matches `M7_TEST_MATRIX.md` §"Synthetic check list (73)".

### 3.2 Replay gate — PASS as documented
Fresh wrapper run (fixtures 07:13:53/55, replays 07:13:55/56, engine 07:11:23 → **no staleness warning**):

- **Literal conservative: 20/24 rows pass → FAIL (exit 1)**. Residual literal rows exactly:
  hotbar precision 0.83 < 0.85; attack precision 0.66 < 0.80; walk false-active 0.18 > 0.10;
  eat false-active 0.25 > 0.15. Context suppression 9/9 PASS.
- **Evaluator-v2 primary: 22/24 rows pass** (same 20 pass rows + walk/eat). Residual primary:
  hotbar recall 0.75 < 0.80; attack recall 0.77 < 0.80 and precision 0.71 < 0.80.
- Exit code 1 is deliberate (conservative literal gate governs exit); the wrapper regenerates fixtures,
  both replays and `export/m7-replay/eval.json`.
- Current `export/m7-replay/eval.json` is **numerically identical** to `evidence/EV-0237/eval.json`
  (97381ff…) after removing volatile fields (generatedAt/mtime/notes/exit) — evidence is reproducible.
- `scripts/m7_lab_replay.sh` without recordings: `SKIP`, exit 0 (verified).
- Gate sensitivity: mutant with `ATTACK_SPEED=0.30` fails gates as expected — literal 19/24, primary
  21/24, attack precision 0.48 + false 9.30/min. Mutant with `FIST_ON=0.10` instead **crashes the
  evaluator** (see §4 fix 3), which is a tooling defect, not a gate failure (reproduced twice).

### 3.3 Reproducibility / artifact identity — PASS
- Two independent builds into `/tmp/verify-m7/final-a` and `final-b`: both
  sha256 `d2c8a8d96e5a0ea0a836b080b2243ed1cb0c16f22bf29ca1da514f48159438fc`, **120,666 bytes**.
- Matches `evidence/EV-0237/provider-jar.sha256` and the documented size; the claim
  "provider jar `d2c8a8d9…` (120,666 bytes), two-build reproducible" is **true**. No doc still cites the
  pre-cleanup hash (`d0d8f07c…` / 120,974 bytes) or `120974`.

### 3.4 Independent metric reproduction (raw JSONL, own feature code) — PASS, one flagged delta
Recomputed from joint matrices / head pose in `export/gesturelab-data` (not repo scripts; stored
features only used as a cross-check: pinch recomputation agrees to 1.45e-08 m).

| Claim (doc) | Reproduced | Delta |
|---|---|---|
| PLACE 76 pinch events; 72 short <0.35 s; 4 long 4.06/3.39/0.61/0.36 s | 76 completed; 72 short (0.06–0.22 s); long 4.06/3.39/0.61/0.36 s | exact |
| BREAK 7 holds 1.21/1.49/1.98/2.24/3.36/4.33/10.44 s | same 7 values | exact |
| MENU 42 events; TELEPORT 16 left events | 42; 16 | exact |
| INVENTORY both-fist runs 24 / 75 frames, p50 0.17 max 0.28 s | 24 / 75, p50 0.17, max 0.28 | exact |
| WALK head-forward crossings 59 (p50 0.500, max 0.923; p95 amp 0.360); world-Z crossings 53; z corr −0.728; head-frame corr −0.376 | 59 (0.500/0.923; 0.360); 53; −0.728; −0.376 | exact |
| ATTACK per-sample p50/p95/max 1.32/2.97/4.75 m/s; 228 frames >1.4; 28 swings | 1.32/2.97/4.75; 228; 28 | exact |
| ATTACK windowed-speed GT count | my simple literal local-peak rule → 29; rising-edge rule → 35; committed literal GT 31, primary GT90 35 | local-peak −6.5% vs literal GT (rule-definition sensitive; analysis' own 28 reproduced exactly) |
| JUMP 29 head-rise events (>0.08 m), peaks 0.114–0.317 m, durations 0.22–3.95 s median 0.39 | 29; peaks 0.12–0.32; durations 0.22–3.95 s median 0.39 | exact (rounding) |
| IDLE is numerically identical to MENU (563/563, t/head/27 joints) | 563/563; max |dt| = 0; max head diff = 0; 20,034 joint comparisons all equal; 0 presence mismatches | exact |
| WALK both-fist frames 420 (<0.55) / 439 (<0.65); BOW 24 runs/216; CLIMB 19/117 | 420 / 439; 24/216; 19/117 | exact |

Only the attack windowed-peak count is definition-sensitive at ~18 Hz: the evaluator's exact
window-sample/peak rule should be spelled out in `M7_EVAL_REPLAY.md` to make 31 reproducible
(suggested doc fix, not a data or engine error — the attack row is the documented residual anyway).

### 3.5 Engine cleanup (`d0d8f07c…` → `d2c8a8d9…`) — dead-code only, verified
- `javap -p` diff of old (pre-cleanup classes, /tmp/verify-m7/build-a) vs final classes shows exactly
  the removed members: `HOTBAR_QUIET_RESET_NS`, `HOTBAR_QUIET_SPEED`, `tipL`, `thumbL`, `thumbR`,
  `pinchLastDurationL`, `bowPrev`, `prevWinSpeedR`, `hotbarTipQuietSinceNs`, `prevTipSpeedR`
  (all write-only/dead); **no method-signature or public-API change**.
- Differential replay of the same fixtures through old vs final engine: `events.jsonl` **byte-identical**
  (0 diff lines) for both 90 Hz and raw 18 Hz replays, summaries identical. No condition changed.
- Fresh engine still passes no-wall-clock grep (pure engine: no `currentTimeMillis/nanoTime/Instant/
  Instant/Clock/random`) and the 73-check/200k-fuzz suite.

### 3.6 Adversarial code review — PASS with minor observations
Verified in the final sources:
- **Purity / frame-rate independence**: engine has no wall-clock/random calls; timestamps come from the
  caller; head baseline is dt-corrected (`alpha = 1-exp(-dt/τ)`), speeds are windowed displacement over
  time, all timers are nanosecond deadlines. Independent probe: same jump/sneak profile at 18/30/45/90/144 Hz
  gives exactly 1 jump and a 4.11–4.20 s sneak latch at every rate.
- **NaN/untracked-hand safety**: probe passes — a NaN right pinch, an untracked right hand, or NaN right
  joints do not release an in-progress left teleport; a NaN head pose fails closed (releases all).
  `updatePinch` is per-hand; only malformed joints/head call `releaseAll`.
- **Release paths**: pulses ≤80 ms; held states require per-frame tracked+geometry; GUI/seated/tracking-loss
  release verified in the probe; `releaseAll` idempotent and complete (fuzz + probe).
- **Tune parsing**: `buildM7Gesture` clamps `pinchOn∈[0.005,0.080]`, `pinchOff ≥ pinchOn+0.005`,
  `fistOn∈[0.20,1.00]`, `fistOff ≥ fistOn+0.03`, rejects non-finite → **no inverted thresholds reachable**
  from the tune file / M4 calibration keys. (Latent hardening only: the public `VisionM7Gesture`
  constructor's fallback at `VisionM7Gesture.java:377/379` uses the default off value if an off ≤ on is
  supplied, which could invert if a future caller bypasses the VisionVR clamp; not reachable today.)
- **Priorities vs `M7_GESTURES.md` §4**: GUI/bow/climb/walk/eat/attack/place/teleport suppression is
  implemented as documented. Minor stale comment: engine class javadoc (`VisionM7Gesture.java:23`) says
  "…climb/grab > eat > walk…" while `M7_GESTURES.md` §4 (lines 58–72) puts walk above eat; the code matches
  §4 (walk suppresses eat), so the code comment is stale, not the behaviour.
- **Stuck path**: no wall-clock latch; output pulses are bounded; dispatch `releaseM7Actions()` runs when
  input is unhealthy/stale (VisionVR `processInputs`), and `releaseAllImmediately` runs when seated or no
  hand is tracked. No stuck path found.
- **Context probes fail closed**: `computeM7Context` (VisionVR:861) wraps GUI/seated/climb probes in
  `catch (Throwable)`; `VisionM7ItemContext` resolves reflection once and returns 0 on any failure
  (bow/eat context off, geometry-only fallback available); `m7.context=off` override exists. The
  GuiHandler mixin is valid JSON and cancels Vivecraft's `processGui` only when `VisionVR.m7OwnsGuiCursor()`.
- **Build/deps**: `build_provider.sh` unchanged; 32 classes from 24 sources on the pre-existing classpath;
  no new dependency added.
- Minor observations (not required fixes): (a) per-frame `buildSummary` (line 1274) formats a summary string
  with `String.format` every frame — small 90 Hz allocation, bounded; (b) climb context does not cancel an
  already-active walk (walking suppresses starting a climb); worst case ~1.2 s latency, no wrong action;
  (c) `closeM7Screen` now prefers `mc.gui.setScreen(null)` over the EV-0236 `onClose()` path — a
  device-path change with no device evidence (must be on the device A/B checklist).

## 4. Discrepancies and required fixes

**Required before commit**

1. **VERIFY.md does not record EV-0237 in §6 (evidence log).** The file rules (§ header lines 9–12 of
   VERIFY.md: "Valid evidence: only entries listed in §6"; §0 rule 1) mean EV-0237 is otherwise
   *unallocated* although cited in AGENT/VERIFY change-log rows and all M7 docs. Currently EV-0237 exists
   only as the last change-log row (line 6066, after §10), while §6 detailed entries end at EV-0236
   (line 5762). Fix: add a §6 detailed EV-0237 entry (and dashboard row if desired).
2. **`export/latest-build-identity.txt` contradicts the device claims.** Lines 8–9 claim provider
   `cf3ef0a0…` / 110,857 bytes "push/integrity: OK", while M7_ACCURACY_ITERATION.md:6, M7_ENGINE.md:64–65,
   M7_PLAN.md:5, STATUS.md:70 and VERIFY.md:6066 all say the EV-0237 jar was **not pushed** and the installed
   D1 provider remains EV-0236 (`b77897dd…` / 109,829 bytes). No evidence artifact references `cf3ef0a0`;
   the file's mtime is 2026-11-02 22:54 (before the final engine), and M7_PLAN says to refresh the identity
   only *after* device A/B. Fix: restore the EV-0236 identity values (or, if a push really happened, record
   it with evidence and correct the four docs) — do not commit the contradiction.
3. **Evaluator robustness defect (recommended fix, blocks using it as a regression gate).**
   `scripts/m7_eval_replay.py:1927` builds `scoring_datasets` only from dataset ids present in the replay
   event files; :2013/2019/2035 then overwrite `score["skipped"] = False` on the "no target ids" early
   return. Result: an engine regression that silences a target dataset (reproduced with
   `FIST_ON=0.10`, which removes all BOW events) makes the evaluator raise
   `KeyError: 'recall'` at :1818 instead of reporting gate failures (stderr traceback, exit 1). Fix: keep all
   replayed/raw datasets in scoring, and only clear `skipped` when the score dict is a real score.

**Minor (docs consistency) — not necessarily blocking**

4. `M7_PLAN.md` "Risks" (lines 32–35) still says the 90 Hz-derived GT variant "is being finalised" — it is
   final and is the primary gate (22/24); stale sentence.
5. `STATUS.md` "Current installed build (D1)" (lines 7–12) lists app `2388965a…` / provider
   `a109ae56…` (92,516 bytes) / package `4d9141f0…`, which contradicts the later "installed device
   provider remains the EV-0236 jar" (line 70). Pre-existing stale section; update for consistency.
6. `M7_EVAL_REPLAY.md:135` cites an evaluator run at 2026-11-03 07:17:10 on replays 07:13:55/56, while
   `evidence/EV-0237/eval.json` was generated at 07:12:10 (from the Lead's wrapper run). The two runs are
   numerically identical (verified), so no number is wrong; if strict provenance matters, recapture the
   evidence eval.json from the cited run or reword the doc to "latest rerun (identical)".
7. Suggest documenting the exact attack ground-truth windowing/peak rule in `M7_EVAL_REPLAY.md`
   (my independent literal re-derivation gives 29 vs the recorded 31; primary GT 35 is reproducible with a
   rising-edge rule).

## 5. VERIFY.md / AGENT.md / hygiene details

- VERIFY.md: 6066 lines (HEAD: 5489); header next ID `EV-0238` (line 8); last row is EV-0237 (line 6066);
  HEAD's final tail line is preserved byte-for-byte as the prefix of current line 6055 (no tail loss).
- Actual diff vs HEAD is **+580/−3 lines**, not the "+1 table row + 2 header edits" in the task brief:
  2 header-line edits + **552-line backfill** of §6 detailed entries EV-0213…EV-0236 + **14 §7 dashboard
  rows** + **12 change-log rows** (EV-0214, EV-0228…EV-0237 appended after §10, extending the previous final
  line). The backfill is evidence-accurate: all **110 artifact paths exist with matching sha256 prefixes**
  (0 missing / 0 mismatch) and all **24/24 cited commits exist** in the repo. Flag this scope to the Lead
  (intended? it is valid content) — and add the missing EV-0237 §6 entry (fix 1).
- AGENT.md: 747 lines; diff is exactly one appended change-log row for EV-0237 (no rewrite, no tail loss).
- Hygiene: nothing staged (`git diff --cached` empty); 13 untracked files are exactly the intended
  source/docs/tests/scripts; no raw JSONL, fixtures, replay outputs, jars or binaries tracked or staged
  (`git ls-files` check clean); `.gitignore` covers `/export/m7-lab-fixtures*/` and `/export/m7-replay*/`
  (verified with `git check-ignore`); `scripts/m7_lab_replay.sh`, `scripts/m7_eval_replay.py`,
  `scripts/m7_lab_fixture.py`, `provider/tests/run_tests.sh` are executable; no unrelated files.
- Evidence bundle: `evidence/EV-0237/` manifest/entry match the final claims; all 9 artifact sha256 values
  match the files; jar sha256 file = `d2c8a8d9… / 120,666`; `git-status.txt`/`diff-stat.txt` match the
  current tree; commit `dab273b` and 27-file dirty list match. `evidence/` is gitignored (local bundle).

## 6. Claims explicitly NOT device evidence

The following are host-only and must never be cited as device/operator evidence:

- Provider host suite results (73 synthetic checks, 200,000-frame fuzz, all fuzz suites, exit 0).
- Replay gates (literal 20/24, primary 22/24, context 9/9), recall/precision/coverage/false numbers, and the
  "baseline 12/24" comparison — all measured by replaying ~18 Hz Gesture Lab recordings through host Java.
- Two-build reproducibility, jar sha256 `d2c8a8d9…`/120,666 bytes, append-only evidence artifacts.
- All dataset analyses (pinch/fist/attack/hotbar/eat/bow/climb/walk/teleport/menu/inventory and
  jump/sneak/head-frame/pitch findings) — recorded lab data, not live device tracking.
- Fitted thresholds, context-bit behaviour, GUI head-ray cursor, item-context probe, GuiHandler mixin,
  `closeM7Screen` path, real-hand jitter/feel, false-trigger rate, latency, and thermals — **EV-0237 has no
  device A/B run**; the installed D1 provider remains EV-0236 (per docs; reconcile the identity file per §4
  fix 2). Everything about actual headset behaviour for this engine revision is NOT RUN.
