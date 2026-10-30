# Manual Device Test Plan

This is the field checklist for D1 (Vision Pro), P1 (Windows/SteamVR), and the pinned
Minecraft/Fabric/Vivecraft profile. Acceptance authority and evidence templates are in
[`VERIFY.md`](../../VERIFY.md); exact procedures are in §4 there. Do not record a pass without
attached evidence.

## Pre-flight

- [ ] D1 build hash/commit and version match the evidence entry.
- [ ] P1: Windows 11, NVIDIA driver version, SteamVR version, Minecraft 1.21.11, Fabric
      loader, Vivecraft 1.21.11-1.3.15, VRMC driver/host build hashes recorded.
- [ ] VRMC driver appears in SteamVR device report; HMD + two controllers.
- [ ] Minecraft window is borderless 3840×1080, DUAL mirror, `dualMirrorSwap=false`,
      `dualMirrorCrop=0`; no DPI scaling.
- [ ] Network N1 selected; PC wired; headset on dedicated 5/6 GHz; latency baseline noted.
- [ ] Hand-tracking and local-network permissions granted; recentered; height calibrated.
- [ ] Telemetry logging enabled on host/client; storage/diagnostics paths known.
- [ ] Test operator has read `LIMITATIONS.md` and stop criteria.

## Core session

- [ ] MT-01 pair/connect; encrypted/insecure indicator matches build; reconnect works.
- [ ] MT-02 Vivecraft enters VR; live stereo; correct eye order; no black half.
- [ ] MT-03 10 minutes; fps target, no corruption, comfort acceptable.
- [ ] MT-04 both hands 27 joints; rate/jitter recorded; occlusion/loss/recovery.
- [ ] MT-05 grab/release, break, place, use/consume, attack, hotbar, offhand, bow, jump/sneak.
- [ ] MT-06 UI pointing, inventory, menus, radial, keyboard/chat.
- [ ] MT-07 locomotion, strafe, turn (snap/smooth), jump, sneak, room-scale/recenter.
- [ ] MT-08 stop/restart host/SteamVR/Minecraft; client stays alive.
- [ ] MT-09 latency/performance CSV + 240 fps camera; 3 runs N1, 3 runs N2/N4.
- [ ] MT-10 60-minute soak; memory/thermal/fps; degradation/recovery.
- [ ] MT-11 failure campaign NF-01..NF-15; every row records detection/recovery/restart.
- [ ] MT-12 new-user reproducibility by someone who did not write the docs.

## Hand-tracking interaction detail

For each gesture, record 10 attempts and latency/accuracy:

- [ ] index pinch → trigger/attack/teleport
- [ ] middle pinch → use/place
- [ ] fist → grip/grab/hotbar
- [ ] palm-up left → locomotion; displacement axes; turn; exit
- [ ] palm-to-face short → inventory; long → menu; no double action
- [ ] palm-down low → sneak
- [ ] ring pinch/flick → jump
- [ ] two-hand bow/shield
- [ ] left-handed profile
- [ ] gesture while walking/turning/attacking (chord suppression)
- [ ] hand crossing/touching; one hand lost; both lost

## Failure drills (no full restart allowed)

- [ ] cover one hand, then both; behind back; below view
- [ ] 1% and 5% UDP loss; reorder/duplicate; 30 Mbps cap; 300 ms and 5 s outage
- [ ] kill host; restart host; restart SteamVR; kill Minecraft; relaunch profile
- [ ] corrupt/skip frame; encoder stall; decoder error; clock step
- [ ] Wi‑Fi roam between APs
- [ ] record whether input released, overlay shown, IDR requested, recovery time, restart used

## Sign-off packet

- [ ] Completed `VERIFY.md` §9 entries (one per scope, with raw numbers).
- [ ] Screenshots: stereo test pattern, eye-order check, SteamVR devices, in-game interactions.
- [ ] Video: full interaction pass and latency camera run (redact personal data).
- [ ] CSV: telemetry and latency analysis.
- [ ] Defect list with workarounds/limitations.
- [ ] Operator/reviewer signatures per VERIFY §10.
