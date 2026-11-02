# M3c plan — black immersive on device: presentation-stage isolation (2026-11-01)

Status: **RESOLVED ON DEVICE (EV-0094 PASS).** Black-immersive root cause found and fixed (EV-0093), and the
v14 build passed the on-device visual acceptance: stereo/alignment pattern and a JIT game run rendering the
Vivecraft menu world in the immersive space with stereo aligned and head tracking, operator-confirmed.
Evidence: EV-0091 (fresh post-JNI-fix runs), EV-0092 (M3c diagnostics + simulator control),
EV-0093 (depth-clear A/B root cause). No gate is claimed until the final build is visually confirmed on
D1; M3-W3/W4 remains PARTIAL.

## 0. Operator directive (2026-11-01, recorded)

- The game ran in a visionOS **Window scene**, not in an immersive space; true VR requires the game
  output to be presented by **CompositorServices in an ImmersiveSpace**.
- Do not jump to the Info.plist preferred-scene-role route (Option 1) yet. Stage Option 2 first: keep a
  minimal startup window, add a **manual "Enter VR" trigger**, verify it on device, then make the
  automatic post-JIT open the default; keep the window/error surface as fallback; record an EV per stage.
- Confirm the game render loop is CompositorServices-driven. VRMC already does this: Minecraft renders
  stereo eye targets (Vulkan/MoltenVK), the provider exports `MTLTexture` handles, and the native
  CompositorServices renderer samples them into the drawable (the window's `CAMetalLayer` is only the
  2D launcher/game surface and is parked when immersive is active).

Implemented: manual `Enter VR` overlay button (with failure message), automatic open after
`VRMCGameStarted` (JIT proven by the game starting), audible first-frame canary, alpha-only parking
after the first presented frame + periodic re-park, willResignActive grace, scene-activation and
layer-state logging, and a no-JIT immersive selftest. Info.plist unchanged.

## 1. ROOT CAUSE (EV-0093): drawable depth clear 0.0 blacks out the immersive

- The CompositorServices drawable has a depth attachment (Depth32Float, reverse-Z: 1 = near, 0 = far).
- The known-good M3A probe (EV-0074, displays on D1) clears it to **1.0**.
- The M3b commit `1b3b73c` changed our compositor to clear it to **0.0** ("report the flat image at
  infinity"), and every device run from EV-0087 onward showed a black immersive.
- Device A/B (this work):
  - depth clear 0.0 (default until now; array API and deprecated API, clear-only and pattern) -> **black**;
  - depth clear 1.0 (probe parity, `vrmc-depth-near.flag`) -> **solid magenta/cyan visible** immediately
    (operator-confirmed), with the same command buffer, same drawable readback (bright), same shell.
- Therefore the presented content was always correct; visionOS 27.2 discarded/blacked the layer because
  of the depth clear value. Keeping 1.0 (near) is safe because the flat sampled image has no meaningful
  per-pixel depth; it never reaches the window's depth testing (separate presentation path).
- Fix: default `rp.depthAttachment.clearDepth = 1.0`; `vrmc-depth-zero.flag` restores 0.0 for A/B only.
  Regression guard: `scripts/tests/DepthClearRegressionTest.sh`.
- Important verification lesson: the **simulator displays correctly with depth 0.0**, so the simulator
  cannot be evidence for this presentation path (consistent with VERIFY §0.7); only D1 reproduced it.

## 2. What is proven (device)

- Provider/display-view path is correct: display views published/applied (Lpos/Rpos exact), per-eye
  textures bright (luma 103-154), no command-buffer failures (EV-0091, EV-0092).
- The compositor writes a bright image into the presented built_in drawable (64x64 strided readback +
  raw dumps, encNil=0, one drawable/2 views) (EV-0092).
- Known-good M3A probe displays per-eye red/green on D1 (control; EV-0093 device run).
- Depth clear 1.0 makes the VRMC immersive visible; 0.0 black (EV-0093 A/B).
- Amethyst hybrid vs pure SwiftUI is exonerated: a pure-SwiftUI device host embedding the same
  VRMCShell.framework was also black with depth 0.0, and the A/B fix applies to the same app.

## 3. Bisect matrix results (staged / executed 2026-11-01 evening)

| # | Variant | Result |
|---|---|---|
| T1 | Known-good M3A probe (pure SwiftUI, deprecated drawable API, depth clear 1.0) | **displays red/green** (control) |
| T2 | Current full app + manual Enter VR + scene logging | used for the depth A/B below |
| T3 | Minimal SwiftUI window (no launcher) + current compositor, depth 0.0 | black |
| T4 | Layered layout variant | not needed (root cause found) |
| T5 | No-device-anchor A/B | not needed (root cause found) |
| T6 | Legacy compositor + current shell | not needed (root cause found) |
| T7 | Deprecated single-drawable API + depth 0.0 | black -> the drawable API is not the cause |
| T9 | Depth clear 1.0 (probe parity) + clear-only colours | **magenta/cyan visible** -> root cause |
| T10 | Default depth 1.0 (array API) + scene logging | superseded by the accepted v14 build; visual/game acceptance PASS (EV-0094) |

## 4. Device acceptance - DONE (2026-11-01, EV-0094 PASS)

The staged v14 build was installed and run on D1:
- manual/immersive test: the eye-distinct stereo/alignment pattern displays (fusion cross, per-eye tint,
  checker border); the drawable readback proves the per-eye content (L warm, R green, centre luma ~171).
  Operator: "pattern + fusion cross + border visible, window faded".
- JIT game run: auto-immersive after VRMCGameStarted; the Vivecraft menu world renders in the immersive
  space with stereo aligned and head tracking. Operator: "the game launched successfully! the eyesight is
  aligned and it shows the game properly in immersive!". Logs: depthZero=0, mode=flat, provider eye
  textures live (luma 35-156), drawable proof luma 35-129, windows parked alpha-0, no command-buffer
  failures. The black-immersive blocker is CLOSED (root cause EV-0093).

## 4b. Independent audit (m3c-reviewer, pre-device-run)

Report: docs/analysis/m3c-review.md (no runtime blocker; depth fix and present path verified
in source and in the installed binary). Fixed before handoff: B1 per-launch log rotation +
session-scoped triage; H1 proof border on the manual test pattern; H2 complete diagnostic-flag
cleanup + pre-neutralisation capture of selftest/open-on-launch; H3 re-entry trap removed from
the operator checklist; M1 auto-retry generation; M2 deferred-open retry; M4 provider capture
can now be disabled by flag content (off); M5 preflight script + recorded build identity;
M6 self-check builds the shell framework; M7 texture-vs-view index in the format probe.
Residual MEDIUM: cancelled-frame submission contract (documented in code), device-unproven
provider sync/capture paths.

## 5. Follow-ups after visual confirmation

Headset-free regression tooling now in-repo: `runtime/probes/m3c-provider-sim/` runs the real shell +
compositor in the visionOS simulator against a fake provider dylib (real `MTLTexture`s, known pattern)
and asserts the flat sampled output orientation/layout, the `MTLSharedEvent` sync wait path, the
stereo/alignment test pattern markers and background→foreground re-entry (`run.sh`, six scenarios, all
PASS). One-command self-check: `scripts/m3c_selfcheck.sh`. Use these after any compositor/shader/bridge/
lifecycle change; they are not a substitute for device evidence for presentation or stereo.

1. **Stereo/ alignment**: flat 1:1 mapping of the provider display frustum; verify no exotropia; then
   per-eye projection parity check with the compositor diag logs.
2. **Window chrome**: verify `persistentSystemOverlays(.hidden)` with the modal game surface.
3. **Re-entry**: background/foreground reopen with the hardened shell; verify no generation-2 invalidation.
4. **Provider GPU sync**: implemented flag-gated and OFF by default (<gameDir>/vrmc-gpu-sync.flag or
   -Dvrmc.gpuSync=1): exportable timeline VkSemaphore + MTLSharedEvent signalled through MC own
   frame submission, with graceful fallback; host tests PASS (incl. real MoltenVK export), device
   path NOT RUN (see docs/analysis/provider-gpu-sync.md). The EV-0094 device build keeps the
   previous provider jar to minimise variables; stage the new jar for a later flagged sync run.
5. Eye-target PNG capture (`instances/default/vrmc-capture.flag`) for off-device content inspection.
6. **Depth semantics**: the flat sampled image is currently reported at a constant near depth (1.0) because
   0.0 blacks out the layer (EV-0093). Verify that late-stage reprojection remains stable while head-moving;
   if it does not, the correct long-term solution is to export the provider's per-pixel depth (or a depth
   estimate) into the drawable depth attachment instead of a constant clear.
6. Clean up: remove diagnostic flags from the container (clear-diagnostics already covers them), keep
   the depth regression test in the repo.