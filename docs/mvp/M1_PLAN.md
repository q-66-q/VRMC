# M1 execution plan — launcher shell + install + flat MC boot

Status: **planning started 2026-10-31**, while the last M0 item (S2 30-minute device soak) is deferred.

## 1. Where we are (device-proven baseline)

On 2026-10-31, Minecraft **26.2** rendered a singleplayer world on Apple Vision Pro `RealityDevice14,1`
(visionOS 27.2), through Vulkan/MoltenVK, with JIT enabled:

| Component | Working value | Evidence |
|---|---|---|
| Launcher | Amethyst iOS **1.2.0** (GPL-3.0), re-signed as `dev.vrmc.amethyst` | EV-0029, EV-0031 |
| JIT enabler | StikDebug **3.2.0** with `amethyst.js` assigned (UniversalJIT26 + Extension) | EV-0033, EV-0034 |
| JVM | external **OpenJDK 25.0.4** iOS arm64 (`MirrorMappedCodeCache`) | EV-0031, EV-0034 |
| LWJGL | **3.4.1** Java + iOS natives | EV-0031/32 (graft learning), EV-0034 (1.2.0 has native support) |
| Graphics | MC `preferredGraphicsBackend:"vulkan"` → **MoltenVK 1.4.3** | EV-0034 |
| World session | “New World”, 4m20s, clean save + shutdown, no crash | EV-0034, EV-0035 |
| Crash blocker (older IPA) | LWJGL 3.3.3 vs 3.4.1; fixed by 1.2.0 build | EV-0031, EV-0032, `export/` |

Known device quirks:
- **Mouse/cursor behaviour is abnormal** on visionOS under Amethyst; user says it does not block for
  now, but it belongs to M1 input work.
- `devicectl` screenshot is unavailable on visionOS; log capture is the evidence path.
- JIT needs a per-launch StikDebug enable + script assignment.
- MC `options.txt` needed manual edits (`preferredGraphicsBackend:"vulkan"`, `startedCleanly:true`) to
  avoid the crash-reset forcing ANGLE. These must become first-run defaults.

Outstanding M0 item: **ST-S2 30-minute device soak** (EV-0035 is clean but 4m20s). M0 closes when that
is recorded; M1 implementation starts after that (or an explicit waiver).

## 2. M1 goal and acceptance

**Goal:** a fresh install of the VRMC launcher on a wiped AVP goes to a flat singleplayer world with a
reproducible, documented flow — no ad-hoc file pushes from the Mac.

Acceptance criteria:
1. Fresh install → launch MC 26.2 → create/enter a flat world entirely from the app UI.
2. 30 minutes stable in-world, clean exit, save preserved on relaunch.
3. No manual host steps after install (JRE, LWJGL, MC options, JIT script all provisioned by the app
   or documented one-tap UI).
4. JIT readiness UX: detect no-JIT, guide through StikDebug (or future enabler), retry cleanly.
5. Crash/log capture: MC log stored and retrievable; crash produces an in-app report.
6. Input is usable for flat-world movement/look (keyboard/controller at minimum; mouse issue triaged).
7. GPL-3.0 compliance: corresponding source + build instructions published for the distributed build.

## 3. Workstreams

| ID | Workstream | Key tasks | Exit criterion |
|---|---|---|---|
| W1 | **Our app shell** | Decide build route: (a) build Amethyst from source with our patches, or (b) pin the tested 1.2.0 binary and re-sign/brand with our identity; add app icon/name/first-run screen | App bundle `dev.vrmc.vrmc` installed from our own build/artifact |
| W2 | **Runtime provisioning** | Bundle Java 25 JRE, LWJGL 3.4.1, MoltenVK, scripts inside the app; first-run copying to Documents; remove external `java_runtimes` push | Fresh install can launch the JVM with no Mac-side pushes |
| W3 | **JIT readiness** | Encode the working StikDebug flow (3.2.0 + `amethyst.js`), detect `CS_DEBUGGED`, guide the user, handle failure/retry; track the AGPL script distribution | First-run JIT check + retry works; documented in app |
| W4 | **MC install + boot** | Demo/Microsoft account flow, 26.2 install, default options (`vulkan`, `startedCleanly`), create flat world, quick-play | Acceptance #1 on a clean container |
| W5 | **Input** | Fix mouse/cursor on visionOS; keyboard + controller defaults; look/move comfort | Flat world traversal without a Mac |
| W6 | **Observability** | MC log capture, crash report, phase timings (JIT → JVM → menu → world) | Log/report retrievable per launch |
| W7 | **Stability** | 30-min soak, FPS/thermals baseline, relaunch/save integrity | Acceptance #2 |

## 4. Sprint 1 — next actions (ordered)

1. **T1 pin the working stack**: record hashes/versions of Amethyst 1.2.0 IPA, StikDebug 3.2.0,
   Java 25 JRE, LWJGL 3.4.1 jars/natives, MoltenVK 1.4.3, MC 26.2; update `versions.env` and a
   dedicated `docs/mvp/DEVICE_STACK.md` (ADR needed if a pin changes).
2. **T2 move ad-hoc scripts into the repo**: `scripts/sign_ipa.sh`, `scripts/push_mc_options.sh`,
   `scripts/push_jit_script.sh`, `scripts/capture_device_logs.sh` (currently in `/tmp` only).
3. **T3 choose W1 route** and produce the first `dev.vrmc.vrmc` app bundle:
   - preferred: build Amethyst from source with submodules and our branding;
   - fallback: pin the tested 1.2.0 binary, re-sign as our bundle id, add first-run shell.
4. **T4 first-run provisioning**: copy MC options defaults + JIT script + Java 25 runtime from the app
   (no Mac pushes); show a JIT checklist screen.
5. **T5 input triage**: reproduce the mouse/cursor issue and either fix or document a controller-first
   default.
6. **T6 when the user is available**: 30-minute world soak on D1 → closes ST-S2/M0 (EV-0036+).

## 5. Risks / open items

- **M0 not formally closed** until the 30-minute soak is recorded; M1 implementation should wait for it
  (or an explicit waiver), but W1/W2 preparation can proceed.
- **Amethyst build reproducibility**: current working app came from a tested 1.2.0 artifact, not our
  build; source zip lacks submodules. This is the largest W1 risk.
- **StikDebug external dependency** (AGPL-3.0 scripts): per-launch enabler and script assignment stay
  user-visible until a different JIT path exists.
- **Free-team expiry**: profiles expire ~7 days; A2 remains MEDIUM and re-signing is a recurring task.
- **visionOS input quirks** (mouse/cursor) may require Amethyst-side patches.
- GPL obligations: publish corresponding source + build steps for every distributed build (ADR-0006).
