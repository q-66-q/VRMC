import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: LabModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var immersiveOpen = false

    private let labels = [
        "IDLE",
        "MENU_RIGHT_PINCH",
        "ESCAPE_LEFT_FIST",
        "WALK_BOTH_FISTS",
        "JUMP_HEAD",
        "SNEAK_HEAD",
        "TELEPORT_LEFT_PINCH",
        "ATTACK_RIGHT_SWING",
        "EAT_RIGHT_HAND_HEAD",
        "BOW_BOTH_FISTS",
        "PLACE_RIGHT_PINCH",
        "INVENTORY_BOTH_FISTS",
        "HOTBAR_RIGHT_TAP",
        "CLIMB_ALTERNATE"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VRMC Gesture Lab").font(.title2).bold()
            Text("Separate data-collection app: visualizes the 27-joint ARKit skeleton and records "
                 + "labelled hand motion for the simplified M7 gesture set. It never controls Minecraft.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Circle()
                    .fill(model.running ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(model.status).font(.callout)
                Spacer()
                Text(model.headTracked ? "head ✓" : "head —")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("tracked joints: \(model.visibleJointCount)   samples: \(model.sampleCount)")
                .font(.system(.caption, design: .monospaced))
            Text("classifier: \(model.classification)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("L: \(model.leftFeatures)    R: \(model.rightFeatures)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Button(immersiveOpen ? "Close Hand Lab" : "Open Hand Lab") {
                    Task {
                        if immersiveOpen {
                            await dismissImmersiveSpace()
                            immersiveOpen = false
                        } else {
                            switch await openImmersiveSpace(id: LabSpace.id) {
                            case .opened: immersiveOpen = true
                            default: model.status = "immersive space failed to open"
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                if model.recording {
                    Button("Stop & Save") { model.stopRecording() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Start Recording") { model.startRecording() }
                        .buttonStyle(.bordered)
                        .disabled(!model.running)
                    Button("Record 30s") { model.startTimedRecording(seconds: 30) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.running || model.recording || model.guidedActive)
                    Button("Guided Capture") { model.startGuidedCapture() }
                        .buttonStyle(.bordered)
                        .disabled(!model.running || model.guidedActive || model.recording)
                }
            }

            HStack {
                Text("next samples are labelled:").font(.caption)
                Picker("Label", selection: $model.selectedLabel) {
                    ForEach(labels, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(.caption)
            }

            if model.recording && model.recordRemaining > 0 {
                Text("RECORDING — \(model.recordRemaining)s remaining").font(.title3).foregroundStyle(.red)
            }
            if model.guidedActive {
                Text("GUIDED \(model.guidedProgress) — \(model.guidedPrompt)").font(.headline)
            } else if model.guidedPrompt != "ready" {
                Text("guided: \(model.guidedPrompt)").font(.caption)
            }
            Text("file: \(model.recordFile)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("Actions: hold both fists and swing alternating arms for walk; quick both-fist tap for "
                 + "inventory; right-hand swing for attack; right pinch for menu/place; left pinch hold for "
                 + "teleport; right hand to head for eat; both fists front/back for bow; alternating hand "
                 + "reach for climb. Record each label for 5–10 seconds, 10 repetitions.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 520, maxWidth: 760)
    }
}
