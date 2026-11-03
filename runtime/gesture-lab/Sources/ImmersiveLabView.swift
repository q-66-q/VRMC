import SwiftUI
import RealityKit

struct ImmersiveLabView: View {
    @EnvironmentObject private var model: LabModel

    var body: some View {
        RealityView { content in
            model.setupScene()
            content.add(model.root)
        }
        .task {
            await model.start()
        }
        .onDisappear {
            model.stop()
        }
    }
}
