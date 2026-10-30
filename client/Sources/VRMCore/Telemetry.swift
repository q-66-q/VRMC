import Foundation

public enum PipelineStage: String, CaseIterable, Sendable {
    case capture
    case encode
    case network
    case reassembly
    case decode
    case render
    case present
    case inputUplink
    case driver
}

public struct LatencySummary: Equatable, Sendable {
    public var count: Int
    public var p50Ms: Double
    public var p95Ms: Double
    public var p99Ms: Double
    public var maxMs: Double

    public init(count: Int = 0, p50Ms: Double = 0, p95Ms: Double = 0, p99Ms: Double = 0, maxMs: Double = 0) {
        self.count = count
        self.p50Ms = p50Ms
        self.p95Ms = p95Ms
        self.p99Ms = p99Ms
        self.maxMs = maxMs
    }
}

public final class LatencyTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [PipelineStage: [Double]] = [:]
    private let capacity: Int

    public init(capacity: Int = 600) {
        self.capacity = max(16, capacity)
    }

    public func reset() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    public func record(_ stage: PipelineStage, milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        lock.lock()
        var values = samples[stage] ?? []
        values.append(milliseconds)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
        samples[stage] = values
        lock.unlock()
    }

    public func summary(_ stage: PipelineStage) -> LatencySummary {
        lock.lock()
        let values = (samples[stage] ?? []).sorted()
        lock.unlock()
        guard !values.isEmpty else { return LatencySummary() }
        return LatencySummary(
            count: values.count,
            p50Ms: percentile(values, 0.50),
            p95Ms: percentile(values, 0.95),
            p99Ms: percentile(values, 0.99),
            maxMs: values.last ?? 0
        )
    }

    public func allSummaries() -> [PipelineStage: LatencySummary] {
        var result: [PipelineStage: LatencySummary] = [:]
        for stage in PipelineStage.allCases {
            result[stage] = summary(stage)
        }
        return result
    }

    private func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        let t = position - Double(lower)
        return sorted[lower] * (1 - t) + sorted[upper] * t
    }
}

public struct FrameCounters: Equatable, Sendable {
    public var received: UInt32 = 0
    public var decoded: UInt32 = 0
    public var presented: UInt32 = 0
    public var dropped: UInt32 = 0
    public var queueDepth: UInt16 = 0
    public var lastFrameId: UInt32 = 0

    public init() {}
}

public final class TelemetryCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var frameCounters = FrameCounters()
    private var inputSent: UInt32 = 0
    private var inputLost: UInt32 = 0
    private var packetLoss: UInt32 = 0
    private var nacks: UInt32 = 0
    private var idrRequests: UInt32 = 0

    public init() {}

    public func onFrameReceived(id: UInt32) {
        lock.lock()
        frameCounters.received &+= 1
        frameCounters.lastFrameId = id
        lock.unlock()
    }

    public func onFrameDecoded() {
        lock.lock(); frameCounters.decoded &+= 1; lock.unlock()
    }

    public func onFramePresented() {
        lock.lock(); frameCounters.presented &+= 1; lock.unlock()
    }

    public func onFrameDropped() {
        lock.lock(); frameCounters.dropped &+= 1; lock.unlock()
    }

    public func setQueueDepth(_ depth: Int) {
        lock.lock(); frameCounters.queueDepth = UInt16(min(max(depth, 0), Int(UInt16.max))); lock.unlock()
    }

    public func onInputSent() {
        lock.lock(); inputSent &+= 1; lock.unlock()
    }

    public func onInputLost() {
        lock.lock(); inputLost &+= 1; lock.unlock()
    }

    public func onPacketLoss() {
        lock.lock(); packetLoss &+= 1; lock.unlock()
    }

    public func onNack() {
        lock.lock(); nacks &+= 1; lock.unlock()
    }

    public func onIDRRequest() {
        lock.lock(); idrRequests &+= 1; lock.unlock()
    }

    public func snapshot() -> (frames: FrameCounters, inputSent: UInt32, inputLost: UInt32, packetLoss: UInt32, nacks: UInt32, idrRequests: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        return (frameCounters, inputSent, inputLost, packetLoss, nacks, idrRequests)
    }
}

public enum TelemetryCSV {
    public static func header() -> String {
        "stage,count,p50_ms,p95_ms,p99_ms,max_ms\n"
    }

    public static func line(stage: PipelineStage, summary: LatencySummary) -> String {
        String(
            format: "%@,%d,%.2f,%.2f,%.2f,%.2f\n",
            stage.rawValue, summary.count, summary.p50Ms, summary.p95Ms, summary.p99Ms, summary.maxMs
        )
    }
}
