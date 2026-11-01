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
/// Amethyst's `UIKit_launchMinecraftSurfaceVC` replaces the window's root view controller with
/// `SurfaceViewController` (and Amethyst code relies on that), which tears down the WindowGroup's SwiftUI
/// view. Everything that must outlive the launcher UI — game-start, compositor-ended and app lifecycle
/// observers, and the open/dismiss immersive actions — therefore lives here, not in a view.
@MainActor
@Observable
final class ShellCoordinator {
    static let shared = ShellCoordinator()

    /// Drives the WindowGroup chrome visibility (scene-level, survives the root VC replacement).
    private(set) var immersiveOpen = false

    @ObservationIgnored private var gameStarted = false
    /// Set when the immersive session was ended by backgrounding/resigning; cleared once it is reopened.
    @ObservationIgnored private var reopenOnActive = false
    @ObservationIgnored private var opening = false
    @ObservationIgnored private var openAction: OpenImmersiveSpaceAction?
    @ObservationIgnored private var dismissAction: DismissImmersiveSpaceAction?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        observe(Notification.Name("VRMCGameStarted")) { $0.gameDidStart() }
        observe(Notification.Name("VRMCImmersiveEnded")) { coordinator, note in
            coordinator.compositorDidEnd(generation: note.userInfo?["generation"] as? Int32)
        }
        observe(UIApplication.willResignActiveNotification) { $0.stopForBackground("willResignActive") }
        observe(UIApplication.didEnterBackgroundNotification) { $0.stopForBackground("didEnterBackground") }
        observe(UIApplication.didBecomeActiveNotification) { $0.appDidBecomeActive() }
        shellLog("coordinator ready")
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
        if let generation, generation != current { return }
        immersiveOpen = false
        setGameWindowsVisible(true, log: "window restored")
        Task {
            // The compositor may have exited on a stop request while SwiftUI still has the space open;
            // dismiss so a later openImmersiveSpace is not rejected.
            await dismissAction?()
            shellLog("immersive space dismissed")
            if reopenOnActive && UIApplication.shared.applicationState == .active {
                openVR(reason: "ended-while-active")
            }
        }
    }

    private func stopForBackground(_ reason: String) {
        shellLog("\(reason) gameStarted=\(gameStarted) immersive=\(immersiveOpen)")
        if gameStarted && (immersiveOpen || opening) {
            reopenOnActive = true
        }
        VRMCCompositor_RequestStop()
    }

    private func appDidBecomeActive() {
        shellLog("didBecomeActive gameStarted=\(gameStarted) immersive=\(immersiveOpen) reopen=\(reopenOnActive)")
        if gameStarted && reopenOnActive && !immersiveOpen {
            openVR(reason: "foreground")
        }
    }

    private func openVR(reason: String) {
        guard !immersiveOpen, !opening else { return }
        guard let openAction else {
            shellLog("\(reason): openImmersiveSpace action not bound yet")
            return
        }
        opening = true
        Task {
            defer { opening = false }
            if reason != "auto" {
                // Give the scene time to finish activating; opening during activation is rejected.
                try? await Task.sleep(for: .seconds(1))
            }
            for attempt in 1...4 {
                guard UIApplication.shared.applicationState != .background else {
                    shellLog("\(reason): app in background; deferring open to next activation")
                    return
                }
                let result = await openAction(id: "vr")
                shellLog("\(reason) attempt \(attempt) openImmersiveSpace result=\(result)")
                if case .opened = result {
                    immersiveOpen = true
                    reopenOnActive = false
                    setGameWindowsVisible(false, log: "window parked")
                    return
                }
                if case .userCancelled = result { return }
                // `.error` usually means SwiftUI still considers a previous space open.
                await dismissAction?()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Hide/show the content of regular windows (not the immersive space). The window chrome is hidden
    /// separately via the scene-level `persistentSystemOverlays` bound to `immersiveOpen`.
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
        shellLog("\(log) windows=\(count) visible=\(visible)")
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
        // still applies after Amethyst swaps the window's root view controller for the game surface.
        .persistentSystemOverlays(shell.immersiveOpen ? .hidden : .automatic)

        ImmersiveSpace(id: "vr") {
            CompositorLayer(configuration: ShellLayerConfiguration()) { layerRenderer in
                VRMCCompositor_InitAndRun(layerRenderer)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
