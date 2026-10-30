import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VRMC")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("Vivecraft on Apple Vision Pro")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("M0/M1 dev build")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("PC host").foregroundStyle(.secondary)
                    TextField("127.0.0.1", text: $model.host)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.immersiveOpen)
                }
                GridRow {
                    Text("Control port").foregroundStyle(.secondary)
                    TextField("48625", text: $model.port)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.immersiveOpen)
                }
            }
            .frame(maxWidth: 460)

            HStack(spacing: 12) {
                Button(model.immersiveOpen ? "Disconnect" : "Start VR") {
                    if model.immersiveOpen {
                        Task { await dismissImmersiveSpace(); model.immersiveDidClose(); model.disconnect() }
                    } else {
                        model.connect()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if !model.immersiveOpen {
                    Button("Connect only") { model.connect() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(model.status.hasPrefix("Connecting"))
                }
                if model.immersiveOpen {
                    Button("Recenter") { model.recenter() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }

            Text(model.status)
                .font(.callout)
                .foregroundStyle(model.status.lowercased().contains("error") || model.status.lowercased().contains("lost") ? .red : .secondary)

            if let metrics = model.metrics {
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Metric(title: "State", value: metrics.state)
                        Metric(title: "FPS", value: String(format: "%.1f", metrics.fps))
                        Metric(title: "Latency p50", value: String(format: "%.1f ms", metrics.latencyP50Ms))
                    }
                    GridRow {
                        Metric(title: "Frames", value: "\(metrics.framesDecoded)/\(metrics.framesReceived)")
                        Metric(title: "Dropped", value: "\(metrics.framesDropped)")
                        Metric(title: "Clock", value: String(format: "%+.1f ms", metrics.clockOffsetMs))
                    }
                    GridRow {
                        Metric(title: "Hands", value: metrics.tracking)
                        Metric(title: "Locomotion", value: metrics.locomotion ? "on" : "off")
                        Metric(title: "Queue", value: "\(metrics.queueDepth)")
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Label(model.trackingStatus, systemImage: "hand.raised")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Development transport is currently unencrypted. Use only on a trusted LAN. No Minecraft or Vivecraft binaries are included.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(32)
        .frame(minWidth: 620, minHeight: 460)
        .task {
            if model.demoMode {
                model.connect()
            }
            await openImmersiveIfRequested()
        }
        .onChange(of: model.wantsImmersive) { _, newValue in
            if newValue {
                Task { await openImmersiveIfRequested() }
            }
        }
    }

    private func openImmersiveIfRequested() async {
        guard model.wantsImmersive, !model.immersiveOpen else { return }
        let result = await openImmersiveSpace(id: "VRMC")
        switch result {
        case .opened:
            model.immersiveDidOpen()
        case .userCancelled:
            model.immersiveDidClose()
        default:
            model.status = "Could not open immersive space (\(String(describing: result)))"
        }
    }
}

private struct Metric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced))
        }
        .frame(minWidth: 120, alignment: .leading)
    }
}
