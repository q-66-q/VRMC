# Troubleshooting

## "HMD not found" / Vivecraft does not enter VR

- Confirm SteamVR sees `VRMC Virtual HMD` and both `VRMC Knuckles` controllers.
- `vrmc_host` must be running **before** starting SteamVR/Vivecraft; the driver reads its
  shared-memory snapshot. Without it poses are invalid.
- Check the driver folder name/paths: `<SteamVR>\drivers\vrmc\driver.vrdrivermanifest`,
  `bin\win64\driver_vrmc.dll`, `input\vrmc_knuckles_profile.json`.
- Check `steamvr.vrsettings` has `"activateMultipleDrivers": true` and
  `"driver_vrmc": { "enable": true }`. Restart SteamVR after installing/enabling.
- Open SteamVR Developer → Web Console and filter `vrmc`; check the driver log for HMD/controller
  activation errors.
- Try the SteamVR null driver only for isolating other hardware; VRMC needs its own display
  component.

## Vivecraft enters VR but the stream is black / no video

- Is the host `capture` log line present with the expected 3840×1080?
- The game must be borderless windowed, visible, and not minimized; WGC cannot capture some
  exclusive/fullscreen or protected windows.
- Confirm DUAL mirror: two distinct eye halves. If only one half, set Mirror Mode to DUAL and
  restart the world.
- Check the client `streaming` state and frames received; if 0, verify UDP 48626/48627 and the
  PC firewall. The host learns the client's UDP source port; allow inbound UDP.
- If the client shows a huge clock offset, clock sync may still be converging; wait 2–3 s.
- If the image is vertically flipped, set the vertical-flip stream flag (host build option) or
  report it; do not edit the shader ad hoc.

## Hand tracking not working

- Grant Hand Tracking and World Sensing permission (Settings → Privacy & Security → Hand
  Tracking / World Sensing), then relaunch.
- Hands must be within the headset's tracking volume and not fully occluded. Sleeves, hair,
  and holding hands together can reduce accuracy.
- In simulator, hand tracking is unavailable by design; use `-VRMCDemoMode`/synthetic hands.
- If one hand disappears, the other must keep working; if both disappear, check battery/thermal
  state and the client's `tracking` status.
- If pinch/fist thresholds are hard to reach, record a usability defect; do not silently change
  the profile.

## Input is stuck / attacks repeat

This is a P0/P1 defect. Stop the session, release physically, and capture client/host logs plus
the last input telemetry. The design requires every loss path to release all buttons; a stuck
input means a state-machine bug. Do not continue acceptance testing until fixed.

## High latency / stutter

- Use 5/6 GHz Wi‑Fi 6E with the PC wired; avoid shared/mesh networks. Disable VPNs.
- Check client fps, dropped frames, queue depth, decode/render times; host capture/encode times
  and bitrate.
- Lower resolution/bitrate via config; close GPU-heavy apps; update NVIDIA driver.
- 90 Hz is the target; 72 Hz is the floor. If p95 view latency >70 ms on N1, run the full
  MT-09 measurement and record a limitation; do not claim acceptance from the UI p50.
- Audio is not yet implemented and cannot be used to judge sync.

## Tracking/connection recovery

- The client should show `degraded`/`reconnecting`, release inputs, freeze the last frame, and
  resume automatically. If it requires relaunching the app, record it as an AC-5 failure.
- After network loss, request an IDR; if video stays corrupt, restart the host encoder and
  reconnect.
- After SteamVR/Minecraft restart, wait for the host to re-open the window and re-register the
  driver; if SteamVR does not reload the driver, restart SteamVR (client can stay open).

## Pairing/security

The current development transport is unencrypted and only for a trusted LAN. Do not expose
ports 48625–48627 to the internet or an untrusted network. Secure pairing/AEAD is not yet
implemented; this blocks release (see `LIMITATIONS.md`). If you see a pairing UI in a build,
treat it as experimental and verify the code path against `VERIFY.md` §8.

## Collect diagnostics

```bash
./scripts/collect_evidence.sh EV-0001 "short description"
```

Attach client/host logs, SteamVR system report, Minecraft/Vivecraft logs, telemetry CSV, and a
screen recording. Redact account names, server addresses, tokens, and hand skeletons unless the
tester explicitly consents. Large binaries may live outside Git with hashes in the manifest.
