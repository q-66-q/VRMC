# M4 device run — immersive-scene input (operator checklist)

One-page procedure for the first on-headset validation of the M4-W1 input channel: **control the game
from the immersive scene** (not only from the 2D window). Design:
[docs/analysis/immersive-input.md](../analysis/immersive-input.md); plan: [M4_PLAN.md](M4_PLAN.md);
flags: [M3C_FLAGS.md](M3C_FLAGS.md) (M4 section).

Status framing (read first):
- **Step 1 is SYNTHETIC** (scripted hand data from the compositor, no real hand tracking). It proves
  the device stack compositor -> bridge -> provider -> Vivecraft actions. It is NOT hands evidence.
- **Step 2 is the real-hands check** (ST-S5-hands scope). Only an operator-confirmed Step 2 can move
  AC-4/ST-S5-hands off NOT RUN. The game must render in the immersive space (M3/EV-0094 build or later).

## 0. Preconditions (Mac side)

1. A signed app bundle whose embedded `VRMCShell.framework` and `Vrmc_bridge.dylib` come from the
   **frozen M4 tree**, plus the M4 provider jar pushed into the game instance. The Lead builds and
   stages this bundle at `artifacts/staged/VRMC-native-m4-input.app` (git-ignored). To rebuild it
   from source instead:

       # 1) device shell framework from the frozen tree (also dirties the TRACKED preview path
       #    runtime/native-shell/build/ locally - that is a local build output, NEVER commit it)
       scripts/build_shell.sh
       # 2) ABI v3 device bridge dylib
       MODE=device OUT_DIR=/tmp/vrmc-bridge-build scripts/build_bridge.sh
       # 3) refuse to stage a stale framework: the M4 compositor must be inside the binary
       strings runtime/native-shell/build/VRMCShell.framework/VRMCShell | grep -q 'INPUT-SIM SYNTHETIC' \
         || { echo 'STALE FRAMEWORK: no M4 input code - rebuild before staging'; exit 1; }
       # 4) stage/sign (never installs)
       SRC_APP=/tmp/VRMC-native-v14-auditfix.app DEST_APP=artifacts/staged/VRMC-native-m4-input.app \
         scripts/stage_native_app.sh runtime/native-shell/build/VRMCShell.framework \
         /tmp/vrmc-bridge-build/libvrmc_bridge.dylib
       # 5) push the M4 provider jar into the installed app's game instance
       OUT_DIR=/tmp/vrmc-m4-provider-build scripts/build_provider.sh
       scripts/push_provider_jar.sh /tmp/vrmc-m4-provider-build/vrmc-provider.jar

   (Installing on the shared headset is the operator's decision; the build/stage steps are
   host-only. Staging is not installing.)
2. The app data container keeps the existing Minecraft install/worlds — do not uninstall the app.
3. Hand-tracking permission: the visionOS Info.plist already carries
   NSHandsTrackingUsageDescription. On the first launch after installing a new build, visionOS asks
   for hand-tracking access — **allow it**. If it was denied, reset it in Settings > Privacy &
   Security > Hand Tracking (or reinstall) before Step 2.
4. Push the clear-diagnostics trigger once so stale flags from earlier M3c runs cannot poison the run:

       printf 'clear\n' > /tmp/vrmc-clear.flag
       xcrun devicectl device copy to --device <D1-UDID> \
         --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc \
         --source /tmp/vrmc-clear.flag --destination Documents/vrmc-clear-diagnostics.flag

## Step 1 — SYNTHETIC input (no real hands; proves the device stack)

1. Push the synthetic-input flag (content selects the script; 'cycle' walks right pinch -> right
   release -> left fist -> release -> both fists -> release):

       printf 'cycle\n' > /tmp/vrmc-input-sim.flag
       xcrun devicectl device copy to --device <D1-UDID> \
         --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc \
         --source /tmp/vrmc-input-sim.flag --destination Documents/vrmc-input-sim.flag

2. Launch VRMC through StikDebug (JIT) as usual, press Play, and wait for the automatic immersive
   open (~15 s after VRMCGameStarted; M3C behavior).
3. Expected device logs (pull them after the run with Step 3):
   - compositor: a `hand tracking supported=...` line and repeated
     `INPUT-SIM ... SYNTHETIC` lines; `input publish ... seq=... valid_mask=3` (both hands tracked
     in the fabricated snapshot); a final `input release` line (valid_mask=0) when the space ends.
   - game latestlog: `[VRMC-M4]` lines showing input snapshots consumed
     (`first input snapshot ... valid_mask=3`, `left hand acquired`/`right hand acquired`), gesture
     edges (`pinch right press (d=0.005)` ... `pinch right release`, `fist left engaged (r=0.77)` ...,
     `fist-tap left pulse`, `both-fist tap pulse (inventory)`), and the action-dispatch proof
     `[VRMC-M4] action <KeyMappingName> press|release origin=<left|right|none>` exactly once per
     scripted cycle. Action-set note: the right pinch maps to `key.attack` (INGAME) in the world and
     `vivecraft.key.guiLeftClick` (GUI) while a screen is open — only one of them is active per frame,
     never both; the left fist tap is `vivecraft.key.ingameMenuButton press origin=left` and both fists
     are `key.inventory press origin=right`.
   - no `VRMC-M4 input ... error` lines; no crash.
4. Report: did the immersive view stay up (same as EV-0094)? Did anything visibly react (a GUI click
   from the synthetic right pinch may select a menu button — the log evidence is the primary signal)?
   Any beep/parking differences?

## Step 2 — REAL hands (the actual fix)

1. Remove the synthetic flag. `devicectl` has no delete subcommand, so use the clear-diagnostics
   trigger:

       printf 'clear\n' > /tmp/vrmc-clear.flag
       xcrun devicectl device copy to --device <D1-UDID> \
         --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc \
         --source /tmp/vrmc-clear.flag --destination Documents/vrmc-clear-diagnostics.flag
       # relaunch: the shell deletes the M4 diagnostic flags at startup (vrmc-input-sim.flag included)

2. Launch VRMC through StikDebug (JIT), press Play, wait for the immersive open.
3. In the immersive space, with the Vivecraft main menu in front of you:
   - raise your **right hand**, point it at the menu (the GUI cursor follows the right-hand ray),
     **pinch thumb+index** -> primary click (Select); a fist (thumb/index apart, fingers curled) held
     ~0.4 s -> secondary/right click;
   - left pinch -> teleport (in world) / shift-click (in menus);
   - left fist held ~0.4 s -> menu/Escape (goes back, closes screens);
   - both fists held ~0.4 s -> inventory.
   The cursor needs your right hand to be tracked (raise it in view); pinching is also how you click.
4. Report the per-gesture result and any of: cursor not visible, cursor not following the hand, clicks
   in the wrong place, a gesture that is too hard to trigger, stuck attack/teleport after dropping the
   hand, menu not opening/closing, hand tracking permission prompt.

## Step 3 — pull the logs

    DEVICE=<D1-UDID> scripts/m3c_pull_and_check.sh       # presentation triage
    SHELL_LOG=<pulled>/vrmc-shell.log COMPOSITOR_LOG=<pulled>/vrmc-compositor.log \
      GAME_LOG=<pulled>/latestlog.txt bash -c 'grep -E "INPUT-SIM|input publish|input release|hand tracking|VRMC-M4" ...'

or collect the three files directly:

    xcrun devicectl device copy from --device <D1-UDID> \
      --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc \
      --source Documents/vrmc-compositor.log --destination /tmp/m4/compositor.log
    xcrun devicectl device copy from --device <D1-UDID> \
      --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc \
      --source Documents/vrmc-shell.log --destination /tmp/m4/shell.log
    xcrun devicectl device copy from --device <D1-UDID> \
      --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc \
      --source Documents/instances/default/latestlog.txt --destination /tmp/m4/latestlog.txt

## Expected healthy lines

- **Step 1 (synthetic)**: the compositor logs `INPUT-SIM SYNTHETIC input mode: hand-tracking
  authorization not requested ...`, then `ARKit session started ... hand tracking supported=<0|1>
  provider=not-started inputMode=synthetic`, `INPUT-SIM SYNTHETIC input publish seq=...
  valid_mask=3 source=synthetic`, phase lines, `... lap complete ...`, and finally `input release`.
  No hand-tracking permission prompt should appear in this mode (the request is skipped).
- **Step 2 (real hands)**: `hand tracking supported=1; requesting hand-tracking authorization`, then
  `hand tracking authorization: request result status=allowed`, then `ARKit session started ...
  provider=started inputMode=arkit authorization=allowed`, then `input publish ... source=arkit
  valid_mask=<3 while both hands are tracked>`, periodic `input hands L=1 R=1 wristL=... wristR=...`.
  On denied/timeout the line says `hand tracking NOT AVAILABLE this session ... RELAUNCH` and the
  session stays world-only (no hands; presentation unaffected).
- game (`[VRMC-M4]` lines, exact formats): `input tuning: pinchOn=... pinchOff=... fistOn=... fistOff=...
  holdMs=... armMs=... staleMs=... tapFrames=...`; `input channel ready (caps {...})`; `first input
  snapshot frame=.. valid_mask=.. ts=.. Ltracked=.. Rtracked=..`; `left/right hand acquired|lost
  (frame=.. valid_mask=..)`; gesture edges `pinch <left|right> press|release (d=...)`, `fist
  <left|right> engaged|released (r=...)`, `fist-tap <left|right> pulse`, `both-fist tap pulse
  (inventory)`; and the action-dispatch proof `action <KeyMappingName> press|release
  origin=<left|right|none>` (W1-bound actions only). No `[WARN] input stale` lines in normal play.
- shell: unchanged M3c presentation lines (`VRMCCompositorRunning`, window parking).

## Triage matrix

| Symptom | Meaning | Next A/B |
|---|---|---|
| No `INPUT-SIM` lines, presentation fine | compositor input flag not read / old framework embedded | verify embedded shell has M4 build; relaunch |
| `INPUT-SIM` present, no `[VRMC-M4]` in game log | bridge ABI mismatch or provider jar not the M4 build | check `[VRMC-M2] bridge handshake`/ABI size lines; re-push jar (sha round-trip) |
| `[VRMC-M4] input` present, no action lines | binding table/action-set issue | pull full latestlog; check screen state (`screenOpen`) at that moment |
| Actions fire, no visible effect | GUI cursor/target issue | check right-hand tracking bits; look at the cursor while moving your hand |
| Cursor missing with hands tracked | controller pose/aim convention | `grep -E '^\[VRMC-M4\] pose:' latestlog.txt` (first tracked pose + every ~300 tracked frames: wrist + R*(0,0,-1) aim per hand, untracked hands skipped) and `grep -E '^\[VRMC-M4\] first input snapshot' latestlog.txt`; report those values for the next iteration |
| Stuck attack/teleport | safety invariant defect | stop input immediately (digital crown); report `[VRMC-M4] stale/release` lines |

## Recording the evidence

Add a VERIFY.md EV entry with: date, commit, dirty state, device model/OS, app build hashes (shell
framework, bridge dylib, provider jar), Step 1/Step 2 outcome, log artifact paths, and an explicit
evidence-class line. Step 1 only = `PARTIAL (device synthetic plumbing PASS; hands NOT RUN)`. Both
steps operator-confirmed = hands PASS and AC-4/ST-S5-hands can move.
