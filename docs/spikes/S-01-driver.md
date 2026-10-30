# S-01 — Virtual SteamVR driver + Vivecraft session

**Question:** Can a third-party OpenVR driver expose a virtual HMD (display component) and two
`knuckles` controllers such that SteamVR registers them and unmodified Vivecraft enters VR and
renders?

**Status:** BLOCKED — no Windows/SteamVR/Vivecraft runtime in this workspace. Source written
(`bridge/driver`), not compiled or executed here.

**Go criterion:** SteamVR device report shows `VRMC Virtual HMD` + both controllers; Vivecraft
log shows successful OpenVR initialization; the game window renders; controllers' poses/inputs
are visible in SteamVR; 10-minute session stable.

**No-go:** driver rejected, devices not tracked, Vivecraft refuses OpenXR-less HMD, or inputs
do not bind. Fallback: direct-mode driver (option B) or a patched backend (new ADR).

**Method (when hardware available):**

1. Build `scripts/build_bridge.ps1`; install driver; start SteamVR; inspect device report and
   Web Console for `vrmc` errors.
2. Start `vrmc_host` with a file or WGC source; confirm shared-memory snapshot and device poses.
3. Launch pinned Vivecraft profile; confirm VR init and DUAL mirror; exercise trigger/grip/
   thumbstick/A/B with a test input injection, then real hands.
4. Record logs/screenshots per `VERIFY.md` MT-02/EV-0005.

**Evidence:** pending; see `VERIFY.md` EV-0005.
