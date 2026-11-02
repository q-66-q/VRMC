# VRMC device-log forensics — per-session timeline and black-immersive root-cause ranking

**Author:** log-forensics (task-1)
**Date:** 2026-11-01 (local HST = UTC-10; device shell/compositor timestamps are UTC, +0000)
**Scope:** every device session from EV-0082 (11:02 HST) through the fresh EV-0091 pull (16:39 HST), reconstructed from
evidence/EV-0082..EV-0090/*, evidence/EV-0091-fresh/* and export/logs/*.
**Constraint:** no device access in this task (analysis only). All claims below are either (a) directly quoted log lines,
(b) derived by arithmetic from frame counters/timestamps, or (c) explicitly labelled hypothesis.

> **Headline (answer to the mission):** in the two post-JNI-fix runs (15:36, 16:39 HST) the provider content was
> **bright, both eyes, correct display views, flat 1:1 mapping, first command buffer completed, 1080–1560 frames rendered**,
> and the 16:39 run additionally had Documents/vrmc-test-pattern.flag on the device (created 16:13) which by code
> inspection forces the procedural test pattern for every frame. The operator still reports a black immersive.
> **This points at the presentation/compositing stage (drawn drawable not reaching the wearer's eyes), not at dark game
> content and not at the provider eye-render path.** The EV-0090 "pure black" (15:28, pre-fix) is explained by
> dark world58 content + a corrupted left-eye display view, but that explanation cannot cover the post-fix runs.
> The single most important missing instrument is a **drawable readback** (what the compositor actually wrote into the
> drawable) plus a **logged forceTestPattern flag** — the current build logs neither, so the 16:39 test-pattern claim is
> code-path certainty, not yet log-certainty.

---

## 1. Sources, provenance and reliability

| Source | Contents | Notes |
|---|---|---|
| evidence/EV-0082 .. EV-0090/{vrmc-compositor.log,vrmc-shell.log,latestlog.txt} | device logs pulled per run | The two device logs are **append-only files in the app data container**, so each later pull contains all earlier sessions (EV-0082's compositor log is a prefix of EV-0083's, etc.). Re-pulled at EV-0086, EV-0089, EV-0090, EV-0091. |
| evidence/EV-0091-fresh/{vrmc-compositor.log,vrmc-shell.log,latestlog.txt} | pull at ~16:50 HST | 542-line compositor log = EV-0090's 426 lines + two new blocks (15:36 run lines 427–485, 16:39 run lines 486–542). 205-line shell log = EV-0090's 171 lines + two new sessions (lines 172–188, 189–205). latestlog.txt is the **16:39 run only** (starts at 16:39). |
| export/logs/m3b-device-*.log | copies of the 14:41 HST session (= EV-0089) | same content as the corresponding blocks in the cumulative compositor/shell logs |
| latestlog.txt per run | Minecraft/Amethyst stdout of **one launch only** (overwritten) | [VRMC-M2] provider lines, MenuWorlds lines, and (sometimes) captured NSLog lines from the compositor/shell. |

Known log gaps / caveats:

1. **No run ever entered a loaded world.** Every recent session is the Vivecraft **VR main menu with a MenuWorlds panorama**
   (Vivecraft: MenuWorlds: ...); there is no "Started server"/"Loading terrain"/"Preparing spawn" line in any latestlog from
   EV-0082 through the EV-0091 pull. So (c) is answered: **all "immersive" content in these sessions is the title/menu world, never
   a downloaded save.**
2. The compositor/shell logs do not carry a wall-clock on every line in the older builds; comments below note which lines are
   timestamped (only the diagnostic build of 14:33–14:41 and the NSLog mirror in latestlog have timestamps).
3. **forceTestPattern is not logged** by the current build (see VRMCCompositor.mm:340,346); the diagnostics line logs only
   reprojMode/debugShading/samplingDisabled. Therefore the test-pattern assertion for 16:39 is a code-path inference from the
   Documents flag mtime (16:13) + per-session flag read, not a log observation. **This must be fixed before the next run.**
4. EV-0084/EV-0089 have no latestlog.txt (EV-0084's run had no per-launch pull; the 14:41 run = EV-0089 predates the
   latestlog recovery). Game-state statements for those sessions are inferred from surrounding sessions.

---

## 2. Per-session timeline (local HST; device UTC in parentheses)

Frame counts are compositor frame log lines; rate estimates are arithmetic (frames / wall time between log anchors).

| # | Session (HST) | Build / evidence | Game state | Immersive lifecycle | Presentation (compositor) | Provider eye textures | Operator / outcome |
|---|---|---|---|---|---|---|---|
| A | 11:02 (21:02Z) **EV-0082** | c348cec | menu world (loading) | auto-open at 11:02:24 (0 s settle in this build); no window parking | frames 1…1080, **eyes=0**, p0=p1=0, anchor=1; then layer invalidated | none (no provider textures yet) | MC crashed: VK_ERROR_DEVICE_LOST … Insufficient Permission (to submit GPU work from background) at 11:02:41; app aborted at cp_frame_end_submission (EV-0082) |
| B | 11:12 **EV-0083** | 487cc59 | menu world **world21** built 11:12:22 | auto-open 11:12:22 (15 s settle) | frames 1…4080 **eyes=1**, flat fullscreen, anchor=1; ends layer left running state before endSubmission | sampled, handles 0x72219ca580/0x72219ca300 | visible but misaligned; game window stayed; immersive quit on background |
| C | 11:33 **EV-0084** | 2863aa4 | menu world (assumed; no latestlog) | auto-open 11:33:48; window parked windows=3 alpha=0.0 | frames 1…2760 eyes=1 flat; then **SIGABRT __BUG_IN_CLIENT__ at cp_frame_end_submission** on layer invalidation | 0x722e01a300/0x722e01a080 | window disappeared, immersive crashed after background, still misaligned |
| D | 11:42 / 11:49 / 11:57 **EV-0085** | 5493626 / bfdc052 | menu world **world18** (11:57 run) | each: 15 s settle → open → park windows | frames 1…3840 / 1…1560 / 1…1680, eyes=1 flat; clean stop/invalidation + VRMCImmersiveEnded | e.g. 0x722b0b2300/0x722b0b2080 | chrome (bottom bar) never hidden; exotropia persists; no re-entry |
| E | 13:08 **EV-0086** | 335a65f | menu world **world4** (13:08:48) | auto-open 13:08:50, park windows=2; background 13:09:10; foreground 13:09:17 reopen gen2; gen2 invalidated 13:09:26 | gen1 frames 1…1680 eyes=1 **reprojection** (no flat path in this build); gen2 invalidated before frames | sampled, 0x722d0b2580/0x722d0b2300 | **"completely black and still have windows"** — first black report |
| F | 14:23 | 1b3b73c (M3b) | menu world (assumed) | auto-open 14:23:31, park windows=2, background 14:23:50 | thread + pipeline only: stop requested before frame; exiting loop — **no frame presented** | none observed | no visual reported |
| G | 14:33 / 14:40–14:41 | **uncommitted diagnostic build** (gameSurfaceMode/chromeMode=hidden-when-presenting, NO-FRAME logic; never committed) | menu world (14:41 run in EV-0089) | 14:33:21 open → **NO-FRAME 8 s** → dismiss; 14:41:01 open → NO-FRAME → dismissed; 14:41:33 gen2 open → first frame at 14:41:57.59 → **window parked → UIScene.willDeactivate/willResignActive/didEnterBackground in the same second** → ended 14:41:57.70 | 14:41:57 block: drawable, views, **1 frame** (frame 1 at 57.602, cmd buffer completed 57.608, stop 57.700) | **bright/day** L mean (83.0,108.0,51.0) luma 80.67, R (78.1,100.7,47.9) luma 75.58, nonBlack 1024/1024, alpha 255 | ~0.1 s of content, then killed; no visual report (EV-0089) |
| H | 15:22 / 15:24 | installed build at that time | menu world (assumed) | 15:24:20 open + park; willDeactivate 15:24:42; background 15:24:53 | stop requested before frame (no frames) | none | no report |
| I | **15:28 EV-0090** | display-view build (65594d8 lineage, **pre-JNI-fix**) | menu world **world58** (loads 15:28:17, built 15:28:22) | auto-open 15:28:18 + park windows=2; scene remains active **121 s**; willDeactivate 15:30:19; background 15:30:22 | frames 1…6360 over ~124 s ≈ 45–51 fps, eyes=1, **mode=flat**, anchor=1, first cmd buffer completed, no failure lines | dark menu-world: L luma 21.9–36.0, R luma 12.3–214.3, several R frames alpha=0; see §4 | **"it is pure black."** Pre-JNI-fix: applied Lpos=(-0.0024,-0.0155,0.9999) (= published L viewToDevice col2) vs R correct; 6360 frames |
| J | **15:36 (01:36Z)** | **post-JNI-fix** (app installed 15:35) | menu world (assumed; that launch's latestlog not pulled) | auto-open 15:37:05 + park; willDeactivate 15:37:22; background same second | frames 1…~1560 in ~17 s; **frame 1 eyes=0 → frame 240 eyes=1**; mode=flat; display views correct Lpos=(-0.0316,-0.0268,-0.0357); first cmd buffer completed | **bright**: L/R luma 43→128; e.g. frame 1200 L mean (120.9,143.5,119.2) luma 127.86 | unreported in evidence (if operator saw it: still black) |
| K | **16:39 (02:39Z) EV-0091-fresh** | **post-JNI-fix**; **vrmc-test-pattern.flag present since 16:13** | menu world **world27** (built 16:39:44) | auto-open 16:39:44 + park; **willDeactivate 16:39:49 (only +5 s)**; background 16:39:57; app keeps running (OSC errors 16:40:05) | frames 0…1080 in ~13 s, eyes=1 from frame 1, **mode=flat**, display views correct Lpos=(-0.0322,-0.0266,-0.0356), first cmd buffer completed | **bright, both eyes**: L/R luma 102.8–153.7, e.g. frame 0 L (115.6,110.4,89.1) luma 105.05 / R (113.9,108.7,87.6) luma 103.38, nonBlack 1024/1024 | **operator reports pure black** (per Lead; see §8 caveat) |

Sessions A–D have **no "pure black" report**; the black reports are E (13:08), I (15:28) and now K (16:39) as reported by the
Lead. That is exactly the sequence in which the compositor moved from the simple flat path (A–D) to the reprojection path (E) and
then to display-views + flat (I, J, K) — i.e. **the regression appears with the post-EV-0085 compositor/presentation changes.**

---

## 3. Was the compositor presenting? (mission question a)

Evidence format: [vrmc-comp] frame N eyes=… anchor=… … every 120 frames, plus asynchronous
frame N command buffer completed (first) / frame N command buffer FAILED ….

* **Presentation loop alive:** yes in every session from B onward. Frame counters reach 1080 (EV-0082), 4080 (EV-0083),
  2760 (EV-0084, crash), 1680 (EV-0086 gen1), 6360 (EV-0090), ~1560 (15:36), 1080 (16:39).
* **Command buffer health:** frame 0 command buffer completed (first) is present in all runs from the M3b build onward
  (evidence/EV-0091-fresh/vrmc-compositor.log:275, 326, 461, 522) and **no command buffer FAILED line exists in any log**.
  (Caveat: the completion handler only logs the first success; later failures would log — none do.)
* **Layer invalidation / stop reasons (complete list, newest first):**
  * 16:39 run — stop/invalidation after timing wait; exiting without submission (comp log 541) directly after
    didEnterBackground (shell 201–203); i.e. background, not a crash.
  * 15:36 run — same clean stop (comp 484–485).
  * 15:28 run (EV-0090) — same clean stop (comp 425–426) after background.
  * 15:24 run — stop requested before frame; exiting loop (comp 288) — the app backgrounded before the layer ever ran.
  * 14:41 run — 1 frame then stop/invalidation after timing wait (comp 279); caused by window parking (see §5).
  * EV-0086 13:08 — gen1 clean stop (comp 201–202), gen2 layer invalidated before any frame (comp 206).
  * EV-0084 11:33 — **crash** at cp_frame_end_submission (no clean stop line; app.ips).
  * EV-0083 11:12 — layer left running state before endSubmission; exiting loop (comp 65).
  * EV-0082 11:02 — layer invalidated (comp 24) simultaneous with MC's background-GPU VK_ERROR_DEVICE_LOST.
* **Placement (anchor):** anchor=1 in all sessions except the very first frame of the 13:08 and 16:39 sessions and one
  frame of EV-0083; ARKit tracking frames show real head positions (e.g. 16:39 latestlog display views gen=1152 applied …
  Lpos=(-0.0321,-0.0267,-0.0245)).
* **Presentation rate is not 90 Hz:** ~45–51 fps in the 15:28 run (6360 frames / ~124 s), ~83 fps in 16:39 (1080 frames / 13 s),
  ~88 fps in 15:36. Frame-rate is a secondary issue; it does not explain a uniformly black display.

So, for (a): **the compositor was running and presenting drawables in every run where frames > 0, command buffers completed,
and the only stops are app-background / window-parking teardown (plus the single EV-0084/EV-0082 crash modes, both since fixed).**

---

## 4. Provider eye-texture content over time (mission question b)

The compositor blits the 32×32 **centre** of each provider eye texture every ~300 frames and logs mean RGB, alpha, max, nonBlack,
luma (VRMCCompositor.mm:250-308). Exact lines:

**15:28 run (EV-0090, pre-JNI-fix, menu world world58) — comp log 323–424:**
   323: provider tex L L: mean=(45.3,35.3,27.4) alpha=255.0 max=(93,67,54) nonBlack=1024/1024 luma=36.00 frame=0
   324: provider tex R R: mean=(44.8,35.3,27.8) alpha=255.0 max=(93,67,54) nonBlack=1024/1024 luma=35.95 frame=0
   328: provider tex L L: mean=(21.2,19.6,11.9) … luma=17.56 frame=1
   332: provider tex L L: mean=(120.3,120.3,120.3) … nonBlack=1016/1024 luma=120.34 frame=300
   333: provider tex R R: mean=(0.0,0.0,0.0) alpha=255.0 max=(0,0,0) nonBlack=0/1024 luma=0.00 frame=300
   337: provider tex L L: mean=(112.4,140.7,215.3) … luma=156.14 frame=600
   342: provider tex R R: mean=(181.0,207.0,255.0) alpha=0.0 … luma=214.33 frame=900
   391: provider tex L L: mean=(11.8,11.5,49.1) … luma=24.11 frame=4200
   401: provider tex R R: mean=(9.0,10.0,18.0) alpha=0.0 … luma=12.33 frame=4800
   424: (last frame 6360)
* The left texture is mostly a **near-uniform dark navy** (≈RGB 10–13,10–13,46–51) from frame ~1200 on — consistent with a
  corrupted left-eye camera looking at (night) sky/fog, not at a rendered scene. The right texture alternates between
  uniform bright sky blue (181,207,255, alpha=0) and darker terrain colours. **The two eyes are wildly inconsistent**, which is
  the expected fingerprint of the pre-fix JNI left-eye matrix corruption, not of a black render target.
* **15:36 run (comp 425-484):** frame 1–120 eyes=0 (provider had not exported yet); from frame 240: L/R luma
  43.25 → 53.62/107.72 → 48.66/98.28 → 127.86/75.56 → 86.10/106.41; one alpha=213.0 (frame 1200 L) but otherwise 255.
  **Both eyes bright and structurally plausible (not black).**
* **16:39 run (comp 486-542):** frame 0/1 L luma 105.05, R 103.38 (means (115.6,110.4,89.1)/(113.9,108.7,87.6)); frame 300
  L 106.56 / R 108.57; frame 600 L 108.27 / R **153.68**; frame 900 L 102.85 / R 112.06. **Bright, both eyes, matching
  each other closely — the provider eye-render path is working.** This is the decisive new fact: content is no longer dark.

Answers for (b): provider eye textures were **dark in the 15:28 session** (menu-world world58, luma 14–59, plus a corrupted left
camera), but **bright and consistent in both post-JNI-fix sessions** (luma 43–128 and 103–154). Alpha is 255 in every 16:39
sample; alpha=0 only appears in the 15:28 run's right texture (a pre-fix artifact worth keeping on the watch list).

---

## 5. Lifecycle sequence around immersive opening (mission question d)

The shell's committed logging (Shell.swift) emits: vrmc_shell_start invoked → activity init … → coordinator ready →
UIScene.didActivate/didBecomeActive → VRMCGameStarted received → (+15 s) auto attempt 1 openImmersiveSpace result=opened
epoch=N → window parked windows=2 visible=false chrome=… → immersive session opened generation=N … reason=auto and later
willResignActive/didEnterBackground → VRMCImmersiveEnded generation=N → window restored → immersive space dismissed epoch=N.

Exact timings for the five committed-build sessions (shell lines in evidence/EV-0091-fresh/vrmc-shell.log):

| Session | open | window parked | first frame seen (comp) | UIScene.willDeactivate | willResignActive / didEnterBackground | ended / dismissed | minutes with scene active while parked |
|---|---|---|---|---|---|---|---|
| 15:24 | 01:24:20 | 01:24:20 | never (stop before frame, comp 288) | 01:24:42 (+22 s) | 01:24:53 | 01:24:53 | 0 (no frame) |
| 15:28 (EV-0090) | 01:28:18 | 01:28:18 | ~01:28:19 | 01:30:19 (**+121 s**) | 01:30:22 | 01:30:22 | **2:01** |
| 15:36 | 01:37:05 | 01:37:05 | ~01:37:05 | 01:37:22 (+17 s) | 01:37:22 | 01:37:22 | 0:17 |
| 16:39 (EV-0091) | 02:39:44 | 02:39:44 | ~02:39:44 | 02:39:49 (**+5 s**) | 02:39:57 | 02:39:57 | 0:13 |

Observations:

1. **No run ever survived with the window scene active for more than ~2 minutes after the immersive opened**, and every run ended
   in the same order: UIScene.willDeactivate → (0–11 s later) willResignActive+didEnterBackground → compositor stop →
   VRMCImmersiveEnded → dismiss. There is never a willResignActive without willDeactivate or an immersive dismissal *before*
   the window-scene event: the **window-scene deactivation is the leading event in all teardowns**.
2. The delay from parking to deactivation varies 5 s / 17 s / 121 s across runs with identical parking code, so parking alone does
   **not** deterministically and immediately deactivate the scene. Two candidate causes remain: (i) the wearer removing the
   headset after seeing the black screen (visionOS then deactivates the window scene / backgrounds the app), or (ii) a deferred
   system reaction to all windows being hidden. The 15:28 run (121 s with frames flowing) shows parking does not kill presentation
   within the first two minutes, which makes (i) — operator/headset removal — the more likely common cause, and the
   deactivation is then a *consequence*, not the cause, of the black experience.
3. The 14:41 diagnostic-build session is the exception that shows the reverse order is possible: VRMCCompositorRunning →
   compositor presenting; hiding chrome + parking windows → window parked → **UIScene.willDeactivate in the same second** →
   background → gen-2 ended 0.1 s after the first frame. Parking *while the layer has just started presenting* can apparently
   deactivate the window scene immediately. This is a real risk for the committed build too, because it parks windows right after
   openImmersiveSpace returns.
4. **App/process survives the background in the latest runs.** The 16:39 latestlog continues after didEnterBackground
   (display views gen=1152 applied … then OSCPortIn Bad file descriptor errors at 16:40:05) — the app is not suspended
   immediately and the game keeps polling display views after the immersive ended.
5. **The game never crashes in the post-fix runs.** Unlike EV-0082/EV-0084, no VK_ERROR_DEVICE_LOST, no crash report in the
   15:36/16:39 teardowns. So the black is not a crash artifact.

Also relevant: the 16:39 run has UIScene.willDeactivate only **5 s** after opening — under 5 s the operator cannot have done much
more than put the headset on and look; that strongly suggests the operator observed the black and immediately took the headset off.

---

## 6. What the operator most likely saw in the "pure black" sessions (mission question e)

**15:28 EV-0090 (pre-JNI-fix) — black is expected from *content + transform*, not from presentation:**
* provider textures: world58 (night-ish) with L eye ~uniform dark navy (mean RGB ≈ (10,10,48) ⇒ luma ≈ 23 at many samples) and a
  *garbage* left-eye display view. The left eye image is a corrupt-camera render (mostly uniform navy); the right eye is
  intermittent bright/dark but never a coherent stereo partner. Binocular fusion of one navy-near-black eye + one odd image reads as
  "pure black".
* plus the flat-mode badge is only the top 1.5 % of the drawable, and the whole scene was dark ⇒ plausible "pure black" report even
  if the display path worked.
* → **This session is NOT decisive evidence of a presentation bug.** It is explained by two independent game-side defects, both now
  addressed in code (JNI fix f4d0617; content bright in the next runs).

**15:36 and 16:39 (post-JNI-fix) — black can no longer be explained by content:**
* display views applied correctly (L/R positions within 1 mm of the published values; latestlog 16:39 display views gen=1 applied
  ipd=0.0644 Lpos=(-0.0322,-0.0266,-0.0356), and every later gen the same within millimetres);
* provider eye textures bright (luma 103–154) and consistent across eyes, in both runs;
* compositor in **flat 1:1** mode — i.e. the drawable is literally the eye texture plus the green top-strip badge;
* command buffer completed, no failure lines, 1080–1560 frames in 13–17 s.
* **16:39 additionally should have shown the procedural test pattern for every frame** because
  Documents/vrmc-test-pattern.flag existed since 16:13 and VRMCCompositor.mm:340 reads it at every compositor-thread start
  (const BOOL forceTestPattern = documentFlag(@"vrmc-test-pattern.flag"); testPattern = (!haveEyes || samplingDisabled ||
  forceTestPattern || autoTestPattern) at line 701). A forced test pattern is a bright procedural gradient with a blue top
  strip (fmain_test, VRMCCompositor.mm:206-213) — impossible to mistake for black. **Caveat:** this build does **not log** the
  resolved forceTestPattern value (diagnostics line at 346), so the flag effect is a code-path certainty, not a log observation.
  Also the 15:36 run had eyes=0 for its first ~240 frames, during which the compositor *automatically* draws the test pattern
  regardless of flags — another missed chance to see a pattern if the display had been working.
* Therefore, if the operator black report refers to a post-fix run, **the drawn drawable (game image or forced pattern) did not reach
  the wearer's eyes.**

**Answer:** the most likely black-report split is: 13:08 (EV-0086) = reprojection-path black (see H2), 15:28 (EV-0090) = dark
world58 + corrupt left eye (content), **16:39 (and likely 15:36) = presentation/compositing failure: the layer renders but is not
visible (or is black) on the display.**

---

## 7. Ranked hypotheses (with confidence and discriminators)

### H1 — The compositor's present path is not reaching the display (PRIMARY; confidence 0.7)
The drawable is encoded/presented, command buffers complete, yet the wearer sees black even with bright provider content and a
forced procedural pattern. The failure is between "we draw into the drawable color texture" and "CompositorServices composites it
for the wearer". Sub-candidates, most probable first:

* **H1a (0.30) — window-scene / foreground state:** the app parks all regular windows immediately after openImmersiveSpace
  returns (Shell.swift:289-301, setGameWindowsVisible(false)), and the SwiftUI WindowGroup content was also destroyed by the
  *legacy root swap* (see H1b). Sequence in every run: parked → (5–121 s) → UIScene.willDeactivate → background → layer end.
  CompositorServices may render the layer while the system has already decided the window scene is not participating
  (or while the app is mid-transition), showing black. Discriminator: a run that **never parks** the windows (new
  vrmc-no-window-park.flag), or parks only after N s, with the forced test pattern; also correlate scene state with the first
  presented frame timestamp.
* **H1b (0.25) — confound: the device has been running the *legacy root-swap* path for every post-M3b run.**
  evidence/EV-0091-fresh/latestlog.txt:116: [VRMC] legacy root-view-controller swap for the game surface
  (vrmc-legacy-root-swap.flag), and the same line exists in the 15:28 run's latestlog. The M3b modal game-surface patch
  (patches/vrmc-m3w3-modal-game-surface.patch, keeps the SwiftUI scene alive, keeps chrome hiding working) has therefore
  **never been exercised on device since EV-0086**. The root swap destroys the WindowGroup view; the scene's
  persistentSystemOverlays binding and any SwiftUI scene resources die. This can plausibly leave the window scene in a
  state that deactivates shortly after and may break immersive compositing. Discriminator: **remove vrmc-legacy-root-swap.flag**
  (the flag is currently on the device) and repeat the test-pattern run.
* **H1c (0.10) — CompositorServices drawable/present misuse** (depth attachment, view texture map, cp_frame_end_submission
  ordering, layer state). The code follows the M3a-evidenced pattern that passed EV-0074, but it now runs from a thread inside a
  much larger app; the drawable-readback instrumentation (task-3) will prove what was encoded. Discriminator: blit the drawable
  color texture to a shared buffer each frame and log mean/max luma; if the log says "bright pattern" and the operator sees black
  ⇒ present path; if "black" ⇒ encode path.
* **H1d (0.05) — frame timing / presentation deadline:** frames at 45–88 fps with a 90 Hz layer; if every drawable is submitted
  late the system could drop them (black) while the loop runs. Unlikely to produce a *uniform* black immersive (usually shows the
  last presented frame), and the M3a probe presented test patterns fine with the same APIs; keep as a fallback after readback.

### H2 — EV-0086 (13:08) black is a reprojection-specific bug, now superseded (confidence 0.15 for that run only)
That build had only the reprojection path: display-view tangents from the headset vs. provider symmetric 110° FOV; per-pixel ray→UV
via matrices. Its own operator report was "completely black". It predates the CPU ray diagnostics. Given EV-0087's host validation
and EV-0090's flat mode, this is now moot for the current build; do not re-open it unless the drawable readback shows black with
flat mode (which would move weight to H1c/H3).

### H3 — Provider texture / game content is black or unsynchronised (confidence 0.10 after the 15:36/16:39 data)
* **H3a (0.05) — GPU cross-queue race:** the compositor samples MoltenVK-exported MTLTextures on its own Metal queue **without
  GPU synchronisation** (task-4's scope: no MTLSharedEvent/timeline wait on the game's frame). Unsynchronised reads could return
  stale/garbage and, at worst, black. Discriminated by the test pattern (pattern does not sample textures) and by task-4's sync fix.
  Note the CPU readbacks show correct content, so memory does contain the image; a pure GPU hazard is possible but must explain why
  *every* frame was black.
* **H3b (0.05) — dark content:** was the true cause at 15:28 (world58 + corrupt left eye), but is refuted for 15:36/16:39
  (bright, eye-consistent readbacks) unless the operator's report predates those runs (see §8 open question).

### H4 — Operator/timing artefact (confidence 0.05)
The 5 s race between "immersive opens" and "operator puts the headset on" could mean the operator looked at a space that had already
deactivated (black home environment / brief black before passthrough). UIScene.willDeactivate at +5 s in 16:39 is suspiciously fast.
Discriminator: operator script — wear the headset *before* launching, keep it on, and report continuously; and a run where the
operator confirms whether the system home/passthrough was visible around the black. (Comfort of the operator matters here: do not
ask for repeated long black sessions.)

**What is ruled out:** frame loop dead (frames and completed command buffers in all runs); provider eye textures black (refuted
by 15:36/16:39 readbacks); display views corrupt (fixed and verified in 15:36/16:39 latestlog lines); MC crash/device-loss (no
crashes in post-fix runs); app background before first frames (frames flow for 13–17 s before background).

---

## 8. Open question the Lead must resolve before ranking is final

The Lead's brief states the operator still reports "pure black" and attributes it to the 16:39 run. **The logs cannot by
themselves confirm which run the operator's report refers to.** The EV-0090 entry (pure black) is the 15:28 run; the 15:36/16:39
runs have no operator report in the evidence files. If the "pure black" report predates 16:13/16:39, then H1 is not yet proven and
the priority is a clean operator-reported run with the test pattern. If the report is from after 16:39, H1 is proven and the next
work is the drawable readback + parking/legacy-flag A/B. **This distinction must be stated explicitly in the next VERIFY entry.**

---

## 9. Minimal decisive device-run matrix (Documents/ flags; Lead executes)

Flag inventory relevant to the current build (all in the app data container Documents/):
vrmc-test-pattern.flag (forces procedural pattern), vrmc-no-sampling.flag (pattern + never sample), vrmc-reproj-off.flag,
vrmc-reproj-on.flag, vrmc-reproj-debug.flag, vrmc-hide-chrome-always.flag, vrmc-legacy-root-swap.flag
(**currently present — must be removed for the M3b path**), plus stale vrmc-immersive-on-launch.flag (read only by an
uncommitted shell build; dead in the installed one) and autolaunch.flag (intended).
**Currently present (per Lead):** vrmc-test-pattern.flag (16:13), vrmc-legacy-root-swap.flag (14:26),
vrmc-immersive-on-launch.flag (14:39), autolaunch.flag (08:36).

**Instrumentation to add before the runs (owner: compositor task-3; one-line risk):**
1. log the resolved forceTestPattern and the three reprojMode/debugShading/samplingDisabled values **per session**;
2. after each frame, for the first ~3 frames and every ~60 frames, **blit the drawable color texture to a shared buffer and log
   mean/max luma per view** — this is the ground truth "what did we present";
3. make the test pattern unmistakable (e.g. full-screen saturated quadrant pattern + white corner markers) and log its mode badge.

| Run | Flags to push | Flags to remove | What it proves / pass criterion |
|---|---|---|---|
| **R1 — presentation ground truth (highest priority)** | vrmc-test-pattern.flag | **vrmc-legacy-root-swap.flag**, vrmc-immersive-on-launch.flag (stale), all reproj flags | Operator must see the saturated pattern (blue badge strip). Drawable-readback log must show bright luma. If pattern visible ⇒ presentation works ⇒ black in previous runs was content/state; if black while readback is bright ⇒ **H1a/H1c proven (present path)**, then R2. Also tests the never-run **modal M3b game-surface path** and its chrome hiding. |
| **R2 — parking A/B (only if R1 black)** | vrmc-test-pattern.flag + new vrmc-no-window-park.flag (Shell.swift: skip setGameWindowsVisible(false); ~5 lines) | vrmc-legacy-root-swap.flag; keep chrome flag if desired | If pattern becomes visible with parking disabled ⇒ parking/window-scene state is the cause (H1a). If still black ⇒ present-path/CompositorServices bug (H1c/H1d); escalate to the drawable/frame-timing investigation. |
| **R3 — content/alignment sanity (after R1/R2 show content)** | remove vrmc-test-pattern.flag; keep a known-good menu world; optional vrmc-reproj-debug.flag | legacy flag stays removed | Operator: is the menu world (world27/58 etc.) visible at sane brightness and aligned (no exotropia)? Then create/enter a world and confirm in-world content. This is the first real "M3 visual" run. |
| **R4 — re-entry / lifecycle** | same as R3 | — | Background (crown) and foreground; expect reopen (generation 2) with scene active; verify no immediate invalidation. |
| **R5 — GPU sync control (only if R1 shows pattern but R3 is black)** | vrmc-no-sampling.flag vs. normal | — | If pattern (no texture sampling) works but sampled content is black ⇒ cross-queue sync/race (H3a; task-4 fix). |

Do not run more than one confounded variable at a time: **R1 first** (it also cleans up the legacy-root-swap confound that has
invalidated every post-M3b device run). Keep the headset-wearing window short (R1 can be < 60 s); stop on any discomfort.

---

## 10. Exact citations used above

* Shell lifecycle / timings: evidence/EV-0091-fresh/vrmc-shell.log:189-205 (16:39 run), :172-188 (15:36 run),
  :155-171 (15:28 EV-0090 run), :138-154 (15:24 run); earlier sessions in evidence/EV-0090/vrmc-shell.log:1-171
  (EV-0082/83/84/85/86 at lines 7-55, 56-72, 73-95, 96-127, 128-171).
* Compositor blocks: evidence/EV-0091-fresh/vrmc-compositor.log:486-542 (16:39), :427-485 (15:36), :290-426
  (15:28 EV-0090), :281-289 (15:24), :239-280 (14:41 EV-0089), :217-238 (14:33/14:41 dismissed opens),
  :10-24 (EV-0082), :25-65 (EV-0083), :66-94 (EV-0084), :156-177 (EV-0085 11:57), :178-207 (EV-0086).
* Menu world / game state: evidence/EV-0091-fresh/latestlog.txt:312-317 (world27, 16:39 run),
  evidence/EV-0090/latestlog.txt:301-314,370,580 (world58, 15:28 run), evidence/EV-0083/latestlog.txt:298-315 (world21),
  evidence/EV-0085/latestlog.txt:298-315 (world18), evidence/EV-0086/latestlog.txt:298-315 (world4).
* Legacy-root-swap confound: evidence/EV-0091-fresh/latestlog.txt:116; patches/vrmc-m3w3-modal-game-surface.patch:25,49,75;
  export/README.md:66.
* Provider content readbacks: 15:28 evidence/EV-0090/vrmc-compositor.log:323-424; 15:36 :427-485; 16:39 :486-542.
* forceTestPattern code path: runtime/native-shell/Sources/VRMCCompositor.mm:340 (flag read), :346 (diagnostics line, does
  not include it), :701 (testPattern selection), :206-213 (test shader incl. blue top strip).
* Compositor shader/flat path: VRMCCompositor.mm:179-184 (flat fragment + green top strip, forced alpha=1), :193-204
  (reproj branches), :673-745 (render pass + clear colours red/green, viewport, encode present).
* First protocol crash root cause: evidence/EV-0082/latestlog.txt:271,280,297 (background GPU submission not permitted ⇒
  VK_ERROR_DEVICE_LOST), EV-0082 app.ips at cp_frame_end_submission.
* Flag mtimes / installed app: Lead's pull /tmp/vrmc-pull-1650 (reported 2026-11-01 ~16:50), not independently verifiable
  from logs (documented as a Lead-supplied fact).

---

## 11. One-paragraph answer to the mission

Every device session from 11:02 to 16:39 HST was the **Vivecraft VR main menu rendering a MenuWorlds panorama** (world21/18/4/58/27),
never a loaded save. The compositor loop presented frames and completed command buffers in all runs where the layer ran, and the
only teardown modes are app background / window parking (plus the two fixed early crash modes). The **first black report (13:08,
EV-0086)** came from the reprojection-only compositor; the **15:28 EV-0090 "pure black"** is explained by a dark night-time menu
world plus the JNI-corrupted left-eye display view (applied Lpos=(-0.0024,-0.0155,0.9999), i.e. the view matrix's third column,
while the right eye was exact). The **JNI fix works**: the 15:36 and 16:39 runs show both eyes rendering bright, consistent
images (luma 103–154) with correctly applied display views and flat 1:1 mapping, and the 16:39 run had the **test-pattern flag on
the device** which should have replaced the game image with an unmistakable procedural pattern. If the operator still reports a
black immersive on that run, **the eye-render/content side is exonerated and the blocker is in the CompositorServices present /
window-scene parking path**, with two prime suspects: the immediate all-window parking right after opening the immersive space and
the fact that the device has been running the legacy root-view-controller swap (so the M3b modal game-surface / chrome fix has
never been tested). The next run must (1) log the resolved test-pattern flag and blit-readback the drawable, (2) remove
vrmc-legacy-root-swap.flag, and (3) A/B window parking — that matrix is §9.
