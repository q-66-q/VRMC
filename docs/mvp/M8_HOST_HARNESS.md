# M8 host Fabric harness — provider render-feedback → eye-target resize (desktop GL)

**Evidence class:** **host only.** This runs the real M8 provider inside a real Minecraft 26.2 + Fabric +
Vivecraft client on the Mac build host (desktop OpenGL backend) and feeds it **fake** compositor display
feedback through the real native-shared bridge channel. It validates the provider-side code path; it is
**not** device/visionOS evidence for eye-tracked foveation, Vulkan/MoltenVK, optics, 4K or refresh rate.
Device rows A6–A9 remain [M8_DEVICE_RUN.md](M8_DEVICE_RUN.md).

## 1. What it proves

The CompositorServices compositor publishes a 68-byte `vrmc_render_settings` payload (per-eye logical
display size at the current render quality, physical foveated drawable, foveation/rate-map state,
quality, measured display cadence). The provider must, inside a live Minecraft client:

1. initialize normally at its default eye target (1024×1024) when no display feedback exists yet
   (`[VRMC-M8] render settings: none published yet` … `keeping 1024x1024`);
2. poll the payload per rendered frame, parse it and apply the eye-scale policy;
3. resize the stereo eye targets from the display logical size — `1024x1024 -> 1832x1600` (0.50 auto
   scale of 3660×3200) — through Vivecraft's render-target reinit path
   (`Vivecraft: Reinit Render: VRMC M8 eye target 1832x1600`, `VR Provider supplied texture resolution:
   1832 x 1600`, `VR target: 1832x1600 [2.9MP]`);
4. keep rendering without M8 exceptions; the auto eye-scale controller then ramps only when the host
   actually shows headroom — the reproducible script run observed
   `resizes=1 scale=0.50 → resizes=2 scale=0.60 (2200x1928) → resizes=3 scale=0.70 (2568x2248)`
   at the 240-frame evaluation cadence, i.e. the resize rate limit and the ramp both work;
5. hold the scale in the dead band when the host's measured frame pacing does not prove the target
   cadence — the first manual run (slower GL pacing) correctly stayed at 0.50 with `resizes=1`.

This de-risks the provider half of device row A7 (4K-class display path → provider eye targets follow
it) before the headset session. The compositor half (foveation, rate maps, physical drawable, measured
cadence) is device-only; the foveation sampling math is separately validated on host Metal by
[`runtime/probes/m8-foveation`](../runtime/probes/m8-foveation/README.md).

## 2. How to run

Requirements (none committed to the repo):

- the external Vivecraft 26.2 multiloader reference tree (Gradle project) at `VIVECRAFT_REF`;
- JDK 25 (default `/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home`);
- a built M8 provider jar `/tmp/vrmc-provider-build/vrmc-provider.jar`
  (`scripts/build_provider.sh`);
- Gradle caches or network for the reference project.

```bash
VIVECRAFT_REF=/path/to/VivecraftMod-Multiloader-26.2 scripts/m8_host_harness.sh
# optional M8 target-cadence knob exercised in the same real client (provider re-reads it every ~300 frames):
VIVECRAFT_REF=/path/to/VivecraftMod-Multiloader-26.2 TARGET_HZ=100 scripts/m8_host_harness.sh
# optional M8 content-first knob (provider logs the mode it read):
VIVECRAFT_REF=/path/to/VivecraftMod-Multiloader-26.2 CONTENT_FIRST=on scripts/m8_host_harness.sh
# optional simulated display cadence: exercises the target-cadence guardrail (TARGET_HZ > DISPLAY_HZ
# must log "unreachable ... reverting to auto"):
VIVECRAFT_REF=/path/to/VivecraftMod-Multiloader-26.2 DISPLAY_HZ=90 TARGET_HZ=120 scripts/m8_host_harness.sh
# options: --timeout <seconds> (default 240), --keep-running (leave the dev client up)
```

The script is idempotent and:

1. builds a **host test bridge dylib** from the real bridge sources plus
   `bridge/tests/host_render_settings_publisher.c` — a constructor-gated publisher that (when
   `VRMC_HOST_TEST_RENDER_SETTINGS=1`) waits for the game to boot and then publishes 3660×3200 logical /
   2412×2108 physical / foveation=1 / 120 Hz display feedback every 16 ms. It is never compiled into the
   device bridge;
2. patches the reference tree's `:fabric:runClient` run config with
   `-Dvrmc.hostHarness=true -Dvrmc.bridge.lib=<host test dylib> -Dfabric.addMods=<provider jar>`;
3. writes `fabric/runs/client/config/vivecraft-client-config.json` with `vrEnabled=true` and
   `stereoProviderPluginID=OPENVR` (the provider Mixin substitutes `VisionVR` for `MCOpenVR`);
4. runs `:fabric:runClient` and waits for the resize evidence line, prints the decisive lines, then
   stops the client. Exit 0 PASS / 1 FAIL-or-timeout / 2 setup error.

Artifacts: `/tmp/vrmc-m8-host-harness/harness.log` and `latest.log` (the Minecraft log).

## 3. Expected decisive lines (from the first run, EV-0272)

```
[VRMC-M2] provider redirect; original=org.vivecraft.client_vr.provider.openvr_lwjgl.MCOpenVR
[VRMC-M2] bridge handshake ok (ABI 3)
[VRMC-M2] VisionVR.init() succeeded
[VRMC-M8] render texture size 1024x1024 (default until the compositor reports display geometry)
[VRMC-M8] render settings: none published yet (compositor immersive layer not up or old bridge); keeping 1024x1024 eye target
[VRMC-M8] render settings: logical L=3660x3200 R=3660x3200 drawable=2412x2108 foveation=1 rateMaps=2 (foveated display path) quality=1.00/1.00 displayHz=120.0 frame=8.33ms providerEye=0x0 frameIndex=0
[VRMC-M8] eye target resize #1: 1024x1024 -> 1832x1600 (logical=3660x3200 scale=0.50 auto(default); displayHz=120.0 quality=1.00/1.00)
[VRMC-M8] cleared the shared eye frame before the eye-target rebuild (compositor shows its fallback pattern until the new targets are submitted)
Vivecraft: Reinit Render: VRMC M8 eye target 1832x1600
[VRMC-M8] creating eye targets 1832x1600 (scale=0.50 source=auto(default) displayLogical=3660x3200 resizes=1)
[VRMC-M2] eye target L 1832x1600
VR Provider supplied texture resolution: 1832 x 1600
VR target: 1832x1600 [2.9MP]
[VRMC-M8] render state frame=4200 eyeTarget=1832x1600 logical=3660x3200 drawable=2412x2108 foveation=1 rateMaps=2 displayHz=120.0 quality=1.00/1.00 scale=0.50(auto(default)) resizes=1
```

## 4. Limitations (must be stated with any claim)

- The display feedback is **fabricated** (no CompositorServices): it proves the provider consumes and
  acts on the channel, not that the compositor produces correct device values.
- Desktop **OpenGL** backend, not the visionOS **Vulkan/MoltenVK** path; the eye-target/resize logic is
  backend-generic, but the Vulkan side is exercised only on device.
- Menu room only (no world load): it validates the menu-room branch of the resize policy
  (`canResizeNow`); the in-world branch needs a world (device or a scripted world load).
- No claim about foveation, 4K, 120 Hz, optics, latency or thermals.
