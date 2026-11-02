import Foundation
import CompositorServices
import Metal

/// Minimal CompositorServices renderer, structurally the same as runtime/native-shell/Sources/
/// VRMCCompositor.mm: a dedicated render thread that waits for the layer, loops
/// queryNextFrame -> startUpdate/endUpdate -> wait optimal input -> startSubmission -> draw ->
/// endSubmission, and honours the paused/invalidated layer states.
///
/// It renders a bright animated red/green checker test pattern (red left eye, green right eye) with
/// a moving white band, so a screenshot proves whether the compositor is (still) presenting.
///
/// Drawable-array diagnostics (-M3CDrawablesMode all|first|builtin|legacy):
///   all     - cp_frame_query_drawables(): draw and present EVERY drawable in the array (default)
///   first   - draw only drawables[0] (what a "single drawable" renderer would present)
///   builtin - draw only drawables whose target is builtIn (skip capture targets)
///   legacy  - cp_frame_query_drawable() (the API deprecated in visionOS 26) and draw that one
/// The log prints, per drawable: target (builtIn/capture), view/texture/depth/rrm counts, format and
/// size, plus the per-frame array count, so a capture target appearing/disappearing is visible.

struct M3CUniforms {
    var phase: Float
    var eye: Float
    var target: Float
}

enum M3CDrawablesMode: String {
    case all
    case first
    case builtin
    case legacy

    static func fromProcess() -> M3CDrawablesMode {
        let raw = UserDefaults.standard.string(forKey: "M3CDrawablesMode") ?? "all"
        return M3CDrawablesMode(rawValue: raw) ?? .all
    }
}

private let kM3CShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VOut { float4 pos [[position]]; float2 ndc; };

vertex VOut vmain(uint vid [[vertex_id]]) {
    float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
    VOut o;
    o.pos = float4(p[vid], 0, 1);
    o.ndc = p[vid];
    return o;
}

struct Uniforms { float phase; float eye; float target; };

fragment float4 fpattern(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 q = floor(in.ndc * 6.0 + float2(u.phase, 0.0));
    float checker = fmod(abs(q.x + q.y), 2.0);
    float3 col = mix(float3(1.0, 0.06, 0.03), float3(0.04, 1.0, 0.08), checker);
    if (u.eye > 0.5) { col = col.gbr; }
    if (u.target > 0.5) { col = float3(col.b, col.r, 1.0 - col.g); }  // capture target tint
    float band = step(abs(in.ndc.y - sin(u.phase * 1.3) * 0.55), 0.03);
    col = mix(col, float3(1.0), band);
    float cross = clamp(step(abs(in.ndc.x), 0.012) + step(abs(in.ndc.y), 0.012), 0.0, 1.0);
    col = mix(col, float3(1.0), cross);
    return float4(col, 1.0);
}
"""

final class M3CCompositor: @unchecked Sendable {
    static let shared = M3CCompositor()

    private let lock = NSLock()
    private var generation = 0
    private var pipelineColorFormat: MTLPixelFormat = .invalid

    func start(layerRenderer: LayerRenderer) {
        lock.lock()
        generation += 1
        let gen = generation
        lock.unlock()
        M3CLog.comp("CompositorLayer closure entered; starting render thread generation=\(gen)")
        M3CStats.shared.noteRunStarted(generation: gen)
        let thread = Thread { [weak self] in
            self?.run(layerRenderer: layerRenderer, generation: gen)
        }
        thread.name = "M3C-Render-\(gen)"
        thread.stackSize = 1 << 21
        thread.start()
    }

    private func stateName(_ layerRenderer: LayerRenderer) -> String {
        switch layerRenderer.state {
        case .paused: return "paused"
        case .running: return "running"
        case .invalidated: return "invalidated"
        @unknown default: return "unknown"
        }
    }

    private func targetName(_ drawable: LayerRenderer.Drawable) -> String {
        switch drawable.target {
        case .builtIn: return "builtIn"
        case .capture: return "capture"
        @unknown default: return "unknownTarget"
        }
    }

    private func describe(_ drawables: [LayerRenderer.Drawable]) -> String {
        var parts: [String] = []
        for (index, drawable) in drawables.enumerated() {
            let color = drawable.colorTextures.first
            let width = color?.width ?? 0
            let height = color?.height ?? 0
            let format = color?.pixelFormat.rawValue ?? 0
            parts.append("d\(index){target=\(targetName(drawable)) views=\(drawable.views.count) " +
                         "colors=\(drawable.colorTextures.count) depths=\(drawable.depthTextures.count) " +
                         "rrms=\(drawable.rasterizationRateMaps.count) fmt=\(format) size=\(width)x\(height)}")
        }
        return parts.joined(separator: " ")
    }

    private func run(layerRenderer: LayerRenderer, generation gen: Int) {
        let mode = M3CDrawablesMode.fromProcess()
        M3CLog.comp("gen=\(gen) render thread started; drawablesMode=\(mode.rawValue)")
        layerRenderer.waitUntilRunning()
        M3CLog.comp("gen=\(gen) waitUntilRunning returned state=\(stateName(layerRenderer))")
        M3CStats.shared.noteState(stateName(layerRenderer), generation: gen)

        let device = layerRenderer.device
        guard let queue = device.makeCommandQueue() else {
            M3CLog.comp("gen=\(gen) FAILED to create command queue")
            M3CStats.shared.noteInvalidated(generation: gen)
            return
        }
        let cfg = layerRenderer.configuration
        let colorFormat = cfg.colorFormat
        let depthFormat = cfg.depthFormat
        M3CLog.comp("gen=\(gen) config colorFormat=\(colorFormat.rawValue) depthFormat=\(depthFormat.rawValue) " +
                    "foveation=\(cfg.isFoveationEnabled) layout=\(String(describing: cfg.layout)) " +
                    "defaultDepthRange=\(cfg.defaultDepthRange)")
        let pipeline = makePipeline(device: device, colorFormat: colorFormat,
                                    depthFormat: depthFormat, generation: gen)

        var frameCount = 0
        var phase: Float = 0
        var lastLogged = 0
        var lastSignature = ""
        let startTime = CFAbsoluteTimeGetCurrent()

        loop: while true {
            let state = layerRenderer.state
            if state == .invalidated {
                M3CLog.comp("gen=\(gen) layer INVALIDATED at frame \(frameCount) " +
                            "elapsed=\(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - startTime))")
                break loop
            }
            if state == .paused {
                M3CLog.comp("gen=\(gen) layer PAUSED at frame \(frameCount); blocking in waitUntilRunning")
                M3CStats.shared.noteState("paused", generation: gen)
                layerRenderer.waitUntilRunning()
                M3CLog.comp("gen=\(gen) resumed from pause state=\(stateName(layerRenderer))")
                continue
            }
            guard let frame = layerRenderer.queryNextFrame() else { continue }
            guard let timing = frame.predictTiming() else { continue }
            frame.startUpdate()
            frame.endUpdate()
            LayerRenderer.Clock().wait(until: timing.optimalInputTime)
            let afterWait = layerRenderer.state
            if afterWait != .running {
                M3CLog.comp("gen=\(gen) layer left running state after timing wait " +
                            "(state=\(stateName(layerRenderer))) at frame \(frameCount); exiting")
                break loop
            }
            frame.startSubmission()

            var toRender: [LayerRenderer.Drawable] = []
            var arrayCount = 0
            if mode == .legacy {
                // Deprecated single-drawable API (what VRMCCompositor.mm uses today).
                if let drawable = frame.queryDrawable() {
                    toRender = [drawable]
                    arrayCount = 1
                }
            } else {
                let drawables = frame.queryDrawables()
                arrayCount = drawables.count
                if drawables.isEmpty {
                    M3CStats.shared.noteState("no-drawables", generation: gen)
                    frame.endSubmission()
                    continue
                }
                switch mode {
                case .all: toRender = drawables
                case .first: toRender = [drawables[0]]
                case .builtin: toRender = drawables.filter { drawable in
                    if case .builtIn = drawable.target { return true }
                    return false
                }
                case .legacy: break
                }
                let signature = describe(drawables)
                let logThisFrame = frameCount == 0 || signature != lastSignature || frameCount - lastLogged >= 120
                if logThisFrame {
                    lastSignature = signature
                    M3CLog.comp("gen=\(gen) frame \(frameCount): drawable array count=\(arrayCount) " +
                                "builtinViews=\(frame.drawableTargetViewCount(target: .builtIn)) " +
                                "captureViews=\(frame.drawableTargetViewCount(target: .capture)) | \(signature)")
                }
            }
            if mode == .legacy, let drawable = toRender.first {
                M3CLog.comp("gen=\(gen) legacy queryDrawable target=\(targetName(drawable)) " +
                            "views=\(drawable.views.count) colors=\(drawable.colorTextures.count)")
            }
            if toRender.isEmpty {
                M3CLog.comp("gen=\(gen) frame \(frameCount): nothing to render for mode=\(mode.rawValue) " +
                            "(array count=\(arrayCount))")
            }
            render(drawables: toRender, queue: queue, pipeline: pipeline, phase: phase)
            frame.endSubmission()
            frameCount += 1
            M3CStats.shared.noteFramePresented(generation: gen, frame: frameCount)
            phase += 0.02
            if frameCount == 1 || frameCount - lastLogged >= 120 {
                if frameCount != 1 { lastLogged = frameCount }
                M3CLog.comp("gen=\(gen) frame \(frameCount) submitted rendered=\(toRender.count)/\(arrayCount) " +
                            "elapsed=\(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - startTime))")
            }
            if CFAbsoluteTimeGetCurrent() - startTime > 600 {
                M3CLog.comp("gen=\(gen) 600 s safety exit")
                break loop
            }
        }
        M3CLog.comp("gen=\(gen) render thread exit frames=\(frameCount)")
        M3CStats.shared.noteEnded(generation: gen)
    }

    private func makePipeline(device: MTLDevice, colorFormat: MTLPixelFormat,
                              depthFormat: MTLPixelFormat, generation gen: Int) -> MTLRenderPipelineState? {
        do {
            let library = try device.makeLibrary(source: kM3CShaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vmain")
            descriptor.fragmentFunction = library.makeFunction(name: "fpattern")
            descriptor.colorAttachments[0].pixelFormat = colorFormat
            if depthFormat != .invalid {
                descriptor.depthAttachmentPixelFormat = depthFormat
            }
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            pipelineColorFormat = colorFormat
            M3CLog.comp("gen=\(gen) pipeline ready (colorFormat=\(colorFormat.rawValue) " +
                        "depthFormat=\(depthFormat.rawValue))")
            return pipeline
        } catch {
            M3CLog.comp("gen=\(gen) pipeline FAILED: \(error)")
            return nil
        }
    }

    private func render(drawables: [LayerRenderer.Drawable], queue: MTLCommandQueue,
                        pipeline: MTLRenderPipelineState?, phase: Float) {
        guard !drawables.isEmpty else { return }
        guard let commandBuffer = queue.makeCommandBuffer() else { return }
        for drawable in drawables {
            let isCapture: Bool
            if case .capture = drawable.target { isCapture = true } else { isCapture = false }
            let colorTextures = drawable.colorTextures
            let depthTextures = drawable.depthTextures
            let rateMaps = drawable.rasterizationRateMaps
            for (index, colorTexture) in colorTextures.enumerated() {
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = colorTexture
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = index == 0
                    ? MTLClearColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
                    : MTLClearColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
                if index < depthTextures.count, depthTextures[index].pixelFormat != .invalid {
                    pass.depthAttachment.texture = depthTextures[index]
                    pass.depthAttachment.loadAction = .clear
                    pass.depthAttachment.storeAction = .store
                    // CompositorServices uses a reverse-Z depth range (0 = infinitely far).
                    pass.depthAttachment.clearDepth = 0.0
                }
                if index < rateMaps.count {
                    pass.rasterizationRateMap = rateMaps[index]
                }
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { continue }
                if let pipeline, colorTexture.pixelFormat == pipelineColorFormat {
                    encoder.setRenderPipelineState(pipeline)
                    var uniforms = M3CUniforms(phase: phase, eye: Float(index), target: isCapture ? 1 : 0)
                    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<M3CUniforms>.stride, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
                encoder.endEncoding()
            }
            drawable.encodePresent(commandBuffer: commandBuffer)
        }
        commandBuffer.commit()
    }
}
