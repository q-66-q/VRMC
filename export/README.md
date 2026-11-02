# VRMC — native immersive integration (M3b) — **current state**

**Date:** 2026-11-01
**Status:** **PARTIAL (build/static validation; device run NOT RUN).** The M3b build below is signed and
installed on D1. It carries the fixes for the three EV-0086 issues plus one-run diagnostics that make the
next device session decisive and never silently black. Read this file, then run the procedure in
**"Next device run"** and record the result as EV-0088.

The M3b evidence in this folder ("evidence/EV-0087.md", "logs/m3b-*") is **build/static/simulator evidence,
not device evidence** (AGENT.md §9, VERIFY.md §0.7). The only device evidence here is the earlier EV-0086 run.

## What changed since EV-0086 (the black-screen run)

**1) The black immersive — cause narrowed to the provider eye texture (or device presentation), not the
compositor math.** We validated the exact reprojection path two ways:

- macOS Metal unit test (runtime/probes/m3b-shader-test): the shipping MSL shader + uniform layout reproduce
  the CPU ray->UV reference at 81/81 samples (max error 0.0022, linear-filter tolerance).
- visionOS-simulator probe (runtime/probes/m3b-reproj): the exact shader + drawable pass (rgba16Float +
  depth attachment, clearDepth 0.0, no rate map) present correctly (drawable readback == CPU reference at
  25/25 probes; on-screen simulator capture == drawable). Replaying the pipeline on the **EV-0086 device
  views reconstructed from the device log** maps **87.88 % of each eye inside the provider 110° frustum**,
  with **0 % behind-camera rays, 0 % NaN** and only a ~12 % outer-edge border outside (roll ±20°: 87.9–89.7 %).
  An all-black provider texture through the same shader reproduces the EV-0086 symptom exactly.

Conclusion: if the provider's eye image contains content, the immersive shows content. The remaining
explanations are (a) the provider eye texture was black/empty/unsynchronised on the device, or (b) a
device-side presentation failure. The M3b compositor makes both visible in one run:

- CPU ray->UV + per-eye 9x9 coverage diagnostics, raw projection/view matrices, per-view texture-map viewport.
- **Provider eye-texture readback** (32x32 centre of each eye every ~300 frames): mean RGB, **alpha**, luma.
  If both eyes read back black twice, the compositor switches to a **procedural test pattern** automatically.
- **No silent black:** out-of-frustum UVs clamp, behind-camera/NaN falls back to flat sampling, sampled colour
  is forced opaque (alpha=1); debug shading colours the failure branches (magenta = outside provider frustum,
  blue = behind camera, orange = NaN) via Documents/vrmc-reproj-debug.flag.
- Command-buffer health is logged (frame N command buffer FAILED/completed), so a failing present path is
  no longer invisible.
- **Mode badge:** the top ~1.5 % of the image is tinted by the active path — **red = reprojection,
  green = flat sampling, blue = test pattern** — so an operator report can name the path without pulling logs.

**2) Window chrome — architectural cause fixed.** In the simulator, WindowGroup.persistentSystemOverlays(.hidden)
*does* hide the visionOS window chrome; the preference died on device because Amethyst's game launch
**replaced the window's root view controller** with SurfaceViewController, destroying the SwiftUI
WindowGroup view. M3b patches Amethyst to **present the game surface modally over the live SwiftUI host**
(patches/vrmc-m3w3-modal-game-surface.patch), so the scene survives and the chrome preference keeps working.
Amethyst code that assumed window.rootViewController was the game surface now uses
vrmcCurrentSurfaceViewController(). Siblings fixed: input bridge, gyro/controller input, external-display,
SDL view lookup, isRunning, resolution sync.

**3) Re-entry after background — hardened.** Shell.swift now epoch-guards every awaited open/dismiss (a stale
teardown cannot kill a newer session), requires the app **and** its window scene to be foreground-active,
confirms the previous dismiss and settles before reopening, ignores stale generation notifications, and
**auto-retries up to 2x** when a layer invalidates right after opening (the EV-0086 generation-2 symptom).

## Diagnostic flags (push with devicectl, no rebuild needed)

App data container Documents/:

| Flag | Effect |
|---|---|
| vrmc-reproj-off.flag | Force the old flat fullscreen sampling (known-visible in EV-0083/84/85) |
| vrmc-reproj-on.flag | Force reprojection (skips the auto fallback) |
| vrmc-reproj-debug.flag | Colour-coded failure branches + NaN diagnostics |
| vrmc-test-pattern.flag | Always draw the procedural test pattern |
| vrmc-no-sampling.flag | Test pattern without touching provider textures |
| vrmc-legacy-root-swap.flag | Restore the EV-0086 game-launch behaviour (root VC swap, chrome preference lost) |
| vrmc-hide-chrome-always.flag | Keep the window chrome hidden for the whole launch |

Push example:

    xcrun devicectl device copy to --device <D1-UDID> \
      --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc \
      --source /tmp/vrmc-reproj-debug.flag --destination Documents/vrmc-reproj-debug.flag

## Next device run (EV-0088) — procedure

1. Install VRMC-native-m3b.app (already done via devicectl device install, data container preserved) — or
   rebuild + restage with the commands in **"Rebuild / reinstall"**.
2. StikDebug -> Assign amethyst.js -> Enable JIT -> launch **VRMC** (not from Home).
3. Launcher -> **Play** -> wait ~15 s for the auto-open.
4. Observe while the game runs:
   - **Window chrome:** is the bottom bar/windows gone in the immersive session? (Expected: yes if the modal
     presentation keeps the scene alive; if not, push vrmc-hide-chrome-always.flag and retry.)
   - **Immersive content:** visible Minecraft image, black, or a coloured pattern? If a pattern: the badge
     strip colour identifies the path (red = reprojection, green = flat sampling, blue = test pattern). If
     black with a blue badge -> provider image is black; the texture readback lines below confirm.
5. Background the app (press the Digital Crown once / look away and back), then return: does the immersive
   space reopen by itself? Expected: didBecomeActive ... reopen=true -> foreground attempt 1 result=opened,
   and VRMCImmersiveEnded generation=2 should only appear on a real end (auto-retry logs if the layer dies
   immediately).
6. Collect artefacts and record EV-0088:
   - devicectl device copy from ... --source Documents/vrmc-compositor.log --destination /tmp/m3b/vrmc-compositor.log
   - same for Documents/vrmc-shell.log and Documents/latestlog.txt; plus system crash logs.
7. Decisive lines to read:
   - [vrmc-comp] diag view 0/1 ... — conventions, d.z sign, in-frustum coverage; "... coverage 9x9: inside=...".
   - [vrmc-comp] provider tex L/R ... — provider image luma **and alpha**; if auto-fallback fired:
     "AUTO TEST-PATTERN: provider eye textures measured black ...".
   - [vrmc-comp] frame N command buffer FAILED/... completed — presentation path health.
   - [vrmc-comp] shading mode=... — and the mode badge colour on screen.
   - [shell] activity ..., immersive session opened generation=..., auto-retry n/2, ignoring stale generation ...
   - [VRMC] game surface presented modally over the SwiftUI host ... in the app log (new App window path).

## Rebuild / reinstall

    scripts/build_provider.sh                 # provider jar (verify sha) + scripts/push_provider_jar.sh to device
    scripts/build_bridge.sh                   # arm64-ios bridge dylib (vtool visionOS retag, symbol checks)
    cd runtime/native-shell && xcodebuild -project VRMCShell.xcodeproj -scheme VRMCShell \
      -configuration Debug -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO build
    # Amethyst executable (patched): replicate the Makefile native target with cmake against the iphoneos SDK
    # in a copy of vendor/amethyst-build with patches/*.patch applied, then retag the executable:
    #   vtool -arch arm64 -set-build-version 11 1.0 1.0 -replace -output <exe> <exe>
    scripts/stage_native_app.sh <path/to/VRMCShell.framework> /tmp/vrmc-bridge-build/libvrmc_bridge.dylib
    DEVICE=<D1-UDID> scripts/install_device.sh /tmp/VRMC-native-m3b.app   # update install (keeps data)

See docs/mvp/M3_PLAN.md §17 and export/logs/m3b-* for the full build/stage log and hashes.

## Build identities (installed on D1)

| Item | sha256 |
|---|---|
| App tree (485 files, dev.vrmc.vrmc, signed) | 19a7078bbfe20c04364c03fdf7aa4b0a192d85aecc1285c7d8a6fbf5e942fe26 |
| AngelAuraAmethyst executable (signed) | 52880363be47c1142466e8177691704fe1917ce31aba5179ff1e55a4d14b2e5e |
| Frameworks/VRMCShell.framework/VRMCShell (signed) | 4880ab19e2bf2b2e4cf124e1e6026e877a03e31d39aa5b41662b7a667e24e2ef |
| Frameworks/libvrmc_bridge.dylib (signed) | b7af2c77206670e3962968d25f3e2eb020a181311f91a9c9fb6b7abb7c2186f1 |
| provider jar (Documents/instances/default/mods/vrmc-provider.jar, byte-identical to EV-0086) | 80ea3a757243e5eacfe655eb75d397b9bacdda80c3b98fea652edd7262e1f9ea |

## What already works (unchanged since EV-0086)

| Item | Evidence |
|---|---|
| Native visionOS launcher builds/runs; launcher UI + Play | EV-0079 |
| SwiftUI app-lifecycle shell hosts the launcher and opens ImmersiveSpace/CompositorLayer | EV-0081 |
| Game-start auto-open (15 s), game survives, no Vulkan device-loss | EV-0083 |
| Compositor samples provider eye textures (eyes=1) and feeds ARKit tracking to the provider | EV-0083/84/85 |
| Window content parking; clean compositor exit on background; re-entry lifecycle (generation 2 opens) | EV-0084/85/86 |
| Compositor reprojection math + pass setup validated on Metal and in the simulator | EV-0087 |
| Signed M3b app built and installed on D1 | EV-0087 |

## Open issues to be decided by the next device run

1. **Black immersive** — provider eye image black/unsynced vs device presentation; the texture readback,
   command-buffer log, mode badge and auto test-pattern distinguish them in one run.
2. **Window chrome** — expected fixed by the modal game-surface presentation; A/B with
   vrmc-hide-chrome-always.flag / vrmc-legacy-root-swap.flag.
3. **Re-entry** — expected fixed; auto-retry protects the gen-2 invalidation case.
4. Stereo alignment / exotropia — only judgeable once content is visible; the CPU diag + badge path will
   show whether reprojection or flat sampling is active.

## Evidence / logs

- evidence/EV-0087.md — build/static validation entry (EV-0087; full VERIFY.md entry recorded).
- logs/m3b-shader-test.log, logs/m3b-reproj-summary.txt — Metal + simulator validation summaries.
- runtime/probes/m3b-reproj/results/report.md (full probe report), results/m3b.log, results/summary.txt.
- evidence/EV-0086.md, logs/*fixes-run.log, evidence/EV-0083/84/85.md — earlier device evidence.
- export/patches/vrmc-m3w3-modal-game-surface.patch — the Amethyst modal game-surface patch.
- export/VRMC-immersive-integration-blocker-2026-11-01.zip — this dossier (updated for M3b).


## Alignment fix staged (EV-0088) + recovered M3b device logs (EV-0089)

After the macstream reference analysis (VERIFY.md Phase 8 root causes 3+4: eye matrices must be
head-relative, and the provider must use the client's asymmetric per-eye FOV with cached-projection
invalidation), VRMC now has a display-view channel:

- compositor publishes `cp_view_get_tangents` + `cp_view_get_transform` + measured IPD to the bridge,
- provider renders the display frustum and sets head-relative eye matrices, invalidating cached
  projections (NaN farClip, as macstream 43981c8),
- compositor uses flat 1:1 eye-texture mapping once views are published (EV-0086 black reprojection
  branch bypassed).

Offline: `scripts/test_display_views.sh` PASS (lopsided device views + symmetric fallback), bridge stub
display-view roundtrip PASS, provider compiles; app/bridge/provider built+installed (device run pending).

A recovered M3b device session log (14:41 local) shows the provider eye textures were **valid non-black
content** (L mean RGB 83/108/51, R 78/100/48; 1024/1024 non-black, alpha 255), the first command buffer
completed, and chrome/windows were parked/hidden; the session backgrounded before a visual alignment
check. So EV-0086's black screen was compositor reprojection/presentation, not provider content.
