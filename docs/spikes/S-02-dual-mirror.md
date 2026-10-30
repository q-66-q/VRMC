# S-02 — Vivecraft DUAL mirror capture

**Question:** Does Vivecraft's DUAL mirror produce complete, correctly ordered left/right eye
images in the game window at ≥72 fps, capturable by WGC at 3840×1080?

**Status:** PARTIAL — source inspection confirms the DUAL blit in tag `1.21.11-1.3.15`
(`ShaderHelper.java`); no Windows capture measurement.

**Go criterion:** both eyes present, correct order, no tearing/bars, no black half, ≥72 fps,
10-minute stable; eye pattern survives WGC copy/encode/decode.

**No-go:** DUAL output is mono/missing/tearing or WGC cannot capture it. Fallback: direct-mode
driver frame capture (option B) or a supported compositor capture path.

**Method:** set DUAL, swap off, crop 0, borderless 3840×1080; display an asymmetric test pattern
and a moving counter in both halves; capture 10 minutes; verify hashes/frame counts and inspect
decoded output; repeat with the game window at different positions/monitors.

**Evidence:** pending; see `VERIFY.md` S-02/MT-02/MT-03.
