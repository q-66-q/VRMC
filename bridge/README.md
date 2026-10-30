# PC Bridge (Windows)

## Components

- **`core/`** — portable C++20 protocol header/reader, control/media/input codecs, frame meta,
  NACK/IDR payloads, and the versioned shared-memory snapshot with a seqlock. Built/tested on
  macOS/Linux CI and Windows.
- **`driver/`** — OpenVR `IServerTrackedDeviceProvider` exposing `VRMC Virtual HMD` (display
  component) and two `knuckles` controllers. Reads the shared-memory snapshot; publishes
  poses/inputs; no frame capture (the DUAL mirror is captured by the host). Built only on
  Windows; OpenVR SDK v2.15.6 fetched at configure time.
- **`host/`** — Windows `vrmc_host.exe`: TCP control handshake, UDP input receiver, shared-
  memory writer, Windows Graphics Capture of the Vivecraft DUAL window, NVENC HEVC/H.264
  encoding, frame metadata/fragmentation/sending, clock replies. `--video FILE` streams
  pre-encoded access units for control-path testing.

## Build (Windows)

```powershell
pwsh .\scripts\build_bridge.ps1 -Configuration Release
pwsh .\scripts\install_driver.ps1
pwsh .\scripts\run_host.ps1 -WindowTitle "Minecraft"
```

Requires VS 2022 Desktop C++, Windows SDK 10.0.26100+, CMake 3.24+, NVIDIA driver (NVENC), and
SteamVR. CMake fetches OpenVR v2.15.6 and FFmpeg's `nv-codec-headers` (headers only) at
configure time. No NVIDIA/SteamVR binaries are redistributed.

## Build/test core (macOS/Linux)

```bash
./scripts/build_bridge.sh --core
```

## Status

The driver source passes a macOS syntax check against OpenVR v2.15.6. The Windows host/driver
have **not** been compiled or run on a Windows/SteamVR/Vivecraft rig in this workspace; see
`VERIFY.md` EV-0005/EV-0006 and `docs/spikes/S-01-driver.md`. The development transport is
insecure until pairing/AEAD is implemented.
