# M3c independent pre-device-run audit (m3c-reviewer)

**Date:** 2026-11-01 · **Auditor:** m3c-reviewer (task-6; read-only outside this file)
**Range audited:** `f4d0617..HEAD`; HEAD moved during the audit (`d142f9c` -> `54cee57` -> `def7681`). Findings are stated against the files as of `def7681`; line numbers were re-checked at that revision.
**Installed build under test:** `/tmp/VRMC-native-v13-reentry.app` (the app the operator is about to run). No device access was used.

---

## 0. Bottom line

- **No runtime BLOCKER was found in the CompositorServices present path.** The EV-0093 root cause is fixed in code and in the installed binary (depth clear defaults to **1.0**; `vrmc-depth-zero.flag` is the only way back to 0.0), the drawable-array/present ordering matches the device-proven M3A probe, and every frame-level resource in the loop is autoreleased or bounded.
- **One evidence-integrity BLOCKER (B1) and three HIGH items (H1-H3) should be fixed or explicitly worked around before the operator session**, otherwise the decisive EV-0094 can produce a wrong PASS/FAIL regardless of what the headset shows.
- Build/repro is healthy at HEAD: `xcodebuild` framework build, bridge `MODE=both` build (27 exported symbols), `DepthClearRegressionTest`, `test_display_views.sh` all PASS locally. The staged v13 app verifies with `codesign --verify --deep --strict`, its framework/bridge are visionOS platform 11, and its framework string set is identical to a fresh build of the audited source (so the device binary is built from the audited tree).
- Item **M5** is the main build/repro caveat: HEAD (`def7681`) now contains the flag-gated provider GPU-sync feature ("host PASS, device NOT RUN") that is **not** in the v13 device payload; the plan says to keep the previous provider jar, but the runbook/checklist has no step that verifies what is actually installed on D1 or which provider jar the game container is using.

---

## 1. Ranked findings

| # | Severity | Finding | Primary location |
|---|---|---|---|
| B1 | **BLOCKER (evidence)** | Session logs are appended forever and the runbook triage gate greps the whole file, so a previous session can satisfy the decisive checks ("first presented frame", "depthZero=0", scene fgActive) while the current session failed. | `runtime/native-shell/Sources/Shell.swift:10-22`, `runtime/native-shell/Sources/VRMCCompositor.mm:107-112`, `scripts/m3c_pull_and_check.sh:49-68` |
| H1 | **HIGH** | Runbook expects a cyan/white checker border in the no-game Enter-VR test, but the proof overlay is only drawn with `vrmc-present-proof.flag` or the selftest flag. The manual path draws the test pattern **without** the border, so the operator sees a "missing" expected element in the decisive step 1. | `docs/mvp/M3C_PLAN.md:81`, `docs/mvp/M3C_DEVICE_RUN.md:27`, `runtime/native-shell/Sources/VRMCCompositor.mm:689,1340` |
| H2 | **HIGH** | `vrmc-clear-diagnostics` does not clear every diagnostic flag the docs say it clears (`vrmc-present-proof`, `vrmc-no-parking`, `vrmc-hide-windows`, `vrmc-hide-chrome-always` survive) **and** it deletes `vrmc-immersive-selftest.flag`/`vrmc-open-on-launch.flag` before the shell reads them, so the documented "push clear-diagnostics + selftest together" procedure cannot work. A stale A/B flag can poison the decisive run (a stale `vrmc-hide-windows.flag` re-introduces the isHidden parking the project moved away from). | `Shell.swift:42-59,86-93,210-238`, `docs/mvp/M3C_FLAGS.md:14`, `docs/analysis/compositor-presentation.md` section 5 item 4 |
| H3 | **HIGH** | Operator checklist step 2 offers "leave it in the background" after step 1. Foregrounding the process after a manual open **auto-reopens the test-pattern immersive space** (wantsImmersive/reopenOnActive) and parks the launcher window alpha-only/non-interactive, so the operator cannot reach Play and sees the test pattern while expecting the game. | `Shell.swift:496-503,548-550,603`, `docs/mvp/M3C_DEVICE_RUN.md:37` |
| M1 | MEDIUM | The "layer ended right after opening" auto-retry is dead: `lastOpenGeneration` is read *before* the compositor thread exists, so the ended generation is always one greater and the equality test never matches. Log line "immersive session opened generation=0" is misleading in evidence. | `Shell.swift:449-451,609`; `evidence/EV-0092/selftest-shell.log:117,119` |
| M2 | MEDIUM | A deferred open is silently dropped for `auto`/`foreground`/`selftest` (only `manual` surfaces an error); if the scene is not foreground-active at the 15 s auto-open moment, VR never opens and nothing retries on the next activation. | `Shell.swift:319-327,535-551,569-579` |
| M3 | MEDIUM | Empty drawable array is abandoned **after** `cp_frame_start_submission` without `cp_frame_end_submission`; the log comment claims no submission was started, which is wrong. Contract risk / state ambiguity on the rare cancelled-frame path. | `VRMCCompositor.mm:784,809-818` |
| M4 | MEDIUM | Provider eye-target PNG capture (`Screenshot.grab` from `endFrame` on the render thread) is off by default but the container was prepared with `instances/default/vrmc-capture.flag`, i.e. it runs during the decisive game step at frames 0/300/600 and has never been exercised on device. A render-thread exception/readback problem here would break the game-in-immersive acceptance run. | `provider/src/main/java/dev/vrmc/provider/VisionRenderer.java:246-296` (HEAD); capture flag present per `docs/analysis/m3c-selfcheck.md` |
| M5 | MEDIUM | Payload/identity drift: HEAD now includes provider GPU-sync code not in the v13 payload ("device NOT RUN"), and neither the runbook nor the checklist verifies the installed app build or the game-container provider jar hash. The "installed build is v13" claim is only in prose. | `docs/mvp/M3C_PLAN.md:70,103-106`, `docs/mvp/M3C_DEVICE_RUN.md:4`, commit `def7681` |
| M6 | MEDIUM | `scripts/m3c_selfcheck.sh` (the documented "one-command self-check" after any compositor/shell change) does **not** build the shell framework; a Shell.swift/VRMCCompositor.mm compile break is not caught by it. | `scripts/m3c_selfcheck.sh:22-48`, `docs/mvp/M3C_PLAN.md:93-95` |
| M7 | MEDIUM | Pipeline-format probe calls `cp_drawable_get_color_texture(mainDrawable, leftView)` / `get_depth_texture(..., leftView)` using a *view* index as a *texture* index. Valid for the current dedicated layout (textures=2) but out-of-range for a single-texture layout, and it can mask a real format mismatch. | `VRMCCompositor.mm:870-889` |
| L1 | LOW | New `vrmc-gpu-sync.flag` table row was inserted into the middle of the intro paragraph of `M3C_FLAGS.md` (malformed markdown, wrong section). | `docs/mvp/M3C_FLAGS.md:6-7` |
| L2 | LOW | Stale doc references: runbook says "v12 build; v11 has the plain gradient" although the installed build is v13; provider-sim doc says "four scenarios" while `run.sh` runs six; `M3C_PLAN` section 5 has two items numbered 6. | `docs/mvp/M3C_PLAN.md:77,95,108-110`, `runtime/probes/m3c-provider-sim/run.sh` |
| L3 | LOW | The "first presented frame" audible canary (`AudioServicesPlaySystemSound(1057)`) is presented in the checklist as the step-1 success signal but is unverified on visionOS. | `Shell.swift:399`, `docs/mvp/M3C_DEVICE_RUN.md:23` |
| L4 | LOW | Step 1 gives no exit path for the immersive space (Digital Crown) and no devicectl push command for the recovery flags; while immersive is open the window is alpha-0 and non-interactive, so the Enter-VR control is unreachable. | `docs/mvp/M3C_DEVICE_RUN.md:33-35,60-67` |
| L5 | LOW | The VERIFY.md restore commit is faithful to `f4d0617`, but that baseline itself has a section-7 dashboard row embedded in the middle of the EV-0090 procedure list - pre-existing read->write corruption the restore did not clean. | `VERIFY.md:2313` (both revisions) |
| L6 | LOW | Compositor comment states "querying before startSubmission ... was the selftest black-immersive root cause", while `docs/analysis/compositor-presentation.md` section 1/F4 says the opposite fix ("drawables are queried before the submission is opened") and EV-0093 attributes the black to the depth clear. No recorded A/B artifact backs the ordering claim. | `VRMCCompositor.mm:779-783` vs `docs/analysis/compositor-presentation.md` section 1 F4 |

---

## 2. Detail and minimal fixes

### B1 - BLOCKER (evidence integrity): appended session logs + whole-file triage = false PASS/REGRESSION
- `Shell.swift:10-22` appends to `Documents/vrmc-shell.log` (seekToEndOfFile) and `VRMCCompositor.mm:107-112` opens `vrmc-compositor.log` with `fopen(path, "a")`. Neither is rotated per process/session, and `vrmc-clear-diagnostics.flag` does not remove logs.
- Not hypothetical: `evidence/EV-0091-fresh/vrmc-shell.log` contains **19** `vrmc_shell_start invoked` markers and `evidence/EV-0092/selftest-compositor.log` contains **18** `starting compositor thread` markers from different sessions. The same growing shell log was copied into EV-0082...EV-0092.
- `scripts/m3c_pull_and_check.sh` prints `tail` lines for context but makes its verdict with whole-file `grep -q` (lines 50-68): `depthZero=1` anywhere -> hard "REGRESSION"; `first presented frame` anywhere -> "OK: compositor presented at least one frame this log"; scene-fgActive anywhere -> OK. A current run that fails to present (NO-FRAME) after an old successful session pulls as PASS; a diagnostic flag left in one old session can flip the verdict the other way.
- **Why it matters:** the runbook step 3 ("Expected PASS-ish lines ... exit 2 on hard regression") is the planned acceptance evidence for EV-0094. It cannot distinguish "this session" from "any session in the container".
- **Minimal fix:** rotate at process start - in `vrmc_shell_start` (before `VRMCShellApp.main()`) rename `vrmc-shell.log`/`vrmc-compositor.log` to `*.prev.log` (or delete them), so a pulled log is exactly one process. In parallel make `m3c_pull_and_check.sh` session-scoped: split at the last `vrmc_shell_start invoked` / `starting compositor thread (generation` marker and only assert on the tail; print a session fingerprint in the verdict block.

### H1 - HIGH: expected checker border is not drawn by the manual Enter-VR path
- The proof overlay is drawn only when `presentProof || selfTest` (`VRMCCompositor.mm:1340`); `presentProof` is the marker file `vrmc-present-proof.flag` (`VRMCCompositor.mm:689`). The manual Enter-VR path with no game sets neither; it shows the procedural pattern only because `haveEyes` is false (`VRMCCompositor.mm:1151-1152`). Every device diagnostics line captured so far has `presentProof=0`, and the only runs with `PRESENT-PROOF active` are selftest runs.
- Both operator documents list "a cyan/white checker border (present-proof) around each eye image" as expected step-1 output (`M3C_PLAN.md:81`, `M3C_DEVICE_RUN.md:27`). The operator will either report a missing expected element or (if a stale `vrmc-present-proof.flag` exists - it is not cleared, see H2) see an inconsistent result.
- **Minimal fix (pick one):** (a) docs: delete the border line from both documents and make the recovery-matrix row explicit that the border requires pushing `vrmc-present-proof.flag` first; or (b) code: draw the proof overlay by default for the no-game pattern, e.g. `BOOL proofNow = presentProof || selfTest || (!haveEyes && testPatternNow);` - one line at `VRMCCompositor.mm:1340`; matches what the docs already promise and the simulator pattern scenario (`check.py --pattern`) already asserts.

### H2 - HIGH: stale-flag cleanup is incomplete and contradicts the documented selftest flow
- `diagnosticFlagsClearedAtStartup` (`Shell.swift:42-59`) is missing four flags that M3C_FLAGS.md lists as diagnostic: `vrmc-present-proof.flag`, `vrmc-no-parking.flag`, `vrmc-hide-windows.flag`, `vrmc-hide-chrome-always.flag` (`vrmc-drawable-dump.flag` exclusion is intentional and documented). `M3C_FLAGS.md:14` however says the trigger deletes "the diagnostic flags below", and the EV-0094 runbook relies on the trigger for a clean slate. A stale `vrmc-no-parking`/`vrmc-hide-windows` flag directly changes what the operator sees in the decisive run.
- `vrmc_shell_start` runs `neutralizeDiagnosticFlagsIfRequested()` before `VRMCShellApp.main()` (`Shell.swift:86-93`), and the clear list includes `vrmc-immersive-selftest.flag` and `vrmc-open-on-launch.flag`; `ShellCoordinator.init()` reads those flags later (`Shell.swift:213-214`). Therefore the guidance in `docs/analysis/compositor-presentation.md` section 5 item 4 ("push `vrmc-clear-diagnostics.flag` + `vrmc-immersive-selftest.flag` together") can never start the selftest: the clear pass deletes the flag first.
- **Minimal fix:** add the four missing names to the clear list (keep the documented `vrmc-capture.flag`/`vrmc-drawable-dump.flag` exclusions); fix the doc guidance to require two launches (launch 1: clear-diagnostics; launch 2: push selftest/open-on-launch and launch) or move the neutralisation after the shell reads its own flags while keeping the autolaunch deletion ordering. Also update `M3C_FLAGS.md` "delete the diagnostic flags below" to name the exact list.

### H3 - HIGH: checklist step 2 "leave it in the background" conflicts with the re-entry design
- On a successful open the shell sets `wantsImmersive = true` (`Shell.swift:603`). `stopForBackground` arms `reopenOnActive` whenever `gameStarted || wantsImmersive` (`Shell.swift:496-498`), and `appDidBecomeActive` opens VR again for `reopenOnActive && !immersiveOpen && windowSceneActive` (`Shell.swift:548-550`). This is intentional (commit `4a08aec`, "re-entry for all immersive modes") and simulator-tested, but it means a merely backgrounded step-1 process automatically re-opens the **manual test-pattern** space the moment it is foregrounded, parks the launcher window alpha-0/non-interactive, and shows the pattern instead of the launcher the operator wanted to press Play on.
- `docs/mvp/M3C_DEVICE_RUN.md:37` says "Exit VRMC (or leave it in the background), start StikDebug, enable JIT for VRMC, launch VRMC, press Play" - the "or leave it in the background" branch is exactly the trap.
- **Minimal fix (doc-level):** require terminating VRMC first ("quit from the app switcher; StikDebug launch terminates and relaunches for JIT") and state that foregrounding a parked session intentionally restores the previous immersive session. If StikDebug attach fails while VRMC is alive, press the Digital Crown and force-quit before relaunching.

### M1 - MEDIUM: auto-retry is unreachable (generation read before the compositor exists)
- `lastOpenGeneration = VRMCCompositor_CurrentGeneration()` is read immediately after `openImmersiveSpace` returns (`Shell.swift:609`); the CompositorLayer closure (which bumps `gGeneration`) has not run yet. Device evidence: "opened generation=0" then "VRMCCompositorRunning generation=1"; "opened generation=1" then "... generation=2" (`evidence/EV-0092/selftest-shell.log:117,119`). The retry condition `generation == lastOpenGeneration` (`Shell.swift:450`) is therefore always false, so a layer that invalidates right after opening is never retried. It also makes the "opened generation=N" log line misleading.
- **Minimal fix:** set `lastOpenGeneration = generation` when `VRMCCompositorRunning` arrives (in `compositorDidStartPresenting`) and drop the read in `openVR`, or compare `generation == VRMCCompositor_CurrentGeneration()` in the end handler; keep `lastOpenAt` for the 20 s window.

### M2 - MEDIUM: deferred auto/foreground opens are dropped
- `openVR` scene-inactive branch logs "deferring open to next activation" and returns (`Shell.swift:569-579`); only `manual` stores a user-visible error. Nothing re-arms the open on the next `didBecomeActive` for `reason=auto`, `reason=foreground` or `reason=selftest` (the selftest loop retries itself; auto/foreground do not). The 15 s game auto-open (`Shell.swift:319-327`) is exactly when a StikDebug/system overlay or a transient resign can make `windowSceneActive` false.
- **Minimal fix:** if the open is deferred for a non-manual reason, set `reopenOnActive = true` (or a dedicated `pendingOpen` flag) so `didBecomeActive` retries; keep the manual path error message.
### M3 - MEDIUM: cancelled frame leaves a started-but-unended submission
- `cp_frame_start_submission(frame)` is called at `VRMCCompositor.mm:784` **before** the drawable array is queried; if the array count is 0 the code logs "abandoning the frame WITHOUT start/endSubmission" and `continue`s (`809-818`). The comment is false - the submission has already been started. The array-API header says a 0-count frame is cancelled and "invalid to access", while the device-proven M3A probe (deprecated API) calls `cp_frame_end_submission` for a nil drawable; the current code matches neither contract exactly.
- **Minimal fix:** query availability before opening the submission using `cp_frame_get_drawable_target_view_count(frame, cp_drawable_target_built_in)` (visionOS 26 API, available in this SDK); if 0, discard the frame without `start_submission`. Otherwise at minimum fix the comment and decide/record the end-submission behaviour so the cancelled-frame path cannot leave the layer in an inconsistent submission state.

### M4 - MEDIUM: provider capture is on for the decisive game run and has never run on device
- `vrmc-capture.flag` is enabled in the game directory (per `docs/analysis/m3c-selfcheck.md`), so `VisionRenderer.endFrame` calls `maybeCaptureEyeTargets` on the render thread at `frameIndex % 300 == 0` (frame 0 included) and runs `Screenshot.grab` on eye RenderTargets (`provider VisionRenderer.java:246-296` at HEAD). It is a diagnostic extra, not needed for the acceptance decision (the compositor `drawable proof` readback is the ground truth), and a failure inside the game render thread would poison the game-in-immersive step.
- **Minimal fix:** for EV-0094 either remove `instances/default/vrmc-capture.flag` before the run (re-add later for a dedicated capture run), or accept the risk explicitly; when timing allows, exercise capture in a non-decisive run first.

### M5 - MEDIUM: build/payload identity is prose, not verified; HEAD now differs from the v13 payload
- HEAD is `def7681` (provider GPU-timeline sync, *host PASS, device NOT RUN*). The installed v13 app was staged earlier; `M3C_PLAN.md` section 5 item 4 says "the EV-0094 device build keeps the previous provider jar", but neither `M3C_DEVICE_RUN.md` nor the runbook tells the operator/Lead how to confirm (a) the installed app bundle is v13 and (b) the game container still has the pre-GPU-sync provider jar. If anyone rebuilds/stages from clean HEAD before the run, both the app payload and the provider jar change and the expected log lines/hashes no longer describe the device.
- **Minimal fix:** add a pre-run identity block - `devicectl device info apps` / container path check plus the `stage_native_app.sh`-reported hashes for `VRMCShell`, `libvrmc_bridge.dylib` and provider jar; note explicitly "do not rebuild provider from HEAD for EV-0094" (the plan already says it - the checklist should too). Record the actual hashes in EV-0094.

### M6 - MEDIUM: self-check does not build the shell framework
- `scripts/m3c_selfcheck.sh` runs the depth guard, display-view math, provider build, bridge build, bridge tests and simulator harness - but no `xcodebuild` of `VRMCShell` (`m3c_selfcheck.sh:22-48`). `M3C_PLAN.md:93-95` recommends it "after any compositor/shader/bridge/lifecycle change"; a Shell.swift/VRMCCompositor.mm compile error would pass the self-check (the depth guard is a grep). This audit ran the missing build manually at HEAD: **BUILD SUCCEEDED** - so this is a gap, not a current failure.
- **Minimal fix:** add a "shell xcodebuild (device, CODE_SIGNING_ALLOWED=NO)" step to `m3c_selfcheck.sh`; it is cheap and catches the most likely regression.

### M7 - MEDIUM: view index used as texture index in the format probe
- `probeColor = cp_drawable_get_color_texture(mainDrawable, (size_t)leftView)` (and the depth counterpart) at `VRMCCompositor.mm:870-873` use the *view* index, while the render loop correctly uses `cp_view_texture_map_get_texture_index`. With the current `.dedicated` layout (device logs: `views=2 textures=2`) this is correct; with a single 2D-array texture and `leftView == 1` it is out of range (undefined/nil) and the resulting "DRAWABLE COLOR TEXTURE IS NIL ... every view will be skipped" warning plus skipped pipeline-format rebuild would be misleading.
- **Minimal fix:** use the texture map of view 0 for the format probe (or pass `texIndex` from the map) and only warn about nil after the bounded check.

### L1-L6 (docs/hygiene, no device effect)
- L1: `M3C_FLAGS.md:6-7` - move the `vrmc-gpu-sync.flag` row into the "Provider flags" table and repair the broken paragraph.
- L2: stale "v12 build; v11 has the plain gradient" (`M3C_PLAN.md:77`) against the v13 install; "four scenarios" vs six in `run.sh`; duplicate item "6" in `M3C_PLAN` section 5.
- L3: beep as success signal unverified on visionOS; keep it as a nice-to-have, not the only step-1 success cue (the visible pattern is decisive).
- L4: document the Digital Crown exit and the devicectl flag-push command; the parked window is non-interactive by design.
- L5: pre-existing VERIFY.md corruption at `VERIFY.md:2313` (dashboard row inside EV-0090 procedure) survived the restore; clean it in a future targeted edit (per AGENT section 0.8, never a read->write round-trip).
- L6: reconcile the submission-ordering narrative between `VRMCCompositor.mm:779-783` and `docs/analysis/compositor-presentation.md` section 1/F4; if the ordering change was a real fix, record the A/B artifact.

---
## 3. What was checked and found correct (coverage for the audit brief)

**Compositor present path** (`runtime/native-shell/Sources/VRMCCompositor.mm`, device build verified):
- Submission order follows the device-proven M3A probe (EV-0074): `query_next_frame -> predict_timing -> start/end_update -> wait(optimal_input_time) -> start_submission -> query_drawables -> per-drawable set_device_anchor/render/encode_present -> commit -> end_submission` (the probe also ends a nil-drawable submission; see M3).
- Drawables: array API, up to 4, `built_in` prioritized for tracking/display-views, all drawables rendered and presented, topology logged; no single-drawable assumption remains (deprecated path kept only behind `vrmc-legacy-single-drawable.flag`).
- Depth clear: default **1.0** at `VRMCCompositor.mm:1263`, `vrmc-depth-zero.flag` the only 0.0 path; regression guard matches the source exactly and PASSes; the installed v13 framework contains the fix (`vrmc-depth-zero.flag` string).
- `cp_frame_end_submission` only after a presented drawable (1+), command buffer committed first, present encoded last before commit, matching the EV-0074 probe; only the cancelled-frame case (M3) is ambiguous.
- Flag interactions: `clearProbe` (clear-only colours, no draws), `testPattern` (`!haveEyes || samplingDisabled || forceTestPattern || autoTestPattern || selfTest`), `presentProof`/`selfTest` (proof overlay) are mutually consistent; the auto-pattern fallback after two black provider probes only triggers on genuinely black provider textures (mean luma < 1.0).
- Shader parameter layouts: `fmain_test` reads `float4 viewInfo [[buffer(2)]]` (16 B) and `fmain_proof` reads `float2 vpSize [[buffer(2)]]` (8 B); each draw re-binds the correct byte length with its own pipeline state - no layout mismatch, no Metal validation issue found. Pipelines are rebuilt from the actual drawable attachment formats (device logs: color=115 rgba16Float, depth=252 Depth32Float, matching the layer configuration).
- Readback/proof blits are encoded inside the presented command buffer after the render passes and before `encode_present`; the probe buffer is retained by the completion handler; 64x64 dumps are bounded (frames 0-2 and every 300; raw written only when flagged/early/selfTest).
- Memory/leaks: per-frame objects are autoreleased in the per-frame `@autoreleasepool`; Metal retains resources referenced by committed command buffers; probe buffers are bounded; ARKit C objects are ARC-managed in this ARC ObjC++ target (`ar_device_anchor_create` is NS_RETURNS_RETAINED, project has CLANG_ENABLE_OBJC_ARC=YES) - no per-frame ObjC leak found. Provider texture handles are retained by the strong local at the sampling site and then by the command buffer, satisfying the bridge lifetime contract for the normal path (only the publish->acquire window for a concurrent provider render-target reinit remains theoretical; the bridge re-acquires every frame and logs generation changes).
- Error paths: nil colour texture, nil encoder and format mismatch are logged once with context; nil-encoder views are skipped without corrupting the drawable list (`presented` still counts the drawable); pipeline-format mismatch triggers a rebuild before encoding. (Except M3/M7.)
- `cp_layer_renderer_state`: paused -> `wait_until_running`; invalidated -> break; `wait_until_running` returns on invalidation so stop requests cannot pin the thread in the normal path; `VRMCImmersiveEnded` is always posted from the thread exit path.

**Shell lifecycle** (`Shell.swift`):
- Open/close is guarded by `opening`/`immersiveOpen`; an epoch counter invalidates in-flight Tasks; stale `VRMCImmersiveEnded` generations are ignored; compositor stop requests are generation-scoped (`VRMCCompositor_RequestStop` uses the current generation).
- `willResignActive` 1.8 s grace: cancels on `didBecomeActive`, only stops on `didEnterBackground`/expiry, and the expiry checks `UIApplication.shared.applicationState == .active` before stopping - so a transient scene resign while the app stays active cannot kill the compositor.
- Parking is alpha-only by default and gated on the first presented frame (`VRMCCompositorRunning`); `isHidden` only behind `vrmc-hide-windows.flag`; `vrmc-no-parking` respected; periodic re-park only while immersive+presenting.
- Notification handlers are delivered on `.main` with `MainActor.assumeIsolated`; the compositor posts them via `dispatch_async(main)`; `@Observable`/UI state updates are main-thread. I verified the `userInfo["generation"] as? Int32` bridging cast works (NSNumber -> Int32 returns the value), so generation filtering is not silently disabled.
- Retain cycles: Tasks hold `[weak self]` except the short-lived 15 s `gameDidStart` task (completes; no cycle); NotificationCenter tokens are owned by the process-lifetime singleton.

**Bridge** (`bridge/src/vrmc_stub.c`, `vrmc_jni.c`, `vrmc_native_shared.h`):
- Publish/acquire of eyes+sync+generation is done under one mutex (no torn frame); `texture_generation` bumps only on handle/size change; sync pair validated; legacy submit clears sync.
- `fill_eye_targets` converts display-view tangents with `atanf` into the `left,right,up,down` convention the compositor consumes (`sourceTangentsFromFov` re-applies `tanf`), and the JNI display-views copy is 164 B = `sizeof(vrmc_display_views) - 4` with a matching bounds check (Java `DISPLAY_VIEWS_BYTES` consistent; no overflow).
- Device bridge dylib built from this tree exports all `vrmc_*` + JNI symbols the build script requires; the staged v13 app embeds the same bridge (signature-verified), and the installed framework resolves `vrmc_shared_acquire_eyes` etc.

**Build / stage**:
- `xcodebuild ... -destination generic/platform=visionOS CODE_SIGNING_ALLOWED=NO` -> **BUILD SUCCEEDED** at HEAD (verified in this audit, not just claimed).
- `scripts/build_bridge.sh MODE=both` -> device dylib platform 11/minos 1.0, host dylib platform 1, symbol list PASS.
- `scripts/stage_native_app.sh` signs every Mach-O file, then every nested framework bundle, then the app with entitlements; the staged v13 bundle passes `codesign --verify --deep --strict`; framework/bridge platform 11; framework strings equal to a fresh HEAD build.
- `scripts/tests/DepthClearRegressionTest.sh` PASS; `scripts/test_display_views.sh` PASS.

---

## 4. Residual risks (not defects, for the operator report)

1. Provider eye submission is still the **unsynchronized** legacy path by default; L/R tearing or asymmetric brightness during the game run remains possible (plan section 5 item 4 keeps the old provider jar for EV-0094). Judge content with the compositor `drawable proof` luma and the provider eye PNGs, not by eye alone.
2. Late-stage reprojection stability with the constant near-depth (1.0) is unverified; the depth-semantics follow-up in the plan remains open. If the operator reports swimming/drifting while head-moving, that is a known open item, not the black bug.
3. The simulator cannot reproduce the depth-clear black layer (EV-0093); all simulator/harness PASSes remain non-evidence for the presentation path.
4. Menu-world darkness is content (time of day), not the bug; use `drawable proof`/capture PNGs to distinguish.

## Post-audit outcome (Lead, 2026-11-01)

All BLOCKER/HIGH findings were fixed before handoff (B1 log rotation + session-scoped triage; H1 proof
border on the manual test pattern; H2 full flag cleanup + pre-neutralisation capture; H3 runbook fix), plus
M1 (auto-retry generation), M2 (deferred-open retry), M4 (capture can be disabled remotely via flag
content), M5 (preflight script + build identity), M6 (selfcheck builds the shell framework) and M7
(texture-vs-view index). The v14 build then passed the on-device acceptance (EV-0094): stereo pattern
visible and a JIT game run rendering the Vivecraft menu world in the immersive space with stereo aligned
and head tracking.
