### EV-0032 — MC 26.2 on D1: after grafting LWJGL 3.4.1 Java, JNI_OnLoadGLFW in the app binary crashes (embedded 3.3.3 natives)

| Field | Value |
|---|---|
| Date | 2026-10-31T18:40:23-10:00 |
| Commit | `231f06056ded70c19af0e5b893a6816241330257` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `FAIL` |

**Procedure:**

1. graft merged LWJGL 3.4.1 Java jars + 3.4.1 iOS natives into the launcher, re-sign, install
2. launch via StikDebug with amethyst.js; JIT26 grants mapping; MC 26.2 starts
3. pull latestlog + hs_err

**Expected:** MC loads LWJGL 3.4.1 and reaches the Vulkan client bootstrap

**Actual:** spvc class error gone; MC dies with SIGSEGV in jni_GetStaticObjectField called from JNI_OnLoadGLFW inside the Amethyst app binary, reached from org.lwjgl.system.Library.<clinit>. The app binary embeds LWJGL 3.3.3 JNI code, incompatible with 3.4.1 Java.

**Artifacts:** evidence/EV-0032/latestlog.txt (432923ebf2b1); evidence/EV-0032/hs_err.log (7652537202b7); evidence/EV-0032/summary.log (a645fa9497b2)

**Limitations:** Conclusive: released and nightly Amethyst artifacts both bundle LWJGL 3.3.3 JNI in the app binary; MC 26.2 requires 3.4.1. Next: rebuild Amethyst from source (needs its git submodules) or use another launcher/runtime. Exporting the full problem to export/.
