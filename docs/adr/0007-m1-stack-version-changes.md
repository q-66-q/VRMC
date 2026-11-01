# ADR-0007 — M1 stack version changes: Amethyst 1.2.0, MoltenVK 1.4.3, amethyst.js

**Status:** Accepted (2026-10-31)
**Related:** Decision 45=A, Decision 46=A+C; AGENT §5 (Pins), §6 (S2), §7 (M0/M1), §13; `VERIFY.md`
EV-0001/EV-0004/EV-0005/EV-0010/EV-0016/EV-0021/EV-0031/EV-0032/EV-0034/EV-0035; `docs/mvp/M1_PLAN.md`

## Context

M0 closed on EV-0034 with a device-proven MC 26.2 Vulkan world on Apple Vision Pro. That run used a
different stack from the one pinned during M0 evidence gathering:

| Item | M0 state | M1 state (device-proven) |
|---|---|---|
| Amethyst | 1.0-development (EV-0001 latestlog) | **1.2.0** |
| MoltenVK | 1.4.2 (EV-0010 build; EV-0016 device verification) | **1.4.3** |
| StikDebug script | `universal.js` (EV-0021) | **`amethyst.js`** (UniversalJIT26 + Extension) |

Decision 46=A+C requires these changes to be recorded as an immediate fact record (done in the M0
closure commit) plus this ADR, and requires an explicit statement about whether Amethyst 1.2.0 fixes
the JNI crash observed in EV-0032.

## Decision

1. **Amethyst is pinned at 1.2.0** for M1 (prior pin: 1.0-development).
2. **MoltenVK is pinned at 1.4.3** for M1 (prior pin: 1.4.2). The 1.4.2 xros build record (EV-0010) is
   retained; 1.4.3 is the version shipped and exercised on the device.
3. **The StikDebug script is `amethyst.js`** (prior script: `universal.js`). It is a new combined file
   (UniversalJIT26 + JIT26 extension), not a rename.

## Rationale

### Amethyst 1.2.0 — does it fix the EV-0032 JNI crash?

**Yes, for the pinned build.** The EV-0032 SIGSEGV (`jni_GetStaticObjectField` from
`JNI_OnLoadGLFW` inside the app binary) was caused by mixing two ABI generations: we grafted LWJGL
**3.4.1** Java classes and native dylibs into an app whose binary still embedded LWJGL **3.3.3** JNI.
Amethyst 1.2.0 ships native LWJGL **3.4.1** support: the device log shows
`[JavaLauncher] Using LWJGL from lwjgl-3.4.1` and `Backend library: LWJGL version 3.4.1-snapshot`, and
MC 26.2 subsequently reached and rendered a world (EV-0034). The mixed-ABI condition no longer exists
on 1.2.0, so the JNI fault is resolved **for this pinned build**.

This is not a blanket guarantee: if the Amethyst build, LWJGL version, or native set changes, M1a
(JNI ABI alignment) must be re-verified. 1.2.0 is not a routine bump that merely happened to align with
M0 evidence — it removes the root cause of EV-0032.

### MoltenVK 1.4.3

1.4.3 is the version bundled with Amethyst 1.2.0 and used for the device world render (`Using graphics
backend Vulkan, using drivers: 1.2.357 MoltenVK 1.4.3`, EV-0034). The project's own xros build remains
1.4.2 (EV-0010); we have not yet produced or hash-pinned a standalone 1.4.3 xros build.

### amethyst.js

`amethyst.js` is the concatenation of Amethyst's `UniversalJIT26.js` and `UniversalJIT26Extension.js`.
It is needed because Amethyst's startup dyld bypass can issue JIT26 commands (including command 4,
"prepare for patching") **before** the game-launch handshake sends the extension; assigning only
`universal.js` leaves those startup calls unhandled. EV-0021 proved the JIT26 mechanism with
`universal.js`, and that PASS is not invalidated — the mechanism is what it proved; the script identity
is now historical.

## Evidence impact

| EV | Status after this ADR |
|---|---|
| EV-0001 (Amethyst 1.0-development baseline) | Historical. Retained; forward-reference to the new 1.2.0 pin |
| EV-0004 / EV-0005 (host tests referencing 1.0-development) | Historical. Retained; not re-run against 1.2.0 |
| EV-0010 (MoltenVK 1.4.2 xros build record) | Valid for 1.4.2 only. 1.4.3 build/re-record is a T1 pending item; first device use (EV-0034) exercises 1.4.3 |
| EV-0016 (5/5 extensions + 9/9 features on 1.4.2) | Stands for 1.4.2. **Re-verification against 1.4.3 is required at first M1 device use or by recording that the 1.4.2 verification stands in for 1.4.3 unless a behavioral difference is found.** MC 26.2 selecting Vulkan on 1.4.3 (EV-0034) is implicit evidence, not an explicit re-enumeration |
| EV-0021 (`universal.js` PASS) | Not invalidated: the JIT26 mechanism and cold-relaunch behaviour stand. Script identity is historical |
| EV-0032 (JNI crash on grafted 3.4.1) | Historical root-cause record; not expected to recur on 1.2.0 (see rationale) |
| EV-0034 / EV-0035 | Current M0/ M1-gate evidence under the new pins |

## BundleScriptMap implications

- `amethyst.js` is a **new file**, not a rename, so the StikDebug assignment must be re-established on
  each device/install (long-press Amethyst → Assign Script → `amethyst.js`).
- After reinstalling StikDebug 3.2.0, prefs showed `dev.vrmc.amethyst → amethyst.js`, i.e. the mapping
  can persist across an app upgrade — but the behaviour was observed as unstable once, and the
  persistence question from **Decision 36 remains unresolved**.
- M1 must not assume the mapping survives; W3's readiness flow must detect missing/incorrect assignment
  and guide the user. Re-confirm this before M1 uses `amethyst.js` in an automated flow.

## Consequences

- `versions.env` is updated: Amethyst 1.2.0, MoltenVK 1.4.3 (device path), StikDebug 3.2.0,
  `amethyst.js`, plus the hashes available today.
- `docs/mvp/DEVICE_STACK.md` records provenance and hashes; the Amethyst 1.2.0 IPA and the MoltenVK
  1.4.3 dylib still need their hashes pinned (IPA provenance is pending).
- T1 (stack pinning) is now concrete; T2 (move ad-hoc scripts into the repo) is the second day-1 task.
- The 1.4.3 extension/feature re-verification is added to the M1 startup checklist.
