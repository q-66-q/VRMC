# VRMC M4-W1 — Immersive Input On-Device Acceptance Report

**Status: PASS for the M4-W1 input slice (operator-confirmed on Apple Vision Pro).**
**Report date:** 2026-11-01 (evening, Pacific/Honolulu) · **Prepared by:** VRMC Lead (agent session)
**Test type:** device acceptance, operator session on physical Apple Vision Pro (D1)

| Field | Value |
|---|---|
| Device under test | Apple Vision Pro `RealityDevice14,1` (N301AP), visionOS 27.2 |
| Build host | MacBook Pro `Mac16,7`, macOS 27.0.1, Xcode 27.2 |
| Application under test | VRMC `dev.vrmc.vrmc` 1.2.0, signed staged bundle `VRMC-native-m4-input.app` (bundle tree sha256 `102c0e55ad05315cdfa005504c0385b542ea9a407a7cb99d66b3c54dffd21b1c`) |
| Provider mod | `vrmc-provider.jar` sha256 `94cfe0d9b7b1855431d33e29e597a5258a5205a88f427e76d731a77fb5e084bd` (M4, bridge ABI v3) |
| Source commit | `b352d84` (feature), `b4692ea` (test evidence/report); git tree clean |
| Evidence entry | `VERIFY.md` **EV-0096** (device); supporting host+simulator entry **EV-0095** |
| Evidence bundle | `evidence/EV-0096/` (10 hashed artifacts) + `evidence/EV-0095/` (21 hashed artifacts) |

## 1. Objective

Verify the reported defect: *while the game is running, the user can only control it from the 2D window;
the immersive scene accepts no input.* Acceptance requires the game to be controllable **from inside the
immersive scene with the headset's real hand tracking**, while immersive presentation (stereo + head
tracking) continues to work.

## 2. What was delivered for this test

M4-W1 adds the missing input path end-to-end:

~~~
ARKit 27-joint hand tracking -> bridge ABI v3 input snapshot (752 B, per frame)
  -> provider gesture engine (pinch/fist, hysteresis, arming, stale release, chord priority)
  -> Vivecraft action bindings (GUI click / attack / use / teleport / menu / inventory)
  -> game (MCVR/GuiHandler) ; while the compositor keeps presenting the stereo image
~~~

- Bridge ABI v3: `vrmc_hand_state`/`vrmc_input_state`, `vrmc_poll_input`, native-shared publish/acquire,
  JNI `nativePollInput`, safe-zero state, zeroed release-on-exit, fail-closed ABI mismatch.
- Compositor: ARKit hand tracking in the same session as world tracking, explicit hand-tracking
  authorization, per-frame publication at the trackable-anchor time, synthetic diagnostic mode
  (`vrmc-input-sim.flag`) for headset-free verification, rate-limited logs.
- Provider: continuous controller pose from the 27 joints (`R*(0,0,-1)=aim`) with gaze/shoulder
  fallback, pinch/fist gesture mapping, action-set gating, no-stuck-input safety invariants,
  `VRInputAction.isEnabled` Mixin (Vivecraft itself remains unmodified).

## 3. Test procedure (executed on D1)

1. Installed the signed M4 app over the previous build (game data container preserved) and pushed the
   M4 provider jar (SHA-256 round-trip verified on device).
2. **Step 1 — synthetic plumbing run (no hands required):** enabled `vrmc-input-sim.flag=cycle`, launched
   VRMC through StikDebug with JIT, pressed Play, waited for the automatic immersive open, ran two full
   gesture cycles, quit; pulled all logs.
3. **Step 2 — real hands:** cleared diagnostic flags (deletes the synthetic flag at app startup),
   relaunched through StikDebug/JIT, **allowed the hand-tracking permission prompt**, used real hands in
   the immersive scene (right pinch, fists, both fists), quit; pulled all logs.

## 4. Results

| # | Criterion | Result | Key evidence |
|---|---|---|---|
| 1 | M4 build and provider ABI v3 actually running on device | **PASS** | `bridge handshake ok (ABI 3)`, `input channel ready (caps {\"abi\":3,…})`, 12/12 binding rows over 10 actions |
| 2 | Immersive scene receives ABI v3 hand input | **PASS** | `input publish … valid_mask=3 source=synthetic` (Step 1) and `source=arkit` with real-valid-mask transitions (Step 2) |
| 3 | Real hand tracking authorized and live | **PASS** | `hand tracking authorization: … status=allowed`; `ARKit session started … provider=started authorization=allowed inputMode=arkit`; continuous real wrist/aim `pose:` logs |
| 4 | Gestures dispatch to Vivecraft actions | **PASS** | **120 action-dispatch lines** per step (`guiLeftClick`, `guiShift`, `guiRightClick`, `ingameMenuButton`, `key.inventory`, `key.attack`); both-fist chord produces only `key.inventory`; action-set gating switches GUI↔INGAME correctly |
| 5 | No stuck input on tracking loss / session end | **PASS** | hand `lost` → same-frame release; provider `input stale … all actions released`; compositor release snapshot `valid_mask=0` before session stop |
| 6 | Presentation unchanged in immersive mode | **PASS** | 6144 presented frames, windows parked alpha-0, immersive scene foreground-active, background→foreground re-entry (generation 2) |
| 7 | Operator experience with real hands | **PASS** | Operator statement: **“It ran very well!”** — the game was controllable from the immersive scene |

**Conclusion for the reported defect: FIXED and operator-confirmed on device.**

## 5. Defects / open items (not blocking this acceptance)

1. **Shutdown JVM SIGSEGV (recorded follow-up defect).** Reproduced on both device runs: after
   `[Minecraft] Stopping!` the JVM reports a SIGSEGV in a native Foundation thread (`objc_retain`); the
   faulting register equals a provider eye `MTLTexture` handle exported earlier in the same run
   (e.g. `0x7225e35900`). The host app survives and backgrounds normally; all input verification
   completed before the crash. Most likely an M3 eye-texture lifetime/teardown race, unrelated to the
   M4 input channel. Triage/fix is scheduled before any stability claim.
2. **Full hands acceptance not run.** This test covers the M4-W1 input slice; the complete P0 hands
   checklist (locomotion beyond look/pinch teleport, jump, sneak, hotbar, bow, climbing, full menu
   inventory interactions) remains `NOT RUN` (AC-4 / ST-S5-hands).
3. **Operator-requested W2 refinements:** smooth/filtered continuous hand pose (threshold tuning;
   device data showed a fist engage at ratio 1.24 vs the 1.25 threshold — margin too small) and
   **gaze highlight + pinch selection** using visionOS 26 CompositorServices tracking areas + automatic
   hover effect + `onSpatialEvent` tracking-area identifiers. Design recorded in
   `docs/analysis/gaze-and-hand-input.md`.

## 6. Evidence and reproducibility

- **EV-0096 (device):** `VERIFY.md` §6 — includes procedure, exact log lines, defect note, limitations;
  hashed artifacts in `evidence/EV-0096/` (Step-1 and Step-2 compositor/shell/game logs + M4 extracts +
  operator-session notes).
- **EV-0095 (host + simulator):** bridge/ABI v3 layout + TSan concurrency tests, cross-language C→Java
  fixture (`50926fdc…` / `43d52113…`), provider JVM tests (layout 68 / gestures 157 / pose 61 /
  fixture 61 checks), visionOS-simulator input publication scenario, one-command selfchecks; independent
  verifier report `docs/analysis/m4-input-verification.md` (no open BLOCKER/HIGH).
- Reproduce: `scripts/m4_input_selfcheck.sh` and `scripts/m3c_selfcheck.sh` (host+simulator); device
  procedure and staging in `docs/mvp/M4_DEVICE_RUN.md`.

## 7. Limitations / evidence class

Device evidence for the M4-W1 input slice only. Operator reports are informal (no recording); immersive
stereo optics were previously accepted in EV-0094 and were not re-measured here; frame pacing, thermal
behavior, latency, and the full action checklist were not measured. The simulator is not evidence for
hands/gaze behavior (VERIFY §0.7).

## 8. Recommendation

**Accept M4-W1 (immersive-scene input) on device:** the reported defect is fixed and operator-confirmed
with real hands; host+simulator plumbing is independently verified. Before M4 exit, fix the shutdown
SIGSEGV and complete the full hands checklist; build the operator-requested W2 gaze-hover + pinch
selection and hand smoothing next.
