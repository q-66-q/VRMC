import Foundation
import SwiftUI
import UIKit

/// App-level lifecycle recorder for the M3C probe.
///
/// Reproduces the notification set the real shell uses (Shell.swift's ShellCoordinator):
///   UIApplication.willResignActive / didBecomeActive / didEnterBackground / willEnterForeground
///   UIScene.didActivate / willDeactivate / didEnterBackground / willEnterForeground
/// plus SwiftUI scenePhase, 1 Hz window-state ticks, and the window "parking" variants under test.
///
/// It deliberately does NOT stop the compositor when the app resigns active: the question is what
/// the *system* does to the window scene and the immersive space, not what the shell does on top.
final class M3CLifecycle {
    static let shared = M3CLifecycle()

    let cfg = M3CConfig.fromProcess()
    private(set) var appStateString: String = "unknown"
    private(set) var spaceOpen = false
    private(set) var parked = false
    private(set) var windowParkedCount = 0
    private(set) var swiftUIScenePhase = "unknown"
    private var openAction: OpenImmersiveSpaceAction?
    private var dismissAction: DismissImmersiveSpaceAction?
    private var openWindowAction: OpenWindowAction?
    private var observers: [NSObjectProtocol] = []
    private var tickTimer: Timer?
    private var tick = 0
    private var openCount = 0
    private var didStart = false
    private var reopenedOnce = false
    /// Session id of the window scene hosting the main content (used by -M3CParkScope main).
    private var mainSceneID: String?
    private let startedAt = CFAbsoluteTimeGetCurrent()

    private init() {}

    // MARK: - Setup

    func bind(open: OpenImmersiveSpaceAction,
              dismiss: DismissImmersiveSpaceAction,
              openWindow: OpenWindowAction) {
        openAction = open
        dismissAction = dismiss
        openWindowAction = openWindow
        M3CLog.shell("actions bound (open/dismiss immersive space, openWindow)")
    }

    func start() {
        guard !didStart else {
            M3CLog.shell("start() called again; ignoring")
            return
        }
        didStart = true
        M3CLog.shell("================ M3C lifecycle probe start ================")
        M3CLog.shell("config \(cfg.summary)")
        M3CLog.shell("argv \(CommandLine.arguments)")
        refreshAppState("start")
        installObservers()
        captureMainSceneID()
        M3CLog.shell("windows at start: \(windowDump())")
        startTicker()
        scheduleSecondWindowIfNeeded()
        scheduleSequence()
    }

    private func captureMainSceneID() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.session.role == .windowApplication else { continue }
            mainSceneID = windowScene.session.persistentIdentifier
            M3CLog.shell("main window scene id=\(shortID(mainSceneID))")
            return
        }
    }

    private func installObservers() {
        observe(UIApplication.didFinishLaunchingNotification, "UIApplication.didFinishLaunching")
        observe(UIApplication.willResignActiveNotification, "UIApplication.willResignActive")
        observe(UIApplication.didBecomeActiveNotification, "UIApplication.didBecomeActive")
        observe(UIApplication.didEnterBackgroundNotification, "UIApplication.didEnterBackground")
        observe(UIApplication.willEnterForegroundNotification, "UIApplication.willEnterForeground")
        observe(UIScene.willDeactivateNotification, "UIScene.willDeactivate")
        observe(UIScene.didActivateNotification, "UIScene.didActivate")
        observe(UIScene.didEnterBackgroundNotification, "UIScene.didEnterBackground")
        observe(UIScene.willEnterForegroundNotification, "UIScene.willEnterForeground")
        observe(UIScene.didDisconnectNotification, "UIScene.didDisconnect")
    }

    private func observe(_ name: Notification.Name, _ label: String) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            self?.handleEvent(label, note: note)
        }
        observers.append(token)
    }

    private func handleEvent(_ label: String, note: Notification) {
        refreshAppState(label)
        var sceneDetail = ""
        if let scene = note.object as? UIScene {
            sceneDetail = " scene(role=\(sceneRole(scene)) sid=\(shortID(scene.session.persistentIdentifier)) " +
                "activation=\(activationString(scene.activationState)))"
        }
        let s = M3CStats.shared.snapshot()
        M3CLog.shell("EVENT \(label)\(sceneDetail) app=\(appStateString) scenePhase=\(swiftUIScenePhase) " +
                     "spaceOpen=\(spaceOpen) parked=\(parked) " +
                     "comp(frames=\(s.frames) state=\(s.state) presentAge=\(fmt(s.presentAge))) | \(windowDump())")
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        swiftUIScenePhase = String(describing: phase)
        let s = M3CStats.shared.snapshot()
        M3CLog.shell("EVENT SwiftUI.scenePhase=\(swiftUIScenePhase) app=\(appStateString) " +
                     "spaceOpen=\(spaceOpen) parked=\(parked) " +
                     "comp(frames=\(s.frames) state=\(s.state)) | \(windowDump())")
    }

    // MARK: - Sequence

    private func scheduleSecondWindowIfNeeded() {
        guard cfg.secondWindow else { return }
        M3CLog.shell("scheduling second window open in 0.5 s (kept visible for the test)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.openSecondWindow()
        }
    }

    private func openSecondWindow() {
        guard let openWindowAction else {
            M3CLog.shell("openSecondWindow: openWindow action not bound")
            return
        }
        openWindowAction(id: "second")
        M3CLog.shell("openWindow(id: second) requested | \(windowDump())")
    }

    private func scheduleSequence() {
        guard cfg.autoOpen else {
            M3CLog.shell("autoOpen disabled (control run): the immersive space is never opened")
            return
        }
        let delay = max(0, cfg.openDelay)
        M3CLog.shell("scheduling immersive open in \(delay) s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.openSpace(reason: "auto")
        }
    }

    private func openSpace(reason: String) {
        guard !spaceOpen else {
            M3CLog.shell("openSpace(\(reason)) skipped: space already open")
            return
        }
        guard let openAction else {
            M3CLog.shell("openSpace(\(reason)): open action not bound yet")
            return
        }
        openCount += 1
        let attempt = openCount
        M3CLog.shell("OPEN begin reason=\(reason) attempt=\(attempt) | \(windowDump())")
        Task { @MainActor in
            let result = await openAction(id: "m3c")
            M3CLog.shell("OPEN result=\(result) reason=\(reason) attempt=\(attempt) | \(self.windowDump())")
            if case .opened = result {
                self.spaceOpen = true
                M3CLog.shell("OPEN immersive space opened; scheduling parking according to " +
                             "park=\(self.cfg.park) parkWhen=\(self.cfg.parkWhen) parkScope=\(self.cfg.parkScope)")
                self.parkIfNeeded(reason: reason)
                self.scheduleRestore()
                self.scheduleReopenIfNeeded()
            }
        }
    }

    private func parkIfNeeded(reason: String) {
        if cfg.park == "none" {
            M3CLog.shell("PARK skipped (park=none) reason=\(reason)")
            return
        }
        if cfg.parkWhen == "firstframe" {
            M3CLog.shell("PARK waiting for the first compositor frame (reason=\(reason))")
            Task { @MainActor in
                var waited = 0.0
                while M3CStats.shared.snapshot().frames == 0 && waited < 20.0 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    waited += 0.1
                }
                let s = M3CStats.shared.snapshot()
                M3CLog.shell(String(format: "PARK first-frame wait finished waited=%.2fs frames=%d state=%@",
                                    waited, s.frames, s.state))
                self.park(mode: self.cfg.park, reason: reason + "-firstframe")
            }
        } else {
            park(mode: cfg.park, reason: reason + "-open")
        }
    }

    private func park(mode: String, reason: String) {
        M3CLog.shell("PARK begin mode=\(mode) scope=\(cfg.parkScope) reason=\(reason) | before: \(windowDump())")
        var touched = 0
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.session.role == .windowApplication else { continue }
            if cfg.parkScope == "main", windowScene.session.persistentIdentifier != mainSceneID {
                M3CLog.shell("PARK skip scene sid=\(shortID(windowScene.session.persistentIdentifier)) (scope=main)")
                continue
            }
            for (windowIndex, window) in windowScene.windows.enumerated() {
                let root = window.rootViewController.map { String(describing: type(of: $0)) } ?? "nil"
                switch mode {
                case "hidden":
                    window.alpha = 0
                    window.isHidden = true
                    window.isUserInteractionEnabled = false
                case "alpha":
                    window.alpha = 0
                    window.isUserInteractionEnabled = false
                case "tinyalpha":
                    window.alpha = 0.01
                    window.isUserInteractionEnabled = false
                case "contentalpha":
                    window.rootViewController?.view.alpha = 0
                case "contenthidden":
                    window.rootViewController?.view.isHidden = true
                case "transparent":
                    // Keep the UIWindow attached and "visible" to the system but render it fully
                    // transparent: clear window background + invisible root view content.
                    window.isHidden = false
                    window.alpha = 1
                    window.isUserInteractionEnabled = false
                    window.isOpaque = false
                    window.backgroundColor = .clear
                    window.rootViewController?.view.alpha = 0
                default:
                    break
                }
                touched += 1
                M3CLog.shell("PARK w\(windowIndex) root=\(root) mode=\(mode) -> " +
                             "window(hidden=\(window.isHidden) alpha=\(String(format: "%.2f", window.alpha))) " +
                             "rootView(hidden=\(window.rootViewController?.view.isHidden ?? false) " +
                             "alpha=\(String(format: "%.2f", window.rootViewController?.view.alpha ?? 1)))")
            }
        }
        parked = true
        windowParkedCount = touched
        M3CLog.shell("PARK done mode=\(mode) scope=\(cfg.parkScope) reason=\(reason) touched=\(touched) | after: \(windowDump())")
    }

    private func scheduleRestore() {
        guard cfg.restoreAfter >= 0 else { return }
        M3CLog.shell("scheduling window restore in \(cfg.restoreAfter) s")
        DispatchQueue.main.asyncAfter(deadline: .now() + cfg.restoreAfter) { [weak self] in
            self?.restore(reason: "restore-timer")
        }
    }

    private func restore(reason: String) {
        M3CLog.shell("RESTORE begin reason=\(reason) | before: \(windowDump())")
        var touched = 0
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.session.role == .windowApplication else { continue }
            for window in windowScene.windows {
                window.alpha = 1
                window.isHidden = false
                window.isUserInteractionEnabled = true
                window.isOpaque = true
                window.backgroundColor = nil
                window.rootViewController?.view.alpha = 1
                window.rootViewController?.view.isHidden = false
                touched += 1
            }
        }
        parked = false
        windowParkedCount = 0
        M3CLog.shell("RESTORE done reason=\(reason) touched=\(touched) | after: \(windowDump())")
    }

    private func scheduleReopenIfNeeded() {
        guard cfg.reopen, !reopenedOnce else { return }
        reopenedOnce = true
        M3CLog.shell("scheduling dismiss+reopen in \(cfg.reopenAfter) s")
        DispatchQueue.main.asyncAfter(deadline: .now() + cfg.reopenAfter) { [weak self] in
            self?.closeAndReopen()
        }
    }

    private func closeAndReopen() {
        M3CLog.shell("REOPEN phase 1: dismiss | before: \(windowDump())")
        Task { @MainActor in
            if let dismissAction = self.dismissAction {
                await dismissAction()
            }
            self.spaceOpen = false
            M3CLog.shell("REOPEN dismissed | \(self.windowDump())")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.openSpace(reason: "reopen")
        }
    }

    // MARK: - Ticker / state

    private func startTicker() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickLog()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func tickLog() {
        tick += 1
        refreshAppState("tick")
        let s = M3CStats.shared.snapshot()
        M3CLog.shell("TICK t=\(tick)s app=\(appStateString) scenePhase=\(swiftUIScenePhase) " +
                     "spaceOpen=\(spaceOpen) parked=\(parked) " +
                     "comp(frames=\(s.frames) state=\(s.state) runs=\(s.runs) inv=\(s.invalidations) " +
                     "presentAge=\(fmt(s.presentAge)) frameInterval=\(fmt(s.frameInterval))) | \(windowDump())")
    }

    private func refreshAppState(_ reason: String) {
        switch UIApplication.shared.applicationState {
        case .active: appStateString = "active"
        case .inactive: appStateString = "inactive"
        case .background: appStateString = "background"
        @unknown default: appStateString = "unknown"
        }
    }

    // MARK: - Window / scene description

    private func windowDump() -> String {
        var parts: [String] = []
        var index = 0
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            var windows: [String] = []
            for (windowIndex, window) in windowScene.windows.enumerated() {
                let root = window.rootViewController.map { String(describing: type(of: $0)) } ?? "nil"
                let alpha = String(format: "%.2f", window.alpha)
                let level = String(format: "%.1f", window.windowLevel.rawValue)
                let rootAlpha = String(format: "%.2f", window.rootViewController?.view.alpha ?? 1)
                let head = "w\(windowIndex)[hidden=\(window.isHidden) alpha=\(alpha) level=\(level)"
                let tail = " key=\(window.isKeyWindow) rootAlpha=\(rootAlpha) root=\(root)]"
                windows.append(head + tail)
            }
            let role = sceneRole(windowScene)
            let activation = activationString(windowScene.activationState)
            let sid = shortID(windowScene.session.persistentIdentifier)
            let header = "scene\(index)(role=\(role) sid=\(sid) activation=\(activation) count=\(windowScene.windows.count)) "
            parts.append(header + windows.joined(separator: " "))
            index += 1
        }
        return parts.isEmpty ? "no-window-scenes" : parts.joined(separator: "  ")
    }

    private func shortID(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "nil" }
        return String(id.suffix(6))
    }

    private func sceneRole(_ scene: UIScene) -> String {
        if scene.session.role == .windowApplication { return "windowApplication" }
        return String(describing: scene.session.role)
    }

    private func activationString(_ state: UIScene.ActivationState) -> String {
        switch state {
        case .unattached: return "unattached"
        case .foregroundInactive: return "foregroundInactive"
        case .foregroundActive: return "foregroundActive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    private func fmt(_ value: Double) -> String {
        value < 0 ? "n/a" : String(format: "%.2f", value)
    }
}
