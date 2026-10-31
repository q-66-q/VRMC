# S1a — iOS compatibility-mode JIT probe

**Status:** scaffolded 2026-10-31. The harness compiles for iOS; it has **not** been signed,
installed, or run on device. Device S1a is `NOT RUN`.

**Purpose.** Prove the JIT26 mechanism on the paired Vision Pro in iOS compatibility mode: an
unmodified iOS OpenJDK 25 JRE starts under a JIT enabler, compiles a hot method, **executes** it, and
keeps the code cache executable after the enabler detaches. See
[`docs/mvp/SPIKES.md`](../../../docs/mvp/SPIKES.md) §S1.

**Pass criteria (all four).**
1. JIT-compiled methods are actually executed, not only compiled.
2. No `brk #0x69` trap occurs.
3. After the enabler detaches, the code cache remains executable.
4. A cold relaunch reproduces the result, or persistence is proven. This criterion decides A2's
   MEDIUM vs LOW.

**Out of scope:** Minecraft, Vivecraft, CompositorServices (S1b/S2/S4).

## Contents

| File | Purpose |
|---|---|
| `HelloJit.java` | Hot loop (`200M` iterations) with `-XX:+PrintCompilation`-friendly methods |
| `main.m` | iOS app: dlopen `libjli.dylib`, `JLI_Launch` with the JIT26 flags, log to `Documents/s1a-jit.log` |
| `Info.plist` | iOS app manifest (`VRMC_BUNDLE_ID` placeholder) |
| `s1a.entitlements` | `get-task-allow` (JIT requires a debugged/prepared process) |
| `build.sh` | Syntax check, compile, assemble, sign, install |

## Prerequisites

- Extracted **iOS arm64 JRE 25** (e.g. Amethyst's `jre25-ios-aarch64` bundle): `lib/libjli.dylib`,
  `lib/server/libjvm.dylib`.
- Apple Development identity and a provisioning profile whose device list includes the AVP UDID
  (`<D1-UDID>`). As of 2026-10-31 the only local profile is iPad-only; creating the
  AVP profile is a pending action.
- Developer Mode on the headset and a JIT enabler capable of preparing a JVM-sized code-cache region
  (Apparition/StikDebug-style), with a script that implements the JVM's allocation-style
  `brk #0x69` request.
- The device must be reachable (`xcrun devicectl list devices`).

## Build and run

```bash
./build.sh --check                        # compile-only check, no JRE needed

JRE_DIR=/path/to/jre25-ios ./build.sh     # assemble S1AProbe.app

IDENTITY="Apple Development: ..." \
  PROFILE=/path/to/avp.mobileprovision \
  DEVICE_ID=<D1-UDID> \
  JRE_DIR=/path/to/jre25-ios ./build.sh   # sign + install
```

Launch **through the JIT enabler**, not from Home, so the debugger prepares the code cache; then pull
`Documents/s1a-jit.log` from the app container.

## Evidence to capture

- `[JIT26] Requesting…` / `[JIT26] Got JIT mapping…` / `[JIT26] mapping at RW=…,RX=…`.
- `PrintCompilation` tier 3/4 lines for `HelloJit::hot` and `HelloJit::main`.
- `HELLOJIT iterations=… acc=… elapsed_ms=…` printed by the app.
- No `brk #0x69` trap (`SIGTRAP`/exit 133) during execution.
- Re-launch results for the cold-relaunch criterion.

## Divergence note

If the headset's behavior differs from the macOS host (no TXM trap, another failure mode, or the
enabler script's semantics mismatch), record it here and in the S1b plan.
