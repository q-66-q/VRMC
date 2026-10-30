import SwiftUI
import CompositorServices

@main
struct VRMCApp: App {
    @StateObject private var model = AppModel()
    @State private var immersionStyle: ImmersionStyle = .full

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: "VRMC") {
            CompositorLayer(configuration: VRMCConfiguration()) { layerRenderer in
                let renderer = StereoRenderer(layerRenderer: layerRenderer, frameStore: model.frameStore)
                renderer.start()
            }
        }
        .immersionStyle(selection: $immersionStyle, in: .full)
        .upperLimbVisibility(.hidden)
    }
}

struct VRMCConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(
        capabilities: LayerRenderer.Capabilities,
        configuration: inout LayerRenderer.Configuration
    ) {
        configuration.colorFormat = .rgba16Float
        configuration.depthFormat = .depth32Float
        configuration.isFoveationEnabled = false
        configuration.layout = .dedicated
    }
}
