import Foundation

public enum PosePredictor {
    /// Predicts a pose forward by `horizonSeconds`, clamped to `maxHorizon`.
    /// Uses constant linear/angular velocity. Returns the input pose on invalid input or
    /// when the horizon is zero.
    public static func predict(
        pose: Pose,
        velocity: PoseVelocity,
        horizonSeconds: Float,
        maxHorizon: Float = 0.05
    ) -> Pose {
        guard pose.isFinite, horizonSeconds.isFinite, horizonSeconds > 0 else { return pose }
        let horizon = min(max(horizonSeconds, 0), maxHorizon)
        guard horizon > 0 else { return pose }
        let positionDelta = velocity.linear * horizon
        let angular = velocity.angular
        let clampedSpeed = angular.length
        let rotation: Quat
        if clampedSpeed > 20 {
            rotation = Quat.fromAngularVelocity(angular.normalized() * 20, seconds: horizon)
        } else {
            rotation = Quat.fromAngularVelocity(angular, seconds: horizon)
        }
        return Pose(
            position: pose.position + positionDelta,
            orientation: (rotation * pose.orientation).normalized()
        )
    }

    /// Confidence-weighted horizon: zero movement when confidence is low.
    public static func horizon(
        requestedMs: Double,
        confidence: Float,
        maxMs: Double = 50
    ) -> Float {
        let clamped = min(max(requestedMs, 0), maxMs)
        return Float(clamped / 1000) * min(max(confidence, 0), 1)
    }
}

public struct OneEuroFilter3: Sendable {
    public var minCutoff: Float
    public var beta: Float
    public var derivativeCutoff: Float
    private var previousValue: Vec3?
    private var previousDerivative: Vec3 = .zero
    private var previousTime: Timestamp?

    public init(minCutoff: Float = 1.5, beta: Float = 0.05, derivativeCutoff: Float = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    public mutating func reset() {
        previousValue = nil
        previousDerivative = .zero
        previousTime = nil
    }

    public mutating func filter(_ value: Vec3, timestamp: Timestamp) -> Vec3 {
        guard value.isFinite else { return previousValue ?? .zero }
        guard let previousValue, let previousTime else {
            self.previousValue = value
            self.previousTime = timestamp
            return value
        }
        let dt = Float(timestamp.distance(to: previousTime)) / 1_000_000_000
        guard dt > 0.0001, dt < 1 else {
            self.previousValue = value
            self.previousTime = timestamp
            return value
        }
        let derivative = (value - previousValue) / dt
        let derivativeAlpha = alpha(cutoff: derivativeCutoff, dt: dt)
        let filteredDerivative = previousDerivative + (derivative - previousDerivative) * derivativeAlpha
        let cutoff = minCutoff + beta * filteredDerivative.length
        let valueAlpha = alpha(cutoff: cutoff, dt: dt)
        let filtered = previousValue + (value - previousValue) * valueAlpha
        self.previousValue = filtered
        self.previousDerivative = filteredDerivative
        self.previousTime = timestamp
        return filtered
    }

    private func alpha(cutoff: Float, dt: Float) -> Float {
        let tau = 1 / (2 * .pi * max(cutoff, 0.0001))
        return 1 / (1 + tau / dt)
    }
}

public struct QuatSmoother: Sendable {
    public var alpha: Float
    private var previous: Quat?

    public init(alpha: Float = 0.5) {
        self.alpha = min(max(alpha, 0.01), 1)
    }

    public mutating func reset() { previous = nil }

    public mutating func filter(_ value: Quat) -> Quat {
        guard value.isFinite, value.lengthSquared > 0.5 else { return previous ?? .identity }
        guard let previous else {
            self.previous = value.normalized()
            return value.normalized()
        }
        let filtered = Quat.slerp(previous, value.normalized(), t: alpha)
        self.previous = filtered
        return filtered
    }
}

public struct VelocityEstimator: Sendable {
    private var previousPose: Pose?
    private var previousTimestamp: Timestamp?
    public init() {}
    public mutating func reset() {
        previousPose = nil
        previousTimestamp = nil
    }

    public mutating func update(pose: Pose, timestamp: Timestamp) -> PoseVelocity {
        guard pose.isFinite else { return .init() }
        guard let previousPose, let previousTimestamp else {
            self.previousPose = pose
            self.previousTimestamp = timestamp
            return .init()
        }
        let dt = Float(timestamp.distance(to: previousTimestamp)) / 1_000_000_000
        guard dt > 0.0001, dt < 1 else {
            self.previousPose = pose
            self.previousTimestamp = timestamp
            return .init()
        }
        let linear = (pose.position - previousPose.position) / dt
        let delta = (pose.orientation * previousPose.orientation.conjugate).normalized()
        let angle = 2 * acos(min(max(delta.w, -1), 1))
        let axis = Vec3(delta.x, delta.y, delta.z)
        let angular = angle > 1e-4 ? axis.normalized() * (angle / dt) : .zero
        self.previousPose = pose
        self.previousTimestamp = timestamp
        return PoseVelocity(linear: linear, angular: angular)
    }
}
