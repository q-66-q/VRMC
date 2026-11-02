# M4-W1 independent verification — immersive-scene input channel

**Status: COMPLETE — verifier verdict on the frozen tree (2026-11-01).**
**Auditor:** m4-verifier (task-4). Product code is read-only for this role; defects were reported to the
Lead and fixed by the implementers, never patched by the verifier. No device access, no git commits.

- **Frozen tree:** repo HEAD `5d6622c` + 43 uncommitted M4-W1 changes; implementers' last write
  2026-11-01 20:16 HST, frozen snapshot taken 20:17 HST. After the freeze only Lead-owned
  finalization changed: doc status rows, the EV-0095 VERIFY entry + evidence bundle, and the revert of
  the tracked preview framework (F13). The verifier re-hashed every implementation file after both
  frozen selfcheck runs and they are byte-identical to the frozen snapshot (§8); post-verdict
  finalization was re-audited (§5.1) — implementation untouched.
- **Contract:** [immersive-input.md](immersive-input.md) · **Plan:** [M4_PLAN.md](../mvp/M4_PLAN.md) ·
  **Device runbook:** [M4_DEVICE_RUN.md](../mvp/M4_DEVICE_RUN.md) · **Rules:** AGENT.md §0/§9/§10.
- **Evidence classes:** **HOST** (C bridge / JVM provider / cross-language fixture) · **SIM**
  (visionOS simulator: real compositor + fake bridge/provider; plumbing only) · **INSPECT** (code
  reading; never `PASS` on its own) · **DEVICE / HANDS = NOT RUN** (no headset access in this audit;
  nothing in this document is hands evidence).

---

## 0. Bottom line

- **W1 host + simulator: PASS** — independently reproduced on the frozen tree (every command and log in
  §4/§8): ABI v3 byte contract, bridge publish/acquire/poll + release semantics, TSan concurrency, C→Java
  cross-language fixture, JVM gesture/pose/action-set/binding logic, the Mixin-only Vivecraft extension,
  the real compositor's input publication + zeroed release in the visionOS simulator, and both
  one-command self-checks end-to-end.
- **Safety-critical invariant (G4 "no stuck input") holds in code and is test-enforced**: same-frame
  release on tracking loss, 250 ms stale-input release, 100 ms released-state arming, 2-frame tap edges
  (never latches), release snapshot before `ar_session_stop`, fail-safe on malformed/short/old bridge
  input. No open stuck-input path was found.
- **No open BLOCKER/HIGH defects at freeze.** 13 findings were raised during the work (F1–F13), plus a
  noted-only docs nuance (F14) and one evidence-metadata defect found in the post-verdict finalization
  (F15); all are fixed or resolved-by-decision and re-verified (§5). Lead
  finalization after the verdict applied the two required conditions: the tracked preview framework is
  reverted (working tree clean; F13) and EV-0095 is recorded in VERIFY.md with an honest evidence class
  (H4). One LOW/MEDIUM evidence-metadata defect found in that finalization (manifest dirty-list typo,
  F15) was fixed and re-verified (manifest now matches the final pre-commit working tree exactly; §5.1);
  it does not affect the verification result.
- **Real hands / device input remain NOT RUN.** This verification does NOT claim hands evidence, device
  input PASS, stereo optics, thermals or latency; AC-4/ST-S5-hands are unchanged. The device runbook and
  a signed staged bundle are ready for the operator session.
- **The window/UIKit input path is unchanged** by this change (all product edits are additive to the
  input channel / provider backend), and the M3c presentation scenarios remain green (no regression).

---

## 1. Method and evidence boundaries

1. Everything was run by the verifier from the repo root on the frozen tree; implementer evidence was
   not taken on faith (each item below was re-executed or re-derived with the verifier's own tools).
2. The ABI contract was re-derived from `bridge/abi/*.h` + the design tables with an independent C
   program and an independent Python parser of the fixture bytes (not the project's own test code).
3. The simulator scenario was run by the verifier and the capture/logs were independently analysed.
4. **Host PASS proves logic and the byte contract, not hands. Simulator PASS proves the real
   compositor→bridge publication path and wire format, not ARKit hand capture on device.**
5. A device synthetic run would prove the device stack down to the game's action handling, and only an
   operator-confirmed real-hands session can move AC-4/ST-S5-hands — both are explicitly NOT RUN.

## 2. Frozen-tree scope audit (A1–A5)

Changed tracked files: 25; new files: 14 (all text: C/Java/Swift/docs/scripts). No Minecraft jars,
IPAs, prebuilt frameworks, caches or device artifacts are added; `/evidence`, `/artifacts`,
`/export`, `/vendor` are untouched by this change. Reference trees are untouched (newest
`VivecraftMod-Multiloader-26.2` source mtime is 2026-10-06; no files newer than the M4 start; Amethyst
tree likewise). Vivecraft stays unmodified; the only Vivecraft-facing code is the two provider Mixins
plus `extends MCVR`. macstream-derived code carries LGPL-3.0 + upstream `ec5a851c…` + ADR-0009
provenance comments and lives only in the LGPL provider (ADR-0009, MACSTREAM_REFERENCE §4/§6b,
AGENT §10.4).

**One working-tree hygiene item (F13, Lead-decided):** the tracked preview build
`runtime/native-shell/build/VRMCShell.framework/` (4 binaries) is dirty in the working tree because the
device-staging framework was rebuilt from the frozen tree there. Decision: **keep git clean** — the
Lead reverts those 4 files before committing and the runbook now builds+verifies the framework
immediately before staging. The staged artifact lives outside git (`artifacts/`, ignored). Residual
footgun recorded in §6.

## 3. Checklist verdicts

Legend: **PASS** = executed by the verifier on the frozen tree (or INSPECT + tests where only static
review applies, marked); no item failed. Evidence pointers reference §4 rows / §8 paths.

### A. Change hygiene / scope

| # | Check | Verdict |
|---|---|---|
| A1 | Diff touches only M4-W1 scoped paths (bridge ABI per Lead, bridge src/tests, provider src/tests/README, `VRMCCompositor.mm` + 1-line `Shell.swift`, m3c-provider-sim, docs, scripts) | **PASS** (frozen fingerprint §8; out-of-scope filter: none) |
| A2 | No generated binaries/build outputs/caches/device artifacts in the change | **PASS** — the only exception, the tracked framework preview (F13), was reverted by the Lead after the verdict: `git status runtime/native-shell/build/` is now clean at the post-verdict re-audit; no new binary files are added; evidence bundle added under git-ignored `evidence/` (not committed). |
| A3 | No third-party trees / Minecraft jars / IPAs / prebuilt framework binaries committed | **PASS** — reference trees git-ignored and untouched; staged bundle under ignored `artifacts/` |
| A4 | Vivecraft reference tree unmodified ("Vivecraft unmodified" claim holds) | **PASS** — no writes under the reference tree; change is provider `extends MCVR` + Mixins only |
| A5 | Licensing provenance for macstream-derived code, LGPL provider only, upstream commit recorded | **PASS** — provenance comments in VisionVR/VisionInput/VRInputActionMixin; ADR-0009 + MACSTREAM_REFERENCE updated |

### B. ABI v3 byte contract

| # | Check | Verdict |
|---|---|---|
| B1 | `sizeof(vrmc_hand_state)==368`, `sizeof(vrmc_input_state)==752`, 8-byte alignment | **PASS** (independent C program; bridge static asserts; provider layout test) |
| B2 | Offsets match design §3.1/3.2 (hand 0/4/8/16/32/44, joint stride 12; input 0/4/8/16, hands[1] at 384) | **PASS** — independent C `offsetof` + bridge `_Static_assert` + `VisionInputLayoutTest` 68 checks |
| B3 | Headers compile as C11 and ObjC++/C++17; new entry points are **unmangled C** symbols (dlsym) | **PASS** (verifier header check; this was the F1 early BLOCKER, fixed and re-verified) |
| B4 | Java constants match C exactly; test-enforced | **PASS** — `VrmcBridge` constants compared exhaustively; joint-index constants match the ARKit enum order; layout test PASS |
| B5 | caps `{"abi":3,"eyes":2,"hands":2,"input":1}`; abi 2 rejected; mismatch fails closed in provider init | **PASS** — `vrmc_init` abi-3 accept / abi-2 reject in bridge tests + verifier JNI smoke; provider returns false on mismatch. (Stub bridge matches the abi token by substring; the effective gate is `vrmc_abi_version()` + paired shipping — note in §6) |
| B6 | `hands[0]=LEFT / hands[1]=RIGHT` independent of chirality; chirality NORMALIZED 0=left/1=right with explicit ARKit-enum mapping | **PASS** — compositor maps ARKit's inverted enum, publishes by slot; fixture shows Lchir=0/Rchir=1; provider indexes by slot |
| B7 | Cross-language fixture: 752 B contract snapshot + 7520 B/10-record/150 ms timeline; Java replay asserts timeline + exactly one f7 tap; SKIP-not-PASS when unset | **PASS** — independent Python parser (written only from the design doc) reproduces the exact timeline and f7 tap arm; hashes `50926fdc…`/`43d52113…`; provider fixture test 61 checks; SKIP/FAIL/PASS paths all exercised |
| B8 | `vrmc_poll_input` contract: safe zeroed pre-publish, short-buffer/uninitialized rejection, JNI capacity validation | **PASS** — bridge tests + verifier JNI smoke (12/12: safe zero, -6 short, -5 non-direct, abi-2 reject) |
| B9 | Sequence: 0 before first publish, monotonic per publish, for change detection only; release snapshot supported | **PASS** — bridge input test + TSan; init resets the channel to the safe zero state (documented in the bridge) |

### C. Bridge implementation (task-1)

| # | Check | Verdict |
|---|---|---|
| C1 | Full `bridge/tests/run_tests.sh`: all pre-existing tests + new input test | **PASS** — frozen run 38 PASS lines, 0 FAIL, `ALL PASS` (metal host probe SKIP: no MoltenVK SDK, pre-existing) |
| C2 | Input test: layout asserts, round-trip, seq, pre-publish zero, short buffer, uninitialized, release | **PASS** (5 sections + TSan variant) |
| C3 | TSan input test: 500k publishes × 4 readers, no race/torn state | **PASS** — `input-test-tsan` 0 torn/0 seq regressions, 2.4M reads in the verifier run |
| C4 | `build_bridge.sh MODE=both` PASS; symbol list includes all ABI-v3 input + JNI symbols; platform retag valid | **PASS** — both dylibs platform=11/minos 1.0 (device) and platform=1/minos 27.0 (host); verifier `nm` confirms `_vrmc_poll_input`, `_vrmc_shared_{publish,acquire}_input`, `_vrmc_shared_input_sequence`, `_Java_…_nativePollInput` |
| C5 | ABI 3 accept / ABI 2 reject; no stale abi-2 caps in tests/tools | **PASS** — stub self-test + input test + sync/metal tests updated; remaining "v2" mentions are historical/explanatory only |
| C6 | Mutex-protected snapshot copies, no torn reads, error paths set last_error | **PASS** — INSPECT + TSan |
| C7 | Fixture generator compiles/runs standalone; 752 B + 7520 B artifacts; prints sha256/frame table | **PASS** — generator run + artifact sha check + verifier parser (§4) |

### D. Provider implementation (task-3 + follow-ups)

| # | Check | Verdict |
|---|---|---|
| D1 | Full `provider/tests/run_tests.sh`: all pre-existing GPU-sync steps + M4 steps | **PASS** — frozen run ALL PASS: build, flag, fallback ×3, VkReflect ×2, m4-layout 68, m4-gestures 157, m4-pose 61, m4-fixture 61 checks, 0 failed; vulkan-host SKIP (no MoltenVK SDK, pre-existing) |
| D2 | `scripts/build_provider.sh` PASS; jar contains the new classes; no game/LWJGL dependency added | **PASS** — 14 classes from 10 sources, 51,298 B jar (build sha varies per jar-tool timestamp by design); jar grep confirms VisionInput/VisionHandPose/VRInputActionMixin classes |
| D3 | Gesture tests: pinch/fist hysteresis, tap single-fire, both-fist chord priority, arming, stale release, action-set gating, binding table | **PASS** — 157 checks incl. the follow-up both-fist chord priority (per-hand taps suppressed while both fists engaged; single-hand taps unchanged) |
| D4 | Pose tests: `R*(0,0,-1)=aim`, orthonormal basis, left/right, gaze fallback, degenerate fallback | **PASS** — 61 checks (this test caught the F2-class transposed-matrix bug during the work; fixed and re-verified) |
| D5 | Parse tests: offsets, slot indexing, tracked mask, malformed/short buffer, stale sequence | **PASS** — parse/acquisition/arming sections + layout + fixture replay + INSPECT `parseHand` |
| D6 | Integration: ONE preallocated direct ByteBuffer, poll order getTracking → input/poses → pollDisplayViews → updateAim → processInputs → hmdSampling → markPolled, no per-frame allocation, rate-limited `[VRMC-M4]` logs, seated warning, pose diagnostic | **PASS (INSPECT + host build/tests)** — order matches design §5.6; action dispatch logging (F12) and pose diagnostic added; allocations only on log paths |
| D7 | Mixin applies only for `MCVR.get() instanceof VisionVR`; MCOpenVR path untouched; generic backend/origin/priority logic; listed in `vrmc.mixins.json` | **PASS (INSPECT + compile against pinned Vivecraft 26.2)** — HEAD inject, cancellable only for VisionVR; MCOpenVR falls through; config `required:true`, `defaultRequire:1`; project limitation: no game instance in host tests, so mixin application is target-level/compile-level (pre-existing limitation, same for `VRStateMixin`) |
| D8 | Binding table matches design §5.4 exactly (12 rows, 10 actions, hands, sets, origins 1=L/2=R, inventory both-fist origins) | **PASS** — test asserts the exact table; INSPECT confirms |
| D9 | Tap pulses are 2-frame edges, never latches; release paths cannot leave a pressed state | **PASS** — tests + INSPECT (dispatch + immediate-release paths; chord priority cancels in-flight per-hand pulses) |
| D10 | Tuning: file + `-D` fallbacks read once, logged, defaults match design | **PASS** — keys `pinch.on/off`, `fist.on/off`, `fist.hold.ms`, `arm.ms`, `stale.ms`, `tap.frames`; `-Dvrmc.input.<key>`; single `input tuning:` line; docs aligned (F7) |
| D11 | Failure modes: old/missing bridge, short buffer, stale, tracking loss, seated — log once, fail safe, no crash | **PASS (INSPECT + tests)** — init/poll catch paths, one-time warnings, release-on-fault; seated releases + one warning; never silently pretends hands work |

### E. Compositor implementation (task-2)

| # | Check | Verdict |
|---|---|---|
| E1 | Hand provider in the SAME ARKit session as world tracking; `is_supported()` logged once; unsupported degrades gracefully; **authorization requested once, status logged, denied ⇒ untracked + clear log; synthetic skips the request**; chirality normalized | **PASS (INSPECT)** — every F3/F4 requirement encoded; negative paths keep the session world-only so presentation never regresses |
| E2 | Per-frame query at `cp_frame_timing_get_trackable_anchor_time` → `ar_hand_tracking_provider_query_anchors_at_timestamp`; 27 joints via anchor-from-joint composition; wrist transform; device/anchor space (same as head, no extra transform) | **PASS (INSPECT + SDK cross-check)** — API names/shapes verified against the XROS 27.2 ARKit headers; composition `originFromAnchor * anchorFromJoint`; positions/quaternion copied; nil skeleton/joint guarded (F10) |
| E3 | One publication per frame via dlsym `vrmc_shared_publish_input`; missing symbol logs once and presentation continues; frame_index/valid_mask/timestamp set; no per-frame malloc; rate-limited logs | **PASS (INSPECT + SIM log)** — publication once per drawn frame, dlsym-failure branch, preallocated stack state, rate-limited lines |
| E4 | Release-on-exit: zeroed snapshot before `ar_session_stop` on all loop-exit paths | **PASS** — code path covers stop-requested/invalidated exits; simulator capture's LAST record is `valid_mask=0` (363/341-record runs) |
| E5 | Synthetic input via `Documents/vrmc-input-sim.flag` (content-selectable scripts, default cycle), plausible 27-joint hands (pinch 5 mm vs open 68 mm; fist ratio 0.77 vs 1.89), ignores ARKit hands, `INPUT-SIM … SYNTHETIC` labelling | **PASS (INSPECT + SIM capture/logs)** |
| E6 | Simulator `input` scenario PASS: ≥30 snapshots, valid_mask framing, pinch/fist crossings, final release, no input errors | **PASS** — frozen-tree verifier run: 341 records (340 tracked + final mask 0), seq contiguous, pinch 0.0050→0.0744, fist 0.767→1.890, 0 error markers; plus Lead's frozen run 363 lines |
| E7 | Existing presentation scenarios still green (no presentation regression) | **PASS** — verifier `flat` run on the candidate tree + frozen-tree `m3c_selfcheck` full run (all six presentation scenarios) |
| E8 | Device-target shell compile with the compositor changes | **PASS** — verifier `xcodebuild … generic/platform=visionOS` BUILD SUCCEEDED; also exercised by the frozen m3c run's `build_shell(device)` |

### F. One-command self-checks

| # | Check | Verdict |
|---|---|---|
| F1 | `scripts/m4_input_selfcheck.sh` (full) end-to-end PASS | **PASS** — frozen-tree verifier run: RESULT PASS (bridge-tests, fixture, provider-build, provider-tests, simulator input all PASS) |
| F2 | The selfcheck fails closed on a defect (meaningful assertions, not just command runners) | **PASS (INSPECT)** — per-step exit-code checks, fixture size/label checks, provider tests require the cross-language `PASS` grep (a silent SKIP fails), bridge suite exit code propagated |
| F3 | `scripts/m3c_selfcheck.sh` includes the M4 step and full run PASS end-to-end; presentation checks unchanged | **PASS** — step 7/7 runs the M4 selfcheck full; frozen verifier run RESULT: PASS |
| F4 | Output states the evidence class explicitly (host+simulator, not hands/device) | **PASS** — final lines of both scripts state it |
| F5 | Selfcheck scripts never touch the physical device | **PASS** — no `devicectl`/install/launch commands in either script |

### G. Safety invariants (G4 "no stuck input")

| # | Check | Verdict |
|---|---|---|
| G1 | Hand not tracked ⇒ that hand's sources released the same frame | **PASS** — `VisionInputTest` tracking-loss sections + `releaseActionsForHand` immediate releases (INSPECT) |
| G2 | Stale input (>250 ms or frozen sequence) ⇒ everything released + one warning | **PASS** — test section + provider code; stale line format matches runbook |
| G3 | 100 ms released-state arming after acquisition; an unarmed press can never present | **PASS** — dedicated test section + code review |
| G4 | Tap/teleport/GUI-click are edges, not latches; 2-frame pulse; single-fire per hold re-armed on release; both-fist chord owns its gesture | **PASS** — tests (157 gesture checks) + chord follow-up |
| G5 | Session end/crash: release snapshot + 250 ms stale release; no path leaves attack/teleport pressed | **PASS** — sim capture ends with release; stale timer covered for crash/kill cases |
| G6 | ABI mismatch/old bridge/short buffer ⇒ fail safe, never stale motion | **PASS** — bridge + provider tests, JNI smoke, INSPECT |

### H. Docs consistency / evidence honesty

| # | Check | Verdict |
|---|---|---|
| H1 | M4 docs/READMEs do not claim hands/device PASS; statuses labelled | **PASS** — hands claims appear only as "NOT RUN unless an operator session"; plan says "PASS to be recorded as EV-0095", design status still IMPLEMENTING at freeze (accurate) |
| H2 | Simulator input described as plumbing only, never hands | **PASS** — harness README, plan matrix, selfcheck output, runbook all label it |
| H3 | Device runbook preconditions real: Info.plist keys, clear-diagnostics, build+verify framework from frozen tree, staged bundle+jar, M4 markers | **PASS** — staged app independently verified: bundle id/NSHandsTrackingUsageDescription, embedded framework platform 11 with 3× `INPUT-SIM SYNTHETIC` strings, bridge exports the input symbols, `codesign --verify --deep --strict` rc=0; provider jar contains the final classes; runbook Step 0 now builds+greps the framework (F13) |
| H4 | VERIFY.md/AGENT.md final status/EV entries consistent | **PASS (post-verdict re-audit)** — EV-0095 is recorded in VERIFY.md §6 with an honest status ("PASS (host + simulator plumbing) — device synthetic and real hands NOT RUN"), explicit limitations, the verifier-report link and 21 hashed artifacts; "Next evidence ID" moved to EV-0096; §7 dashboard has an honest M4-W1 row (PASS host+sim / NOT RUN device+hands) and M2/M3 rows reference it correctly; AGENT/README text matches the evidence class. The only metadata defect found (**F15**: manifest dirty list typo/omission) was fixed and re-verified (see §5.1). No false PASS/hands claim exists. |
| H5 | No stale references (fixture sizes, tune keys, thresholds, ABI v3, action log formats) | **PASS** — greps clean in product docs; runbook expected-lines block matches the final code formats (F12/F13 updates verified) |

### I. Defect handling

| # | Check | Verdict |
|---|---|---|
| I1 | Every defect reported to the Lead immediately; fixes re-verified (never taken on faith) | **PASS** — F1–F13 reported as found; each fix re-checked on the frozen tree |
| I2 | Report states residual risks + explicit proven/not-proven split | **PASS** — §6/§7 |

## 4. Exact commands and results (frozen tree, verifier-run)

All logs under `/tmp/vrmc-m4-verify/logs/`; the same commands were also run on the candidate tree
earlier with identical results.

| # | Command (repo root) | Result |
|---|---|---|
| 1 | `{git diff --name-only; git ls-files --others --exclude-standard}` + per-file sha256/type | 25 changed + 14 new files, all text, all in scope; fingerprint §8 |
| 2 | `clang -std=c11 -I bridge/abi /tmp/vrmc-m4-verify/tools/abi_layout.c -o … && ./abi_layout` | `PASS: ABI v3 layout matches design §3.1/§3.2` |
| 3 | `/tmp/vrmc-m4-verify/tools/hdrcheck.sh <repo>` (C11 + ObjC++/C++17 + `nm -u` mangling) | `PASS: … C entry points are unmangled C linkage` |
| 4 | `OUT_DIR=/tmp/vrmc-m4-verify/bridge-frozen bridge/tests/run_tests.sh --skip-metal` | `[bridge-tests] ALL PASS` — 38 PASS lines, 0 FAIL; input-test + input-test-tsan (500k × 4 readers, 0 torn); build_bridge MODE=both; metal probe SKIP (no MoltenVK SDK) |
| 5 | verifier JNI smoke: `java -Dvrmc.bridge.lib=…libvrmc_bridge_host.dylib M4JniSmoke` | `[m4-jni-smoke] ALL PASS` 12/12 (abi 3; abi-2 caps reject; safe-zero 752-byte poll; short -6; heap -5) |
| 6 | frozen fixture: `clang … make_input_fixture.c vrmc_stub.c; ./make_input_fixture out.bin; shasum; python3 fixture_parse.py out.bin.frames --expect-scenario` | 752 B sha256 `50926fdc…562d77`; 7520 B sha256 `43d52113…f76fa45`; `PASS: fixture matches the documented 10-frame/150 ms scenario and enables exactly one f7 fist-tap pulse` |
| 7 | `TMPDIR=<private> PROVIDER_OUT=/tmp/vrmc-m4-verify/provider-frozen VRMC_INPUT_FIXTURE=… VRMC_INPUT_FIXTURE_FRAMES=… provider/tests/run_tests.sh` | `[provider-tests] ALL PASS` — m4-layout 68 / m4-gestures 157 / m4-pose 61 / m4-fixture 61 checks, 0 failed; pre-existing steps PASS; vulkan SKIP (pre-existing) |
| 8 | `OUT_DIR=/tmp/vrmc-m4-verify/selfcheck-m4-frozen scripts/m4_input_selfcheck.sh` (full) | `RESULT: PASS` — all five steps PASS; simulator input `OVERALL PASS` |
| 9 | `scripts/m3c_selfcheck.sh` (full) | `RESULT: PASS` — verifier frozen-tree run: PASS DepthClearRegressionTest, DisplayViewsTest, build_shell(device), build_provider, build_bridge(both), bridge_host_tests, provider-sim (six scenarios: flat sync hidepark nopark pattern reentry), m4_input_selfcheck step 7; log `frozen-m3c-selfcheck.log` (Lead frozen-tree run agrees: M4RC=0 M3RC=0) |
| 10 | verifier analysis of the frozen sim capture `selfcheck-m4-frozen/provider-sim/case-input/input-capture.txt` | 341 records: seq contiguous 1..341, frame non-decreasing, 340 tracked + final `valid_mask=0` release, timestamps monotonic, right pinch 0.0050→0.0744 (crosses 0.030/0.045), left fist 0.767→1.890 (crosses 1.25/1.55), 0 compositor input error markers; `INPUT-SIM SYNTHETIC` lines present |
| 11 | `xcodebuild -project runtime/native-shell/VRMCShell.xcodeproj -scheme VRMCShell -configuration Debug -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath … build` | `BUILD SUCCEEDED` |
| 12 | staged device artifact check (no install): plist keys, embedded framework/bridge platform + markers + symbols, `codesign --verify --deep --strict` | PASS — framework platform 11 with 3× `INPUT-SIM SYNTHETIC`, bridge exports `_vrmc_shared_publish_input`/`_vrmc_poll_input`/`nativePollInput`, codesign rc=0, provider jar contains final classes |
| 13 | docs consistency greps (§3H) + scope/out-of-scope filters | PASS (H4 Lead action noted) |

Supporting candidate-tree runs (same commands before task-6; kept for lineage): `bridge-final.log`,
`provider-final.log`, `provider-f12.log`, `provider-task6.log`, `sim-input.log`, `sim-flat.log`,
`selfcheck-m4-early.log`, `shell-device-build.log`.

## 5. Findings (all raised during the work; status at freeze / post-verdict re-audit)

| # | Severity | Finding | Status |
|---|---|---|---|
| F1 | BLOCKER (build/link) | `vrmc_native_shared.h`: premature `#ifdef __cplusplus }` close made ObjC++ TUs fail with an extraneous brace and would have C++-mangled the new input entry points (compositor dlsyms plain C names). | **FIXED** (Lead) — re-verified: C11+ObjC++ compile clean, `nm -u` shows unmangled symbols |
| F2 | note | Layout math independently confirmed (368/752, offsets). | recorded |
| F3 | HIGH (device-only) | Hand-tracking authorization was unspecified/unimplemented: ARKit does not prompt from `ar_session_run`; without `ar_session_request_authorization` a device real-hands run would silently never track while all host/sim tests stayed green. | **FIXED** — request at session start, status logged once, denied ⇒ untracked + clear log; synthetic mode skips the request entirely (device runbook updated) |
| F4 | MEDIUM (ABI comment) | Chirality documented as "0=left/1=right (ARKit enum)" but the raw ARKit C enum is inverted (right=0, left=1). | **FIXED by contract** — normalized convention documented; compositor maps explicitly; fixture verifies L=0/R=1 |
| F5 | note | All ARKit API names/shapes in design §4 verified against the XROS 27.2 SDK headers (positive). | recorded |
| F6 | note | Early fixture-contract ambiguity (752 B primary vs timeline) resolved as 752 B + 7520 B `.frames` at 150 ms; independently re-parsed. | **RESOLVED** |
| F7 | MEDIUM (docs↔code) | Tune-property key names/startup log label mismatched the provider; documented keys would have been silently ignored on device. | **FIXED** — docs now list the exact code keys + `input tuning:` label |
| F8 | LOW (Lead script) | `m4_input_selfcheck.sh` passed `PROVIDER_OUT` to `build_provider.sh` (which reads `OUT_DIR`). | **FIXED** — step 3 uses `OUT_DIR` |
| F9 | MEDIUM (device risk) | Authorization request ran even in synthetic mode and blocked compositor start up to a fixed 20 s; slow first-run response silently lost the hand provider. | **FIXED** — synthetic skips request/wait; timeout logs explicit "allow then RELAUNCH" guidance |
| F10 | LOW (defensive) | Missing nil checks on ARKit skeleton/joint handles (crash vs graceful untracked). | **FIXED** — guards present |
| F11 | LOW (docs) | Duplicate "2." item numbering in design §4 after the authorization insertion. | **FIXED** — renumbered 1–7 |
| F12 | MEDIUM (docs↔code, device evidence) | Device Step 1 claimed action-press log evidence that the provider did not emit. | **FIXED (task-5)** — `[VRMC-M4] action <name> press|release origin=<left|right|none>` added (dedupe per action+hand, burst 60/kind then every 300th, all immediate-release paths covered, W1 actions only); runbook expected-lines block aligned; INSPECT + build/tests only (no game instance on host) |
| F13 | HIGH (change hygiene / device footgun) | Tracked preview framework under `runtime/native-shell/build/` was rebuilt from the frozen tree; it is the path the device runbook staged from, so reverting it naively would embed a **pre-M4** shell. | **RESOLVED BY DECISION (Lead, option b "keep git clean")** — binaries not committed; runbook Step 0 builds `scripts/build_shell.sh` from the frozen tree and refuses a stale framework (grep `INPUT-SIM SYNTHETIC`) before staging; signed bundle kept outside git (`artifacts/`, ignored); operator local build dirties the tracked preview path locally and must not commit it. **Residual footgun:** a stale tracked framework could still be staged if the build+verify step is skipped — the runbook now mandates it. **Applied and re-audited post-verdict:** the tracked framework is reverted (`git status runtime/native-shell/build/` clean); the signed staged bundle (git-ignored) was independently verified against the M4 markers. |
| F14 | LOW (docs nuance, noted not filed) | Runbook example lists `key.attack` alongside `guiLeftClick` for the right pinch; at the main menu the INGAME set is inactive, so only GUI-set actions fire. The triage table mentions screen state, so this is a wording nuance, not a defect. | noted |
| F15 | LOW/MEDIUM (evidence metadata, found in post-verdict finalization) | `evidence/EV-0095/manifest.json` `dirty` list was off by two entries: it contained `GENT.md` (typo for `AGENT.md`) and omitted `VERIFY.md` (actual vs manifest 41 vs 40 paths). `evidence/EV-0095/frozen-sha256.txt` listed `AGENT.md` correctly, so the underlying evidence was sound. | **FIXED and re-verified** — the Lead regenerated the list from the final pre-commit `git status`: it now matches the working tree exactly (42/42 paths incl. `AGENT.md`, `VERIFY.md`, `docs/adr/0009-macstream-tracked-reference.md`; `GENT.md` gone) and `entry.md` gained the "(host + simulator plumbing) — device synthetic and real hands NOT RUN" status qualifier. No effect on the verification verdict |

### 5.1 Post-finalization re-audit (Lead-owned changes after the verdict)

After this verdict the Lead finalized the acceptance package; the verifier re-audited those changes
(they are docs/evidence only — every implementation file was re-hashed and is unchanged from the
frozen snapshot, §8):

- **F13 applied:** `runtime/native-shell/build/` is reverted to HEAD; `git status --porcelain` shows the
  four tracked preview-framework binaries clean, so the commit diff contains no framework binaries. The
  device runbook now builds `scripts/build_shell.sh` from the frozen tree, refuses a stale framework
  (grep `INPUT-SIM SYNTHETIC`) and stages to git-ignored `artifacts/staged/VRMC-native-m4-input.app`.
- **F13 staging artifacts re-verified by the verifier:** signed bundle (`codesign --verify --deep
  --strict` rc=0), embedded framework platform 11 with 3× `INPUT-SIM SYNTHETIC` strings, embedded
  bridge platform 11 exporting `_vrmc_poll_input`/`_vrmc_shared_publish_input`/`nativePollInput`;
  provider jar contains the final `VisionInput`/mixin classes.
- **EV-0095 recorded in VERIFY.md §6** (long-form entry: host+simulator procedure, expected/actual, 21
  hashed artifacts, explicit limitations); "Next evidence ID" moved to **EV-0096**; §7 dashboard has an
  honest M4-W1 row ("PASS (host + simulator plumbing) / NOT RUN (device, hands)") and the M2/M3 rows
  reference it consistently. README.md and AGENT.md status text matches the same evidence class.
- **Evidence bundle `evidence/EV-0095/`:** 21 artifacts present with sha256 matching `manifest.json`
  (checked before the final report re-copy); `staged-artifacts.txt` records the staged app/framework/
  bridge/jar hashes and the "nothing installed on the headset" statement; the verifier report is copied
  in (the Lead refreshes that copy + its manifest sha after this final edit).
- **F15 fixed:** the manifest `dirty` list now exactly matches the final pre-commit `git status`
  (42/42 paths, incl. `AGENT.md`, `VERIFY.md`, `docs/adr/0009-macstream-tracked-reference.md`;
  the `GENT.md` typo is gone), and `entry.md` carries the host+simulator/device+hands qualifier in its
  Status row.

Remaining post-verdict actions (Lead): re-copy this report into `evidence/EV-0095/`, refresh its sha256
in `manifest.json`, and commit; then the verifier performs a message-only post-commit re-audit
(clean tree, framework revert in the diff, EV-0095 present) and reports the confirmation.

## 6. Residual risks (what remains unproven or fragile)

1. **Real hands and device input are NOT RUN.** ARKit hand capture, joint quality/jitter on the device,
   permission-prompt UX, the device synthetic chain down to the game's action handling, the hand ray
   actually moving the GUI cursor, gesture comfort/fatigue, and seated-mode behavior are unproven until
   an operator session (M4_DEVICE_RUN.md Steps 1–2). AC-4/ST-S5-hands stay NOT RUN.
2. **Mixin application is target-level/compile-level in host tests** (no game instance). It is pinned to
   Vivecraft 26.2-1.3.15 and fails closed (required mixin + `defaultRequire:1`), and the MCOpenVR path
   is untouched by construction; a Vivecraft drift will fail the provider build/load, not silently
   change behavior.
3. **Device-only ARKit specifics**: authorization prompt availability/timing, hand-only vs world-tracking
   combined session behavior, and joint-space correctness versus the head pose can only be confirmed on
   the headset. The code maps the ARKit enum explicitly and uses the same anchor-origin space as the
   head; the device runbook now mandates the permission prompt and exposes pose diagnostics
   (`[VRMC-M4] pose:`).
4. **Binding ergonomics/action-set interactions on device** (teleport vs attack vs GUI clicks, tap timing
   at 90 Hz, chord priority feel) are host-verified logic only; tuning knobs are documented and
   log-printable for the operator session.
5. **Jar identity drift**: the provider jar sha256 changes per build because the jar tool stamps
   timestamps (documented in `build_provider.sh`); use the staged artifact/class content as identity.
6. **Stub-bridge caps parsing is substring-based** (abi token) and does not validate the individual
   capability tokens; the effective ABI gate is `vrmc_abi_version()` + provider/bridge paired shipping
   (pre-existing stub design; a real bridge may harden it).
7. **F13 residual footgun** (§5): always run the runbook's build+verify step before staging; do not
   stage the tracked preview framework from git.
8. **Commit sequencing** (Lead): the EV-0095 entry, AGENT/README status text and this report land in the
   same commit; the Lead re-copies this report into `evidence/EV-0095/` and refreshes its sha256 in
   `manifest.json` immediately before committing. After the commit the verifier performs a message-only
   post-commit re-audit (clean tree, framework revert in the diff, EV-0095 present) and does not edit
   repo files afterwards.

## 7. What is proven / what is NOT proven

**Proven (host + simulator, reproduced by the verifier on the frozen tree):**
- The ABI v3 byte contract is correct on both sides (size/offset/stride/order; C→Java fixture replay),
  and the JNI entry point is correctly wired (safe zero, fail-closed rejections).
- The bridge input channel is race-free (TSan) and honours publish/acquire/sequence/release semantics,
  including the documented pre-publish safe-zero state and release snapshot.
- The provider gesture engine implements the design thresholds with hysteresis, released-state arming,
  single-fire tap edges, both-fist chord priority, stale/tracking-loss release, action-set gating, and
  the W1 binding table — test-enforced.
- The hand→controller pose math yields `R*(0,0,-1)=aim` and an orthonormal basis (the actual GUI/aim
  convention), plus the documented shoulder/gaze fallback.
- The real compositor compiles for the device target, runs in the visionOS simulator, publishes
  synthetic 27-joint snapshots through the vendored bridge ABI (the simulator harness's fake bridge
  records them), and publishes a final zeroed release before `ar_session_stop`; presentation scenarios
  remain green (no regression).
- The one-command self-checks (`m4_input_selfcheck.sh` full and `m3c_selfcheck.sh` full) pass
  end-to-end, and the device staging bundle (signed, git-ignored) contains the M4 framework/bridge/jar.

**NOT proven (and must not be claimed by this workstream):**
- **Real ARKit hand tracking on the Vision Pro** — no device run; no hand-joint capture evidence.
- **Device input end-to-end** — compositor→bridge→provider→Vivecraft actions on the actual headset,
  including the synthetic device run (Step 1), permission prompt behavior, and device-side latency.
- **Hands acceptance (AC-4 / ST-S5-hands)** — remains NOT RUN; requires an operator wearing the headset.
- **Stereo optics, thermals, 90 Hz/soak, comfort** — out of scope; governed by the M3/M4 device tracks.
- **Mixin application inside a live Minecraft process** — compile/target-level only on the host.
- **A committed final state** — the Lead commits after this verdict; pre-commit conditions: revert the
  4 tracked preview binaries (F13) and record EV-0095/status rows (H4).

## 8. Frozen-tree fingerprints and evidence index

- **Repo:** `/Volumes/Untitled/Projects/VRMC`; **HEAD:** `5d6622c2ea5e91b94ff4cc11fc546b47e9f25d7f`;
  frozen snapshot 2026-11-01T20:17:38-10:00 (43 working-tree changes then: 25 modified tracked + 14 new
  text files + 4 tracked preview-framework binaries). Post-verdict finalization: those 4 binaries are
  reverted (F13, working tree clean) and the docs/evidence rows were added; the final pre-commit tree has
  42 `git status` paths (see `evidence/EV-0095/manifest.json` dirty list, F15-fixed). Every
  implementation file was re-hashed and is unchanged from the frozen snapshot.
- Per-file sha256 of every frozen changed/new file: `/tmp/vrmc-m4-verify/logs/frozen-sha256.txt`.
  Post-freeze re-hash check (after both verifier selfcheck runs, 20:2x): all implementation files
  (compositor, provider sources/tests, bridge src/tests/ABI, sim harness, selfcheck scripts) are
  UNCHANGED versus the frozen hashes; only Lead-owned docs were edited after the freeze.
  Key source hashes at freeze:
  `VRMCCompositor.mm 3912bd0d…`, `VisionVR.java c9cdfd1d…`, `VisionInput.java dce34be3…`,
  `VisionHandPose.java 1b9d82f6…`, `VRInputActionMixin.java 4946e88b…`, `VrmcBridge.java e10ca76f…`,
  `vrmc_abi.h d1e595ca…`, `vrmc_native_shared.h 1798114d…`, `vrmc_stub.c ca156af3…`,
  `vrmc_jni.c ca6872c8…`, `make_input_fixture.c 2ea0e55e…`, `bridge_input_test.c 7233740a…`.
- Fixture contract: primary 752 B sha256 `50926fdc3ffc640dcbdee440679f83aa4c28ccbcdf628ec0cbca6c05cf562d77`;
  `.frames` 7520 B (10 records × 752 B, 150 ms) sha256
  `43d52113c5e925e2a59c48387a2fddb5b4427bf4342d0a2bbe83f8914f76fa45`.
- Verifier logs: `/tmp/vrmc-m4-verify/logs/` — `bridge-frozen.log`, `provider-frozen.log`,
  `frozen-m4-selfcheck.log`, `frozen-m3c-selfcheck.log`, `frozen-abi-layout.log`,
  `frozen-hdrcheck.log`, `frozen-jni-smoke.log`, `frozen-fixture-*.log`, `sim-input.log`,
  `sim-flat.log`, `selfcheck-m4-early.log`, `shell-device-build.log`.
- Verifier tools: `/tmp/vrmc-m4-verify/tools/` — `abi_layout.c` (independent ABI checker),
  `hdrcheck.sh` (C/C++ compile + mangling), `M4JniSmoke.java` (JNI contract),
  `fixture_parse.py` (independent fixture parser, written from the design doc only).
- Simulator artifacts: `/tmp/vrmc-m4-verify/selfcheck-m4-frozen/provider-sim/case-input/` (capture,
  compositor/shell logs, drawable readback, screenshot); candidate-tree runs in
  `/tmp/vrmc-m4-verify/sim-input/`.
- Device staging (git-ignored): `artifacts/staged/VRMC-native-m4-input.app` (signed; verifier
  re-verified: `codesign --verify --deep --strict` rc=0, embedded framework platform 11 with 3×
  `INPUT-SIM SYNTHETIC` strings, bridge exports the input symbols; verifier content+path tree hash over
  485 files `f584e7ad9a620f6cc0466bb5dc9d5b450f691bd2eb4fd19587aae830a5b3ed14`, method differs from the
  Lead's so the tree hashes are not directly comparable) and `artifacts/staged/vrmc-provider.jar` (final
  `VisionInput`/mixin classes; sha256 `94cfe0d9…` — jar sha varies per build by design).

## 9. Verifier recommendation

**M4-W1 is ready to be recorded as host+simulator PASS (EV-0095), NOT device/hands.** The frozen tree
implements the contract with the safety-critical stuck-input invariants intact and the device runbook +
signed staging bundle prepared. The pre-commit conditions have been met and re-audited:
(1) `runtime/native-shell/build/` is reverted (F13; no framework binaries in the commit); (2) EV-0095 is
recorded in VERIFY.md §6 with the evidence-class split and a link to this report; (3) AGENT/README/M4
status rows say "host+simulator PASS; device/hands NOT RUN"; (4) the EV-0095 evidence bundle and
manifest are consistent (F15 fixed). The only remaining step is the Lead re-copying this report into the
evidence bundle + commit, followed by the verifier's message-only post-commit re-audit. The physical-
device session (M4_DEVICE_RUN Steps 1–2) is the next evidence step and is the only thing that can move
AC-4/ST-S5-hands.
