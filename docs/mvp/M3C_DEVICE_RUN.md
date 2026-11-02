# M3c device run — operator checklist (EV-0094)

One-page procedure for the next Apple Vision Pro session. Full context: `docs/mvp/M3C_PLAN.md`,
flags reference: `docs/mvp/M3C_FLAGS.md`. Installed build: `/tmp/VRMC-native-v14-auditfix.app`
(depth-clear fix EV-0093 + eye-distinct stereo/alignment pattern + scene logging + resilient re-entry).

## Before you start

- Run the identity pre-flight from the Mac and paste its output into the session notes:

    DEVICE=<D1-UDID> scripts/m3c_preflight.sh --expect-app v14

  It prints the installed app bundle URL, the provider jar sha256 round-tripped from the
  device, and the Documents/game-dir flags. The EV-0094 build keeps the previous
  (pre-GPU-sync) provider jar on purpose.

- The device app container has a pending `Documents/vrmc-clear-diagnostics.flag`; the first launch
  deletes stale diagnostic flags automatically (check `vrmc-shell.log` for `clear-diagnostics:` lines).
- The fixed depth value is logged as `depthZero=0` in `vrmc-compositor.log`; if you ever see
  `depthZero=1` the black-immersive root cause is re-enabled (should not happen).
- Provider eye-target PNG capture is **disabled for this run** (the game-dir capture flag
  content is off), so do not expect PNGs; content evidence is the compositor drawable proof
  log lines.
- If the menu world looks dark it is the Vivecraft menu world's time-of-day, **not** the black bug:
  look at the log `drawable proof` luma and ask for the `vrmc-capture` PNGs; the top 1.5 % of the
  immersive image also carries a **green strip** when flat sampling is active.

## Step 1 — manual Enter VR (no game, no JIT)

1. Put on the headset, unlock, launch **VRMC** from Home.
2. The launcher window appears with a small overlay at its top-left: **Enter VR** (green when active).
3. Pinch **Enter VR**.
4. Expected:
   - a short beep (best-effort audible canary for the first presented frame; not itself
     device-verified - the pattern and border are the primary signal);
   - the window fades out (alpha-only parking after the first presented frame, re-applied every second);
   - the immersive view fills with the **stereo/alignment test pattern AND a cyan/white checker
     border** (the manual no-game path now draws the proof border automatically): warm/red
     left eye, green right eye, one white centre cross per eye that should fuse into a single
     sharp cross, a red square marker in one corner of the left-eye image (green in the right
     eye).
5. Report exactly what you see, especially:
   - pattern visible / black / passthrough;
   - one fused centre cross, or doubled/offset crosses (and which direction);
   - if you close one eye: is the visible tint warm/red (left) or green (right)? (eye order check)
   - did the launcher window disappear?
6. Leave it open ~20 s so the STATE scene-activation lines are written.
7. To exit the immersive space press the **Digital Crown** (the launcher window is alpha-0 /
   non-interactive while the immersive space is open; the window returns when the session ends).

## Step 2 — game run (JIT)

1. Exit VRMC (or leave it in the background), start **StikDebug**, enable JIT for VRMC, launch VRMC,
   press **Play**.
2. Expected: Minecraft + Fabric + Vivecraft boot; ~15 s after the game starts the immersive space opens
   automatically (beep), windows park, and the Vivecraft menu world + menu GUI fill the field of view;
   turning your head moves the view (not a floating window).
3. Report: game visible in immersive / still only a 2D window / black / any misalignment or doubled image;
   whether the 2D game window disappeared.
4. (Optional, if comfortable) look at different parts of the view and move your head; note any content
   that looks flat, inverted, or offset.

## Step 3 — hand back the logs

Run from the Mac (pulls logs + readbacks and prints the decisive lines):

```bash
DEVICE=<D1-UDID> scripts/m3c_pull_and_check.sh
```

Expected PASS-ish lines: `diagnostics: ... depthZero=0`, `first presented frame: ...`,
`frame N ... layerState=2 ... encNil=0 nilColor=0`, `drawable proof ... luma≈80-150`,
`STATE ... scenes=[CPSceneSessionRoleImmersiveSpaceApplication:fgActive, ...]`,
`window parked after first presented frame ... alpha=0.00`.

## If it is still black (recovery matrix, one relaunch per A/B)

| Symptom | A/B to try | How |
|---|---|---|
| Black pattern in Step 1 | `vrmc-present-proof.flag` / `vrmc-clear-probe.flag` | push into `Documents/`, relaunch, tap Enter VR: clear-only magenta/cyan should always show if presentation works |
| Window remains over the view | `vrmc-hide-windows.flag` | push, relaunch: parking uses `isHidden=true` (plus alpha 0) |
| Content visible but geometry wrong | logs only | do not change anything; send `vrmc-compositor.log` + `vrmc-shell.log` (the diag lines carry the matrices/frusta) |
| Immersive opens then immediately closes | send logs | check `willResignActive`/grace/`VRMCImmersiveEnded` lines; re-entry fix is in this build |

Recovery flag push (so the operator does not have to edit container files by hand):

    echo x > /tmp/vrmc-audit.flag
    xcrun devicectl device copy to --device <D1-UDID> \
      --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc \
      --source /tmp/vrmc-audit.flag --destination Documents/vrmc-hide-windows.flag

Do not uninstall the app (it keeps the Minecraft install and test worlds).
