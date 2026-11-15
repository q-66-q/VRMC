# Render bugfix — sub-1 s purple flash on immersive menu/pause screens (EV-0295..EV-0297)

Status: **diagnosis + instrumentation; no visual-behaviour change.** Owner: render-investigate (task-7).
Worktree: `claude/project-overhaul-bugs-features-ui-c2719a`, release commit `8e85dc8`.
Scope: `runtime/native-shell/Sources/VRMCCompositor.mm` (changed) + this document.
Provider/Vivecraft content and `Shell*.swift` are out of scope for this task.

## TL;DR

The flash **cannot be reproduced or explained by the 1.3.3 release compositor path**. The M8
sessions where the operator reported it had **no developer surface on screen** (all diagnostic
flags 0, no procedural test pattern ever activated), so the standing "diagnostics pattern" theory
is **wrong for those sessions**. The only rendering change that lines up with the first report is
the **hardware sRGB texture view** ("after the colour correction"), whose M8 implementation had a
stale-view hazard that the 1.3 checkpoint has already hardened. Without a device A/B the remaining
candidate cannot be confirmed, so this pass adds **release-neutral instrumentation** plus a
defensive cache-key tightening (no image change on a correct path) so the next D1 run can prove or
exonerate a compositor texture-view bug. This is the 1.3.4 path: keep the release gating (which
provably closed the *real* pre-1.3 pattern flashes), do not guess a visual fix.

**Status 2026-11-11:** the instrumentation is in the 1.3.4 build and **verified live** on the first
1.3.4 device run (device-verify, 37 s headless): 5/5 eye-texture swaps logged (1.3.3 logged 1 of 11),
10/10 sRGB views rebuilt with the correct sizes, **no stale view sampled**, release surfaces off,
grace intact. The run did not open a pause/inventory screen, so it neither reproduced nor explained
the flash — the capture hook is armed for the next observation session (see §"1.3.4 verification"
and the D1 checklist).

## Evidence sources

| Source | What it is | Used for |
|---|---|---|
| `/tmp/vrmc-t2-pull/` (2026-11-11 19:24–19:28) | user's **1.3.3 release** run: `vrmc-compositor.log`, `latestlog.txt`, `vrmc-shell.log` (**volatile**: device `*.prev.log` rotation will overwrite the source on the next launch) | release-path proof |
| `evidence/device-1.3/logs/1.3.3-release-run/app-data/` + `ANALYSIS.md` + `sha256sums.txt` (worktree; pulled by device-verify 2026-11-11) | **preserved copy** of the same 1.3.3 run (compositor `0a4020ca…`, latestlog `1dd2dd5a…`, 83-row trace `0a227bc7…`), incl. the full launch/VR-entry/pause timeline and the framework-strings evidence | timing bound + long-term evidence |
| `evidence/device-1.3/logs/prior-1.3.0-run/` (worktree) | previous 1.3.0 release run | corroboration |
| `/Volumes/Untitled/Projects/VRMC/evidence/EV-0293..EV-0297/` (main checkout, read-only) | the **actual M8 device-run pulls**: compositor logs, shell logs, frame trace, status, and `EV-0297/final-device-summary.log` with the operator statement | M8 timeline + rule-outs |
| `VERIFY.md` EV-0293..EV-0297; `docs/mvp/M8_DEVICE_RUN.md` | recorded results | cross-check |
| `runtime/native-shell/Sources/VRMCCompositor.mm` at `31bd21b` (M8 build) and at `8e85dc8` (1.3.3) | the two compositor versions | code-path analysis |

## Timeline

### M8 device run, 2026-11-07 (the sessions in which the bug was recorded)

| EV | build | dev surfaces (compositor log) | procedural pattern | operator flash report |
|---|---|---|---|---|
| EV-0293 | pre-sRGB | all flags 0 | **shown at immersive open** (2 `TEST PATTERN state changed` lines) | no statement collected |
| EV-0294 | pre-sRGB | all flags 0 | **shown at immersive open** (2 state changes) | no statement collected |
| EV-0295 | first hardware **sRGB texture-view** build (dirty compositor) | `forceTestPattern=0 presentProof=0 clearProbe=0 selfTest=0` | **never active** (0 state-change lines, 0 AUTO TEST-PATTERN) | **purple flash first reported** |
| EV-0296 | sRGB + sharpening + right-fist | same, plus leftover `dumpRaw=1` (GPU readback flag, invisible) | **never active** | flash persists |
| EV-0297 | same as 0296 | — | — | recorded as known cosmetic bug |

The operator statement recorded in `evidence/EV-0297/final-device-summary.log` is explicit:
"brief (<1 s) purple-ish flash on immersive menu/pause/inventory screens, **after the colour
correction**; cannot be captured on demand; recorded as a cosmetic bug, not a blocker."

Consequences:

1. The flash was **not** the procedural test pattern / mode badge / clear-probe: in EV-0295/0296 the
   pattern was never drawn (zero `TEST PATTERN state changed` lines) and `clearProbe/presentProof/
   selfTest/forceTestPattern` were all 0. The 1.3 checkpoint note "two immersive opens showed the
   test pattern for 715 and 320 frames" is consistent with **EV-0293/0294**, i.e. sessions where the
   flash was *not* reported. The 1.3 release gating is still correct and must stay (it removed a
   real, operator-visible pre-1.3 artifact), but it is not the purple-flash fix.
2. The flash **is temporally tied to the sRGB texture-view colour correction** (EV-0295 is the first
   build containing it; the operator says "after the colour correction"). That is the only
   rendering-path change in the window.

### 1.3.3 release run (/tmp/vrmc-t2-pull, 163 frame diagnostics, 19,517 presented frames)

- `diagnostics: … forceTestPattern=0 presentProof=0 clearProbe=0 … diagnosticsEnabled=0` — every
  developer surface is release-gated **and off**; no diagnostics flag file present.
- **Zero** `TEST PATTERN state changed`, `AUTO TEST-PATTERN`, `CLEAR-PROBE`, `PRESENT-PROOF` lines;
  zero `AUTO TEST-PATTERN` latch (which in the M8 build could have replaced the game for the rest of
  a session).
- All 163 periodic frame lines: `eyes=1 … presented=1 encNil=0 nilColor=0 layerState=2` — every frame
  had valid eyes, a valid encoder and a non-nil colour attachment; no invalid-pass clears.
- All 11 provider eye-target rebuilds: `eyes absent: reusing the last sampled eye frame for up to
  270 frames` → `eye frame resumed after 2–7 frame(s)`. The release path held the last good frame
  and **never drew a pattern or a coloured clear**.
- `color: sRGB->linear ON`, view applied (`provider fmt=70 -> view fmt=71`), 7 sharpening lines, no
  colour-path warning.
- `latestlog.txt`: only `Missing texture references in model vivecraft:item/spyglass_in_hand` /
  `climb_claws` (item **models**, not the GUI atlas); the gui atlas loads cleanly. No evidence of a
  magenta missing-texture checker on any menu screen.

So on 1.3.3 the compositor output can only be (i) the sampled provider image, (ii) the retained last
frame during a rebuild gap, or (iii) black after the 270-frame grace. **It cannot paint purple.**
If the flash still occurs on a release build it is either provider/game content (Vivecraft in-world
GUI/menu path) or a stale-texture-view event that this pass instruments.

### 1.3.3 timing bound (device-verify's preserved pull + ANALYSIS.md)

The preserved copy adds the launch timeline needed to bound the flash in this run:

- VR was entered **manually** at 19:25:08 while the Vivecraft **MenuWorld/TitleScreen** was up
  (`menuRoom=1 screen=TitleScreen`). Provider eye-target rebuilds **#1 19:25:08 → #4 19:25:22** =
  **4 texture swaps in the first 14 s of immersive**, while the world loaded.
- The **pause screen opened at 19:28:38** (`screen=PauseScreen`), i.e. **20 s after swap #11
  (19:28:18) and no swap followed it** in this run.
- The installed 1.3.3 framework is the **old** compositor: it contains "provider eye textures
  changed" but **not** "sRGB view rebuilt", and its swap log is gated on the broken
  `texture_generation` counter, so it prints exactly one swap line (publish=141) despite 11 real
  rebuilds. The rest of this run therefore cannot confirm/deny a swap-correlated flash — exactly what
  the new instrumentation fixes.

Consequence for triage: if the operator saw the flash **on VR entry / the menu/title screen**, the
#1-#4 window is compatible with the sRGB/texture-swap class. If it was seen **on pause**, this run
gives no swap nearby — that points to content-side (Vivecraft in-world GUI/postprocess) rather than
the compositor texture path. Capture the operator's **exact moment** (VR entry vs pause vs inventory)
on the 1.3.4 run; it splits the remaining candidates cleanly.

### 1.3.4 verification — instrumentation live and clean (device-verify headless run, 19:57:48–19:58:54 HST)

Evidence: `evidence/device-1.3/logs/1.3.4-release-run/` — compositor log `89da3e4a…`,
`VERIFICATION.md` `e4a2854b…`, status `adeb556b…` (`sha256sums.txt`). 37 s in VR; the user
backgrounded the app with the game running, so this is a **no-flash-observation** run (no pause /
inventory screen was opened; the only menu moments were VR entry at the MenuWorld/TitleScreen and
world join).

What the new code proved on device:

- **Instrumentation is in the staged build and works**: `provider eye textures changed` ×5 — initial
  publish (publish=56, handles `0x0->0x72289b2300 / 0x0->0x72289b2080`, 1024×1024) then 4 eye-target
  resizes 3136×2512, 2512×2016, 1880×1512, 2512×2016 (status `resizes=4`). The 1.3.3 build printed
  **1** swap line for 11 rebuilds; this run prints exactly one per swap.
- **sRGB view follows every swap**: `color: sRGB view rebuilt` ×10 = L/R × 5 publishes; view size
  always equals the new provider target; no view-creation failure line.
- **No stale view was sampled**: all 8 post-swap views report `previousViewOtherTexture=1` — that is
  the **expected cache-replacement case** (the previous view belonged to the texture the swap line
  just replaced; `previousHandle` equals the old handle, and the new view is created and cached
  *before* the draw that samples it). Only the two initial views are `=0` (`previousHandle=0x0`).
  There is no swap whose eye had a missing rebuild before the next draw, and no rebuild with an
  unchanged handle.
- **Release behaviour unchanged**: `diagnosticsEnabled=0`, zero `TEST PATTERN state changed`, no
  nil-drawable/encoder lines, `errors=0` in all 27 render-feedback lines,
  `presentedFrames=3285 framesWithoutDrawable=0 framesWithoutEncoder=0`; 4 resize gaps each held the
  last frame (age=1) and resumed after 2–6 frames.

Interpretation (field semantics, so future logs are read correctly): in this code
`previousViewOtherTexture=1` is **normal** on a swap (`previousHandle != new handle` and a view was
cached). A **stale-view hit** would be either (i) a `provider eye textures changed` line after which
the next draw for that eye has **no** matching `sRGB view rebuilt` line, or (ii) a rebuild whose
`previousHandle` equals the new `handle`. Neither occurred.

Still open: **no flash was observed** in this short run because no pause/inventory screen was opened.
The instrumentation is armed for an observation session; the decision tree below applies once the
flash is reported (with the operator's exact moment).

## Ruled in/out

| Candidate | Verdict | Evidence |
|---|---|---|
| (a) clear-probe / diagnostics clears (magenta left, cyan right) | **RULED OUT** for the reported sessions and for 1.3.3 | flags are 0 in EV-0295/0296 and gated + 0 in the 1.3.3 release log; no `CLEAR-PROBE` line |
| (b) sRGB/linear stale texture / texture-view switch | **LEADING REMAINING CANDIDATE, unconfirmed** | first report in EV-0295, the first sRGB build; operator says "after the colour correction". M8 code had one shared `gSrgbColorGeneration` and no handle check, so a stale view was possible in principle. 1.3 already hardened it (per-eye generation + handle guard). No stale-view line in the 1.3.3 log (the old one-shot log cannot show it — see instrumentation). |
| (c) Minecraft missing-texture magenta checker | **NOT SUPPORTED** | no GUI-atlas missing sprites in any retained log; only item-model warnings. Low likelihood; the game/Vivecraft GUI path stays a live alternative if the flash recurs without any compositor swap event. |
| (d) sharpening on a resizing texture | **RULED OUT as the necessary cause** | flash present in EV-0295 where `sharpen=0.00` (the pass was not selected at all); sharpening is a monotone local-contrast filter in linear space and cannot tint purple |
| (e) clear colour while eyes are invalid | **RULED OUT** | M8 invalid-pass clear colours are red (left) / green (right), not purple; release clears black; 1.3.3 has `nilColor=0 encNil=0` on every frame |
| (f) procedural pattern / mode badge (pre-1.3 unconditional) | **REAL pre-1.3 artifact, NOT the reported flash** | active in EV-0293/0294 (no flash report), never active in EV-0295/0296 (flash reports); fixed by 1.3 release gating — keep it |
| (g) provider publishes eye handle before GPU finishes writing (no sync; `vrmc-gpu-sync.flag` off) | **possible tear source, not purple-specific** | `syncValid=0` in all sessions; out of compositor scope; noted for the provider teammate |

## Chosen deliverable: instrumentation + defensive cache-key tightening (no visual change)

Files changed: **only** `runtime/native-shell/Sources/VRMCCompositor.mm`.
Baseline (release `8e85dc8`) sha256 `9defcec546e1ef4693d03c76bba178ccfb69aac9c89a8754f9c8985cb3e9e936`;
after this pass `45ae88df64afcf12d5ae10e391bc1fbbebb86e8c18d7e3543af9d6564ce93b98`
(+79/−13 lines, 3 hunks). All flags, knobs and the ABI are untouched.

1. **Reliable eye-texture swap logging** (line ~2670). The old line keyed on
   `eyeFrame.texture_generation`, but the bridge's `vrmc_shared_clear_eye_textures()` resets
   `texture_generation` to 0 before each provider rebuild and the next publish sets it back to 1 —
   so only the first swap was ever logged. The M8 device logs show 15 provider rebuilds but a single
   generation line. Now the compositor logs **every** per-eye handle change:
   `provider eye textures changed: generation=… publish=… L=0x…->0x… R=0x…->0x… size=WxH (…)`.
   This is the timeline needed to correlate a flash with a texture swap; it also makes the existing
   A7 device-checker line count match the provider's resize count.
2. **sRGB view cache hardening + per-swap logging** (line ~3020). The cache validity test now also
   requires the cached view's pixel format and extent to match the current texture (handle equality
   remains the primary key). This cannot change the correct path — it can only reject a view that is
   provably not the texture being sampled. Every rebuild is logged (bounded to 64 lines):
   `color: sRGB view rebuilt L|R handle=0x… fmt=… WxH gen=… previousHandle=0x… previousViewOtherTexture=0|1`.
   `previousViewOtherTexture=1` would be direct evidence of the stale-view mechanism.
   A failed view creation (falls back to no gamma decode) is logged once.
3. **Diagnostics-only drawable probe right after a swap** (line ~3140). Behind the existing
   `vrmc-diagnostics.flag` (nothing in release), the drawn-drawable probe now also runs on the first
   3 frames after an eye-texture swap, instead of waiting for the 300-frame cadence. With
   `vrmc-drawable-dump.flag` it also writes the raw 64×64 images. This captures the exact frames
   where a texture-view/format switch could flash: the next D1 run answers "is the purple frame in
   the compositor's drawn output, and which swap produced it?" from the logs alone.

### Risk analysis

- **Release path unchanged**: (3) is gated by `diagnostics`; (1)/(2) add only log lines at texture
  swaps (a handful per session), no allocation, no GPU work, no draw change.
- **(2)** only makes the cached-view condition stricter on a path that must already recreate the view
  whenever the handle changes; on a correct path `cachedViewStale` is always false. No regression of
  immersive colour/sharpening (the added `newTextureViewWithPixelFormat:` calls only occur where the
  previous code also called them, plus at most a no-op rebuild when format/extent mismatches).
- **No ABI/symbol changes; no flag or knob semantics changed.** Host syntax check PASS
  (`xcrun --sdk xros clang++ -fsyntax-only …, visionOS 27.2 SDK`, only pre-existing warnings).
- Cannot regress the shell/provider: the two other scopes are untouched.

## What must be verified on D1 (1.3.4 build)

0. **Staging identity check (device-verify)**: the 1.3.3 framework (`bb243f24…`) has the old
   compositor — it contains "provider eye textures changed" but **not** "sRGB view rebuilt".
   Before the 1.3.4 run, verify the staged framework binary contains **both** new strings
   (`strings … | grep 'sRGB view rebuilt'` and `grep 'previousHandle='`); if not, the new
   instrumentation is not in the build and items 2-4 are void.
1. **Build/smoke**: shell framework builds; immersive session opens, colour/sharpening unchanged,
   90 Hz pacing unchanged; no new warnings.
2. **Swap log coverage**: `grep 'provider eye textures changed' vrmc-compositor.log` should appear
   roughly once per provider `eye target resize #N` (e.g. 11 for a fresh session) — this is the
   logging fix working; previously it showed 1.
3. **sRGB view follows the texture**: one `color: sRGB view rebuilt` per eye per swap; view
   size must equal the provider target. `previousViewOtherTexture=1` is **EXPECTED** on normal swaps
   (cache replacement — confirmed on 1.3.4: 8/8 post-swap views, previousHandle == the replaced
   handle); only the first lifetime views are `=0`. A **stale-view hit** is: a swap line whose eye
   has **no matching rebuild before the next draw**, or a rebuild with `previousHandle == handle`
   — if seen, send the log lines to render-investigate for a targeted cache fix.
4. **Reproduce the flash** on menu / pause / inventory open a few times, and **record the exact
   moment** (VR entry/title screen vs pause vs inventory — see the 1.3.3 timing bound above). Then:
   - flush observed **and** a `provider eye textures changed` / `sRGB view rebuilt` line within the
     preceding ~1 s → compositor texture-view path implicated; the diagnostics `drawable proof`
     mean/max lines from (3) plus `vrmc-drawable-dump.flag` raw images give the failing pixels.
   - flush observed with **no** nearby swap/rebuild line (e.g. on pause as in the 1.3.3 run, where
     the pause screen was 20 s after the last swap) → compositor release path exonerated; the
     content is provider/game (Vivecraft in-world GUI/menu path) — hand to the provider teammate.
5. **Capture protocol**: a diagnostics capture needs `Documents/vrmc-diagnostics.flag` (+ optional
   `vrmc-drawable-dump.flag`) pushed **with Lead sign-off** and removed afterwards; the release
   path must be re-checked with them off (no pattern/badge/probes in the log). **Preserve the pull**
   in `evidence/device-1.3/logs/1.3.4-release-run/` with `sha256sums.txt` as device-verify did for
   1.3.3 — the device rotates `*.prev.log` on the next launch.

## 1.3.4 release-note wording (recommended)

"A sub-1 s purple flash was previously seen on immersive menu/pause screens in pre-1.3 M8
diagnostic-build sessions (EV-0295..EV-0297). It has not been observed in 1.3.3/1.3.4 release-mode
runs (1.3.3: no diagnostics surfaces active, 19,517 frames with valid eyes and no invalid-pass
fills; 1.3.4: 3,285 frames, 4 eye-target rebuilds, no stale texture view). The sRGB texture-view
path and every eye-texture swap are now logged, with a diagnostics-only drawable capture on the
frames after each swap; if it is reported again, the session's logs pinpoint the exact swap and
pixels, or exonerate the compositor path."

## Explicitly NOT done

- No visual fix / no change to sampling, sRGB decode, sharpening, grace length or clear colours:
  none can be justified without a device A/B, and the 1.3.3 release logs show no compositor-origin
  purple frame.
- No compositor-owned copy of the last good eye frame for the resize grace (candidate follow-up:
  removes any provider-texture lifetime hazard during a rebuild, but adds a per-resize GPU copy —
  only worth it if the swap instrumentation implicates the grace window).
- Provider/Vivecraft GUI path not touched (provider teammate's scope).
