# M3c — visionOS window-parking vs immersive lifecycle (simulator harness)

**Date:** 2026-11-01
**Owner:** sim-lifecycle (task-5)
**Harness:** `runtime/probes/m3c-lifecycle-sim/` (own directory, separate app `dev.vrmc.m3c`)
**Environment:** Xcode 27.2, visionOS 27.0 simulator `VRMC-VP` (UDID `F025E133-019D-4811-944F-F3C8226E14CB`), macOS 27.0.1
**Status:** simulator code/convention evidence. **Not device evidence** (AGENT.md §9, VERIFY.md §0.7). No device install/launch/copy was performed.

---

## 1. Question

The M3-W3/W4 blocker has two coupled symptoms: an apparently **pure black immersive space** and a shell
lifecycle where, on device, the log shows *window parked -> (5-22 s later) `UIScene.willDeactivate` ->
`UIApplication.willResignActive` -> `didEnterBackground` -> `VRMCImmersiveEnded` -> space dismissed*.

This harness answers, empirically, on a minimal native visionOS app that reproduces the shell's
architecture (SwiftUI `WindowGroup` hosting a UIKit view controller + `ImmersiveSpace(id:)` with a
CompositorServices `CompositorLayer`):

1. Does **opening** the immersive space deactivate the window scene or background the app?
2. Does **parking the windows** (`isHidden = true` and/or `alpha = 0`, as `Shell.swift` does) deactivate
   the window scene, background the app, or end the immersive space?
3. Which parking variant survives while still producing a clean image (A `isHidden+alpha=0`,
   B `alpha=0` only, C no parking, plus `alpha=0.01`, content-only alpha/hidden, fully transparent window)?
4. Does window-scene deactivation *alone* end the immersive space?
5. Does the 8 s **NO-FRAME auto-dismiss** in the newer shell converge with the observed device
   first-frame latency?
6. Do `cp_frame_query_drawables()` / drawable **targets** (`built_in` vs `capture`) / the deprecated
   `cp_frame_query_drawable()` behave in a way that could explain the black immersive?

## 2. Harness

A fresh, self-contained visionOS app (no game, no JVM, no provider, no bridge) so a run is decisive and
cheap (~30 s per variant):

| File | Purpose |
|---|---|
| `project.yml` | xcodegen project, bundle `dev.vrmc.m3c`, deployment target visionOS 27.0 |
| `Sources/M3CApp.swift` | `@main App`: `WindowGroup` + optional second `WindowGroup(id:"second")` + `ImmersiveSpace(id:"m3c")` with `CompositorLayer` (dedicated layout, foveation off, rgba16Float — same `LayerRenderer.Configuration` as the shell) |
| `Sources/M3CContent.swift` | `UIViewControllerRepresentable` hosting a plain UIKit view controller (like the shell's `LauncherHostView`), scenePhase plumbing, action binding |
| `Sources/M3CCompositor.swift` | Dedicated CompositorServices render thread: `waitUntilRunning` -> `queryNextFrame` -> `startUpdate/endUpdate` -> optimal-input wait -> `startSubmission` -> draw -> `endSubmission`; bright animated red/green checker (red left eye, green right eye, moving white band + cross) drawn into every drawable with depth attachment, reverse-Z clear, rasterization-rate map when present; per-drawable-array diagnostics; honours paused/invalidated states; never stops itself |
| `Sources/M3CLifecycle.swift` | app-level recorder: all `UIApplication`/`UIScene` notifications, SwiftUI `scenePhase`, 1 Hz state ticks, window dumps (`isHidden`, `alpha`, `level`, `rootAlpha`, root class), parking/restore variants, optional second window, optional dismiss/reopen |
| `Sources/M3CLog.swift` | appends to `Documents/sim-shell.log` **and** `NSLog` |
| `scripts/run-sim.sh` | build + install + run the 13-variant parking matrix with timed `simctl io screenshot` captures |
| `scripts/run-drawables.sh` | build + install + run the drawable-array / capture-target probes (all/first/builtin/legacy, with `simctl io recordVideo`) |
| `scripts/summarize.py` | builds `results/summary.md` from the run logs |

Diagnostics are selected with launch arguments (`NSArgumentDomain`), e.g.
```
xcrun simctl launch <udid> dev.vrmc.m3c -M3CPark hidden -M3CParkWhen firstframe -M3COpenDelay 1.0
```
| Argument | Values | Meaning |
|---|---|---|
| `M3CPark` | `hidden`, `alpha`, `tinyalpha`, `contentalpha`, `contenthidden`, `transparent`, `none` | parking variant |
| `M3CParkWhen` | `open`, `firstframe` | park right after `openImmersiveSpace`, or only after the first compositor frame |
| `M3CParkScope` | `all`, `main` | which `windowApplication` scenes to park |
| `M3COpenDelay` | seconds | `0` = open at launch, else delayed |
| `M3CSecondWindow` | 0/1 | open a second visible WindowGroup window (separates scene deactivation from app backgrounding) |
| `M3CRestoreAfter` | seconds, `<0` never | restore the windows N s after parking |
| `M3CReopen` / `M3CReopenAfter` | 0/1 / seconds | dismiss the space then open it again (re-entry) |
| `M3CAutoOpen` | 0/1 | never open the space (control) |
| `M3CDrawablesMode` | `all`, `first`, `builtin`, `legacy` | `queryDrawables()` draw-all / draw-first / built_in-only / deprecated `queryDrawable()` |

Every run writes `results/<variant>/sim-shell.log` (1 Hz `TICK` lines: app state, SwiftUI scenePhase,
`spaceOpen/parked`, compositor frames/state/present-age, full window dump), `console.log` (NSLog copy),
`args.txt`, and 3-5 `simctl io screenshot` JPEGs.

## 3. Results — parking matrix (13 runs, 25 s each)

Command: `cd runtime/probes/m3c-lifecycle-sim && ./scripts/run-sim.sh`
Full table + timelines: [`results/summary.md`](../../runtime/probes/m3c-lifecycle-sim/results/summary.md).

| variant | park | when | first frame | UIScene.willDeactivate | willResignActive | didEnterBackground | layer invalidated | frames at 25 s | final app / scene |
|---|---|---|---|---|---|---|---|---|---|
| 01-nopark-open | none | open | +1.3 s | 0 | 0 | 0 | 0 | 1379 | active / foregroundActive |
| 02-alpha-open | alpha=0 | open | +1.3 s | 0 | 0 | 0 | 0 | 1421 | active / foregroundActive |
| 03-hidden-open | isHidden+alpha=0 | open | +1.3 s | 0 | 0 | 0 | 0 | 1423 | active / foregroundActive |
| 04-hidden-firstframe | isHidden+alpha=0 | firstframe | +1.3 s | 0 | 0 | 0 | 0 | 1423 | active / foregroundActive |
| 05-alpha-firstframe | alpha=0 | firstframe | +1.3 s | 0 | 0 | 0 | 0 | 1423 | active / foregroundActive |
| 06-tinyalpha-firstframe | alpha=0.01 | firstframe | +1.3 s | 0 | 0 | 0 | 0 | 1425 | active / foregroundActive |
| 07-contentalpha-firstframe | root view alpha=0 | firstframe | +1.4 s | 0 | 0 | 0 | 0 | 1417 | active / foregroundActive |
| 08-contenthidden-firstframe | root view hidden | firstframe | +1.4 s | 0 | 0 | 0 | 0 | 1417 | active / foregroundActive |
| 09-nopark-launch | none | open at launch | +0.4 s | 0 | 0 | 0 | 0 | 1417 | active / foregroundActive |
| 10-hidden-restore | isHidden+alpha=0, restore at 6 s | firstframe | +1.3 s | 0 | 0 | 0 | 0 | 1423 | active / foregroundActive |
| 11-alpha-reopen | alpha=0, dismiss+reopen | firstframe | +1.3 s / gen2 +11 s | 0 | 0 | 0 | 0 (only the requested dismiss) | 810 (gen 2) | active / foregroundActive |
| 12-hidden-secondwindow | main window hidden, second window visible | firstframe | +1.3 s | 0 | 0 | 0 | 0 | 1426 | active / 2x foregroundActive |
| 13-transparent-firstframe | UIWindow transparent + content alpha 0 | firstframe | +1.4 s | 0 | 0 | 0 | 0 | 704 | active / foregroundActive |

**Findings**

1. **Opening the immersive space does not deactivate the window scene and does not background the app.**
   Immediately after `openImmersiveSpace result=opened` the log shows two scenes, both
   `activation=foregroundActive`: the app's `windowApplication` scene (2 windows: hosting window +
   `UITrackingElementWindowController` at level 10) and a **separate immersive scene** with role
   `CPSceneSessionRoleImmersiveSpaceApplication` (1 window). `UIApplication` stays `active` and the
   compositor presents continuously. This isolates the open step from the black-immersive symptom.
2. **Parking the windows does not cause scene deactivation, backgrounding, or immersive end — in the
   simulator.** Across all 13 variants, `UIScene.willDeactivate`, `UIApplication.willResignActive`,
   `didEnterBackground`, layer invalidation and `VRMCImmersiveEnded` counts are **0**; every run ends
   `app=active`, window scene `foregroundActive`, compositor at ~1400 presented frames (≈57 fps).
   This holds for `isHidden=true` + `alpha=0` (the current shell behaviour), for `alpha=0`-only, for
   `alpha=0.01`, for parking at open and for parking after the first frame, and for hiding the only
   window while a second window remains (run 12 — the main window scene itself also stays
   `foregroundActive`).
3. **Window-scene deactivation alone does not end the space.** Dismissing the space (run 11) ends the
   **immersive** scene only: `UIScene.didDisconnect` for the `CPSceneSessionRoleImmersiveSpaceApplication`
   scene, render thread exit, and the window scene stays `foregroundActive`; reopening 2 s later starts
   renderer generation 2 and presents 810 frames. The window scene never deactivated in any run.
4. **Only window-level parking gives a clean image.** Screenshots:
   - no parking — live checker + the indigo window in the middle: [shot-t14.jpg](../../runtime/probes/m3c-lifecycle-sim/results/01-nopark-open/shot-t14.jpg)
   - `alpha=0` — live checker, window invisible: [shot-t14.jpg](../../runtime/probes/m3c-lifecycle-sim/results/02-alpha-open/shot-t14.jpg)
   - `isHidden+alpha=0`, parked at open — live checker, window invisible: [shot-t14.jpg](../../runtime/probes/m3c-lifecycle-sim/results/03-hidden-open/shot-t14.jpg)
   - `isHidden+alpha=0`, parked after first frame: [shot-t8.jpg](../../runtime/probes/m3c-lifecycle-sim/results/04-hidden-firstframe/shot-t8.jpg)
   - content-only alpha=0 — window content gone but the window's **black rounded rect stays on screen**:
     [shot-t14.jpg](../../runtime/probes/m3c-lifecycle-sim/results/07-contentalpha-firstframe/shot-t14.jpg)
   - content hidden — same black rect: [shot-t14.jpg](../../runtime/probes/m3c-lifecycle-sim/results/08-contenthidden-firstframe/shot-t14.jpg)
   - fully "transparent" window (clear background + content alpha 0) — still the black rounded rect,
     i.e. the visionOS window surface/glass cannot be made invisible from inside the app:
     [shot-t16.jpg](../../runtime/probes/m3c-lifecycle-sim/results/13-transparent-firstframe/shot-t16.jpg)
5. **The test pattern renders and keeps rendering.** Full-frame simulator captures show a bright
   animated red/green checker (moving white band + centre cross, live `frames=` counter in the window
   content) and compositor frame counters climb ~57 fps. This is the harness's own CompositorServices
   layer, not the product compositor, so it proves the *simulator* presentation path only.

## 4. Results — first-frame latency, and why the 8 s NO-FRAME auto-dismiss is counterproductive

In the simulator the layer becomes `running` **0.09-0.3 s** after `openImmersiveSpace` and the first
frame is presented ~1.3 s after app launch (run 09 with `M3COpenDelay 0`: first frame at +0.4 s).

On **device** (`Evidence/EV-0090` + the 16:39 device pull), the same shell/compositor path shows the
CompositorServices`wait_until_running` call blocking much longer:

| device session | open -> `wait_until_running` returned | outcome |
|---|---|---|
| 14:33:21 -> 14:33:29.525 | 8.16 s | returned `invalidated` — shell's 8 s NO-FRAME dismiss had just fired |
| 14:41:01 -> 14:41:10.133 | 8.17 s | same: the 8 s NO-FRAME dismiss fired first |
| 14:41:33 -> 14:41:57.591 | **23.95 s** | returned `running`, first frames presented, then parking -> same-second `willResignActive` |

Consequences:

- **The black immersive is the "space is open, no first frame yet" window.** On device that window can
  be 8-24 s; the operator looks at pure black with no window (parked) → presses the Digital Crown to
  escape → `willResignActive`/`didEnterBackground` → the shell's `stopForBackground` stops the
  compositor and the space ends. That matches the device log sequence without requiring parking to be
  the cause of the backgrounding.
- **An 8 s NO-FRAME auto-dismiss guarantees a false negative.** It cannot distinguish "the compositor
  is broken" from "the layer has not been made running yet by the system", and in two recorded device
  sessions it fired while the layer was still `paused`. The layer did eventually run at 23.95 s in the
  only session given enough time. Dismissing also resets the layer-start latency on the next open, so
  the retry can loop.
- Keep the window visible until the first frame (prevents a black-looking session), then hide chrome and
  park; never dismiss on a no-frame timeout.

## 5. Results — drawable array and capture targets (Lead's query_drawables question)

Runs: `scripts/run-drawables.sh` (5 runs; recording = `simctl io recordVideo` for 10 s during the run,
plus `simctl io screenshot` while recording; `-M3CDrawablesMode` all/first/builtin/legacy).

| run | mode | `cp_frame_query_drawables()` count | targets | per-drawable | captureViews | during 10 s simctl recordVideo |
|---|---|---|---|---|---|---|
| d1-all-capture | `queryDrawables` draw all | **1** | `builtIn` | views=1 colors=1 depths=1 rrms=0 fmt=115 (rgba16Float) 3840x2160 | 0 | no capture drawable appeared |
| d2-first-capture | `queryDrawables` draw only `[0]` | 1 | `builtIn` | same | 0 | no capture drawable appeared |
| d3-builtin-capture | draw only `target == builtIn` | 1 | `builtIn` | same | 0 | no capture drawable appeared |
| d4-legacy-capture | deprecated `queryDrawable()` | 1 | `builtIn` (logged per frame) | views=1 colors=1 | 0 | returns `builtIn` |
| d5-all-nocapture | `queryDrawables` draw all, no recording | 1 | `builtIn` | same | 0 | n/a |

- **The simulator provides exactly one drawable, target `builtIn`, one view, one color + one depth
  texture, no rasterization-rate map, rgba16Float 3840x2160.** `frame.drawableTargetViewCount(builtIn)=1,
  capture=0` on every frame.
- **`simctl io screenshot` / `simctl io recordVideo` never creates an app capture drawable in the
  simulator** — the simulator IO path records the simulator display (the recording frames show the same
  composited content, incl. the SwiftUI window: [rec-frame.jpg](../../runtime/probes/m3c-lifecycle-sim/results/d1-all-capture/rec-frame.jpg)).
  Therefore "draw all vs draw only one" is indistinguishable *in the simulator*: they render the same
  single `builtIn` drawable. A capture-target partial/black case cannot be produced here; it remains a
  device-only path (AirPlay/screen recording/ReplayKit on device).
- **The deprecated `cp_frame_query_drawable()` returns the `builtIn` drawable in the simulator**, i.e.
  it is not silently returning a capture target. On device the shipping compositor's log line shows
  `drawable: colorFormat=115 views=2` — a stereo built-in drawable — which is also inconsistent with a
  capture target. So the deprecated single-drawable API is **not a plausible cause of the device black
  immersive**, with one caveat: if visionOS ever returns a capture drawable from the deprecated call (or
  if a capture target appears and the renderer only draws `[0]`), the built-in display could go black.
  Cheap hardening: log `cp_drawable_get_target()` of the drawable the compositor actually draws, and
  prefer `cp_frame_query_drawables()` + draw every drawable (built_in and capture).

## 6. Interpretation for the device black-immersive blocker

- The simulator reproduces **the presentation path** (CompositorLayer -> layer running -> frames ->
  visible bright pattern, dims/format/alpha same as the shell's compositor) and shows the open/park/reopen
  lifecycle is not self-terminating in a simulator environment.
- The simulator **does not reproduce** the device-only window/immersion policy. It therefore cannot
  confirm or refute "parking causes `UIScene.willDeactivate` on device". The device evidence is
  ambiguous: the park -> `willDeactivate` gap varies (5 s, 17 s, 22 s, 121 s), and in the 01:24/02:39
  sessions `willDeactivate` precedes `willResignActive` by 11 s / 8 s (a Digital-Crown press would
  produce them together). Two candidate explanations remain: (a) device-only system policy reacting to
  the app having no visible window, or (b) the operator pressing the crown because the immersive looked
  black (the first-frame gap above) — a self-inflicted loop once the shell parks immediately.
- Whatever the trigger, **the shell currently converts it into a definite session end**: it observes
  `willResignActive` -> `stopForBackground` -> `VRMCCompositor_RequestStop()` + dismiss, so a spurious/
  transient deactivation always kills the session. That is the piece worth changing regardless of the
  root cause.
- The **black window itself** is fully explained by the first-frame gap + immediate parking; the fix is
  to keep the 2D UI visible until the immersive has actually presented, and to never auto-dismiss during
  the wait.

## 7. Recommended `runtime/native-shell/Sources/Shell.swift` change (tested rule)

> **Status note (same day, after this matrix):** the working tree of `Shell.swift` was upgraded while this
> probe ran and now already implements items 1-4 below (alpha-only parking, parking only after
> `VRMCCompositorRunning`, a NO-FRAME heartbeat that never dismisses, and a 1.8 s `willResignActive`
> grace cancelled by `didBecomeActive`; `vrmc-hide-windows.flag` / `vrmc-no-parking.flag` for A/B).
> The probe's run **05-alpha-firstframe is exactly that current parking behaviour** and it is
> simulator-safe (screenshots: clean full-screen checker, window invisible). The remaining suggestions are
> item 5 (parking health check), item 6 (longer NO-FRAME heartbeat window + layer-state logging; the only
> device session that produced a frame needed 23.95 s, so 4 x 8 s = 32 s of heartbeats is on the edge) and
> the compositor drawable-target logging.

Rule: **open -> wait for the first presented compositor frame (no short timeout) -> hide chrome + park
the UIWindow (keep `isHidden`+`alpha=0`, it is lifecycle-safe in the simulator and the only visually
clean option) -> treat only a real background/layer-end as the end of the session.**

1. **Do not end the session on `willResignActive` alone.** Add a short grace period and let
   `didBecomeActive` cancel it; only `didEnterBackground` (or the grace period expiring while the app is
   still not active) runs the existing stop/dismiss/reopen path:

   ```swift
   observe(UIApplication.willResignActiveNotification) { $0.resignActivePending("willResignActive") }
   observe(UIApplication.didEnterBackgroundNotification) { $0.stopForBackground("didEnterBackground") }
   observe(UIApplication.didBecomeActiveNotification) { $0.resignActiveRecoveredOrBecameActive() }

   private var resignPending: DispatchWorkItem?

   private func resignActivePending(_ reason: String) {
       shellLog("\(reason) pending: grace period before any teardown (transient resign must not end the session)")
       resignPending?.cancel()
       let item = DispatchWorkItem { [weak self] in
           guard let self else { return }
           if UIApplication.shared.applicationState != .active {
               self.stopForBackground("resignActive-grace-expired")
           } else {
               shellLog("willResignActive recovered before background; immersive session kept")
           }
       }
       resignPending = item
       DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
   }

   private func resignActiveRecoveredOrBecameActive() {
       resignPending?.cancel(); resignPending = nil
       appDidBecomeActive()
   }
   ```

2. **Remove the 8 s NO-FRAME dismiss / retry.** Keep a diagnostic timer only; never dismiss on no-frame.
   Log the layer state and first-frame latency; require >= 45 s before treating "no frame" as a fault,
   and even then only log + restore the window (leave the space open):

   ```swift
   // parked only after the first presented frame:
   observeNotification("VRMCCompositorPresenting") { $0.parkWhenPresenting() }
   // diagnostics instead of the old NO-FRAME dismiss:
   DispatchQueue.main.asyncAfter(deadline: .now() + 8)  { logFirstFrameState("8s") }
   DispatchQueue.main.asyncAfter(deadline: .now() + 45) { logFirstFrameState("45s") } // log only
   ```

3. **Parking health check (defence in depth against the device-only hypothesis).** 1 s after parking,
   if the app or window scene dropped out of the active/foreground state without a real
   `didEnterBackground`, restore the windows and log loudly; do not tear the space down:

   ```swift
   private func parkHealthCheck(parkedEpoch: Int) {
       guard epoch == parkedEpoch, immersiveOpen else { return }
       let appActive = UIApplication.shared.applicationState == .active
       let sceneActive = UIApplication.shared.connectedScenes.contains { scene in
           guard let ws = scene as? UIWindowScene, ws.session.role == .windowApplication else { return false }
           return ws.activationState == .foregroundActive
       }
       if !appActive || !sceneActive {
           shellLog("PARKING SUSPECT: appActive=\(appActive) windowSceneActive=\(sceneActive) after parking; restoring windows (space stays open)")
           setGameWindowsVisible(true, log: "window restored after parking suspect")
       }
   }
   ```

4. **Keep window-level parking** (`window.alpha = 0; window.isHidden = true`) — do **not** switch to
   content-only parking: in the simulator the window surface remains as a black rounded rectangle
   (sections 3.4 / 5, screenshots 07/08/13), whereas window-level parking is visually clean and produced
   no lifecycle reaction in 13/13 runs. Keep `.persistentSystemOverlays(.hidden)` for the chrome.
5. **Log before/after parking** (partially present: `windowStateDescription()`) and add a **parking
   health check**: 1 s after parking, if the app or the window scene is no longer active/foregroundActive
   without a real `didEnterBackground`, restore the windows and log `PARKING SUSPECT` (keep the space
   open). Log the layer state during the no-frame window as well, and extend the NO-FRAME heartbeat window
   beyond 32 s. That makes the next device run decide the remaining ambiguity in one session.
6. **Compositor hardening for the Lead's drawable question**: log
   `cp_drawable_get_target()` + drawable-array count on the first frame, and prefer
   `cp_frame_query_drawables()` drawing every drawable over the deprecated single-drawable call.
   This is future-proofing (capture/AirPlay), not a proven black-immersive fix.

## 8. Limitations

- Simulator-only. Not evidence for device optics, tracking, thermals or the device compositor (VERIFY.md §0.7).
- The simulator does not implement the device window/immersion background policy that the device logs
  hint at; absence of a lifecycle reaction here is **not** proof that parking is safe on device.
- One view / identity view transform / no asymmetric stereo; no rasterization-rate map; no ARKit anchor.
- `simctl io` capture uses the simulator display, so the `capture` drawable-target path cannot be
  exercised here.
- The app is a fresh probe, not the shell: modal game-surface presentation, provider bridge, JVM and the
  Amethyst hosting stack are absent.
- SwiftUI `scenePhase` did not change in these runs (always `unknown`, the initial value); the UIApplication/
  UIScene notifications (which the shell actually uses) provided all lifecycle data.

## 9. Reproduce

```bash
cd runtime/probes/m3c-lifecycle-sim
./scripts/run-sim.sh                  # build + 13-variant parking matrix (~7 min)
./scripts/run-drawables.sh            # build + drawable/capture probes (~4 min)
python3 scripts/summarize.py          # results/summary.md
```

Build output goes to `/tmp/m3c-build`; nothing outside `runtime/probes/m3c-lifecycle-sim/` is modified.