import SwiftUI
import CompositorServices
import UIKit
import Observation
import Foundation
import AudioToolbox

/// Entry point called from the Amethyst C main() (iOS-compat binary) via dlopen/dlsym.
/// The shell adopts SwiftUI's app lifecycle so visionOS immersive scenes / CompositorLayer exist.
func shellLog(_ message: String) {
    let line = "[shell] \(Date()) \(message)\n"
    NSLog("%@", line)
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let url = docs.appendingPathComponent("vrmc-shell.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}

private func shellDocumentsURL() -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
}

private func shellDocumentFlag(_ name: String) -> Bool {
    return FileManager.default.fileExists(atPath: shellDocumentsURL().appendingPathComponent(name).path)
}

private func shellDocumentString(_ name: String) -> String? {
    let url = shellDocumentsURL().appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

// M3c: the app data container cannot be cleaned with devicectl (copy/list only), so a leftover
// diagnostic flag (e.g. a forced test pattern) can poison every later run. Pushing
// Documents/vrmc-clear-diagnostics.flag makes the shell delete the list below at startup, before
// any autolaunch/immersive-on-launch flag could be consumed, and log one line per deletion.
private let diagnosticFlagsClearedAtStartup = [
    "vrmc-test-pattern.flag",
    "vrmc-reproj-off.flag",
    "vrmc-reproj-on.flag",
    "vrmc-reproj-debug.flag",
    "vrmc-no-sampling.flag",
    "vrmc-legacy-root-swap.flag",
    "vrmc-immersive-on-launch.flag",
    "vrmc-immersive-selftest.flag",
    "vrmc-clear-probe.flag",
    "autolaunch.flag",
]

private func neutralizeDiagnosticFlagsIfRequested() {
    let fm = FileManager.default
    let docs = shellDocumentsURL()
    let trigger = docs.appendingPathComponent("vrmc-clear-diagnostics.flag")
    guard fm.fileExists(atPath: trigger.path) else { return }
    shellLog("clear-diagnostics: vrmc-clear-diagnostics.flag present; removing diagnostic flags before app start")
    for name in diagnosticFlagsClearedAtStartup {
        let url = docs.appendingPathComponent(name)
        guard fm.fileExists(atPath: url.path) else { continue }
        do {
            try fm.removeItem(at: url)
            shellLog("clear-diagnostics: deleted \(name)")
        } catch {
            shellLog("clear-diagnostics: FAILED to delete \(name): \(error.localizedDescription)")
        }
    }
    do {
        try fm.removeItem(at: trigger)
        shellLog("clear-diagnostics: deleted vrmc-clear-diagnostics.flag (self)")
    } catch {
        shellLog("clear-diagnostics: FAILED to delete vrmc-clear-diagnostics.flag: \(error.localizedDescription)")
    }
    shellLog("clear-diagnostics: done")
}

@_cdecl("vrmc_shell_start")
public func vrmcShellStart() -> Int32 {
    shellLog("vrmc_shell_start invoked")
    // Must run before VRMCShellApp.main() so no autolaunch/on-launch flag survives this process.
    neutralizeDiagnosticFlagsIfRequested()
    VRMCShellApp.main()
    return 0
}

struct ShellLayerConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities,
                           configuration: inout LayerRenderer.Configuration) {
        configuration.layout = .dedicated
        configuration.isFoveationEnabled = false
        configuration.colorFormat = .rgba16Float
    }
}

struct LauncherHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        if let cls = NSClassFromString("LauncherSplitViewController") as? UIViewController.Type {
            return cls.init()
        }
        let fallback = UIViewController()
        fallback.view.backgroundColor = .systemBackground
        return fallback
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// App-level owner of the immersive lifecycle.
///
/// Amethyst's game launch must not replace the WindowGroup's root view controller (the M3b patch
/// presents the game surface modally over it instead): replacing the root destroys the SwiftUI view,
/// which is what dropped the scene's persistentSystemOverlays(.hidden) chrome preference and the
/// lifecycle subscriptions in EV-0085/EV-0086. The coordinator stays app-level anyway.
///
/// M3c presentation hardening (EV-0090/EV-0091 black immersive):
///  - Windows are NEVER hidden with isHidden anymore (that is followed by UIScene.willDeactivate in
///    the device logs). Parking is alpha-only + non-interactive, and only happens AFTER the
///    compositor posts VRMCCompositorRunning (its first presented frame). vrmc-hide-windows.flag
///    restores the old hide behaviour for A/B; vrmc-no-parking.flag disables parking entirely.
///  - When no presented frame arrives, the shell logs NO-FRAME heartbeats and LEAVES THE IMMERSIVE
///    SPACE OPEN (no dismiss, no auto-retry) so the device log stays collectable.
///  - vrmc-immersive-selftest.flag opens the immersive space without the game (no JIT needed): the
///    shell starts, waits for the scene to be foreground-active, opens the space, and the compositor
///    draws its test pattern + present-proof overlay + drawable raw dumps.
@MainActor
@Observable
final class ShellCoordinator {
    static let shared = ShellCoordinator()

    /// Drives the WindowGroup chrome visibility (scene-level, survives game presentation).
    private(set) var immersiveOpen = false
    /// True once the compositor has presented at least one frame for the current session.
    private(set) var presenting = false

    @ObservationIgnored private var gameStarted = false
    /// Set when the immersive session was ended by backgrounding/resigning; cleared once reopened.
    @ObservationIgnored private var reopenOnActive = false
    @ObservationIgnored private var opening = false
    /// Incremented on every compositor-ended/background transition; guarded Tasks abort when it moves.
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var appActive = false
    @ObservationIgnored private var windowSceneActive = false
    /// Generation of the most recent successful immersive open (0 = never opened).
    @ObservationIgnored private var lastOpenGeneration: Int32 = 0
    @ObservationIgnored private var lastOpenAt: Date = .distantPast
    @ObservationIgnored private var autoRetries = 0
    /// True while a previous immersive space still needs an explicit dismiss before a reopen.
    @ObservationIgnored private var needsDismiss = false
    @ObservationIgnored private var openAction: OpenImmersiveSpaceAction?
    @ObservationIgnored private var dismissAction: DismissImmersiveSpaceAction?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// NO-FRAME watchdog for the current open; cancelled once a presented frame arrives.
    @ObservationIgnored private var noFrameTask: Task<Void, Never>?
    /// Periodic window parking while the immersive session is live: Amethyst/game code can re-show or
    /// re-alpha a window after the first park (observed: the game window stayed visible in a live game
    /// run even though the first park set alpha=0), so re-apply until the session ends.
    @ObservationIgnored private var parkingTask: Task<Void, Never>?
    /// Periodic scene/immersion state logging while immersive is live.
    @ObservationIgnored private var sceneStateTask: Task<Void, Never>?
    /// willResignActive grace timer: a transient resign must not stop the compositor (sim-lifecycle).
    @ObservationIgnored private var resignGraceTask: Task<Void, Never>?
    /// True while alpha-only parking has been applied to the windows.
    @ObservationIgnored private var windowsParked = false

    /// Keep the window chrome hidden for the whole launch (diagnostic A/B for EV-0086 issue 1).
    private(set) var hideChromeAlways = false
    private(set) var chromeMode = "automatic"
    /// Self-test mode: open the immersive space without the game (see class docs).
    private(set) var selftestMode = false
    /// Disable window parking entirely (diagnostic).
    private(set) var noParking = false
    /// Restore the old isHidden=true parking for A/B (default: alpha-only, never hide).
    private(set) var hideWindowsOptIn = false
    /// User-facing status for the window overlay (manual "Enter VR" control, Option 2 staging).
    private(set) var statusMessage = "Preparing VR"
    /// Last failure to open the immersive space, shown in the window so errors stay actionable.
    private(set) var lastOpenError: String?

    /// Manual "Enter VR" (staged immersive entry): open the immersive space on demand, independent of
    /// the game/JIT path, so the CompositorServices renderer can be validated on its own. The automatic
    /// path (after the game starts, i.e. after JIT readiness) stays enabled; this button is also the
    /// recovery path when the automatic open fails.
    func enterVRManually() {
        shellLog("MANUAL: Enter VR pressed (immersive=\(immersiveOpen) opening=\(opening) appActive=\(appActive) windowActive=\(windowSceneActive) presenting=\(presenting))")
        guard openAction != nil else {
            lastOpenError = "Immersive space is not bound yet; try again in a moment."
            statusMessage = "VR unavailable"
            shellLog("MANUAL: openImmersiveSpace action not bound yet")
            return
        }
        lastOpenError = nil
        statusMessage = "Opening immersive space…"
        openVR(reason: "manual")
    }

    private init() {
        hideChromeAlways = shellDocumentFlag("vrmc-hide-chrome-always.flag")
        chromeMode = hideChromeAlways ? "hidden-always" : "hidden-when-immersive"
        selftestMode = shellDocumentFlag("vrmc-immersive-selftest.flag")
        noParking = shellDocumentFlag("vrmc-no-parking.flag")
        hideWindowsOptIn = shellDocumentFlag("vrmc-hide-windows.flag")
        observe(Notification.Name("VRMCGameStarted")) { $0.gameDidStart() }
        observe(Notification.Name("VRMCImmersiveEnded")) { coordinator, note in
            coordinator.compositorDidEnd(generation: note.userInfo?["generation"] as? Int32)
        }
        observe(Notification.Name("VRMCCompositorRunning")) { coordinator, note in
            coordinator.compositorDidStartPresenting(generation: note.userInfo?["generation"] as? Int32)
        }
        observe(UIApplication.willResignActiveNotification) { $0.willResignActive() }
        observe(UIApplication.didEnterBackgroundNotification) { $0.didEnterBackground() }
        observe(UIApplication.didBecomeActiveNotification) { $0.appDidBecomeActive() }
        observe(UIApplication.didFinishLaunchingNotification) { $0.refreshActivityStates("didFinishLaunching") }
        observe(UIScene.didActivateNotification) { $0.refreshActivityStates("UIScene.didActivate") }
        observe(UIScene.willDeactivateNotification) { $0.refreshActivityStates("UIScene.willDeactivate") }
        refreshActivityStates("init")
        shellLog("coordinator ready chromeMode=\(chromeMode) selftest=\(selftestMode) noParking=\(noParking) hideWindowsOptIn=\(hideWindowsOptIn)")
        if selftestMode {
            scheduleSelfTestOpen()
        }
    }

    private func observe(_ name: Notification.Name, _ handler: @escaping (ShellCoordinator) -> Void) {
        observe(name) { coordinator, _ in handler(coordinator) }
    }

    private func observe(_ name: Notification.Name,
                         _ handler: @escaping (ShellCoordinator, Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { handler(ShellCoordinator.shared, note) }
        })
    }

    /// Called from the App body so the coordinator always holds the current environment actions.
    func bind(open: OpenImmersiveSpaceAction, dismiss: DismissImmersiveSpaceAction) {
        openAction = open
        dismissAction = dismiss
    }

    // MARK: - Activity state

    private func windowStateDescription() -> String {
        var parts: [String] = []
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
            where scene.session.role == .windowApplication {
            var desc = "scene(\(scene.windows.count))"
            for (index, window) in scene.windows.enumerated() {
                desc += String(format: " w%d[hidden=%@ alpha=%.2f level=%.1f]",
                               index, window.isHidden ? "true" : "false",
                               window.alpha, window.windowLevel.rawValue)
            }
            parts.append(desc)
        }
        return parts.isEmpty ? "windows=no-window-scenes" : "windows=" + parts.joined(separator: " ")
    }

    private func refreshActivityStates(_ reason: String) {
        appActive = UIApplication.shared.applicationState == .active
        windowSceneActive = false
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
            where scene.session.role == .windowApplication {
            if scene.activationState == .foregroundActive { windowSceneActive = true }
        }
        shellLog("activity \(reason) appActive=\(appActive) windowSceneActive=\(windowSceneActive) \(windowStateDescription()) scenes=[\(sceneStateDescription())]")
    }

    /// Every connected scene with its session role and activation state. This is the objective proof of
    /// whether the immersive-space scene (CPSceneSessionRoleImmersiveSpaceApplication) is actually active
    /// and therefore whether the system should be displaying our CompositorServices layer.
    private func sceneStateDescription() -> String {
        var parts: [String] = []
        for scene in UIApplication.shared.connectedScenes {
            let role = scene.session.role.rawValue
            let state: String
            switch scene.activationState {
            case .foregroundActive: state = "fgActive"
            case .foregroundInactive: state = "fgInactive"
            case .background: state = "background"
            case .unattached: state = "unattached"
            @unknown default: state = "unknown"
            }
            parts.append("\(role):\(state)")
        }
        return parts.joined(separator: ",")
    }

    /// Periodic scene/immersion state while the immersive session is live (objective display evidence).
    private func startSceneStateLoop() {
        sceneStateTask?.cancel()
        sceneStateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                if Task.isCancelled { return }
                shellLog("STATE immersive=\(self.immersiveOpen) presenting=\(self.presenting) appActive=\(self.appActive) appState=\(UIApplication.shared.applicationState.rawValue) scenes=[\(self.sceneStateDescription())] \(self.windowStateDescription())")
            }
        }
    }

    // MARK: - Game start / self-test

    private func gameDidStart() {
        shellLog("VRMCGameStarted received")
        gameStarted = true
        Task {
            // Let the game create its renderer/provider first (provider init + first frames).
            try? await Task.sleep(for: .seconds(15))
            openVR(reason: "auto")
        }
    }

    /// Self-test: every second for up to 15 s, try to open the immersive space even though
    /// VRMCGameStarted never fired. Requires only that the SwiftUI app is foreground-active and the
    /// environment action is bound, so a plain devicectl process launch works (no JIT).
    private func scheduleSelfTestOpen() {
        shellLog("SELFTEST: vrmc-immersive-selftest.flag present; immersive space will open without the game")
        Task { [weak self] in
            guard let self else { return }
            // Let the WindowGroup/scene finish activating before the first attempt (~3 s after launch).
            try? await Task.sleep(for: .seconds(3))
            for attempt in 1...15 {
                try? await Task.sleep(for: .seconds(1))
                if self.immersiveOpen || self.opening { return }
                guard self.openAction != nil else {
                    if attempt % 5 == 0 { self.shellLogSafe("SELFTEST: openImmersiveSpace action not bound yet (attempt \(attempt))") }
                    continue
                }
                guard self.appActive && self.windowSceneActive else {
                    if attempt % 5 == 0 {
                        self.shellLogSafe("SELFTEST: waiting for foreground-active scene (attempt \(attempt) appActive=\(self.appActive) windowActive=\(self.windowSceneActive))")
                    }
                    continue
                }
                self.shellLogSafe("SELFTEST: opening immersive space (attempt \(attempt))")
                self.openVR(reason: "selftest")
                try? await Task.sleep(for: .seconds(2))
                if self.immersiveOpen || self.opening { return }
            }
            self.shellLogSafe("SELFTEST: gave up opening the immersive space after 15 s")
        }
    }

    // MARK: - Compositor notifications

    /// The compositor's first presented frame of this session. Parking the 2D windows before this
    /// (or hiding them at all) is what the device logs correlate with scene deactivation.
    private func compositorDidStartPresenting(generation: Int32?) {
        let generationText = generation.map(String.init) ?? "nil"
        shellLog("VRMCCompositorRunning generation=\(generationText) immersive=\(immersiveOpen) selftest=\(selftestMode) \(windowStateDescription())")
        presenting = true
        statusMessage = "VR presenting"
        lastOpenError = nil
        // Audible canary: the operator can confirm the first presented frame even if they are not
        // looking at the centre of the field of view (diagnostic only; system sound, no asset).
        AudioServicesPlaySystemSound(1057)
        noFrameTask?.cancel()
        noFrameTask = nil
        guard immersiveOpen else {
            shellLog("VRMCCompositorRunning ignored for parking: immersive space not open")
            return
        }
        if selftestMode {
            shellLog("SELFTEST: compositor presenting; windows left visible for the self-test (no parking)")
            return
        }
        if noParking {
            shellLog("parking disabled by vrmc-no-parking.flag; windows left untouched")
            return
        }
        setGameWindowsVisible(false, log: "window parked after first presented frame")
        startParkingLoop()
        startSceneStateLoop()
    }

    private func compositorDidEnd(generation: Int32?) {
        let current = VRMCCompositor_CurrentGeneration()
        shellLog("VRMCImmersiveEnded generation=\(generation.map(String.init) ?? "nil") current=\(current) presenting=\(presenting) \(windowStateDescription())")
        // A session that ended after a newer one was opened must not close the newer one.
        if let generation, generation != current {
            shellLog("ignoring stale generation=\(generation) current=\(current)")
            return
        }
        epoch += 1
        let myEpoch = epoch
        let hadPresentedFrame = presenting
        presenting = false
        statusMessage = "VR ended — window restored"
        AudioServicesPlaySystemSound(1073)
        noFrameTask?.cancel()
        noFrameTask = nil
        parkingTask?.cancel()
        parkingTask = nil
        sceneStateTask?.cancel()
        sceneStateTask = nil
        immersiveOpen = false
        needsDismiss = true
        setGameWindowsVisible(true, log: "window restored")

        // If the layer died while the app is active and this was our most recent open, a guarded
        // reopen recovers instead of leaving the operator stuck in the 2D window (EV-0086 gen-2 case
        // where the layer invalidated within seconds of opening with no rendered frames).
        let shouldAutoRetry = appActive && (gameStarted || selftestMode) && !reopenOnActive &&
            generation != nil && generation == lastOpenGeneration &&
            Date().timeIntervalSince(lastOpenAt) < 20 && autoRetries < 2
        if shouldAutoRetry {
            autoRetries += 1
            shellLog("auto-retry \(autoRetries)/2 generation=\(generation.map(String.init) ?? "nil") hadPresentedFrame=\(hadPresentedFrame) (layer ended right after opening)")
        } else if !hadPresentedFrame {
            shellLog("layer ended before any presented frame; not auto-retrying (presentation never confirmed)")
        }

        Task { [weak self] in
            guard let self else { return }
            // The compositor may have exited on a stop request while SwiftUI still has the space open;
            // dismiss so a later openImmersiveSpace is not rejected.
            await self.dismissIfCurrent(myEpoch: myEpoch)
            self.shellLogSafe("immersive space dismissed epoch=\(myEpoch)")
            if self.epoch != myEpoch { return }
            if shouldAutoRetry {
                try? await Task.sleep(for: .seconds(2))
                if self.epoch != myEpoch { return }
                if (self.gameStarted || self.selftestMode) && !self.immersiveOpen && self.appActive {
                    self.openVR(reason: "auto-retry")
                }
            } else if self.reopenOnActive && self.appActive && !self.immersiveOpen {
                self.openVR(reason: "ended-while-active")
            }
        }
    }

    private func dismissIfCurrent(myEpoch: Int) async {
        guard epoch == myEpoch, needsDismiss else { return }
        if let dismissAction {
            await dismissAction()
        }
        if epoch == myEpoch { needsDismiss = false }
    }

    private func stopForBackground(_ reason: String) {
        resignGraceTask?.cancel()
        resignGraceTask = nil
        shellLog("\(reason) gameStarted=\(gameStarted) immersive=\(immersiveOpen) presenting=\(presenting) \(windowStateDescription())")
        appActive = false
        windowSceneActive = false
        if gameStarted && (immersiveOpen || opening) {
            reopenOnActive = true
        }
        epoch += 1
        noFrameTask?.cancel()
        noFrameTask = nil
        VRMCCompositor_RequestStop()
    }

    /// A transient scene deactivation (the device log shows willResignActive without a real
    /// background in several sessions) must not end the immersive session. Wait 1.8 s: if
    /// didBecomeActive arrives first the grace is cancelled; only didEnterBackground or the timer
    /// expiry actually requests a compositor stop.
    private func willResignActive() {
        shellLog("willResignActive (grace 1.8 s before stopping the compositor) gameStarted=\(gameStarted) immersive=\(immersiveOpen) presenting=\(presenting) \(windowStateDescription())")
        appActive = false
        windowSceneActive = false
        resignGraceTask?.cancel()
        let startEpoch = epoch
        resignGraceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(1800))
            if Task.isCancelled { return }
            if self.epoch != startEpoch { return }
            if UIApplication.shared.applicationState == .active {
                self.shellLogSafe("willResignActive grace: app is active again; not stopping the compositor")
                return
            }
            self.shellLogSafe("willResignActive grace expired; stopping the compositor")
            self.stopForBackground("willResignActive-grace-expired")
        }
    }

    private func didEnterBackground() {
        resignGraceTask?.cancel()
        resignGraceTask = nil
        stopForBackground("didEnterBackground")
    }

    private func appDidBecomeActive() {
        if resignGraceTask != nil {
            resignGraceTask?.cancel()
            resignGraceTask = nil
            shellLog("willResignActive cancelled by didBecomeActive (compositor not stopped, grace 1.8 s)")
        }
        appActive = true
        refreshActivityStates("didBecomeActive")
        shellLog("didBecomeActive gameStarted=\(gameStarted) immersive=\(immersiveOpen) reopen=\(reopenOnActive) windowActive=\(windowSceneActive)")
        if selftestMode && !immersiveOpen && !opening {
            openVR(reason: "selftest")
            return
        }
        if gameStarted && reopenOnActive && !immersiveOpen && windowSceneActive {
            openVR(reason: "foreground")
        }
    }

    // MARK: - Open / close

    private func openVR(reason: String) {
        guard !immersiveOpen, !opening else { return }
        guard let openAction else {
            shellLog("\(reason): openImmersiveSpace action not bound yet")
            return
        }
        let startEpoch = epoch
        let startReopen = reopenOnActive
        opening = true
        Task { [weak self] in
            guard let self else { return }
            defer { if self.epoch == startEpoch { self.opening = false } }
            // The scene must be foreground-active; opening during activation can be rejected or can
            // produce a layer that immediately invalidates (EV-0086 generation 2).
            for _ in 0..<10 where !(self.appActive && self.windowSceneActive) {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard self.appActive && self.windowSceneActive else {
                self.shellLogSafe("\(reason): scene not foreground-active; deferring open to next activation")
                if reason == "manual" {
                    self.lastOpenError = "The VRMC window must be in front. Look at the app and tap Enter VR again."
                    self.statusMessage = "VR open deferred"
                }
                return
            }
            // Give the scene time to finish activating/transitioning; auto/selftest run immediately.
            if reason != "auto" && reason != "selftest" {
                try? await Task.sleep(for: .seconds(2))
            }
            if self.epoch != startEpoch { self.shellLogSafe("\(reason): aborted before open (epoch changed)"); return }
            // A previous space may still be registered with SwiftUI; dismiss it first and settle.
            if self.needsDismiss {
                if let dismissAction = self.dismissAction { await dismissAction() }
                if self.epoch != startEpoch { self.shellLogSafe("\(reason): aborted after dismiss (epoch changed)"); return }
                self.needsDismiss = false
                try? await Task.sleep(for: .milliseconds(500))
            }
            for attempt in 1...4 {
                if self.epoch != startEpoch { self.shellLogSafe("\(reason): aborted attempt \(attempt) (epoch changed)"); return }
                guard self.appActive, self.windowSceneActive else {
                    self.shellLogSafe("\(reason): app no longer foreground-active; deferring open")
                    return
                }
                let result = await openAction(id: "vr")
                self.shellLogSafe("\(reason) attempt \(attempt) openImmersiveSpace result=\(result) epoch=\(self.epoch) \(self.windowStateDescription())")
                if case .opened = result {
                    self.opening = false
                    self.immersiveOpen = true
                    self.presenting = false
                    self.statusMessage = "VR opened — waiting for first presented frame"
                    self.lastOpenError = nil
                    self.reopenOnActive = false
                    self.autoRetries = 0
                    self.lastOpenGeneration = VRMCCompositor_CurrentGeneration()
                    self.lastOpenAt = Date()
                    self.shellLogSafe("immersive session opened generation=\(self.lastOpenGeneration) chrome=\(self.chromeMode) reason=\(reason); waiting for the first PRESENTED compositor frame before parking windows")
                    self.waitForPresentedFrame(reason: reason)
                    return
                }
                if case .userCancelled = result {
                    self.statusMessage = "VR open cancelled"
                    if reason == "manual" { self.lastOpenError = "Immersive space open was cancelled by the system." }
                    return
                }
                // An error usually means SwiftUI still considers a previous space open.
                if let dismissAction = self.dismissAction { await dismissAction() }
                self.needsDismiss = true
                try? await Task.sleep(for: .seconds(2))
            }
            if reason == "manual" || reason == "auto" || reason == "selftest" {
                self.lastOpenError = "Could not open the immersive space (4 attempts). The window stays usable; tap Enter VR to retry."
                self.statusMessage = "VR open failed"
            }
            self.reopenOnActive = self.reopenOnActive || startReopen
        }
    }

    /// NO-FRAME watchdog: never dismiss, never auto-retry from here. Leaving the space open keeps the
    /// compositor log and the immersive session collectable, which is what makes the next run decisive.
    private func waitForPresentedFrame(reason: String) {
        noFrameTask?.cancel()
        let openedAt = Date()
        let generation = lastOpenGeneration
        noFrameTask = Task { [weak self] in
            guard let self else { return }
            for tick in 1...4 {
                try? await Task.sleep(for: .seconds(8))
                if Task.isCancelled { return }
                if self.presenting { return }
                let elapsed = Int(Date().timeIntervalSince(openedAt))
                if tick == 1 {
                    self.shellLogSafe("NO-FRAME: no presented compositor frame \(elapsed) s after open (reason=\(reason) generation=\(generation) \(self.windowStateDescription())); leaving the immersive space OPEN (no dismiss, no retry) - see vrmc-compositor.log")
                } else {
                    self.shellLogSafe("NO-FRAME heartbeat \(tick)/4: still no presented compositor frame \(elapsed) s after open (reason=\(reason)); space left open")
                }
            }
        }
    }

    private func shellLogSafe(_ message: String) {
        shellLog(message)
    }

    // MARK: - Window parking

    /// Park/show the regular windows. Default parking is alpha-only: the window stays in the scene
    /// (isHidden is never set), it is just transparent and non-interactive. Hiding every window is
    /// followed by UIScene.willDeactivate in the EV-0090 device logs, which is the suspected cause of
    /// the scene deactivation/backgrounding that kills the immersive session.
    /// vrmc-hide-windows.flag restores the old hide behaviour for A/B.
    /// Keep the game/launcher windows parked for the whole immersive session (see parkingTask).
    private func startParkingLoop() {
        parkingTask?.cancel()
        parkingTask = Task { [weak self] in
            var lastSignature = ""
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if Task.isCancelled { return }
                guard self.immersiveOpen, self.presenting, !self.noParking else { continue }
                let signature = self.windowStateDescription()
                if signature != lastSignature {
                    lastSignature = signature
                    self.setGameWindowsVisible(false, log: "window re-parked (periodic)")
                } else {
                    self.reapplyWindowParking()
                }
            }
        }
    }

    /// Re-apply the parked values without logging on every tick.
    private func reapplyWindowParking() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
            where scene.session.role == .windowApplication {
            for window in scene.windows {
                window.alpha = 0
                window.isUserInteractionEnabled = false
                if hideWindowsOptIn { window.isHidden = true }
            }
        }
    }

    private func setGameWindowsVisible(_ visible: Bool, log: String) {
        var count = 0
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
            where scene.session.role == .windowApplication {
            for window in scene.windows {
                if visible {
                    window.alpha = 1
                    window.isUserInteractionEnabled = true
                    if hideWindowsOptIn { window.isHidden = false }
                } else {
                    window.alpha = 0
                    window.isUserInteractionEnabled = false
                    if hideWindowsOptIn { window.isHidden = true }
                }
                count += 1
            }
        }
        windowsParked = !visible
        let mode = hideWindowsOptIn ? "hide+alpha0 (opt-in)" : "alpha-only (never isHidden)"
        shellLog("\(log) windows=\(count) visible=\(visible) mode=\(mode) chrome=\(chromeMode) parked=\(windowsParked) \(windowStateDescription())")
    }
}

/// Minimal window control surface for the staged immersive entry (Option 2): the launcher stays in
/// the window while this overlay adds an explicit "Enter VR" trigger, the current immersive status and
/// any actionable error. It lets the CompositorServices path be validated manually, independently of
/// the JIT/game timing; the automatic open after the game starts stays enabled.
struct VRControlOverlay: View {
    let shell: ShellCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { shell.enterVRManually() }) {
                HStack(spacing: 8) {
                    Image(systemName: "visionpro")
                    Text(shell.immersiveOpen ? "VR active" : "Enter VR")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(shell.immersiveOpen ? Color.green.opacity(0.25) : Color.accentColor.opacity(0.30))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(shell.immersiveOpen)

            Text(shell.statusMessage).font(.caption).foregroundStyle(.secondary)
            if let error = shell.lastOpenError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("Automatic VR opens ~15 s after the game starts; this button is the manual path.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(20)
    }
}

@main
struct VRMCShellApp: App {
    @State private var shell = ShellCoordinator.shared
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some Scene {
        shell.bind(open: openImmersiveSpace, dismiss: dismissImmersiveSpace)
        return scenes
    }

    @SceneBuilder private var scenes: some Scene {
        WindowGroup {
            ZStack(alignment: .topLeading) {
                LauncherHostView()
                    .onAppear { shellLog("launcher host appeared") }
                VRControlOverlay(shell: shell)
            }
        }
        // For a WindowGroup this controls the window chrome (bottom bar / ornaments). Scene-level so it
        // applies to the whole game session; with the M3b modal game-surface presentation the SwiftUI
        // scene stays alive, so this preference survives the game launch (EV-0086 regression).
        .persistentSystemOverlays((shell.immersiveOpen || shell.hideChromeAlways) ? .hidden : .automatic)

        ImmersiveSpace(id: "vr") {
            CompositorLayer(configuration: ShellLayerConfiguration()) { layerRenderer in
                VRMCCompositor_InitAndRun(layerRenderer)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
