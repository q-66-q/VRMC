# Install and Configure VRMC

**Status:** Development M0/M1. Hardware steps are written for the baseline but have not been
verified on a physical Vision Pro + Windows/SteamVR rig in this workspace. Read
[`LIMITATIONS.md`](LIMITATIONS.md) first and use [`TROUBLESHOOT.md`](TROUBLESHOOT.md) if a
step fails.

## 1. What you need

- Apple Vision Pro (M2 or later), visionOS 26/27.
- Windows 11 24H2 PC, 8+ cores, 32 GB RAM, NVIDIA RTX 4070+ (NVENC), current driver.
- Steam + SteamVR; a SteamVR-compatible virtual/real HMD is **not** required (VRMC provides
  virtual devices), but SteamVR must launch.
- Minecraft Java Edition **1.21.11**, owned by you.
- Fabric Loader **0.20.1** and Fabric API for 1.21.11.
- Vivecraft **1.21.11-1.3.15** (Fabric) from Modrinth/CurseForge; verify:
  `SHA-512 e7a4184ac287856cffa01b58e598ba984347d011bb5789f2cbe20e3c3e269f0a9607ff2ce96141e3b320cc0cb6de43be56b266d22867d026fc9928abbb26ff03`.
- 5 GHz/6 GHz Wi‑Fi 6/6E with the PC wired; dedicated AP/SSID recommended.
- Xcode 27.1 + Swift 6.4, XcodeGen, CMake 3.24+, Python 3 for building from source.
- Visual Studio 2022 Desktop C++ + Windows SDK 10.0.26100+ for the PC bridge.

VRMC does **not** include Minecraft, Vivecraft, SteamVR, Java, or NVIDIA binaries. You must
install and license them yourself.

## 2. Install the PC stack

1. Install Steam and SteamVR. Launch SteamVR once with a headset/emulator and complete Room
   Setup (Standing). Verify it starts.
2. Install Minecraft Java 1.21.11 and create a **dedicated game directory** (e.g.
   `C:\VRMC\minecraft-1.21.11`). Do not test on a world you care about.
3. Install Fabric Loader 0.20.1 for 1.21.11 into that profile.
4. Put Fabric API and the Vivecraft 1.3.15 Fabric JAR into `<gameDir>\mods\`.
5. Launch the profile once to verify Vivecraft loads. Quit.
6. Set Minecraft to borderless/windowed, **3840×1080**, GUI scale appropriate, and disable
   pause-on-focus-loss (Vivecraft/VRMC expects the game to keep running when unfocused).
7. In Vivecraft VR settings:
   - Display Mirror = **DUAL** (both eyes side by side).
   - Dual mirror swap = off.
   - Dual mirror crop = 0.
   - Do not use exclusive fullscreen.
8. Confirm the game window is titled `Minecraft` (or note the title) and its client area is
   3840×1080. `vrmc_host --window-title` must match.

## 3. Build and install the VRMC driver/host

From a Windows PowerShell in the repository root:

```powershell
pwsh .\scripts\build_bridge.ps1 -Configuration Release
# Desktop -> start SteamVR first, then:
pwsh .\scripts\install_driver.ps1
```

`install_driver.ps1` copies the driver to
`<SteamVR>\drivers\vrmc`, backs up `steamvr.vrsettings`, enables multiple drivers and
`driver_vrmc`, and leaves SteamVR stopped. Start SteamVR and open **Developer → Web Console**
or the system report to confirm:

- `VRMC Virtual HMD`
- `VRMC Knuckles` left/right controllers

The driver needs `vrmc_host` running to receive poses; without it devices appear but poses are
invalid. If you need to uninstall, remove `drivers\vrmc` and restore the `.vrmc-backup`
settings.

## 4. Build the visionOS app

On macOS with Xcode 27.1:

```bash
./scripts/bootstrap.sh
./scripts/build_client.sh --simulator   # simulator smoke test
./scripts/build_client.sh --device      # device build (set DEVELOPMENT_TEAM to sign)
```

For a device build, sign with your Apple development team and install via Xcode, TestFlight,
or Ad Hoc. The app needs:

- Hand Tracking permission (used for both hands and 27 joints).
- Local Network permission (connect to your PC).
- World Sensing permission (head/hand alignment).

The current development build uses the insecure transport mode and shows a warning. **Do not
use it on an untrusted network.** Secure pairing/AEAD is a release gate (see
`VERIFY.md` §8/§10 and `LIMITATIONS.md`).

## 5. First connection

1. Start SteamVR (driver enabled).
2. Start `vrmc_host` (PowerShell):
   ```powershell
   pwsh .\scripts\run_host.ps1 -WindowTitle "Minecraft"
   ```
   Wait for `host ready`.
3. Start the Minecraft/Vivecraft profile; enter a world and confirm the DUAL mirror shows two
   eyes in the game window.
4. Launch VRMC on Vision Pro. For the current development build:
   - Host: your PC's LAN IP (the simulator uses `127.0.0.1`).
   - Control port: `48625` unless changed.
   - Tap **Start VR**; grant permissions; the immersive space opens.
5. Stand up, look forward, and hold both hands in view. The status should show `streaming`,
   `hands`, and a calibrated origin. If not, see TROUBLESHOOT.

## 6. Controls and comfort

See [`RUN.md`](RUN.md) for the mapping and session flow. Start seated/standing in a clear
2×2 m area, remove fragile objects, and stop immediately if you feel discomfort. VR can cause
nausea; locomotion is opt-in (palm-up) and can be disabled by closing the hand or leaving the
session.

## 7. Verification

The install is not accepted until the procedures in [`VERIFY.md`](../../VERIFY.md) §4 are
completed and evidence is recorded. A successful simulator demo is not device acceptance.
