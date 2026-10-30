# Run VRMC

## Session order

1. **PC:** start SteamVR (VRMC driver enabled, virtual HMD/controllers present).
2. **PC:** start `vrmc_host`:
   ```powershell
   pwsh .\scripts\run_host.ps1 -WindowTitle "Minecraft"
   ```
3. **PC:** launch the pinned Minecraft/Fabric/Vivecraft profile; enter a world. The game window
   should be borderless 3840×1080 with DUAL mirror (left eye left half, right eye right).
4. **Vision Pro:** launch VRMC; enter the PC host/IP; tap **Start VR**; grant hand tracking and
   local network access.
5. Stand facing forward, hold hands where the headset can see them, and wait for `streaming` +
   `hands` + `Tracking origin calibrated`.
6. Use the hand controls below. To stop, tap **Disconnect** in the window (or close the
   immersive space with the Digital Crown), then quit the host and SteamVR.

> The window remains visible in the immersive space in the current development build. Close it
> with the window's close control if it obstructs the view; the app keeps running. Auto-hide is
> planned before release.

## Hand controls (`handmap-v1`)

Full spec: [`HAND_MAPPING.md`](../architecture/HAND_MAPPING.md).

| Action | Hand gesture |
| --- | --- |
| Aim / point | Right hand; index extended; controller ray follows the hand |
| Attack / break | Right index–thumb pinch (hold); release to stop |
| Use / place / consume | Right middle–thumb pinch |
| Grab/release / hotbar | Right or left fist (grip click) |
| UI select | Either index pinch on the pointed target |
| Inventory | Left palm facing you for ~0.35 s, then release |
| Game menu | Left palm facing you for ~0.9 s |
| Radial menu | Right palm facing you ~0.7 s (optional) |
| Jump | Quick upward flick while moving, or left ring pinch |
| Sneak | Right palm down low, hold |
| Locomotion | Hold **left palm up** 0.15 s; move hand forward/back/left/right as a joystick |
| Turn | While in locomotion, rotate/twist the left hand; right stick gets the turn axis |
| Stop moving | Lower/close the left hand or open a menu |
| Two-handed bow/shield | Independent left/right hands; Vivecraft's own bow/shield logic applies |

If a gesture is unreliable, use the debug overlay/telemetry (see TROUBLESHOOT) and record it as
a defect. Do not compensate by pressing keyboard/mouse during acceptance tests.

## Comfort

- Start with short sessions (5–10 min), seated or standing, in good lighting.
- Locomotion is opt-in; turning can be snap or smooth based on the mapping profile.
- Keep the room clear; remove trip hazards; take breaks.
- Stop immediately for nausea, headache, eye strain, or disorientation. Persistent symptoms:
  consult a doctor.
- Vision Pro hand tracking works best with hands in view and not occluded by sleeves/hair.
  Occlusion is expected; the system releases inputs and shows a ghost hand.

## Expected state indicators

- `streaming`: media is arriving and decoding.
- `hands`: both hand snapshots are being received; `none` means tracking not started/lost.
- `Tracking origin calibrated`: first tracked head pose established the SteamVR standing origin.
- `latency p50`: network+queue estimate; not a substitute for the MT-09 camera measurement.
- `Clock`: current estimated host-client offset; large values are normal on a freshly booted
  headset/PC.

## Shutdown/recovery

- Quit order: client → host → Minecraft → SteamVR.
- If the link drops, keep the headset app open; the host reconnects after restart.
- If SteamVR/Minecraft restarts, the driver/HMD poses become invalid; the client shows degraded
  state and resumes when media returns (see VERIFY NF-08..NF-10).
- If tracking is lost, inputs release; reacquire by bringing hands into view. Do not restart
  the app.

## Development/demo mode

```bash
./scripts/demo_simulator.sh
```

This starts the mock H.264 SBS host, launches the visionOS simulator with synthetic hands, and
saves a screenshot/log to `artifacts/demo/`. It proves the simulator pipeline only; it is not a
device or Vivecraft test.
