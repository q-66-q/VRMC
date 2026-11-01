# M1 execution plan — launcher shell + install + flat MC boot

Status: **M1 COMPLETE 2026-11-01 (EV-0057)** — acceptance matrix in `docs/mvp/M1_ACCEPTANCE.md`; M2 plan in `docs/mvp/M2_PLAN.md`.

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
| W5 | **Input** | Fix mouse/cursor on visionOS; keyboard + controller defaults; look/move comfort. **Finding (source):** `SurfaceViewController.m` only feeds `GCMouse` deltas when `window.windowScene.pointerLockState.locked`; visionOS does not provide pointer lock in the iOS-compatibility scene, so deltas are dropped / cursor behaves abnormally. Candidate fix: treat the GCMouse as captured while the game surface is focused instead of requiring `pointerLockState.locked`, and add a controller-first default | Flat world traversal without a Mac |
| W6 | **Observability** | MC log capture, crash report, phase timings (JIT → JVM → menu → world) | Log/report retrievable per launch |
| W7 | **Stability** | 30-min soak, FPS/thermals baseline, relaunch/save integrity | Acceptance #2 |

## 4. Sprint 1 — next actions (ordered)

1. **T1 pin the working stack**: record hashes/versions of Amethyst 1.2.0 IPA, StikDebug 3.2.0,
   Java 25 JRE, LWJGL 3.4.1 jars/natives, MoltenVK 1.4.3, MC 26.2; update `versions.env` and a
   dedicated `docs/mvp/DEVICE_STACK.md` (ADR needed if a pin changes).
2. **T2 move ad-hoc scripts into the repo** — **done 2026-10-31**: `scripts/sign_ipa.sh`,
   `scripts/set_mc_options.sh`, `scripts/push_jit_script.sh`, `scripts/capture_device_logs.sh`, plus
   `runtime/jit/amethyst.js` (GPL-3.0, notices updated). Remaining: exercise them in a full install flow.
3. **T3 choose W1 route** and produce the first `dev.vrmc.vrmc` app bundle — **DECIDED (ADR-0008, EV-0041)**: build from source; build path boots MC 26.2 (EV-0036); still to brand/re-sign as `dev.vrmc.vrmc` and run the clean-container acceptance:
   - preferred: build Amethyst from source with submodules and our branding;
   - fallback: pin the tested 1.2.0 binary, re-sign as our bundle id, add first-run shell.
4. **T4 first-run provisioning** — **app-side options done (EV-0037)**: `MinecraftOptionUtils` now forces
   the launcher-decided backend (Vulkan for 26.x) and clears `startedCleanly` before every launch; the
   JREs are bundled in the app. Remaining: JIT readiness checklist/guidance and the clean-container
   acceptance.
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


## 5a. T3 decision — app-shell route (resolved 2026-10-31)

**Decision: route (a) — build Amethyst from source with submodules, brand it as our app
(`dev.vrmc.vrmc`), and add the VRMC first-run layer. Route (b) — pin the tested 1.2.0 binary and
re-sign it — is retained only as an emergency fallback; a hard blocker must be recorded with a
transition deadline. Confirmed by ADR-0008 (2026-10-31).**

Rationale:
- (b) cannot carry our UI/first-run provisioning, icon/branding, or the input fixes without binary
  patching, and its 1.2.0 IPA provenance is still unavailable (SideStore caches were empty; the
  Amethyst CI host was unreachable from the build machine, so the IPA hash remains T1-pending).
- (a) is required anyway for GPL corresponding-source compliance (ADR-0006) and for the M1 acceptance
  ("no ad-hoc Mac pushes"): the runtime provisioning and JIT checklist must live in our app.
- Amethyst's build is a Makefile + CMake project; the source zip lacked submodules, so Sprint-1 starts
  with a recursive clone and a reproducible `payload` build. If the build proves blocked, fall back to
  (b) for the M1 boot acceptance while (a) is fixed.

**Status 2026-10-31: build works (EV-0036).** The Amethyst 1.2.0 reference tree was assembled with
submodules and `make payload` completed with the JDK 8 toolchain; payload deps were `native`,
`dep_mcmetal`, `dep_ame_vulkan`, `java`, `jre`, `assets` (MobileGlues/MobileGL renderer deps dropped for
the Vulkan path). 167 Mach-O were re-signed as `dev.vrmc.amethyst`; our own build launched MC 26.2 and
rendered the Vulkan world (EV-0036). Remaining for W1/T3: brand it as `dev.vrmc.vrmc`, add the first-run
layer, and run the fresh-container acceptance.

Sprint-1 status: **T3 closed (EV-0041)** — build path proven (EV-0036), app-side defaults (EV-0037),
scripts (EV-0039). **W1 remaining:** branded `dev.vrmc.vrmc` installed (EV-0042); clean-container acceptance done (EV-0043); reproducible `scripts/build_launcher.sh` + patch committed and tested (EV-0049). **Still to do:** our app icon, first-run layer + JIT readiness checklist.

## 6. M1 startup decisions (recorded, not M0 blockers)

These came out of the 2026-10-31 review; resolve during Sprint-1 day 1 so M1 does not inherit ambiguous
scope:

| ID | Topic | Why it matters | Proposed resolution |
|---|---|---|---|
| **47** | EV-0034 vs EV-0035 scope distinction | M0 gate cites EV-0034; the soak record cites EV-0035. Without an explicit split, future readers will diverge | M0 gate evidence = EV-0034 (device world render). EV-0035 = feasibility partial for the **M1** 30-minute soak gate (Decision 45=A). State this in every status table that cites both |
| **48** | T3 app-shell route timing | If deferred past Sprint-1 day 1, T4/T5 hit the decision under time pressure | Decide on Sprint-1 day 1: (a) build Amethyst from source with submodules + branding, or (b) pin the tested 1.2.0 IPA, re-sign as `dev.vrmc.vrmc`, add first-run shell |
| **49** | 30-minute soak ownership | Resolved by Decision 45=A | Soak is an **M1 exit gate**, tracked in §7 of AGENT; assigned to Lead/user |
| **50** | M1_PLAN hardness ratings | M1 exit must be checkable against AGENT §4.3 without re-deriving coverage | During T1, mark each workstream W1–W7 with a hardness (LOW/MEDIUM/HIGH) and map it to §4.3 feature IDs |
| **36** | BundleScriptMap persistence | `amethyst.js` must be assigned per install; mapping persistence was observed unstable once | Re-confirm before M1 uses `amethyst.js` in any automated flow; W3 readiness must detect missing/wrong assignment |

## 7. T1 stack-pin hashes

See `docs/mvp/DEVICE_STACK.md` for the full table and hash method. Recorded: StikDebug 3.2.0 IPA,
`amethyst.js`, OpenJDK 25.0.4 deployed tree, LWJGL 3.4.1 jars tree. **Blocked:** Amethyst 1.2.0 IPA
hash (not cached on device; `ci.angelauramc.dev` unreachable from the build host), MoltenVK 1.4.3
dylib hash (same IPA), MC 26.2 version JSON hash, BundleScriptMap re-check. Ask the user for the
1.2.0 IPA or capture it from their AltSource/SideStore install once available.


## 8. Sprint-1 close-out status (2026-10-31)

| Item | Status | Evidence / blocker |
|---|---|---|
| T1 stack pinning + hashes | **DONE** | EV-0038; `versions.env`, `check_versions.sh` 8/8 PASS |
| T2 repo scripts + parameterization | **DONE** | EV-0039; `scripts/README.md`, re-run rehearsals |
| T3 app-shell route | **DONE** | ADR-0008 + EV-0041 (build from source, brand `dev.vrmc.vrmc`) |
| T5 mouse verification | **CLOSED PARTIAL** | EV-0040; patch installed, post-patch behavior unverified; follow-up `task-1` (T5-FUP1) |
| T4 first-run provisioning | **DONE** | Fresh branded VRMC container reached the world with app-side provisioning (EV-0043); app-side defaults (EV-0037) |
| T6 30-minute device soak (K4 precursor) | **DONE** | 1805 s continuous world session; no game crash/watchdog kill; thermal `serious` recorded (EV-0044) |
| Follow-up: cursor hide + rotation smoothness | **CLOSED** | Rotation smooth via grab/relative path; cursor visibility is a visionOS pointer-lock limitation accepted as cosmetic (EV-0045/EV-0047); task-2 closed |
| Follow-up: background freeze + audio loss | **CLOSED** | Scene lifecycle + audio reactivation fix; retest PASS (EV-0048); task-3 closed |
| W1 reproducible build | **DONE** | `scripts/build_launcher.sh` + `patches/` + `docs/mvp/LAUNCHER_BUILD.md`; fresh-tree build PASS (EV-0049) |
| W3 JIT readiness | **DONE** | explicit TXM alert + `[JIT] preflight` logging (EV-0050); no-JIT launch flow verified (EV-0051) |

### T6 definition (as required)

**T6 = 30-minute device soak (K4 precursor):** one continuous 30-minute in-world session on D1 with no
crash, no watchdog kill, and the thermal state recorded; EV on completion. It is the M1 exit gate
deferred from M0 by Decision 45=A.
