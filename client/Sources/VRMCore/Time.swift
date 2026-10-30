import Foundation
import QuartzCore

/// Monotonic nanosecond timestamp. The value is derived from `CACurrentMediaTime()`,
/// the same time base used by ARKit anchors on visionOS.
public struct Timestamp: Comparable, Hashable, Sendable, Codable {
    public var nanoseconds: UInt64

    public init(nanoseconds: UInt64) {
        self.nanoseconds = nanoseconds
    }

    public init(seconds: TimeInterval) {
        if seconds <= 0 || !seconds.isFinite {
            self.nanoseconds = 0
        } else {
            self.nanoseconds = UInt64((seconds * 1_000_000_000).rounded())
        }
    }

    public static let zero = Timestamp(nanoseconds: 0)

    public static func now() -> Timestamp {
        Timestamp(seconds: CACurrentMediaTime())
    }

    public static func fromMachAbsolute(_ value: UInt64) -> Timestamp {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.denom != 0 else { return .zero }
        let product = value.multipliedFullWidth(by: UInt64(info.numer))
        let quotient = UInt64(info.denom).dividingFullWidth(product).quotient
        return Timestamp(nanoseconds: quotient)
    }

    public var seconds: TimeInterval {
        TimeInterval(nanoseconds) / 1_000_000_000
    }

    public var milliseconds: Double {
        Double(nanoseconds) / 1_000_000
    }

    public func adding(milliseconds: Double) -> Timestamp {
        adding(nanoseconds: Int64(milliseconds * 1_000_000))
    }

    public func adding(nanoseconds delta: Int64) -> Timestamp {
        if delta >= 0 {
            return Timestamp(nanoseconds: nanoseconds &+ UInt64(delta))
        }
        let magnitude = UInt64(-delta)
        return Timestamp(nanoseconds: nanoseconds >= magnitude ? nanoseconds - magnitude : 0)
    }

    /// Signed `self - other` in nanoseconds, safe against ordinary wraps.
    public func distance(to other: Timestamp) -> Int64 {
        Int64(bitPattern: nanoseconds &- other.nanoseconds)
    }

    public func isOlder(than other: Timestamp, byMilliseconds limit: Double) -> Bool {
        distance(to: other) > Int64(limit * 1_000_000)
    }

    public static func < (lhs: Timestamp, rhs: Timestamp) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }
}

public enum TimeConstants {
    public static let nanosecondsPerSecond: UInt64 = 1_000_000_000
    public static let nanosecondsPerMillisecond: UInt64 = 1_000_000
}

public struct ClockSample: Equatable, Sendable {
    public let t0: UInt64
    public let t1: UInt64
    public let t2: UInt64
    public let t3: UInt64

    public init(t0: UInt64, t1: UInt64, t2: UInt64, t3: UInt64) {
        self.t0 = t0
        self.t1 = t1
        self.t2 = t2
        self.t3 = t3
    }

    /// host - client offset estimate in nanoseconds.
    public var offset: Int64 {
        let forward = Int64(bitPattern: t1 &- t0)
        let backward = Int64(bitPattern: t2 &- t3)
        return (forward + backward) / 2
    }

    public var roundTrip: Int64 {
        let total = Int64(bitPattern: t3 &- t0)
        let processing = Int64(bitPattern: t2 &- t1)
        return total - processing
    }

    public var uncertainty: Int64 {
        max(0, roundTrip / 2)
    }

    public var isValid: Bool {
        roundTrip >= 0 && roundTrip < 2_000_000_000 && uncertainty < 1_000_000_000
    }
}

public struct ClockEstimate: Equatable, Sendable {
    public let offset: Int64
    public let roundTrip: Int64
    public let uncertainty: Int64
    public let sampleCount: Int
    public let driftPPM: Double

    public init(offset: Int64, roundTrip: Int64, uncertainty: Int64, sampleCount: Int, driftPPM: Double) {
        self.offset = offset
        self.roundTrip = roundTrip
        self.uncertainty = uncertainty
        self.sampleCount = sampleCount
        self.driftPPM = driftPPM
    }
}

/// Robust NTP-style estimator. `offset` is host minus client.
public final class ClockSyncEstimator: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [ClockSample] = []
    private let capacity: Int

    public init(capacity: Int = 64) {
        self.capacity = max(8, capacity)
    }

    public func reset() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    @discardableResult
    public func add(_ sample: ClockSample) -> ClockEstimate? {
        guard sample.isValid else { return nil }
        lock.lock()
        defer { lock.unlock() }
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
        return computeEstimate()
    }

    public var latest: ClockEstimate? {
        lock.lock()
        defer { lock.unlock() }
        return computeEstimate()
    }

    private func computeEstimate() -> ClockEstimate? {
        guard !samples.isEmpty else { return nil }
        let sortedOffsets = samples.map(\.offset).sorted()
        let medianOffset = sortedOffsets[sortedOffsets.count / 2]
        let deviations = samples.map { abs($0.offset - medianOffset) }.sorted()
        let mad = deviations[deviations.count / 2]
        let filterLimit = max(Int64(1_000_000), mad * 4)
        let filtered = samples.filter { abs($0.offset - medianOffset) <= filterLimit }
        let usable = filtered.isEmpty ? samples : filtered

        let filteredOffsets = usable.map(\.offset).sorted()
        let offset = filteredOffsets[filteredOffsets.count / 2]
        let rtts = usable.map(\.roundTrip).sorted()
        let rtt = rtts[rtts.count / 2]
        let uncertainty = rtt / 2

        // Drift estimate: least-squares slope of offset vs. midpoint time, in ppm.
        var drift = 0.0
        if usable.count >= 8 {
            let points = usable.map { sample -> (Double, Double) in
                let midpoint = (Double(sample.t0) + Double(sample.t3)) * 0.5
                return (midpoint, Double(sample.offset))
            }
            let meanX = points.map(\.0).reduce(0, +) / Double(points.count)
            let meanY = points.map(\.1).reduce(0, +) / Double(points.count)
            var numerator = 0.0
            var denominator = 0.0
            for point in points {
                let dx = point.0 - meanX
                numerator += dx * (point.1 - meanY)
                denominator += dx * dx
            }
            if denominator > 0 {
                let slope = numerator / denominator // ns offset per ns
                drift = slope * 1_000_000
                if !drift.isFinite || abs(drift) > 500 {
                    drift = 0
                }
            }
        }

        return ClockEstimate(
            offset: offset,
            roundTrip: rtt,
            uncertainty: uncertainty,
            sampleCount: usable.count,
            driftPPM: drift
        )
    }

    public func hostToClient(_ hostNanoseconds: UInt64) -> UInt64? {
        guard let estimate = latest else { return nil }
        return UInt64(bitPattern: Int64(bitPattern: hostNanoseconds) &- estimate.offset)
    }

    public func clientToHost(_ clientNanoseconds: UInt64) -> UInt64? {
        guard let estimate = latest else { return nil }
        return UInt64(bitPattern: Int64(bitPattern: clientNanoseconds) &+ estimate.offset)
    }
}
