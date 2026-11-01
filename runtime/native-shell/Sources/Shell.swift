import SwiftUI
import CompositorServices

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
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some Scene {
        WindowGroup {
            LauncherHostView()
                .onAppear { shellLog("launcher host appeared") }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("VRMCGameStarted"))) { _ in
                    shellLog("VRMCGameStarted received")
                    guard !immersiveOpen else { return }
                    immersiveOpen = true
                    Task {
                        // Let the game create its renderer/provider first; opening the immersive space
                        // while Minecraft is still initializing caused a Vulkan device-loss during
                        // bring-up. Keep a short settle delay before presenting.
                        try? await Task.sleep(nanoseconds: 15_000_000_000)
                        let result = await openImmersiveSpace(id: "vr")
                        shellLog("auto openImmersiveSpace result=\(String(describing: result))")
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
