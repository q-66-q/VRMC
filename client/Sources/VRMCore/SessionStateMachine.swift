import Foundation

public enum SessionEvent: Equatable, Sendable {
    case connectRequested
    case helloReceived
    case authenticated
    case configReceived
    case clientReady
    case streamStarted
    case mediaReceived
    case mediaTimeout
    case linkLost
    case reconnectRequested
    case trackingLost
    case trackingRecovered
    case stopRequested
    case fatalError(String)
}

public struct SessionTransition: Equatable, Sendable {
    public var from: SessionPhase
    public var to: SessionPhase
    public var reason: String
    public var releaseInputs: Bool
    public var requestIDR: Bool

    public init(from: SessionPhase, to: SessionPhase, reason: String, releaseInputs: Bool = false, requestIDR: Bool = false) {
        self.from = from
        self.to = to
        self.reason = reason
        self.releaseInputs = releaseInputs
        self.requestIDR = requestIDR
    }
}

public final class SessionStateMachine: @unchecked Sendable {
    private let lock = NSLock()
    private var _phase: SessionPhase = .idle
    private var lastMediaAt: Timestamp?

    public init() {}

    public var phase: SessionPhase {
        lock.lock()
        defer { lock.unlock() }
        return _phase
    }

    @discardableResult
    public func handle(_ event: SessionEvent, now: Timestamp = .now()) -> SessionTransition {
        lock.lock()
        defer { lock.unlock() }
        let from = _phase
        var releaseInputs = false
        var requestIDR = false
        var next = from
        var reason = ""

        switch event {
        case .connectRequested:
            next = .connecting; reason = "connect requested"
        case .helloReceived:
            next = from == .connecting ? .authenticating : from; reason = "hello"
        case .authenticated:
            next = .authenticating; reason = "authenticated"
        case .configReceived:
            next = .ready; reason = "config received"
        case .clientReady:
            next = from == .ready ? .ready : from; reason = "client ready"
        case .streamStarted:
            next = .streaming; lastMediaAt = now; reason = "stream started"
        case .mediaReceived:
            lastMediaAt = now
            if from == .degraded { next = .streaming; reason = "media recovered"; requestIDR = true }
            else if from != .streaming { next = .streaming; reason = "media started" }
        case .mediaTimeout:
            if from == .streaming {
                next = .degraded; reason = "media timeout"; releaseInputs = true; requestIDR = true
            }
        case .linkLost:
            if from != .stopping {
                next = .reconnecting; reason = "link lost"; releaseInputs = true
            }
        case .reconnectRequested:
            next = .reconnecting; reason = "reconnect requested"; releaseInputs = true
        case .trackingLost:
            if from == .streaming { next = .degraded; reason = "tracking lost"; releaseInputs = true }
        case .trackingRecovered:
            if from == .degraded { next = .streaming; reason = "tracking recovered" }
        case .stopRequested:
            next = .stopping; reason = "stop requested"; releaseInputs = true
        case .fatalError(let detail):
            next = .error; reason = detail; releaseInputs = true
        }
        _phase = next
        return SessionTransition(
            from: from, to: next, reason: reason,
            releaseInputs: releaseInputs, requestIDR: requestIDR
        )
    }

    /// Call periodically; returns a timeout transition when media has been silent too long.
    public func poll(now: Timestamp = .now(), timeoutMs: Double = 250) -> SessionTransition? {
        lock.lock()
        defer { lock.unlock() }
        guard _phase == .streaming, let last = lastMediaAt,
              Double(now.distance(to: last)) / 1_000_000 >= timeoutMs else { return nil }
        _phase = .degraded
        return SessionTransition(
            from: .streaming, to: .degraded, reason: "media timeout",
            releaseInputs: true, requestIDR: true
        )
    }
}
