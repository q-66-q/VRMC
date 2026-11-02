import SwiftUI
import CompositorServices

/// Layer configuration matching runtime/native-shell/Sources/Shell.swift (dedicated layout,
/// foveation off, rgba16Float) so the probe exercises the same CompositorServices path.
struct M3CLayerConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities,
                           configuration: inout LayerRenderer.Configuration) {
        configuration.layout = .dedicated
        configuration.isFoveationEnabled = false
        configuration.colorFormat = .rgba16Float
    }
}

/// Minimal reproduction of the VRMC shell architecture:
///  - WindowGroup hosting a plain UIKit view controller (like the launcher host)
///  - ImmersiveSpace(id:) with a CompositorServices CompositorLayer rendering a bright test pattern
///  - app/scene/window lifecycle logging and the diagnostic "park the window" variants
///    selected through launch arguments (see M3CConfig.swift).
@main
struct M3CApp: App {
    var body: some Scene {
        WindowGroup {
            M3CContent()
        }
        // Optional second window, used only by the -M3CSecondWindow 1 diagnostic: keeping an extra
        // visible window lets us test "window scene deactivated" independently of "app backgrounded".
        WindowGroup(id: "second") {
            SecondWindowView()
        }
        ImmersiveSpace(id: "m3c") {
            CompositorLayer(configuration: M3CLayerConfiguration()) { layerRenderer in
                M3CCompositor.shared.start(layerRenderer: layerRenderer)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}

struct SecondWindowView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("VRMC M3C second window").font(.title2)
            Text("kept visible for the deactivation-vs-background test").font(.body)
        }
        .padding()
        .onAppear { M3CLog.shell("second window appeared") }
    }
}
