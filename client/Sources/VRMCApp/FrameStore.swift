import Foundation
import CoreVideo
import VRMCore

/// Thread-safe handoff between the network/decode pipeline and the Metal renderer.
public final class FrameStore: @unchecked Sendable {
    public struct RenderFrame {
        public var pixelBuffer: CVPixelBuffer
        public var timestamp: Timestamp
        public var frameId: UInt32
        public var captureHead: Pose
        public var capturedAtHostNs: UInt64
        public var receivedAtClient: Timestamp
    }

    private let lock = NSLock()
    private var latest: RenderFrame?
    private var config: StreamConfig?
    private var sequence: UInt64 = 0

    public init() {}

    public func setConfig(_ config: StreamConfig) {
        lock.lock(); self.config = config; lock.unlock()
    }

    public func currentConfig() -> StreamConfig? {
        lock.lock(); defer { lock.unlock() }; return config
    }

    public func store(
        pixelBuffer: CVPixelBuffer,
        timestamp: Timestamp,
        frameId: UInt32,
        captureHead: Pose,
        capturedAtHostNs: UInt64
    ) {
        lock.lock()
        latest = RenderFrame(
            pixelBuffer: pixelBuffer,
            timestamp: timestamp,
            frameId: frameId,
            captureHead: captureHead,
            capturedAtHostNs: capturedAtHostNs,
            receivedAtClient: .now()
        )
        sequence &+= 1
        lock.unlock()
    }

    public func latestFrame() -> RenderFrame? {
        lock.lock(); defer { lock.unlock() }; return latest
    }

    public func clear() {
        lock.lock(); latest = nil; lock.unlock()
    }

    public var frameSequence: UInt64 {
        lock.lock(); defer { lock.unlock() }; return sequence
    }
}
