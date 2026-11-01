# S4a-device probe (runs inside the VRMC app)

Goal: repeat the S4a-host test on visionOS with the **bundled MoltenVK 1.4.3**: export a Vulkan image
as an `MTLTexture`, read it back through Metal, and verify timeline `MTLSharedEvent` synchronization.

## How it runs

The probe is compiled into the Amethyst app (`Natives/vrmc_s4a_probe.m`, called from `main.m` after
home-directory setup). It is a **no-op** unless `$AME_HOME/vrmc_s4a_device.flag` exists; when present it:

1. deletes the flag,
2. loads `Frameworks/libMoltenVK.dylib`,
3. runs the export/pixel/shared-event test on a background queue,
4. writes `$AME_HOME/s4a-device.log` (also NSLog).

## Trigger from the Mac

```bash
: > /tmp/vrmc_s4a_device.flag
xcrun devicectl device copy to --device <udid> --domain-type appDataContainer \
  --domain-identifier dev.vrmc.vrmc --source /tmp/vrmc_s4a_device.flag \
  --destination "Documents/vrmc_s4a_device.flag"
xcrun devicectl device process launch --device <udid> dev.vrmc.vrmc   # device must be unlocked
# then:
xcrun devicectl device copy from --device <udid> --domain-type appDataContainer \
  --domain-identifier dev.vrmc.vrmc --source Documents/s4a-device.log --destination /tmp/s4a-device.log
```

Vulkan headers for the build come from `assets/vulkan_include` (Apache-2.0/MIT, from the MoltenVK
release); `scripts/build_launcher.sh` copies them into the tree.

## Gate

**S4a-device PASS** requires `S4a-DEVICE PASS` in the log (MTLDevice + MTLTexture export, Metal
readback correct, timeline MTLSharedEvent sees the Vulkan signal) on a real Vision Pro. Host results
do not substitute.
