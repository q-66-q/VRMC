import Foundation

struct M3CCompositorSnapshot {
    var runs: Int = 0
    var frames: Int = 0
    var invalidations: Int = 0
    var state: String = "none"
    var presentAge: Double = -1
    var frameInterval: Double = -1
}

/// Thread-safe counters shared between the render thread and the main-thread lifecycle recorder.
final class M3CStats: @unchecked Sendable {
    static let shared = M3CStats()
    private let lock = NSLock()
    private var snap = M3CCompositorSnapshot()
    private var lastFrameAt: CFAbsoluteTime = 0

    func noteRunStarted(generation: Int) {
        lock.lock()
        snap.runs += 1
        snap.state = "run-started(gen=\(generation))"
        lock.unlock()
    }

    func noteState(_ state: String, generation: Int) {
        lock.lock()
        snap.state = "\(state)(gen=\(generation))"
        lock.unlock()
    }

    func noteInvalidated(generation: Int) {
        lock.lock()
        snap.invalidations += 1
        snap.state = "invalidated(gen=\(generation))"
        lock.unlock()
    }

    func noteFramePresented(generation: Int, frame: Int) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        snap.frames = frame
        if lastFrameAt > 0 { snap.frameInterval = now - lastFrameAt }
        lastFrameAt = now
        snap.presentAge = 0
        snap.state = "running(gen=\(generation))"
        lock.unlock()
    }

    func noteEnded(generation: Int) {
        lock.lock()
        snap.state = "thread-exit(gen=\(generation))"
        lock.unlock()
    }

    func snapshot() -> M3CCompositorSnapshot {
        lock.lock()
        var s = snap
        if s.presentAge >= 0, lastFrameAt > 0 { s.presentAge = CFAbsoluteTimeGetCurrent() - lastFrameAt }
        if s.frames == 0 { s.state = snap.state }
        lock.unlock()
        return s
    }
}
