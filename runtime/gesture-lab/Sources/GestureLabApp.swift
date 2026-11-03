import SwiftUI

enum LabSpace {
    static let id = "handlab"
}

@main
struct GestureLabApp: App {
    @StateObject private var model = LabModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: LabSpace.id) {
            ImmersiveLabView()
                .environmentObject(model)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
