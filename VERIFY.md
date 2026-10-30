# VRMC — Verification and Acceptance

> **Authority:** This file is the single source of truth for verification, acceptance, and
> release sign-off. If it conflicts with `AGENT.md`, this file wins for acceptance decisions.
> **Last updated:** 2026-10-30.
> **Baseline commit:** `aad28d02cd462cb22d3f8e74007a61d1f5b77735` (local); first tagged release TBD.
> **Release candidate:** none.

**Rules**

1. A milestone is not complete unless the corresponding evidence is recorded in §9 and the
   acceptance status in §3 is updated.
2. `PASS` requires a reproducible procedure and linked evidence (log, screenshot, video,
   measurement, or automated test output) produced from the recorded build.
3. A test that was not executed is `NOT RUN`. A test that cannot be executed here is
   `BLOCKED` with an owner and unblock condition. Code inspection is `PARTIAL`, never `PASS`.
4. Never fabricate, backfill, or copy evidence from another build/device. Re-run after any
   change that can affect the result.
5. Flaky or failing tests are defects. Record the failure and do not average it away.
6. Hardware test evidence must include: date, commit, dirty state, headset model/OS, PC
   specs, GPU driver, SteamVR/Minecraft/Vivecraft versions, network topology, exact steps,
   expected, actual, and evidence paths.
7. Acceptance status is decided here, not in commit messages, demos, or chat reports.

**Status legend:** `PASS` · `PARTIAL` · `FAIL` · `BLOCKED` · `NOT RUN` · `N/A` (with reason).

---

## 1. Scope of acceptance

VRMC is accepted only when a user can:

1. start a real Vivecraft VR session from Apple Vision Pro;
2. use both hands with articulated joints as gameplay input;
3. perform grab/release, break/place, attack/use/consume, UI pointing/pinch selection,
   inventory/menu interaction, locomotion/turning, and two-handed interactions;
4. experience motion-to-photon latency within the documented target, or a quantified
   limitation with an accepted mitigation plan;
5. recover from tracking loss, occlusion, reconnection, packet/frame loss, runtime restart,
   and degraded network without restarting the whole stack;
6. rely on a complete test report, user guide, troubleshooting guide, and release checklist.

Out of scope for acceptance: audio quality, multiplayer servers beyond a local test server,
non-Vivecraft OpenVR games, AMD/Intel encoding, Linux host, App Store approval (TestFlight/Ad
Hoc is acceptable for v1 unless release target changes via ADR).

---

## 2. Test environments and identifiers

### 2.1 Device / runtime matrix

| ID | Role | Device | OS | Notes |
| --- | --- | --- | --- | --- |
| D1 | Primary headset | Apple Vision Pro (M2), 256 GB | visionOS 27.x | Baseline acceptance device; serial recorded in evidence |
| D2 | Secondary headset | Apple Vision Pro (later revision, if available) | visionOS 27.x | Compatibility, not required for v1 sign-off |
| D3 | Simulator | visionOS 27 simulator on Apple silicon | macOS 27.x | Development/synthetic only; never evidence for hand tracking or latency |
| P1 | Primary PC | 8-core x86-64, 32 GB, NVIDIA RTX 4070+ | Windows 11 24H2+ | Wired Ethernet to AP; NVIDIA driver pinned |
| P2 | Secondary PC | 12-core, 32 GB, RTX 4080+ | Windows 11 | Performance comparison |
| P3 | Low-end PC | 6-core, 16 GB, RTX 3060 12 GB | Windows 11 | Degradation test; may fail budgets |
| N1 | Network A | Wi‑Fi 6E, 5 GHz, dedicated AP, PC wired | — | Primary acceptance network |
| N2 | Network B | Wi‑Fi 6, shared household network | — | Realistic degraded network |
| N3 | Network C | Wired client via USB-C Ethernet adapter (if supported) | — | Reference low-latency baseline |
| N4 | Network D | Traffic-controlled impairment (netem/TC or router) | — | Loss 1–5%, jitter 10–80 ms, bandwidth 30–300 Mbps |

### 2.2 Software matrix

| Component | Baseline | Compatibility candidates | Evidence required |
| --- | --- | --- | --- |
| Minecraft Java | 1.21.11 | 1.20.1, 26.3 if Vivecraft stable | Launch + 10-minute play per version |
| Mod loader | Fabric (exact loader pinned) | Quilt if Vivecraft supports | Launch only |
| Vivecraft | 1.3.15 Fabric (1.21.11) | latest patch in 1.3.x | Full acceptance on baseline; smoke on candidates |
| SteamVR | Pinned current stable | previous stable | Driver registration + session |
| VRMC client | Build from tagged commit | — | Build hash in every entry |
| VRMC bridge/driver | Build from tagged commit | — | Build hash in every entry |
| GPU driver | Pinned studio/game-ready | one previous | Performance and stability |
| Xcode/Swift | 27.1 / 6.4 | — | Build evidence |
| Windows SDK/VS | 10.0.26100+ / VS 2022 17.12+ | — | Build evidence |

### 2.3 Hand-tracking state matrix

Each row must be exercised with both hands where applicable.

| ID | State | Procedure | Pass condition |
| --- | --- | --- | --- |
| HT-01 | Both hands tracked, neutral | Hold hands in view, palms down | 27 joints/hand, continuous updates ≥72 Hz, no swaps |
| HT-02 | Pinch (index) | Touch thumb/index tips, hold 0.5 s, release | Trigger asserts/releases once; no chatter |
| HT-03 | Pinch (middle) | Touch thumb/middle tips | Use/trackpad click asserts/releases once |
| HT-04 | Fist / grip | Close all fingers, hold, open | Grip asserts/releases; no stuck input |
| HT-05 | Open palm / point | Extend fingers, point at UI | Aim ray stable; selection lands on target |
| HT-06 | Palm-up locomotion | Left palm up, move/tilt, close | Stick axes map smoothly; exit is clean |
| HT-07 | Quick movements | Fast slashes, bow draw, eat | No lost tracking >120 ms; inputs remain coherent |
| HT-08 | Occlusion by body | Move hand behind torso/head | Degraded→lost, inputs released; reacquire ≤1 s |
| HT-09 | Out of FOV | Lower hand below view | Same as HT-08; no frozen pose presented as valid |
| HT-10 | One hand lost | Occlude one hand only | Other hand remains fully functional; lost hand releases |
| HT-11 | Hands close/touching | Bring palms together, cross | No left/right swap; two-hand interaction still works |
| HT-12 | Low light / IR interference | Dim room, sunlight, reflective surfaces | Tracking within documented degradation; recovery works |
| HT-13 | Long session | 30 min continuous | No thermal failure; tracking rate/latency within budget |
| HT-14 | Two-handed bow | Draw bow with main hand, nock/aim with off hand | Bow draws, arrow fires, no stuck trigger |
| HT-15 | Two-handed shield/food | Off-hand use while main hand attacks | Both hands' actions independent |
| HT-16 | UI/inventory | Point, pinch, scroll, move items | Selection, scroll, drag/drop, close all work |
| HT-17 | Menu/chords | Open menu, inventory, radial, keyboard | Correct action per mapping; no accidental chords |
| HT-18 | Locomotion/turn | Walk, strafe, jump, sneak, snap/smooth turn | All directions and actions work; comfort settings |
| HT-19 | Handedness | Switch left-handed profile | Mirrored mapping correct; no broken bindings |
| HT-20 | Tracking permission denied | Revoke permission, relaunch | Clear explanation; no crash; settings link works |

### 2.4 Network and failure matrix

| ID | Condition | Injection | Pass condition |
| --- | --- | --- | --- |
| NF-01 | Clean LAN | N1 | Baseline budgets |
| NF-02 | 1% packet loss | N4 | No visible corruption; recovery ≤500 ms; input remains usable |
| NF-03 | 5% packet loss | N4 | Graceful degradation, IDR recovery, no crash/freeze >1 s |
| NF-04 | 20–80 ms jitter | N4 | Jitter buffer stable; no audio/video desync (audio v1.1) |
| NF-05 | 30 Mbps cap | N4 | ABR degrades resolution/bitrate; session continues |
| NF-06 | 300 ms outage | Firewall/AP toggle | Overlay, inputs released, auto-reconnect ≤5 s |
| NF-07 | 5 s outage | AP restart | Auto-reconnect ≤15 s, IDR, no app restart |
| NF-08 | Host process kill | Task Manager | Client degrades; host relaunch reconnects |
| NF-09 | SteamVR restart | Restart SteamVR | Driver re-registers; Vivecraft restart flow; client recovers |
| NF-10 | Minecraft crash | Kill javaw | Host reports runtime unavailable; relaunch flow recovers |
| NF-11 | Encoder stall | Inject encoder delay/failure | ABR/keyframe recovery; no unbounded queue |
| NF-12 | Decoder error | Corrupt frame/keyframe | Last good frame held, IDR requested, no crash |
| NF-13 | Clock step/drift | Adjust host clock / sleep | Re-sync; no pose teleport; input timestamps sane |
| NF-14 | Duplicate/replayed input | Replay tool | Rejected by replay window; no duplicate actions |
| NF-15 | Wi‑Fi roaming | Walk between APs | Reconnect; session recovers |

### 2.5 Interaction coverage matrix

| Interaction | Input path | Test IDs | Acceptance |
| --- | --- | --- | --- |
| Grab/release | Hand pose + grip | HT-04, HT-14, MT-05 | Required |
| Break block | Aim + trigger hold | HT-02, MT-05 | Required |
| Place block | Aim + use (middle pinch) | HT-03, MT-05 | Required |
| Attack mob/player | Aim + trigger | HT-02, MT-05 | Required |
| Use/consume item | Use + hold | HT-03, HT-15, MT-05 | Required |
| UI pointing | Aim ray + pinch | HT-05, HT-16 | Required |
| Inventory | Menu gesture + point/pinch/scroll | HT-16, MT-06 | Required |
| Game menu | Menu gesture/chord | HT-17, MT-06 | Required |
| Locomotion | Virtual left stick | HT-06, HT-18 | Required |
| Turning | Virtual right stick/comfort | HT-18 | Required |
| Jump/sneak | Gesture buttons | HT-18 | Required |
| Two-handed bow | Both hands | HT-14 | Required |
| Hotbar | Grip gestures | HT-04, MT-05 | Required |
| Keyboard/chat | Menu + system keyboard | MT-06 | Required if chat tested |

---

## 3. Acceptance criteria mapping

Each AC is decomposed into requirements with concrete verification. The status column is
updated only with linked evidence.

### AC-1 — Start a Vivecraft VR session from Vision Pro

| Req | Requirement | Verification | Status |
| --- | --- | --- | --- |
| AC-1.1 | User can discover/pair with the PC from the headset | AT-NET-01, MT-01 | NOT RUN |
| AC-1.2 | Host launches or attaches to the pinned Vivecraft profile | MT-01, MT-02 | NOT RUN |
| AC-1.3 | Virtual HMD and both controllers register in SteamVR | MT-02, AT-DRV-01 | NOT RUN |
| AC-1.4 | Vivecraft enters VR and renders a stereo frame | MT-02, MT-03 | NOT RUN |
| AC-1.5 | Client shows live stereo gameplay in an immersive space | MT-03 | NOT RUN |
| AC-1.6 | Session can be ended and restarted without rebooting devices | MT-08 | NOT RUN |

### AC-2 — Both hands tracked with articulated joints and used in gameplay

| Req | Requirement | Verification | Status |
| --- | --- | --- | --- |
| AC-2.1 | Both hands tracked, 27 joints, position + orientation | AT-HAND-01, MT-04, HT-01 | NOT RUN |
| AC-2.2 | Update rate and accuracy meet targets | MT-04, HT-01, HT-07 | NOT RUN |
| AC-2.3 | Hand snapshots are timestamped, filtered, predicted | AT-HAND-02..04, AT-TIME-01..03 | NOT RUN |
| AC-2.4 | Handedness stable; no swaps | HT-11, MT-04 | NOT RUN |
| AC-2.5 | Skeleton drives virtual controller poses used by Vivecraft | MT-05, AT-MAP-01..06 | NOT RUN |
| AC-2.6 | Tracking loss/occlusion handled without stuck input | HT-08..10, NF-06 | NOT RUN |

### AC-3 — Core Vivecraft interactions with hand tracking

| Req | Requirement | Verification | Status |
| --- | --- | --- | --- |
| AC-3.1 | Grab and release | MT-05, HT-04 | NOT RUN |
| AC-3.2 | Break block | MT-05, HT-02 | NOT RUN |
| AC-3.3 | Place block | MT-05, HT-03 | NOT RUN |
| AC-3.4 | Use/consume | MT-05, HT-15 | NOT RUN |
| AC-3.5 | Attack | MT-05, HT-02 | NOT RUN |
| AC-3.6 | UI pointing and pinch selection | MT-06, HT-05/16 | NOT RUN |
| AC-3.7 | Inventory and menu interaction | MT-06, HT-16/17 | NOT RUN |
| AC-3.8 | Locomotion and turning | MT-07, HT-06/18 | NOT RUN |
| AC-3.9 | Two-handed interactions (bow, shield) | MT-05, HT-14/15 | NOT RUN |
| AC-3.10 | Hotbar/offhand/keyboard | MT-05/06, HT-04/17 | NOT RUN |

### AC-4 — Latency measured and within documented target

| Req | Requirement | Verification | Status |
| --- | --- | --- | --- |
| AC-4.1 | Instrumented capture→display latency telemetry | AT-TELEM-01..03, MT-09 | NOT RUN |
| AC-4.2 | View M2P median ≤50 ms, p95 ≤70 ms on N1/P1/D1 | MT-09, PERF report | NOT RUN |
| AC-4.3 | Action feedback median ≤150 ms, p95 ≤250 ms | MT-09 | NOT RUN |
| AC-4.4 | 90 fps target; 72 fps floor; no >2% dropped frames in 10 min | MT-09, MT-10 | NOT RUN |
| AC-4.5 | Bandwidth/CPU/GPU budgets met | MT-09, MT-10 | NOT RUN |
| AC-4.6 | If target missed: quantified limitation + accepted mitigation | MT-09 + signed waiver | NOT RUN |

### AC-5 — Failure recovery without full-stack restart

| Req | Requirement | Verification | Status |
| --- | --- | --- | --- |
| AC-5.1 | Tracking loss/occlusion recovery | HT-08..10, MT-11 | NOT RUN |
| AC-5.2 | Packet loss/frame drop recovery | NF-02..05/12, MT-11 | NOT RUN |
| AC-5.3 | Network outage/reconnect | NF-06..07/15, MT-11 | NOT RUN |
| AC-5.4 | Host/SteamVR/Minecraft restart recovery | NF-08..10, MT-08 | NOT RUN |
| AC-5.5 | No stuck inputs, crashes, or unbounded queues | AT-SESSION-01..05, MT-11 | NOT RUN |

### AC-6 — Complete documentation and release artifacts

| Req | Requirement | Verification | Status |
| --- | --- | --- | --- |
| AC-6.1 | Test report complete with evidence | This file, §9/§10 | NOT RUN |
| AC-6.2 | User install/run guide tested | MT-12, docs review | NOT RUN |
| AC-6.3 | Troubleshooting guide covers known failures | MT-12, docs review | NOT RUN |
| AC-6.4 | Release checklist and DoD audit complete | §10, signed | NOT RUN |
| AC-6.5 | Clean reproducible build from tag | AT-BUILD-01..03 | NOT RUN |
| AC-6.6 | Licenses/privacy/EULA compliance | §8, legal checklist | NOT RUN |

---

## 4. Manual on-device test procedures

All procedures assume the baseline environment unless stated. Record every step/result in the
evidence log; attach screenshots or video for visual outcomes. Use a fresh build hash.

### MT-01 — Install, pair, and connect

**Preconditions:** D1 has VRMC installed; P1 is on N1; host running; SteamVR installed.

1. Launch VRMC on D1. Grant hand-tracking and local-network permissions when prompted.
2. Confirm the host appears (Bonjour) or enter host IP/port manually.
3. Confirm the host displays a six-digit pairing code; enter it on D1.
4. Verify the client shows `Connected / waiting for video` and the host log shows an
   authenticated session.
5. Quit and relaunch the client; verify the saved host requires no re-pair (token valid) or
   re-pairs cleanly after token reset.

**Expected:** encrypted session, no plaintext credentials in logs, connect ≤10 s on LAN.
**Evidence:** client/host logs, screenshot of connected UI.

### MT-02 — Start Vivecraft and virtual devices

**Preconditions:** VRMC driver installed; SteamVR configured with the driver; pinned
Minecraft/Fabric/Vivecraft profile; DUAL mirror configured; game window 3840×1080 borderless.

1. Start SteamVR. Open the SteamVR system report/devices panel.
2. Verify `VRMC HMD`, `VRMC Left Controller`, `VRMC Right Controller` are present and poses
   update when hands move on D1.
3. Launch the Vivecraft profile. Verify it enters VR mode and does not show "HMD not found".
4. Verify the game window shows the DUAL mirror (both eyes side by side), no black half, no
   eye swap.
5. Verify the in-headset view shows the same scene with stereo depth.

**Expected:** Vivecraft playable; HMD/controller tracking follows hands/head; stereo aligned.
**Evidence:** SteamVR system report, host log, photo/video of game window and headset view,
Vivecraft log.

### MT-03 — Live stereo and basic comfort

1. Enter a safe creative world; look around and walk 10 m.
2. Verify left/right eye images are distinct, correct order, no vertical flip, no black bars
   from wrong aspect.
3. Check horizon level, scale (1 block ≈ 1 m), and IPD comfort.
4. Run 10 minutes; monitor fps, dropped frames, decode/encode times, temperature.
5. Toggle quality (resolution/bitrate); verify graceful changes and recovery.

**Expected:** stable 90 fps (or documented 72), no discomfort, no corruption.
**Evidence:** telemetry export, screenshots per eye if available, session video.

### MT-04 — Hand tracking quality

1. Open the VRMC hand debug overlay (both hands, joints, rates, timestamps).
2. Hold hands neutral. Record joint update rate and jitter for 60 s.
3. Perform fast movements, pinches, fists, palm-up, point, and crossing hands.
4. Occlude each hand behind the torso, then lower it below view; observe degraded/lost/
   reacquired states and input release.
5. Repeat in low light/reflective conditions (HT-12).
6. Switch handedness profile; verify mirroring.

**Expected:** 27 joints/hand, ≥72 Hz, no swaps, recovery ≤1 s, no stuck inputs. Record actual
numbers; do not just mark pass.
**Evidence:** overlay screenshots/video, telemetry CSV, notes.

### MT-05 — Core gameplay interactions

Use the baseline mapping in `docs/architecture/HAND_MAPPING.md`. For each action, record
latency and success/failure over 10 attempts:

1. **Grab/release:** pick up and drop an item/entity with fist/grip.
2. **Break:** aim at a block, index-pinch and hold until broken; release.
3. **Place:** aim at a face, middle-pinch once.
4. **Attack:** aim at a mob, index-pinch; verify damage.
5. **Use/consume:** hold middle pinch with food/potion; verify consumption.
6. **Hotbar:** fist/grip left/right; verify slot change.
7. **Offhand:** use offhand gesture; verify shield/food.
8. **Two-handed bow:** draw with main hand trigger, nock with offhand grip, release; verify
   arrow fires and no stuck state.
9. **Jump/sneak:** perform gestures; verify in-world effect.
10. **Locomotion:** palm-up stick walk/strafe; turn; stop; verify no drift.

**Expected:** all actions work reliably; no accidental actions when idle; no stuck inputs.
**Evidence:** video with time codes, per-action results table, telemetry.

### MT-06 — UI, inventory, menus, keyboard

1. Point at the Vivecraft wrist/HUD menu; pinch to select; verify ray and hover.
2. Open inventory (left palm-to-face short), move an item, split a stack, close.
3. Open game menu (long palm-to-face or mapped chord); navigate; change a setting; close.
4. Open radial menu; select an item.
5. Open keyboard/chat; type using the system keyboard; send a message; close.
6. Verify pinch scrolling in inventory.

**Expected:** all UI interactions work with hands only; no controller required; focus/pointer
is stable; menu does not trap input.
**Evidence:** video/screenshots, step results.

### MT-07 — Locomotion, turning, comfort

1. Walk forward/back/strafe using the virtual stick; verify speed and diagonal behaviour.
2. Turn with snap and smooth modes; verify angle, cooldown, and comfort.
3. Jump, sneak, sprint (if mapped), climb/vine handling.
4. Test room-scale walking and recentring; verify world scale.
5. Test seated mode (if supported) and height calibration.
6. Run 15 minutes; record discomfort (0–10) and stop criteria.

**Expected:** usable locomotion/turning; no nausea-inducing jitter; comfort settings effective.
**Evidence:** notes, video, telemetry.

### MT-08 — Session lifecycle and runtime restart

1. End session from client; verify host releases inputs, driver marks devices invalid, video
   stops, resources close.
2. Restart SteamVR while client stays open; verify recovery per NF-09.
3. Kill and relaunch `vrmc_host.exe`; verify client reconnects and requests IDR.
4. Kill Minecraft; relaunch profile via host; verify client recovers without relaunch.
5. Reboot PC while client stays in immersive space; verify bounded retry and clear status.

**Expected:** no full-stack restart; clear user feedback; automatic recovery where specified.
**Evidence:** logs with timestamps, screen recording.

### MT-09 — Latency and performance measurement

1. Enable telemetry on client and host; synchronise clocks; export CSV.
2. Run the standard scene: 10 minutes of walking, looking, mining, placing, menu use.
3. Record per-stage timestamps (hand sample, send, host receive, driver update, frame
   capture, encode, send, receive, decode, present) and compute percentiles.
4. Hardware M2P: film the Vision Pro display and a physical hand/controller motion at
   240 fps in a dark room; use a visual marker (full-screen flash triggered by a known input)
   or a photodiode where possible; count frames from motion to change.
5. Repeat on N1/N2/N4, 3 runs each; report median/p95 and outliers.
6. Run 30 minutes for thermal/stability; record fps, dropped frames, bitrate, CPU/GPU,
   temperatures.

**Expected:** targets in §5. If missed, quantify and attach mitigation/waiver.
**Evidence:** CSV, analysis script output, high-speed video, report in
`docs/performance/PERF_REPORT.md`.

### MT-10 — Soak and degradation

1. 60-minute session with normal play; record crash/free memory, queue depths, fps, latency.
2. Force 30 Mbps cap and 5% loss for 5 minutes; verify ABR and recovery.
3. Background GPU load/thermal throttle; verify graceful quality reduction.
4. Verify no unbounded log growth or disk fill.

**Expected:** no crash/leak; stable session; documented degradation.
**Evidence:** telemetry, logs, memory graph.

### MT-11 — Failure recovery campaign

Execute NF-01..NF-15 and HT-08..HT-10. For each, record detection time, user-visible state,
input release, recovery time, and whether a restart was required. A full-stack restart counts
as a failure for AC-5.

### MT-12 — New-user reproducibility

A developer who has not seen the project follows `docs/user/INSTALL.md` and
`docs/user/RUN.md` on a clean PC/headset:

1. Clone the tagged repo; run documented bootstrap/build commands.
2. Install SteamVR and the pinned Minecraft/Vivecraft profile using the guide.
3. Install the driver and pair the client.
4. Complete MT-03 and one interaction from MT-05.
5. Record ambiguities, missing steps, and time to first session.

**Expected:** first session ≤60 minutes excluding downloads; no undocumented steps.
**Evidence:** session notes, doc issues filed/fixed.

---

## 5. Performance, latency, bandwidth, and stability budgets

These are acceptance budgets, not aspirations. Measure with telemetry and the procedures in
MT-09/MT-10. Percentiles are over at least 10 minutes of representative play.

| Budget | Target | Floor / limit | Method |
| --- | --- | --- | --- |
| Display refresh | 90 Hz | 72 Hz | Client telemetry, `LayerRenderer` timing |
| View motion-to-photon | P50 ≤50 ms, P95 ≤70 ms | P99 ≤100 ms | Instrumented + 240 fps camera |
| Action-to-feedback | P50 ≤150 ms, P95 ≤250 ms | P99 ≤350 ms | Timestamped action marker + frame metadata |
| Hand sample→PC driver | P50 ≤25 ms, P95 ≤45 ms | P99 ≤70 ms | Input packet timestamps + host log |
| Hand tracking rate | ≥90 Hz per hand | ≥72 Hz | ARKit anchor timestamps |
| Hand pose prediction error | ≤2 cm / ≤3° at 50 ms | ≤4 cm / ≤6° | Recorded replay vs ground truth |
| Capture→encode submit | ≤8 ms | ≤14 ms | Host telemetry |
| Encode latency | ≤8 ms | ≤15 ms (NVENC) | Host telemetry |
| Network one-way | ≤8 ms P50, ≤20 ms P95 | ≤40 ms P99 | Clock sync/ping |
| Decode latency | ≤8 ms | ≤14 ms | Client telemetry |
| Present/compositor | ≤11.1 ms at 90 Hz | 13.9 ms at 72 Hz | Client telemetry |
| Dropped video frames | ≤1% | ≤3% | Frame ID gaps / presented IDs |
| Bitrate (video) | 70–100 Mbps HEVC | 30 Mbps ABR floor | Host encoder |
| Bitrate (total) | ≤120 Mbps | ≤40 Mbps degraded | Host network counters |
| Encode GPU cost | ≤15% RTX 4070 | ≤25% | GPU counters |
| Client decode GPU | ≤20% | ≤30% | Metal/VideoToolbox counters |
| Client render GPU | ≤70% frame budget | ≤90% | Metal counters |
| End-to-end packet loss tolerance | 1% no visible artifact | 5% with recovery | Impairment matrix |
| Reconnect after short outage | ≤5 s | ≤15 s | NF-06/07 |
| Tracking reacquisition | ≤500 ms | ≤1 s | HT-08/09 |
| Session stability | 60 min no crash | 30 min no crash | MT-10 |
| Memory growth | <100 MB/hour | <250 MB/hour | MT-10 |
| Thermal throttling | no >20% fps loss in 30 min | documented | MT-10 |

**Capture geometry baseline:** 3840×1080 SBS (1920×1080 per eye), 90 Hz, 100° horizontal FOV
per eye (driver-reported), 64 mm nominal IPD. Actual values must be recorded; if changed,
re-baseline budgets and expected latency.

**Latency accounting:** define t0 = physical motion/sample timestamp; t1 = packet sent;
t2 = host receive; t3 = driver pose update; t4 = game frame captured; t5 = encode complete;
t6 = first packet received; t7 = decode complete; t8 = presented. Report each delta and the
total. For view M2P, include the display scan-out/compositor delay; instrumented estimates
alone are `PARTIAL`.

---

## 6. Automated test inventory

Commands: `./scripts/test_all.sh` (all locally runnable), `swift test` in `client/`,
`ctest` in the bridge build, `./scripts/test_protocol.sh`. CI runs the same.

### 6.1 Swift client tests

| ID | Area | Test | What it proves | Status |
| --- | --- | --- | --- | --- |
| AT-PROTO-01 | Protocol | control message round-trip | encoder/decoder symmetry | PASS (EV-0002) |
| AT-PROTO-02 | Protocol | malformed/truncated/oversize rejection | parser robustness | PASS (EV-0002) |
| AT-PROTO-03 | Protocol | media fragment reassembly with reorder/loss/duplicate | correct frame assembly | PASS (EV-0002) |
| AT-PROTO-04 | Protocol | conformance vectors match C++/reference | cross-language compatibility | PASS (EV-0002) |
| AT-TIME-01 | Clock | offset/RTT estimator under synthetic jitter | sync accuracy | PASS (EV-0002) |
| AT-TIME-02 | Clock | drift compensation and re-sync | long-session stability | NOT IMPLEMENTED |
| AT-TIME-03 | Time | monotonic timestamp arithmetic/overflow | no wraps/misordering | PARTIAL |
| AT-HAND-01 | Hand | 27-joint snapshot mapping and validation | complete skeleton | PASS (EV-0002) |
| AT-HAND-02 | Hand | one-euro filter step response/noise | stable tracking | PASS (EV-0002) |
| AT-HAND-03 | Hand | constant-velocity prediction bounds | predictable extrapolation | PASS (EV-0002) |
| AT-HAND-04 | Hand | tracking loss hold/release state machine | no stuck poses/buttons | PASS (EV-0002) |
| AT-GEST-01 | Gesture | pinch hysteresis and debounce | no trigger chatter | PASS (EV-0002) |
| AT-GEST-02 | Gesture | fist/grip detection and release | reliable grab/release | PASS (EV-0002) |
| AT-GEST-03 | Gesture | palm-up locomotion activation/exit | no accidental locomotion | PASS (EV-0002) |
| AT-GEST-04 | Gesture | menu/inventory dwell and chord separation | no accidental menus | PASS (EV-0002) |
| AT-GEST-05 | Gesture | two-hand bow/shield sequence | two-handed interactions | PARTIAL |
| AT-GEST-06 | Gesture | noisy/occluded/rapid input robustness | no false positives | PARTIAL |
| AT-MAP-01 | Mapping | pinch→trigger, fist→grip, middle-pinch→use | core controller synthesis | PASS (EV-0002) |
| AT-MAP-02 | Mapping | left/right handedness mirroring | left-handed support | PASS (EV-0002) |
| AT-MAP-03 | Mapping | locomotion axes and turn rates | movement correctness | PASS (EV-0002) |
| AT-MAP-04 | Mapping | menu/inventory/chord button events | UI access | PASS (EV-0002) |
| AT-MAP-05 | Mapping | all-release on tracking/link loss | no stuck inputs | PASS (EV-0002) |
| AT-MAP-06 | Mapping | two-hand independent state | bow/shield | PARTIAL |
| AT-SESSION-01 | Session | connect/handshake/stream/degrade/reconnect state machine | recovery logic | PASS (EV-0002) |
| AT-SESSION-02 | Session | no media >250 ms → degraded, input released | link-loss handling | PASS (EV-0002) |
| AT-SESSION-03 | Session | IDR request on incomplete frame/reconnect | decoder recovery | PARTIAL |
| AT-SESSION-04 | Session | bounded queues/drop-oldest under overload | stability | NOT IMPLEMENTED |
| AT-SESSION-05 | Session | clock re-sync without pose jump | time recovery | PASS (EV-0002) |
| AT-NET-01 | Transport | pairing/auth success and wrong-code rejection | security | NOT IMPLEMENTED |
| AT-NET-02 | Transport | replay/duplicate rejection | security | NOT IMPLEMENTED |
| AT-NET-03 | Transport | UDP loss/jitter simulation | transport resilience | NOT IMPLEMENTED |
| AT-VID-01 | Video | NAL splitter/parameter-set handling | annex-B correctness | PASS (EV-0002) |
| AT-VID-02 | Video | VideoToolbox decode of fixture | hardware decode path | PASS (EV-0002) |
| AT-VID-03 | Video | decode errors return typed errors, no crash | robustness | PARTIAL |
| AT-RENDER-01 | Render | eye UV mapping and no swap | stereo correctness (unit/math) | PASS (EV-0002) |
| AT-RENDER-02 | Render | reprojection math identity/extremes | no distortion/NaN | PASS (EV-0002) |
| AT-TELEM-01 | Telemetry | stage timestamps and percentiles | latency accounting | PARTIAL (tracker exists; no dedicated test) |
| AT-TELEM-02 | Telemetry | dropped frame/packet counters | observability | PARTIAL |
| AT-TELEM-03 | Telemetry | CSV/log redaction | privacy | NOT IMPLEMENTED |
| AT-BUILD-01 | Build | clean Swift build/test | reproducibility | PASS (EV-0002) |
| AT-BUILD-02 | Build | visionOS simulator app build | client integration | PASS (EV-0003) |
| AT-BUILD-03 | Build | portable bridge build/test | bridge core | PASS (EV-0002) |

### 6.2 C++ bridge tests

| ID | Area | Test | Status |
| --- | --- | --- | --- |
| AT-CPP-01 | Protocol | encode/decode control messages vs vectors | PASS (EV-0002) |
| AT-CPP-02 | Protocol | fuzz/truncation of media fragments | NOT IMPLEMENTED |
| AT-CPP-03 | Clock | offset/drift estimator parity with Swift | PASS (EV-0002, offset/RTT; drift parity not yet) |
| AT-CPP-04 | Pose | quaternion/transform math and extrapolation | PASS (EV-0002) |
| AT-CPP-05 | IPC | seqlock snapshot consistency, torn-write detection | PASS (EV-0002) |
| AT-CPP-06 | Media | fragmenter MTU bounds and IDR chunking | NOT IMPLEMENTED |
| AT-CPP-07 | Crypto | AEAD vectors, nonce/replay policy | NOT IMPLEMENTED |
| AT-DRV-01 | Driver | device registration/pose/input smoke (Windows) | NOT IMPLEMENTED |
| AT-CAP-01 | Capture | WGC frame integrity/size/format (Windows) | NOT IMPLEMENTED |
| AT-ENC-01 | Encode | NVENC low-latency config + decodable output (Windows) | NOT IMPLEMENTED |

### 6.3 Integration / end-to-end tests

| ID | Test | Environment | Status |
| --- | --- | --- | --- |
| AT-E2E-01 | Mock host → simulator → decode → immersive render | D3 + Mac | PASS (EV-0003) |
| AT-E2E-02 | Synthetic hands → mapping → mock host input audit | D3 + Mac | PASS (EV-0003) |
| AT-E2E-03 | Client ↔ host handshake/reconnect/IDR | D3 + Mac | PARTIAL |
| AT-E2E-04 | Full PC + Vivecraft + device gameplay | D1/P1/N1 | NOT RUN |
| AT-E2E-05 | Failure campaign automated where possible | D1/P1/N4 | NOT RUN |

---

## 7. How to run automated tests

```bash
# Everything runnable without Windows/SteamVR/Vivecraft
./scripts/test_all.sh

# Swift core
cd client && swift test

# C++ core (after ./scripts/build_bridge.sh --core)
ctest --test-dir build/bridge-core --output-on-failure

# Protocol conformance
./scripts/test_protocol.sh

# Simulator end-to-end
./scripts/demo_simulator.sh
```

Tests that require Windows, SteamVR, a GPU encoder, or a physical headset are **not** part of
the local suite. They run on the hardware runner (manual or self-hosted CI) and must be
recorded in §9. The absence of a hardware runner is a `BLOCKED` state, not a pass.

CI jobs (see `.github/workflows/`):

- `client-core`: macOS, Swift build/test, lint, docs checks.
- `client-visionos`: macOS, simulator app build + unit tests.
- `bridge-core`: Ubuntu/macOS, C++ core build/tests + protocol vectors.
- `bridge-windows`: Windows, host/driver compile (smoke; hardware tests separate).
- `docs`: link/status checks.

---

## 8. Compliance verification

| Area | Requirement | Verification | Status |
| --- | --- | --- | --- |
| Minecraft EULA | No game files/assets distributed; user owns account | Artifact inspection, install script, README | NOT RUN |
| Vivecraft LGPL | No linking/modification/redistribution; arm's-length via SteamVR | Dependency audit, notices, release artifact scan | NOT RUN |
| OpenVR | BSD-3 notice and header pin | `THIRD_PARTY_NOTICES.md`, build audit | NOT RUN |
| NVENC/FFmpeg | License-compatible use/notices | Build audit | NOT RUN |
| Apple privacy | Usage strings, privacy manifest, local-network description, no tracking | `plutil`/archive validation, manual review | NOT RUN |
| Apple platform | No private APIs, JIT, sideload entitlements | `nm`/static audit, review | NOT RUN |
| Data handling | Hand/video stays on LAN; no secrets in logs | Log review, packet capture, redaction tests | NOT RUN |
| Crypto | Standard primitives, authenticated encryption, replay protection | Crypto tests and review | NOT RUN |
| Export compliance | Encryption declaration prepared | Release checklist | NOT RUN |
| Third-party notices | Complete and accurate | `THIRD_PARTY_NOTICES.md` review | NOT RUN |

---

## 9. Evidence log

**This section is append-only for released builds.** Do not edit prior entries except to add
a correction with a new entry referencing it. Each entry must be backed by files under
`evidence/<ID>/` (hashes/manifests committed; large media may live outside Git with hashes).

### 9.1 Entry template

```markdown
### EV-XXXX — <short title>

- **Date/time:** YYYY-MM-DD HH:MM TZ
- **Commit:** <sha> (dirty: yes/no; diff hash if dirty)
- **Build:** <artifact/version/hash>
- **Environment:** <D/P/N IDs, device serial, OS, PC specs, GPU driver, SteamVR, MC/Vivecraft>
- **Procedure:** <test ID + exact steps or link>
- **Expected:** <observable result>
- **Actual:** <observable result, numbers not adjectives>
- **Evidence:** <paths: log/screenshot/video/CSV; SHA-256 manifest>
- **Verdict:** PASS | FAIL | PARTIAL | BLOCKED
- **Notes/limits:** <known caveats; follow-up issue>
```

### 9.2 Current entries

#### EV-0001 — M0 document and source-audit baseline

- **Date/time:** 2026-10-29 (workspace)
- **Commit:** `c0ea23b` (M0/M1 baseline; docs-only follow-ups after)
- **Build:** docs only
- **Environment:** macOS 27.0.1, Xcode 27.1, visionOS 27 SDK; no headset/PC/SteamVR
- **Procedure:** source inspection of Vivecraft (`VivecraftMod`, branch
  `Multiloader-26.2`, checked 2026-10-29) for OpenVR dependency, mirror modes, default
  bindings; reading of Apple visionOS SDK availability; prior prototype archive review.
- **Expected:** identify a viable architecture and its unverified assumptions.
- **Actual:** Vivecraft source uses LWJGL OpenVR (`org.lwjgl.openvr`) and has no OpenXR
  implementation on main; DUAL mirror blits `framebufferEye[0]` and `[1]` side by side;
  `knuckles_defaults.json` maps trigger/grip/thumbstick/A/B/trackpad actions. visionOS has
  no OpenXR/OpenVR runtime. Remote architecture selected; assumptions A-01..A-12 recorded.
- **Evidence:** `docs/feasibility/FEASIBILITY_AUDIT.md`, ADR-0001..0006; source references
  listed therein. This is **PARTIAL** evidence for design, not acceptance.
- **Verdict:** PARTIAL
- **Notes/limits:** No runtime/device evidence. Vivecraft version pinned for acceptance is
  1.3.15 (1.21.11); source inspection was on the current 26.2 branch, so re-inspect the
  pinned tag before M3.

#### EV-0002 — Local automated suite baseline

- **Date/time:** 2026-10-30 08:21 UTC
- **Commit:** `a91c74719961d27bc2a2392868900f4ce3da9aa6` (clean)
- **Build:** client package + C++ core; no device/Windows artifacts
- **Environment:** macOS 27.0.1, Xcode 27.1, Swift 6.4, clang 21, Python 3
- **Procedure:** `./scripts/test_all.sh` (Swift tests, VideoToolbox fixture, C++ core,
  protocol vectors, docs checks)
- **Expected:** all local unit/conformance tests pass.
- **Actual:** PASS. Swift XCTest: 34 core tests + 3 video tests, 0 failures; C++ core: 1/1
  passed (protocol, vectors, clock, pose, IPC); protocol vectors verified; docs links/required files pass. Full log:
  `evidence/EV-0002-local-suite/test_all.log`.
- **Evidence:** `evidence/EV-0002-local-suite/manifest.json`,
  `evidence/EV-0002-local-suite/test_all.log`.
- **Verdict:** PASS (local scope only)
- **Notes/limits:** Does not exercise visionOS hardware, hand tracking, SteamVR, Vivecraft,
  NVENC, WGC, or M2P. Secure-transport tests are not present because that implementation is
  not complete.

#### EV-0003 — Simulator end-to-end stream

- **Date/time:** 2026-10-30 08:20 UTC
- **Commit:** `aad28d02cd462cb22d3f8e74007a61d1f5b77735` (clean code; evidence files added after)
- **Build:** VRMC.app simulator Debug; executable SHA-256
  `a96a277d5471cfc45bf68cc064a0ad3baa93a0ce0ff2ffc2c3072259784ac904`
- **Environment:** D3 (visionOS 27 simulator, VRMC-VP on macOS 27.0.1) + Python mock host on
  loopback; synthetic hands at ~90 Hz
- **Procedure:** start `tools/mock_host/mock_host.py`; install/launch `VRMC.app -
  VRMCDemoMode`; wait 8 s; verify `streaming`/`hands`, decoded frame count, no drops; capture
  screenshot; inspect mock input log.
- **Expected:** live stereo test pattern, immersive render, decoded frames, synthetic intents
  received, no crash.
- **Actual:** PASS for simulator scope. State `streaming`; frames `152/152` decoded (0
  dropped); tracking origin calibrated; head y=1.62 m; mock host received HELLO and INTENT
  datagrams (pinch/fist/locomotion phases). Screenshot shows the SBS test pattern full-screen
  in the immersive scene and the app's development window with metrics.
- **Evidence:** `evidence/EV-0003-simulator/simulator.png` (SHA-256
  `5b8fdbc13a861585235cf9ddff38e323b0255dec896bb7dbc8169b1d31cd9fe6`), `mock_host.log` (20 INTENT lines), `app.log`, `input.jsonl`, `manifest.json`.
- **Verdict:** PASS (simulator scope only)
- **Notes/limits:** This is **not** evidence for hand tracking, Vivecraft, device latency,
  frame rate, or AC-1..AC-5. The window overlay remains visible in this development build.

#### EV-0004 — Physical device hand tracking

- **Date/time:** TBD
- **Commit:** TBD
- **Environment:** D1, visionOS 27.x
- **Procedure:** MT-04 + HT-01..HT-20
- **Expected:** per §3 AC-2.
- **Actual:** NOT RUN
- **Evidence:** TBD
- **Verdict:** BLOCKED — no physical Vision Pro attached to this workspace.
- **Notes/limits:** Owner: device-test owner. Unblock: physical D1 + signed development build.

#### EV-0005 — Vivecraft/virtual driver session

- **Date/time:** TBD
- **Commit:** TBD
- **Environment:** P1, Windows 11, SteamVR, Minecraft 1.21.11, Vivecraft 1.3.15
- **Procedure:** MT-01, MT-02, MT-03
- **Expected:** per AC-1.
- **Actual:** NOT RUN
- **Evidence:** TBD
- **Verdict:** BLOCKED — no Windows/SteamVR/Vivecraft runtime in this workspace.
- **Notes/limits:** Owner: bridge/driver owner. Unblock: P1 hardware + installed pinned stack.

#### EV-0006 — End-to-end gameplay acceptance

- **Date/time:** TBD
- **Commit:** TBD
- **Environment:** D1 + P1 + N1
- **Procedure:** MT-05, MT-06, MT-07, MT-09, MT-11
- **Expected:** per AC-3, AC-4, AC-5.
- **Actual:** NOT RUN
- **Evidence:** TBD
- **Verdict:** BLOCKED — depends on EV-0004 and EV-0005.
- **Notes/limits:** Final acceptance cannot be signed from simulation.

#### EV-0007 — Secure transport implementation

- **Date/time:** 2026-10-30
- **Commit:** `aad28d02cd462cb22d3f8e74007a61d1f5b77735`
- **Environment:** code audit
- **Procedure:** inspect client/host transport and protocol security requirements.
- **Expected:** pairing/AEAD/replay protection before release.
- **Actual:** FAIL/BLOCKED. Protocol and ADR define pairing and AEAD, but the client/host
  currently implement the explicitly marked insecure development path (plaintext control/media).
  No pairing UI, key storage, or crypto tests exist yet.
- **Evidence:** `protocol/PROTOCOL.md` §9, `docs/user/LIMITATIONS.md`, source audit.
- **Verdict:** BLOCKED — release gate; not an acceptance criterion for simulation but required
  by §8/§10.
- **Notes/limits:** Must be implemented and verified before any public/LAN-untrusted release.

---

#### EV-0008 — OpenVR driver source syntax check

- **Date/time:** 2026-10-30
- **Commit:** `a91c74719961d27bc2a2392868900f4ce3da9aa6` (driver source; syntax check)
- **Environment:** macOS 27.0.1, clang 21, OpenVR headers v2.15.6 (fetched, not committed)
- **Procedure:** `clang++ -std=c++20 -fsyntax-only -I<openvr>/headers -Ibridge/core/include bridge/driver/src/driver.cpp`
- **Expected:** the platform-neutral driver source compiles against the pinned OpenVR API.
- **Actual:** PASS (no diagnostics). This does not link a Windows DLL or exercise SteamVR.
- **Evidence:** command output recorded in this entry; source `bridge/driver/src/driver.cpp`.
- **Verdict:** PASS (source-check scope only)
- **Notes/limits:** Windows host/driver build, registration, and Vivecraft session remain
  BLOCKED under EV-0005.

---

## 10. Release checklist and final sign-off

A release candidate may be tagged only when every required item is checked with evidence.

### 10.1 Build and reproducibility

- [ ] `main` is clean, tagged `vX.Y.Z-rc.N`, and CI is green.
- [ ] `versions.env` pins all tool/runtime versions; hashes verified.
- [ ] Clean-checkout build (client simulator, device, bridge core, Windows host/driver)
      succeeds on the documented toolchain.
- [ ] No generated junk/secret/device data in the repo; `.gitignore` verified.
- [ ] Release artifacts built from the tag; SHA-256 manifest produced.
- [ ] Driver installer is reversible and backs up SteamVR config.
- [ ] App archive validates (`xcodebuild -exportArchive`/`altool` checks) and privacy
      manifest is present.

### 10.2 Functional acceptance

- [ ] AC-1 start session — evidence.
- [ ] AC-2 both hands articulated and used — evidence.
- [ ] AC-3 all interactions — evidence per item.
- [ ] AC-4 latency within target or signed quantified limitation — evidence/report.
- [ ] AC-5 failure recovery — evidence for NF-01..NF-15 and HT-08..HT-10.
- [ ] AC-6 docs complete and new-user test — evidence.

### 10.3 Quality and stability

- [ ] 60-minute soak; no crash/leak/unbounded queues.
- [ ] Thermal degradation documented and recoverable.
- [ ] No open P0/P1 defects; P2/P3 documented with workarounds.
- [ ] Logs contain no secrets/hand data; redaction tests pass.
- [ ] Security review: pairing, replay, malformed packets, host spoofing, DoS bounds.
- [ ] Fuzz/property tests for protocol parsers pass.
- [ ] Performance report complete with raw data and analysis script.

### 10.4 Compliance and docs

- [ ] Minecraft EULA / Vivecraft LGPL / OpenVR / NVENC notices verified.
- [ ] No game/Vivecraft binaries in Git or release artifacts.
- [ ] Apple privacy strings, privacy manifest, local-network usage, encryption declaration.
- [ ] User guide: install, configure, run, troubleshoot, known limitations.
- [ ] Manual test report and evidence log complete.
- [ ] `AGENT.md` and `VERIFY.md` current; ADRs superseded where needed.

### 10.5 Final sign-off

| Role | Name | Decision | Date | Signature/commit |
| --- | --- | --- | --- | --- |
| Integration owner |  |  |  |  |
| Verification owner |  |  |  |  |
| Client owner |  |  |  |  |
| Bridge/driver owner |  |  |  |  |
| Release owner |  |  |  |  |

**Final acceptance is withheld until every AC row in §3 is `PASS` with linked evidence and all
checklist items above are complete.** A release with any `BLOCKED` acceptance row is a
prototype, not an accepted release.

---

## 11. Current verification status (snapshot)

| Area | Status | Reason |
| --- | --- | --- |
| M0 documents | COMPLETE | Committed; see EV-0001/EV-0002 |
| M1 client core/simulator | PARTIAL | Core + simulator E2E pass; secure transport, device/PC paths missing |
| Feasibility | PARTIAL | Source/architecture audit; S-01/S-02/S-03 runtime spikes not run |
| Client simulator build | PASS (scope) | EV-0003 |
| Client device hand tracking | BLOCKED | No physical Vision Pro in workspace |
| PC bridge/driver | PARTIAL | Core tests + driver syntax check pass; no Windows/SteamVR runtime evidence |
| Vivecraft session | BLOCKED | Depends on PC bridge/driver |
| End-to-end gameplay | BLOCKED | Depends on device + PC bridge |
| Latency evidence | BLOCKED | Depends on end-to-end |
| Secure transport | BLOCKED | EV-0007 |
| Release | NOT STARTED | — |

**Do not report the project as complete or accepted while this table contains `BLOCKED` or
`NOT RUN` acceptance items.**
