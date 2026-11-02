import SwiftUI
import CompositorServices
import Metal

struct ProbeLayerConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities,
                           configuration: inout LayerRenderer.Configuration) {
        configuration.layout = .dedicated
        configuration.isFoveationEnabled = false
        configuration.colorFormat = .rgba16Float
    }
}

@main
struct M3BProbeApp: App {
    @State private var status = "starting"
    @State private var immersiveOpen = false
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Text("VRMC M3b reprojection probe").font(.title)
                Text(status).multilineTextAlignment(.center).padding()
            }
            .padding()
            .onAppear { autoOpen() }
        }
        ImmersiveSpace(id: "probe") {
            CompositorLayer(configuration: ProbeLayerConfiguration()) { layerRenderer in
                VRMCProbe_InitAndRun(layerRenderer)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }

    private func autoOpen() {
        guard !immersiveOpen else { return }
        immersiveOpen = true
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            let result = await openImmersiveSpace(id: "probe")
            status = "openImmersiveSpace: \(result)"
            NSLog("[m3b-swift] openImmersiveSpace result=\(result)")
        }
    }
}
