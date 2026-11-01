# M2 host harness — run the provider on desktop Fabric (no headset, no SteamVR)

This reproduces EV-0059 (fail-closed scaffold) and EV-0060 (bridge-backed VR frame loop).

## Inputs

- MC 26.2 + Fabric 0.19.3 + Vivecraft 26.2-1.3.15 jars and a Fabric run dir (`/tmp/mc-fabric` used here).
- A classpath file with MC/Fabric/Vivecraft jars (S3 harness: `/tmp/s3-mod/cp.txt`).
- JDK 25 (`javac`/`java`), Xcode command line tools.
- Built bridge dylib (host): see `bridge/README.md`.

## Build the provider jar

```bash
JAVAC=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javac
CP=$(cat /tmp/s3-mod/cp.txt)
rm -rf /tmp/provider-out && mkdir -p /tmp/provider-out
$JAVAC -cp "$CP" -d /tmp/provider-out $(find provider/src/main/java -name '*.java')
rm -rf /tmp/provider-mod && mkdir -p /tmp/provider-mod
cp -R provider/src/main/resources/* /tmp/provider-mod/
cp -R /tmp/provider-out/* /tmp/provider-mod/
(cd /tmp/provider-mod && jar cf /tmp/vrmc-provider.jar .)
```

## Enable VR and launch

```bash
# vrsettings: vrEnabled=true, stereoProviderPluginID=OPENVR
# (Vivecraft 26.2 config: <run-dir>/config/vivecraft-client-config.json)

cp /tmp/vrmc-provider.jar /tmp/mc-fabric/mods/    # keep vivecraft jar too; remove any old probe jar
cd /tmp/mc-fabric
java -XstartOnFirstThread -Xmx2G \
  -Dvrmc.bridge.lib=/tmp/libvrmc_bridge.dylib \
  -cp "$(cat /tmp/s3-mod/cp.txt)" net.fabricmc.loader.impl.launch.knot.KnotClient \
  --gameDir /tmp/mc-fabric \
  --assetsDir "/Users/<user>/Library/Application Support/Swift Craft Launcher/meta/assets" \
  --assetIndex 32 --version 26.2 --accessToken 0 --username M2Harness \
  --uuid 00000000000000000000000000000000 --userType legacy --demo --width 1280 --height 720
```

Expected: `[VRMC-M2] bridge handshake ok`, `VisionVR.init() succeeded`, `VisionRenderer created`,
`eye target L/R 1024x1024`, `VR Provider supplied texture resolution: 1024 x 1024`, tracking frames
logged; no SteamVR. The GL host path submits GL texture ids; on Vulkan/visionOS the S4a Metal-handle
path replaces it.
