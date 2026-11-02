# VRMC privacy summary

VRMC is an on-device Minecraft VR launcher/provider. **It does not ship telemetry or analytics and
does not upload logs, headset data, hand-tracking data, or gameplay data.**

## On-device processing

- **World/head/hand tracking** comes from ARKit and is processed entirely on the Vision Pro. Hand
  skeleton snapshots cross only the in-process bridge to the local Java provider; they are not written
  to persistent storage by VRMC (only aggregated/rate-limited diagnostic lines may appear in local logs).
- **Gaze/tracking-area events** (when the opt-in gaze feature is enabled) are processed on-device by
  visionOS and VRMC; no eye images or raw gaze data are available to VRMC or transmitted.
- **Microphone/camera/passthrough** are not used by VRMC. The app uses hand/world tracking usage strings
  (Info.plist) and requests hand-tracking authorization explicitly.

## Local files

VRMC writes local logs in the app's Documents container (`vrmc-shell.log`, `vrmc-compositor.log`,
`vrmc-thermal.log`, `latestlog.txt`, optional diagnostics, and a local shutdown journal). These are
visible to the user via the launcher/log export and are never sent anywhere by VRMC. The user can delete
them with the app container. Minecraft's own logs are managed by Minecraft.

## Network

Network access is used only for the things the user asks for: Minecraft/Fabric/Vivecraft downloads and
updates, Microsoft account authentication, and multiplayer if the user joins a server. Authentication
is handled by the launcher/Amethyst flow; tokens are stored locally. VRMC does not contact an analytics
or crash-reporting service. Optional JIT tooling (StikDebug/Apparition) runs outside VRMC and has its own
terms.

## Children / App Store

VRMC is a sideloaded, self-hosted product; it does not collect personal data for advertising or
tracking. If distribution changes (App Store), revisit this file and the privacy manifest together.
