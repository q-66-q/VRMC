import SwiftUI
import CompositorServices
import ARKit
import Metal
import simd

struct ProbeLayerConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities,
                           configuration: inout LayerRenderer.Configuration) {
        configuration.layout = .dedicated
        configuration.isFoveationEnabled = capabilities.supportsFoveation
        configuration.colorFormat = .rgba16Float
    }
}

@main
struct M3AProbeApp: App {
    @StateObject private var model = ProbeModel()
    @State private var immersiveOpen = false
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 20) {
                Text("VRMC M3a immersive probe").font(.title)
                Text(model.status).multilineTextAlignment(.center).padding()
                Button(immersiveOpen ? "Immersive space open" : "Open immersive space") {
                    Task {
                        immersiveOpen = true
                        let result = await openImmersiveSpace(id: "probe")
                        model.log("openImmersiveSpace result=\(result)")
                    }
                }
                .disabled(immersiveOpen)
            }
            .padding()
            .onAppear { model.startARKit() }
        }
        ImmersiveSpace(id: "probe") {
            CompositorLayer(configuration: ProbeLayerConfiguration()) { layerRenderer in
                model.renderLoop(layerRenderer)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}

final class ProbeModel: ObservableObject {
    @Published var status = "starting…"
    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private let lock = NSLock()
    private var latestAnchor: DeviceAnchor?
    private var frames = 0
    private var lastLog = Date.distantPast
    private var logURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        logURL = docs.appendingPathComponent("m3a-probe.log")
        log("M3A probe init")
    }

    func log(_ message: String) {
        let line = "[m3a] \(message)\n"
        print(line, terminator: "")
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    func startARKit() {
        Task {
            do {
                try await arSession.run([worldTracking])
                await MainActor.run { self.status = "ARKit world tracking running" }
                log("ARKit world tracking running")
                self.poseTask()
            } catch {
                await MainActor.run { self.status = "ARKit failed: \(error)" }
                log("ARKit failed: \(error)")
            }
        }
    }

    private var renderThread: Thread?

    func renderLoop(_ layerRenderer: LayerRenderer) {
        log("CompositorLayer closure entered; starting retained render thread")
        let thread = Thread { [weak self] in self?.renderLoopThread(layerRenderer) }
        thread.name = "M3A Render Thread"
        renderThread = thread
        thread.start()
    }

    private func renderLoopThread(_ layerRenderer: LayerRenderer) {
        log("render thread started")
        guard let queue = layerRenderer.device.makeCommandQueue() else {
            log("no Metal command queue")
            return
        }
        var frameCount = 0
        while true {
            if layerRenderer.state == .invalidated {
                log("layer invalidated; render loop exiting")
                return
            }
            if layerRenderer.state == .paused {
                layerRenderer.waitUntilRunning()
                continue
            }
            autoreleasepool {
                guard let frame = layerRenderer.queryNextFrame() else { return }
                guard let timing = frame.predictTiming() else { return }
                frame.startUpdate()
                frame.endUpdate()
                LayerRenderer.Clock().wait(until: timing.optimalInputTime)
                frame.startSubmission()
                guard let drawable = frame.queryDrawable() else {
                    frame.endSubmission()
                    return
                }
                renderTestPattern(drawable: drawable, queue: queue)
                frame.endSubmission()
                frameCount += 1
                if frameCount == 1 || frameCount % 60 == 0 {
                    lock.lock(); let anchor = latestAnchor; lock.unlock()
                    if let anchor {
                        let t = anchor.originFromAnchorTransform.columns.3
                        log(String(format: "frame %d anchor pos=(%.3f, %.3f, %.3f)", frameCount, t.x, t.y, t.z))
                    } else {
                        log("frame \(frameCount) anchor=(pending)")
                    }
                }
            }
        }
    }

    private func poseTask() {
        Task {
            while true {
                if let anchor = try? await worldTracking.queryDeviceAnchor(atTimestamp: CFAbsoluteTimeGetCurrent()) {
                    lock.lock(); latestAnchor = anchor; lock.unlock()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func renderTestPattern(drawable: LayerRenderer.Drawable, queue: MTLCommandQueue) {
        guard let cb = queue.makeCommandBuffer() else { return }
        for (index, texture) in drawable.colorTextures.enumerated() {
            let color = index == 0
                ? MTLClearColor(red: 0.8, green: 0.05, blue: 0.05, alpha: 1)
                : MTLClearColor(red: 0.05, green: 0.7, blue: 0.1, alpha: 1)
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture = texture
            desc.colorAttachments[0].loadAction = .clear
            desc.colorAttachments[0].storeAction = .store
            desc.colorAttachments[0].clearColor = color
            if let enc = cb.makeRenderCommandEncoder(descriptor: desc) {
                enc.endEncoding()
            }
        }
        drawable.encodePresent(commandBuffer: cb)
        cb.commit()
    }
}
