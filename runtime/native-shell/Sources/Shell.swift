import SwiftUI
import CompositorServices
import UIKit
import Observation

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

private func shellDocumentFlag(_ name: String) -> Bool {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return FileManager.default.fileExists(atPath: docs.appendingPathComponent(name).path)
}

@_cdecl("vrmc_shell_start")
public func vrmcShellStart() -> Int32 {
    shellLog("vrmc_shell_start invoked")
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
/// Reopen hardening (EV-0086 generation-2 invalidation): every transition bumps an epoch; awaited
/// open/dismiss work is epoch-guarded so a stale teardown cannot kill a newer session; an open only
/// runs while both the app and its window scene are foreground-active, after a settle delay and with a
/// confirmed dismiss of any previous space; a layer that invalidates right after opening triggers a
/// bounded automatic retry (2 attempts) instead of leaving the operator in the 2D window.
@MainActor
@Observable
final class ShellCoordinator {
    static let shared = ShellCoordinator()

    /// Drives the WindowGroup chrome visibility (scene-level, survives game presentation).
    private(set) var immersiveOpen = false

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

    /// Keep the window chrome hidden for the whole launch (diagnostic A/B for EV-0086 issue 1).
    private(set) var hideChromeAlways = false
    private(set) var chromeMode = "automatic"

    private init() {
        hideChromeAlways = shellDocumentFlag("vrmc-hide-chrome-always.flag")
        chromeMode = hideChromeAlways ? "hidden-always" : "hidden-when-immersive"
        observe(Notification.Name("VRMCGameStarted")) { $0.gameDidStart() }
        observe(Notification.Name("VRMCImmersiveEnded")) { coordinator, note in
            coordinator.compositorDidEnd(generation: note.userInfo?["generation"] as? Int32)
        }
        observe(UIApplication.willResignActiveNotification) { $0.stopForBackground("willResignActive") }
        observe(UIApplication.didEnterBackgroundNotification) { $0.stopForBackground("didEnterBackground") }
        observe(UIApplication.didBecomeActiveNotification) { $0.appDidBecomeActive() }
        observe(UIApplication.didFinishLaunchingNotification) { $0.refreshActivityStates("didFinishLaunching") }
        observe(UIScene.didActivateNotification) { $0.refreshActivityStates("UIScene.didActivate") }
        observe(UIScene.willDeactivateNotification) { $0.refreshActivityStates("UIScene.willDeactivate") }
        refreshActivityStates("init")
        shellLog("coordinator ready chromeMode=\(chromeMode)")
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

    private func refreshActivityStates(_ reason: String) {
        appActive = UIApplication.shared.applicationState == .active
        windowSceneActive = false
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
            where scene.session.role == .windowApplication {
            if scene.activationState == .foregroundActive { windowSceneActive = true }
        }
        shellLog("activity \(reason) appActive=\(appActive) windowSceneActive=\(windowSceneActive)")
    }

    private func gameDidStart() {
        shellLog("VRMCGameStarted received")
        gameStarted = true
        Task {
            // Let the game create its renderer/provider first (provider init + first frames).
            try? await Task.sleep(for: .seconds(15))
            openVR(reason: "auto")
        }
    }

    private func compositorDidEnd(generation: Int32?) {
        let current = VRMCCompositor_CurrentGeneration()
        shellLog("VRMCImmersiveEnded generation=\(generation.map(String.init) ?? "nil") current=\(current)")
        // A session that ended after a newer one was opened must not close the newer one.
        if let generation, generation != current {
            shellLog("ignoring stale generation=\(generation) current=\(current)")
            return
        }
        epoch += 1
        let myEpoch = epoch
        immersiveOpen = false
        needsDismiss = true
        setGameWindowsVisible(true, log: "window restored")

        // If the layer died while the app is active and this was our most recent open, a guarded
        // reopen recovers instead of leaving the operator stuck in the 2D window (EV-0086 gen-2 case
        // where the layer invalidated within seconds of opening with no rendered frames).
        let shouldAutoRetry = appActive && gameStarted && !reopenOnActive &&
            generation != nil && generation == lastOpenGeneration &&
            Date().timeIntervalSince(lastOpenAt) < 15 && autoRetries < 2
        if shouldAutoRetry {
            autoRetries += 1
            shellLog("auto-retry \(autoRetries)/2 generation=\(generation.map(String.init) ?? "nil") (layer ended right after opening)")
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
                if self.gameStarted && !self.immersiveOpen && self.appActive {
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
        shellLog("\(reason) gameStarted=\(gameStarted) immersive=\(immersiveOpen)")
        appActive = false
        windowSceneActive = false
        if gameStarted && (immersiveOpen || opening) {
            reopenOnActive = true
        }
        epoch += 1
        VRMCCompositor_RequestStop()
    }

    private func appDidBecomeActive() {
        appActive = true
        refreshActivityStates("didBecomeActive")
        shellLog("didBecomeActive gameStarted=\(gameStarted) immersive=\(immersiveOpen) reopen=\(reopenOnActive) windowActive=\(windowSceneActive)")
        if gameStarted && reopenOnActive && !immersiveOpen && windowSceneActive {
            openVR(reason: "foreground")
        }
    }

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
                return
            }
            // Give the scene time to finish activating/transitioning.
            try? await Task.sleep(for: .seconds(reason == "auto" ? 0 : 2))
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
                self.shellLogSafe("\(reason) attempt \(attempt) openImmersiveSpace result=\(result) epoch=\(self.epoch)")
                if case .opened = result {
                    self.opening = false
                    self.immersiveOpen = true
                    self.reopenOnActive = false
                    self.autoRetries = 0
                    self.lastOpenGeneration = VRMCCompositor_CurrentGeneration()
                    self.lastOpenAt = Date()
                    self.setGameWindowsVisible(false, log: "window parked")
                    self.shellLogSafe("immersive session opened generation=\(self.lastOpenGeneration) chrome=\(self.chromeMode) reason=\(reason)")
                    return
                }
                if case .userCancelled = result { return }
                // An error usually means SwiftUI still considers a previous space open.
                if let dismissAction = self.dismissAction { await dismissAction() }
                self.needsDismiss = true
                try? await Task.sleep(for: .seconds(2))
            }
            self.reopenOnActive = self.reopenOnActive || startReopen
        }
    }

    private func shellLogSafe(_ message: String) {
        shellLog(message)
    }

    /// Hide/show the content of regular windows (not the immersive space). The window chrome is hidden
    /// separately via the scene-level persistentSystemOverlays bound to immersiveOpen.
    private func setGameWindowsVisible(_ visible: Bool, log: String) {
        var count = 0
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
            where scene.session.role == .windowApplication {
            for window in scene.windows {
                window.alpha = visible ? 1 : 0
                window.isHidden = !visible
                window.isUserInteractionEnabled = visible
                count += 1
            }
        }
        shellLog("\(log) windows=\(count) visible=\(visible) chrome=\(chromeMode)")
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
            LauncherHostView()
                .onAppear { shellLog("launcher host appeared") }
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
