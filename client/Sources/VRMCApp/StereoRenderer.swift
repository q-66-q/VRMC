import ARKit
import CompositorServices
import Metal
import CoreVideo
import Foundation
import os
import simd
import VRMCore

private let rendererLogger = Logger(subsystem: "dev.vrmc.app", category: "renderer")

private struct ReprojectUniforms {
    var presentTangents: SIMD4<Float>
    var captureTangents: SIMD4<Float>
    var qCaptureToPresent: SIMD4<Float>
    var uvRect: SIMD4<Float>
    var misc: SIMD4<Float>
}

private final class RetainedCVTexture: @unchecked Sendable {
    let texture: CVMetalTexture
    init(_ texture: CVMetalTexture) { self.texture = texture }
}

/// Full-screen per-eye stereo renderer with rotation-only late reprojection.
final class StereoRenderer: @unchecked Sendable {
    private let layerRenderer: LayerRenderer
    private let frameStore: FrameStore
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    private var renderThread: Thread?
    private var running = true

    init(layerRenderer: LayerRenderer, frameStore: FrameStore) {
        self.layerRenderer = layerRenderer
        self.frameStore = frameStore
        self.device = layerRenderer.device
        self.commandQueue = layerRenderer.device.makeCommandQueue()!
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, layerRenderer.device, nil, &cache)
        guard status == kCVReturnSuccess, let cache else {
            fatalError("Unable to create CVMetalTextureCache (\(status))")
        }
        self.textureCache = cache
        buildPipeline()
    }

    func start() {
        guard renderThread == nil else { return }
        rendererLogger.info("StereoRenderer starting; pipeline=\(self.pipeline != nil, privacy: .public)")
        let thread = Thread { self.renderLoop() }
        thread.name = "VRMC Stereo Render"
        thread.qualityOfService = .userInteractive
        renderThread = thread
        thread.start()
    }

    func stop() {
        running = false
    }

    private func buildPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            rendererLogger.error("No default Metal library")
            return
        }
        guard let vertex = library.makeFunction(name: "vrmc_fullscreen_vertex"),
              let fragment = library.makeFunction(name: "vrmc_reproject_fragment") else {
            rendererLogger.error("Metal shader functions missing")
            return
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            rendererLogger.error("Pipeline creation failed: \(String(describing: error), privacy: .public)")
        }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)
    }

    private func renderLoop() {
        rendererLogger.info("render loop waiting for layer")
        layerRenderer.waitUntilRunning()
        rendererLogger.info("render loop running; state=\(String(describing: self.layerRenderer.state), privacy: .public)")
        while running {
            if layerRenderer.state == .invalidated {
                break
            }
            if layerRenderer.state == .paused {
                layerRenderer.waitUntilRunning()
                continue
            }
            autoreleasepool {
                renderFrame()
            }
        }
    }

    private func renderFrame() {
        rendererLogger.debug("querying next frame")
        guard let frame = layerRenderer.queryNextFrame(),
              let timing = frame.predictTiming() else {
            rendererLogger.debug("no frame/timing; state=\(String(describing: self.layerRenderer.state), privacy: .public)")
            return
        }
        rendererLogger.debug("frame timing optimal=\(String(describing: timing.optimalInputTime), privacy: .public)")
        frame.startUpdate()
        frame.endUpdate()
        rendererLogger.debug("waiting input time")
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)
        rendererLogger.debug("input time reached")
        frame.startSubmission()
        guard let drawable = frame.queryDrawables().first,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            rendererLogger.debug("no drawable/command buffer")
            frame.endSubmission()
            return
        }
        rendererLogger.debug("drawable; eyeCount=\(drawable.views.count)")

        let config = frameStore.currentConfig()
        let latest = frameStore.latestFrame()
        if latest == nil {
            rendererLogger.debug("render frame without video")
        }
        var retained: [RetainedCVTexture] = []
        var sbsTexture: MTLTexture?
        if let latest {
            var cvTexture: CVMetalTexture?
            let width = CVPixelBufferGetWidth(latest.pixelBuffer)
            let height = CVPixelBufferGetHeight(latest.pixelBuffer)
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, textureCache, latest.pixelBuffer, nil,
                .bgra8Unorm_srgb, width, height, 0, &cvTexture
            )
            if status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) {
                sbsTexture = texture
                retained.append(RetainedCVTexture(cvTexture))
                rendererLogger.debug("video texture \(width)x\(height) frame=\(latest.frameId, privacy: .public)")
            } else {
                rendererLogger.error("CVMetal texture creation failed: \(status)")
            }
        }
        let retainedTextures = retained
        commandBuffer.addCompletedHandler { _ in
            _ = retainedTextures
        }

        let eyeCount = drawable.views.count
        let presentHead = drawable.deviceAnchor.map { pose(from: $0.originFromAnchorTransform) } ?? latest?.captureHead ?? .identity
        let captureHead = latest?.captureHead ?? presentHead
        let delta = (presentHead.orientation * captureHead.orientation.conjugate).normalized()
        let flipV: Float = config?.flags.contains(.verticalFlip) == true ? 1 : 0

        for viewIndex in 0..<eyeCount {
            let color = drawable.colorTextures[viewIndex]
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = color
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.01, green: 0.012, blue: 0.018, alpha: 1)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { continue }
            if let sbsTexture, let pipeline, let sampler {
                let eye = eyeIndex(viewIndex: viewIndex, eyeCount: eyeCount, config: config)
                let captureProjection = eye == 0 ? config?.leftProjection : config?.rightProjection
                let drawableProjection = drawable.computeProjection(viewIndex: viewIndex)
                let extracted = ProjectionTangents.from(projectionMatrix: drawableProjection)
#if targetEnvironment(simulator)
                // The simulator drawable FOV differs from a physical Vision Pro; use the
                // capture projection to show the complete debug test pattern.
                let presentTangents = captureProjection ?? .symmetric100
#else
                let presentTangents = extracted ?? captureProjection ?? .symmetric100
#endif
                let captureTangents = captureProjection ?? .symmetric100
                let uvRect: SIMD4<Float>
                if eyeCount >= 2 {
                    uvRect = eye == 0 ? SIMD4(0, 0, 0.5, 1) : SIMD4(0.5, 0, 0.5, 1)
                } else {
                    uvRect = SIMD4(0, 0, 0.5, 1)
                }
                var uniforms = ReprojectUniforms(
                    presentTangents: SIMD4(presentTangents.left, presentTangents.right, presentTangents.bottom, presentTangents.top),
                    captureTangents: SIMD4(captureTangents.left, captureTangents.right, captureTangents.bottom, captureTangents.top),
                    qCaptureToPresent: SIMD4(delta.x, delta.y, delta.z, delta.w),
                    uvRect: uvRect,
                    misc: SIMD4(flipV, 0, 0, 0)
                )
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<ReprojectUniforms>.stride, index: 0)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ReprojectUniforms>.stride, index: 0)
                encoder.setFragmentTexture(sbsTexture, index: 0)
                encoder.setFragmentSamplerState(sampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            encoder.endEncoding()
        }

        rendererLogger.debug("present eyeCount=\(eyeCount) sbs=\(sbsTexture != nil) delta=\(String(describing: delta), privacy: .public)")
        drawable.encodePresent(commandBuffer: commandBuffer)
        commandBuffer.commit()
        LayerRenderer.Clock().wait(until: drawable.frameTiming.renderingDeadline)
        frame.endSubmission()
    }

    private func eyeIndex(viewIndex: Int, eyeCount: Int, config: StreamConfig?) -> Int {
        guard eyeCount >= 2 else { return 0 }
        let leftRight = config?.eyeOrder ?? .leftRight
        if leftRight == .leftRight {
            return viewIndex == 0 ? 0 : 1
        }
        return viewIndex == 0 ? 1 : 0
    }

    private func pose(from matrix: simd_float4x4) -> Pose {
        let position = Vec3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        let m00 = matrix.columns.0.x, m01 = matrix.columns.1.x, m02 = matrix.columns.2.x
        let m10 = matrix.columns.0.y, m11 = matrix.columns.1.y, m12 = matrix.columns.2.y
        let m20 = matrix.columns.0.z, m21 = matrix.columns.1.z, m22 = matrix.columns.2.z
        let trace = m00 + m11 + m22
        var q: Quat
        if trace > 0 {
            let s = sqrt(trace + 1) * 2
            q = Quat((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s)
        } else if m00 > m11 && m00 > m22 {
            let s = sqrt(1 + m00 - m11 - m22) * 2
            q = Quat(0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s)
        } else if m11 > m22 {
            let s = sqrt(1 + m11 - m00 - m22) * 2
            q = Quat((m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s)
        } else {
            let s = sqrt(1 + m22 - m00 - m11) * 2
            q = Quat((m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s)
        }
        q = q.normalized()
        if q.w < 0 { q = Quat(-q.x, -q.y, -q.z, -q.w) }
        return Pose(position: position, orientation: q)
    }
}
