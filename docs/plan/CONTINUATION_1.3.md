# VRMC 1.3 continuation — Claude handoff

## The user's original brief (Claude session)
"This is a very bad project that have tons of bugs. make the project better, discover new feature and redesign the ui. you are allow to ask 5 question and give me the release version in one shot."

Claude's five-question round was answered by the user:
- Bugs hit: hand gestures/input, rendering/visuals, launch/install/crashes, and the app window UI — all four.
- UI direction: **Start over, native visionOS** (the prior SIGNAL DECK custom overlay was dropped).
- Release target: **installed on the headset**.
- New features: **Automatic setup** and an **in-VR quick menu**.

## Claude's 10-step plan and state at interruption
1. Survey project/current state — completed.
2. Ask scoping questions — completed.
3. Confirm build/sign/install path — in progress.
4. Review code and fix bugs — code written (provider + compositor + shell lifecycle).
5. Build automatic setup — implemented in runtime/native-shell/Sources/ShellSetup.swift (SetupManager + LauncherBridge).
6. Build in-VR quick menu — implemented in provider VisionQuickMenuScreen.java + VisionVR wiring.
7. Redesign window UI native visionOS — implemented in runtime/native-shell/Sources/ShellUI.swift (TabView: Play, Comfort, Controls, Help, Launcher).
8. Run host tests and build all parts — provider tests were being run; shell framework built.
9. Sign, install and smoke-test on headset — app 1.3.0 was installed but `devicectl ... launch` returned:
   `Unable to launch dev.vrmc.vrmc because it has an invalid code signature, inadequate entitlements or its profile has not been explicitly trusted by the user. (FBSOpenApplicationErrorDomain error 3)`
   Claude was checking the device trust state when the user interrupted. App logs in the transcript also show the app started at least once (`vrmc_shell_start invoked`, `[VRMC] first-run checklist shown`), so the refusal may be trust/profile-specific or a reinstall regression.
10. Update docs, commit, package — not done.

## Environment facts (2026-11-11)
- Device: Apple Vision Pro D1, UDID <D1-UDID>, visionOS 27.2, paired/available.
- Installed: `VRMC` 1.3.0 (1.3.0), `SideInstaller` 1.6.4. **StikDebug is not installed** (it was present earlier in Claude's session and is required for JIT).
- Signing: Apple Development `<apple-id> (<cert-id>)`, team <TEAM_ID> (Personal Team, 7-day profiles). Cached profile 3e7ca60a… expires 2026-11-15T03:21Z and provisions D1.
- Worktree: this directory; branch `claude/project-overhaul-bugs-features-ui-c2719a`, base 31bd21b; all Claude changes are uncommitted.
- Claude scratchpad: /private/tmp/claude-501/-Volumes-Untitled-Projects-VRMC--claude-worktrees-project-overhaul-bugs-features-ui-c2719a/703f37ce-f5e1-4708-89e7-d0afc52f3ad0/scratchpad (provider env, built jar, tests log).
- StikDebug IPA downloaded to /tmp/vrmc-jit/StikDebug-3.2.2.ipa (unsigned, bundle `com.stik.stikdebug`, no extensions).
- `scripts/push_jit_script.sh` expects StikDebug bundle `com.stik.stikdebug.<TEAM_ID>` and pushes `runtime/jit/amethyst.js` to its Documents/scripts.
- StikDebug JIT assignment is still manual: long-press VRMC in StikDebug → Assign Script → amethyst.js; then Enable JIT → VRMC. A pairing file/trust may be required in StikDebug.

## Continuation goal
1. Install StikDebug (signed for this team/device) on D1 and push amethyst.js; make the JIT flow usable (pairing/trust steps documented if not automatable).
2. Finish and verify the 1.3 worktree: provider builds/tests, shell framework builds cleanly, new UI + automatic setup + in-VR quick menu reviewed/fixed.
3. Produce a signed `dev.vrmc.vrmc` 1.3.x app from the worktree, install on D1, and get it to launch; diagnose the trust/signing refusal if it recurs.
4. Verify what can be verified without the game; record device evidence and remaining manual steps.
5. Update docs (release notes), commit the worktree branch, package the artifacts, and report.

## Known risks
- Free Personal Team limits (3 apps/7 days; profiles last 7 days). StikDebug signing may hit the app limit or need a new App ID.
- The app launch refusal may require the user to trust the development profile on the headset (Settings → General → VPN & Device Management / Developer App), or may be a signing regression we must fix.
- Claude's uncommitted changes must not be lost; commit a WIP checkpoint before invasive edits if needed.
- No visionOS simulator runtime is currently available for UI screenshots; device logs/builds are the evidence path.