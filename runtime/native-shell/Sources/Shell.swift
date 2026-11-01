import SwiftUI
import CompositorServices
import UIKit

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

@main
struct VRMCShellApp: App {
    @State private var immersiveOpen = false
    @State private var gameStarted = false
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase

    private func setWindowAlpha(_ alpha: CGFloat, log: String) {
        DispatchQueue.main.async {
            var count = 0
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                for window in scene.windows {
                    window.alpha = alpha
                    window.isUserInteractionEnabled = (alpha > 0.01)
                    count += 1
                }
            }
            shellLog("\(log) windows=\(count) alpha=\(alpha)")
        }
    }

    private func openVR(reason: String) {
        guard !immersiveOpen else { return }
        immersiveOpen = true
        Task {
            let result = await openImmersiveSpace(id: "vr")
            shellLog("\(reason) openImmersiveSpace result=\(String(describing: result))")
            if String(describing: result).contains("opened") {
                setWindowAlpha(0, log: "window parked")
            } else {
                immersiveOpen = false
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            LauncherHostView()
                .onAppear { shellLog("launcher host appeared") }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("VRMCGameStarted"))) { _ in
                    shellLog("VRMCGameStarted received")
                    gameStarted = true
                    Task {
                        // Let the game create its renderer/provider first (provider init + first frames).
                        try? await Task.sleep(nanoseconds: 15_000_000_000)
                        openVR(reason: "auto")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("VRMCImmersiveEnded"))) { _ in
                    shellLog("VRMCImmersiveEnded received")
                    immersiveOpen = false
                    setWindowAlpha(1, log: "window restored")
                }
                .onChange(of: scenePhase) { _, newPhase in
                    shellLog("scenePhase=\(String(describing: newPhase)) gameStarted=\(gameStarted) immersive=\(immersiveOpen)")
                    if newPhase == .active && gameStarted && !immersiveOpen {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            openVR(reason: "foreground")
                        }
                    }
                }
        }
        ImmersiveSpace(id: "vr") {
            CompositorLayer(configuration: ShellLayerConfiguration()) { layerRenderer in
                VRMCCompositor_InitAndRun(layerRenderer)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
