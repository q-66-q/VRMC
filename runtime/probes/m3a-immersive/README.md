# M3a immersive probe (native visionOS)

Gate 2 of M3a: native visionOS app opens a CompositorServices immersive space, renders a per-eye test
pattern (left red / right green) via `CompositorLayer`, and logs ARKit device-anchor poses to
`Documents/m3a-probe.log`.

Build/sign (after `xcodegen generate`):

```bash
cd runtime/probes/m3a-immersive
xcodegen generate
xcodebuild -project M3AProbe.xcodeproj -scheme M3AProbe -configuration Debug \
  -destination 'platform=visionOS,id=<UDID>' -allowProvisioningUpdates build
```

Install/slot note: installing the probe needs a free app slot; the plan is to temporarily remove
StikDebug (IPA kept at `/tmp/stik320/StikDebug-3.2.0.ipa`), install `dev.vrmc.m3a`, run the probe,
then reinstall StikDebug and re-push `amethyst.js` (BundleScriptMap assignment is per app install).
