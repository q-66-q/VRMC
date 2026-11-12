# REVIEW 1.3 — provider fixes, in-VR quick menu, automatic setup

**Status:** host PASS (provider), code review complete; **device NOT RUN** (owned by the device
teammate). This report is review + host-test evidence, not a device acceptance record — per
AGENT.md §0.2 no feature is claimed working on the headset until a VERIFY.md entry exists.

- Worktree: .claude/worktrees/project-overhaul-bugs-features-ui-c2719a
- Branch: claude/project-overhaul-bugs-features-ui-c2719a, checkpoint 14268d4 (+ this review's
  uncommitted fixes)
- Verifier: verify (independent re-run; the previous session's log was only a cross-check)
- Host: macOS, Java 25 temurin (/Library/Java/JavaVirtualMachines/temurin-25.jdk), no device
- Review scope: the 1.3 provider changes (VisionVR, VisionM7Gesture, VisionQuickMenuScreen,
  VisionSettingsFile, VisionCommandFile, new host tests) and ShellSetup.swift;
  Shell.swift/ShellUI.swift/compositor/signing read-only (owned by other workstreams).
- Out of scope: launcher/UI rework in progress by the ui teammate, compositor changes, signing and
  install (device teammate).

**Verdict:** the provider host suite is green and the jar is byte-reproducible; two gameplay/UX
regressions and two automatic-setup first-run defects were found and fixed in this review. Remaining
items are either low-risk or can only be closed on the headset (see §6).

---

## 1. Provider host tests (independently reproduced)

~~~
source <scratchpad>/provider-env.sh
provider/tests/run_tests.sh
~~~

- Result: [provider-tests] ALL PASS, exit 0 — **0 FAIL**, 3 explicit SKIPs (all environment-optional:
  vkreflect-with-lwjgl because no LWJGL 3.4.1 jar is installed, vulkan-host-test because no host
  MoltenVK dylib, m4-fixture because VRMC_INPUT_FIXTURE is unset; the same three SKIPs as the previous
  session, and the suite fails closed if a configured fixture is missing).
- New/affected M7 evidence:
  - m7-gesture: 74 checks, PASS
  - m7-regression: **35 checks, PASS** (was 33; includes the new look-down test)
  - m7-seated-turn: **17 checks, PASS** (new)
  - m7-fuzz: 200 000 random frames, 0 stuck-input violations, PASS
  - m5-settings-file: 24 checks, PASS; m5-quick-menu-reflection: 5 checks, PASS
  - m5-command: includes the new quick-menu command
- Full log: /tmp/vrmc-verify-run_tests-final.log (the previous-session log was only a cross-check).

## 2. Provider jar — reproducible build

scripts/build_provider.sh (env from provider-env.sh) was run three times: the suite's own build plus
two independent OUT_DIR builds.

| build | bytes | sha256 |
|---|---|---|
| suite build | 158742 | 89be397f57d2c765e61e90afad1705bc07719eb71d91e1aec94c946541dc5e1d |
| independent A | 158742 | 89be397f…dc5e1d (identical) |
| independent B | 158742 | 89be397f…dc5e1d (identical) |

**Final jar: 158 742 bytes, sha256 89be397f57d2c765e61e90afad1705bc07719eb71d91e1aec94c946541dc5e1d**
(41 classes from 32 sources). Byte-identical across builds; entry timestamps are pinned by jar --date
in scripts/build_provider.sh.

> **Integration note:** runtime/native-shell/build/VRMCShell.framework/vrmc-provider.jar in the
> checkpoint is an older 157 800 B jar (938f0563…). scripts/build_shell.sh rebuilds the provider and
> copies it into the framework, so a fresh shell rebuild must happen after this review's fixes or the
> headset gets the pre-fix provider. (Not rebuilt here — the shell build is owned by the Lead/ui.)

## 3. Findings fixed in this review

### F1 (HIGH, fixed) — posture recovery learned a look-down pose → false jump on look-up

- Files: provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java:200-211 and :555-590;
  test provider/tests/dev/vrmc/provider/VisionM7RegressionTest.java.
- The follow-up pass added a 12 s slow-drift posture recovery that adapts the head-height baseline
  toward the current head height whenever the head is quiet and out of the deadband. A steep look-down
  moves the tracked HMD **down 0.10–0.13 m** (the documented pitch lever), which is outside the
  0.10 m deadband; after a few seconds the drift re-baselined *at the look-down height*. Looking back
  up then exceeded HEAD_JUMP_RISE (0.10 m) with headVel > 0.35 m/s → **unintended jump**.
- Pre-1.3 code froze the baseline outside the deadband, so this is a 1.3 regression. Real-world hit:
  mining/building while looking at the floor for 5–10 s, then looking up = jump.
- Host reproduction (probe against the built classes, frame-stepped at 11 ms; head drops 0.13 m at a
  45–64° look-down, then rises over 0.3 s):
  - before fix: hold 5 s → jump=true; hold 10/20/30/45 s → jump=true
  - after fix: hold 2/5/10/20/30/45 s → **jump=false**, baseline stays at standing height
- Fix: baseline adaptation (both the fast deadband drift and the slow posture drift) now only runs
  within ~20° of level (HEAD_POSTURE_LEVEL_PITCH = 0.35 on |forward.y|); the ≥0.30 m sit/stand
  re-baseline branch is unchanged and still works while looking down. Added
  testLookDownDoesNotLearnPosture (2 checks) to VisionM7RegressionTest.

### F2 (MEDIUM, fixed) — seated "double tap = turn right" netted zero rotation

- Files: provider/src/main/java/dev/vrmc/provider/VisionVR.java:229-233 and :2313-2345; new
  provider/src/main/java/dev/vrmc/provider/SeatedTurnGesture.java; new
  provider/tests/dev/vrmc/provider/SeatedTurnGestureTest.java; provider/tests/run_tests.sh.
- The M7 seated play feature advertises "left middle-finger pinch tap = turn left, double tap = turn
  right". The gesture engine emits a **single-tap pulse on the first tap of a double tap** (the
  double-tap pulse arrives later), so acting on the single tap immediately turned left and then the
  double-tap pulse turned right: a double tap netted **zero** rotation, i.e. no effective right turn
  for a seated player. (The same pre-existing behavior remains in the M4 fallback path
  VisionVR.applyLocomotion; it is left untouched because M4 mode is the legacy fallback and changing it
  is a separate UX decision — recorded as R12.)
- Fix (Lead-approved option a): the left single-tap decision is deferred by the engine's middle
  double-tap window (VisionInput.middleDoubleMillis(), 320 ms by default) + 60 ms margin. A double tap
  inside the window becomes exactly **one right turn**; anything else becomes one left turn. Cost:
  ~380 ms latency on a single left tap (a snap turn is a discrete action, acceptable); right turn is
  immediate on double-tap detection. Implemented as a pure-Java helper so it is host-testable: 17 checks
  cover deferral, net-one-right-turn, the 2-frame pulse not extending the deadline, two separate taps =
  two left turns, and cancellation on context loss (GUI/seated off). The advertised gesture copy is
  unchanged and is now truthful.

### F3 (MEDIUM, fixed) — failed provider install was reported as "ready" on refresh

- File: runtime/native-shell/Sources/ShellSetup.swift:332-353 (hunk 4 of this review's ShellSetup diff).
- If installBundledProvider() returned .missing after copying but at hash verification (e.g. corrupt
  copy), a file still exists at mods/vrmc-provider.jar; refresh() → inspectProvider(fallback: .missing)
  found the file and returned .ready("Installed"), enabling Play with an unverified jar.
- Fix: when the build bundles the provider, a non-ready fallback now hashes the installed jar and only
  reports ready if it matches the bundled hash (the same check the startup install makes); otherwise it
  logs the mismatch and stays .missing("…failed verification. Reinstall it."). The hash cost is only paid
  on the failure path (the success path returns the startup .ready immediately).

### F4 (MEDIUM, fixed) — duplicate Vivecraft jars still enabled Play

- File: runtime/native-shell/Sources/ShellSetup.swift:202-214 and :309-317 (hunks 1–3 of this review's
  ShellSetup diff).
- inspectVivecraft() correctly returns .attention("More than one Vivecraft jar … the game will not
  start"), but .attention counts as usable (intended for a single untested build), so Play stayed enabled
  and the first run would fail in the mod loader.
- Fix: track vivecraftDuplicate in refresh() and require !vivecraftDuplicate in readyToPlay. An untested
  *single* jar stays playable. (No API/status-enum change, so the in-progress ShellUI rework is
  unaffected.)

## 4. Reviewed and found sound (no change)

- **Input safety (M7):** every hand action is written through setM7Action each frame, so a missing
  hand/context writes false; releaseAll()/releaseAllImmediately() cover tracking loss, stale input,
  seated mode, destroy and release-input; releaseM7Actions() clears the locomotion analog, GUI mouse
  press, pinch carry, seated jump/sneak and the seated turn pulse. The 200 k-frame fuzz test still
  reports 0 violations.
- **Pinch carry across contexts (VisionVR.java:2113-2122):** a right pinch held while the GUI opens or
  closes is flagged and ignored until released, and the old press duration is forgotten, so "Back to
  Game" cannot place a block/mine. The GUI click path also checks the carry flag.
- **Quick-menu wiring:** "quick-menu" is in VisionCommandFile.COMMANDS and covered by
  VisionCommandFileTest; the pause-screen button is injected through the real 26.2
  Screen.addRenderableWidget(GuiEventListener) (verified against the actual client jar, not only a stub);
  injection failures are logged once and the launcher command remains the fallback. All Host actions
  apply on the client thread and the settings they persist use the same keys the launcher reads
  (comfort.seated, comfort.worldRotationIncrement, comfort.worldScale, performance.renderDistance; ranges
  match ShellUI: turn 0–90, scale 0.8–1.5, draw distance 6–24). The status line refreshes through a
  widget rebuild after each click (vanilla Screen.rebuildWidgets() semantics checked in the 26.2
  bytecode).
- **Settings file (VisionSettingsFile):** key-only edit preserves comments/unknown keys/order, drops
  duplicates, rejects newline/CR and '=' in keys, creates the parent dir, writes temp + atomic move with
  a non-atomic fallback, never throws; the test covers all of it plus the Documents/instances layout
  guard for the vignette flag.
- **M7 fist-tap vs pinch (VisionM7Gesture:213 and :820-840):** a confirmed pinch of the same hand within
  500 ms suppresses the fist-tap (menu/use), so curled pinch fingers cannot fire a surprise gesture;
  plain fist taps and taps >500 ms after a pinch still work (the regression test covers both hands and
  GUI-close).
- **Seated play context:** CTX_NO_HEAD_GESTURES only gates the head jump/sneak and clears a latched
  sneak; hand gestures, locomotion, bow, eat and GUI actions still work; a warning + chat message is
  shown when middle gestures are disabled (the middle family is enabled by default); Vivecraft's own
  keyboard-seated toggle is converted to seated play and persisted, so a headset user cannot lock
  themselves out.
- **Automatic setup paths:** SetupManager.gameDirectory() = Documents/instances/default matches
  shellRuntimeSettingsURL(), the command queue and the provider's vignetteFlag() Documents/instances
  heuristic; the bundled jar is staged to a temp name, replaced/moved, then hash-verified; developer
  builds are preserved via vrmc-dev-provider.flag; download installs only after size/SHA verification.
- **Pinned Vivecraft artifact (network-verified 2026-11-11):** the pinned Modrinth URL
  (cdn.modrinth.com/data/wGoQDPN5/versions/VrqKDtZn/vivecraft-26.2-1.3.15-fabric.jar) returns exactly
  **6 685 183 bytes / sha256 e63aeed1a6b36a55fc38c7633acbbac2cdf8b46f546382c6a2cd9348440b58bb**,
  matching vivecraftBytes/vivecraftSHA256 in ShellSetup.swift. The one-tap download+verify path will
  accept the real artifact.

## 5. Findings reported, not fixed (low; no code change)

| # | Sev | Finding | Location |
|---|---|---|---|
| R1 | low (theoretical) | The pinch-carry guard only arms when the right pinch is still held on the GUI-transition frame. If the pinch is released on the exact frame the GUI closes, the release pulse can still become a place/attack in world (window ≈ 1 frame) | VisionVR.java:2109-2124 |
| R2 | low | Quick-menu comfort vignette quantises to {0, .3, .5, .7}; a launcher-written 0.9 (ShellUI allows it) reads as "Strong" but the next press writes Off — display/actual strength mismatch | VisionSettingsFile.java:105-123, VisionVR.java:2506-2530 |
| R3 | low | Quick-menu button is placed at the bottom centre of the pause screen (height-28); overlap with the vanilla feedback/report row is possible on some layouts — needs the device screenshot (see §6) | VisionVR.java:2410-2442 |
| R4 | low (test robustness) | VisionQuickMenuReflectionTest asserts addRenderableWidget is non-public; if a future MC makes it public the test fails though the provider still works. It also cannot prove the reflective call/button insertion itself (VisionVR is game-coupled, no host test) | VisionQuickMenuReflectionTest.java:33-34 |
| R5 | low | updateQuickMenuEntry() permanently disables the button after the first transient failure (quickMenuInjectFailed never resets); the launcher command remains the fallback | VisionVR.java:2410-2442 |
| R6 | low | Seated play only changes M7-mode behavior; in M4 gesture mode the play-style toggle has no effect (M4 already has its own middle-tap snap turn) | VisionVR.java:2160-2200 |
| R7 | low | Vivecraft download is streamed one byte at a time (6.7 MB), which can be slower than a buffered download on device; not measured | ShellSetup.swift:476 |
| R8 | low | installVivecraft() deletes existing Vivecraft jars before moving the new jar into place; a failed final move loses the previously working jar (same-volume move, very unlikely) | ShellSetup.swift:501-512 |
| R9 | low | vivecraftHashCache is nonisolated(unsafe) and written (= nil) from the background download task while refresh() reads it on the main actor — benign data race | ShellSetup.swift:365, 510 |
| R10 | low | importVivecraft() validates only file name prefix, PK magic and 100 KB–64 MB size for non-pinned jars (pinned jars are SHA-verified); a bogus jar named vivecraft-*.jar installs as "untested" | ShellSetup.swift:514-544 |
| R11 | low (process) | Auto-setup gates Play only on provider+Vivecraft; Fabric profile/account/JIT are deliberately left to the launcher, so a first-run press on Play can end with the "launcher still getting ready" message instead of a setup hint | ShellSetup.swift:174-184, 213-215 |
| R12 | low (pre-existing) | M4 fallback applyLocomotion() still has the old "double-tap = turn right nets zero" behavior (see F2); M7 seated play is fixed | VisionVR.java:2701-2752 |

## 6. Must be checked on the headset (cannot be closed host-side)

1. **Automatic setup on a fresh install:** provider jar copied to Documents/instances/default/mods on
   first launch with the correct 158 742 B hash; Play enabled only when provider+Vivecraft are ready; the
   app installs/updates the jar without a manual copy.
2. **Vivecraft one-tap download:** press the download action and confirm the SHA-verified jar lands in
   mods/ (the pinned URL/size/SHA were network-verified from the host above; the device path and
   URLSession streaming are not), and a failed/cancelled download leaves mods/ unchanged.
3. **Play through the hidden launcher:** the custom Play button presses the launcher's own Play/Install
   button while the launcher is a hidden in-window host (no second UI); the first launch with the JIT
   prompt still works.
4. **In-VR quick menu:** the pause screen shows the "VRMC Quick Menu" button (visible, not overlapping
   the vanilla rows, clickable with head-ray + right pinch); every action works: recenter, height
   calibration, play-style toggle, turn step, vignette (saved, applies next immersive session), world
   scale, draw distance, release stuck input, gesture guide, Back to game / Done.
5. **Quick-menu ↔ launcher settings agreement:** change values in the quick menu, quit, confirm the
   launcher window shows the same values and the next game start applies them.
6. **Seated play on real hands:** right middle-finger pinch tap = jump, hold = sneak; left middle tap =
   turn left (~0.4 s after release); **double tap = one turn right** (the F2 fix — the primary thing to
   prove on device); no head-rise/sneak from the seated head; all other hand gestures unchanged; the
   "seated play needs middle gestures" message is not shown with default tuning.
7. **Gesture guide** text matches the actual M7/seated bindings; the launcher command controls still
   prefixes chat lines once.
8. **Vivecraft seated toggle** (if reachable in its VR settings) is converted to seated play, shows the
   one-time chat message, and persists comfort.seated=true; hands stay active.
9. **Posture fix on device:** look at the floor for 5–10 s then look up → no jump; a deliberate rise on
   toes still jumps; crouch → sneak and stand-up behavior unchanged; recenter/height calibration resets
   the baseline.
10. **Stuck-input safety:** kill/freeze the compositor or lose hand tracking mid-pinch → attack/use/
    teleport release; quick-menu "Release stuck input" clears everything.
11. **Shell framework rebuild** with the final jar (89be397f…) and a clean build/ so the bundled provider
    is the reviewed one (see §2 integration note).

## 7. Evidence/commands used

~~~
# tests (from worktree; env from the session scratchpad)
source <scratchpad>/provider-env.sh && provider/tests/run_tests.sh
# log: /tmp/vrmc-verify-run_tests-final.log
# repro: build_provider.sh twice (OUT_DIR=/tmp/vrmc-final-build-a|-b)
#        both sha256 89be397f57d2c765e61e90afad1705bc07719eb71d91e1aec94c946541dc5e1d, 158742 bytes
# pinned Vivecraft check:
curl -fsSL -o /tmp/vrmc-vivecraft-pin-check.jar https://cdn.modrinth.com/data/wGoQDPN5/versions/VrqKDtZn/vivecraft-26.2-1.3.15-fabric.jar
shasum -a 256 /tmp/vrmc-vivecraft-pin-check.jar   # e63aeed1…, 6 685 183 B
~~~

Adversarial probe used for F1 (not committed; frame-stepped VisionM7Gesture.update with a pitch/Y
transition): before the fix a 0.11–0.13 m look-down held 5–30 s followed by a 0.3 s rise produced
jump=true; after the fix all holds 2–45 s produce jump=false with the baseline unchanged.
Swift changes were syntax-parsed (swiftc -parse, PASS); a full typecheck is environment-blocked here
(the sandbox denies the Swift macro plugin server), so the Lead's shell build is the compile gate for
ShellSetup.swift.
