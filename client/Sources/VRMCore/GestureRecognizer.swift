import Foundation

public struct HandMappingProfile: Codable, Equatable, Sendable {
    public var id: String
    public var pinchIndexPress: Float
    public var pinchIndexRelease: Float
    public var pinchMiddlePress: Float
    public var pinchMiddleRelease: Float
    public var pinchRingPress: Float
    public var pinchRingRelease: Float
    public var fistPress: Float
    public var fistRelease: Float
    public var palmUpPress: Float
    public var palmUpRelease: Float
    public var locomotionDwellMs: Double
    public var locomotionRangeMeters: Float
    public var turnRangeDegrees: Float
    public var jumpFlickMeters: Float
    public var menuShortMs: Double
    public var menuLongMs: Double
    public var predictionMaxMs: Double
    public var staleMs: Double
    public var leftHanded: Bool
    public var palmNormalSignLeft: Float
    public var palmNormalSignRight: Float
    public var buttonPulseMs: Double
    public var deadzone: Float
    public var pinchDebounceMs: Double
    public var fistDebounceMs: Double

    public init(
        id: String = "handmap-v1",
        pinchIndexPress: Float = 0.25,
        pinchIndexRelease: Float = 0.45,
        pinchMiddlePress: Float = 0.30,
        pinchMiddleRelease: Float = 0.50,
        pinchRingPress: Float = 0.32,
        pinchRingRelease: Float = 0.52,
        fistPress: Float = 0.75,
        fistRelease: Float = 0.55,
        palmUpPress: Float = 0.55,
        palmUpRelease: Float = 0.35,
        locomotionDwellMs: Double = 150,
        locomotionRangeMeters: Float = 0.15,
        turnRangeDegrees: Float = 45,
        jumpFlickMeters: Float = 0.08,
        menuShortMs: Double = 350,
        menuLongMs: Double = 900,
        predictionMaxMs: Double = 50,
        staleMs: Double = 120,
        leftHanded: Bool = false,
        palmNormalSignLeft: Float = 1,
        palmNormalSignRight: Float = 1,
        buttonPulseMs: Double = 90,
        deadzone: Float = 0.08,
        pinchDebounceMs: Double = 70,
        fistDebounceMs: Double = 100
    ) {
        self.id = id
        self.pinchIndexPress = pinchIndexPress
        self.pinchIndexRelease = pinchIndexRelease
        self.pinchMiddlePress = pinchMiddlePress
        self.pinchMiddleRelease = pinchMiddleRelease
        self.pinchRingPress = pinchRingPress
        self.pinchRingRelease = pinchRingRelease
        self.fistPress = fistPress
        self.fistRelease = fistRelease
        self.palmUpPress = palmUpPress
        self.palmUpRelease = palmUpRelease
        self.locomotionDwellMs = locomotionDwellMs
        self.locomotionRangeMeters = locomotionRangeMeters
        self.turnRangeDegrees = turnRangeDegrees
        self.jumpFlickMeters = jumpFlickMeters
        self.menuShortMs = menuShortMs
        self.menuLongMs = menuLongMs
        self.predictionMaxMs = predictionMaxMs
        self.staleMs = staleMs
        self.leftHanded = leftHanded
        self.palmNormalSignLeft = palmNormalSignLeft
        self.palmNormalSignRight = palmNormalSignRight
        self.buttonPulseMs = buttonPulseMs
        self.deadzone = deadzone
        self.pinchDebounceMs = pinchDebounceMs
        self.fistDebounceMs = fistDebounceMs
    }

    public static let v1 = HandMappingProfile()

    public func normalSign(for chirality: HandChirality) -> Float {
        chirality == .left ? palmNormalSignLeft : palmNormalSignRight
    }

    public var locomotionChirality: HandChirality {
        leftHanded ? .right : .left
    }

    public var aimChirality: HandChirality {
        leftHanded ? .left : .right
    }

    public func controllerRole(for physical: HandChirality) -> HandChirality {
        leftHanded ? physical.opposite : physical
    }
}

public struct HandSignals: Equatable, Sendable {
    public var chirality: HandChirality
    public var timestamp: Timestamp
    public var tracked: Bool
    public var degraded: Bool
    public var controllerPose: Pose
    public var palmCenter: Vec3
    public var palmNormal: Vec3
    public var handYaw: Float
    public var trigger: Float
    public var triggerPressed: Bool
    public var usePressed: Bool
    public var grip: Float
    public var gripPressed: Bool
    public var ringPinchEdge: Bool
    public var palmUp: Bool
    public var palmToFace: Bool
    public var palmDownLow: Bool
    public var linearVelocity: Vec3
    public var angularVelocity: Vec3

    public static func released(_ chirality: HandChirality, timestamp: Timestamp = .now()) -> HandSignals {
        HandSignals(
            chirality: chirality, timestamp: timestamp, tracked: false, degraded: false,
            controllerPose: .identity, palmCenter: .zero, palmNormal: .up, handYaw: 0,
            trigger: 0, triggerPressed: false, usePressed: false,
            grip: 0, gripPressed: false, ringPinchEdge: false,
            palmUp: false, palmToFace: false, palmDownLow: false,
            linearVelocity: .zero, angularVelocity: .zero
        )
    }
}

public final class GestureRecognizer: @unchecked Sendable {
    private struct PinchState {
        var value: Float = 0
        var pressed = false
        var candidateSince: Timestamp?
        var lastValue: Float = 1
    }

    private struct HandState {
        var pinchIndex = PinchState()
        var pinchMiddle = PinchState()
        var pinchRing = PinchState()
        var fist = PinchState()
        var previousFeatures: HandFeatures?
        var previousTimestamp: Timestamp?
        var previousRing = false
        var hasTrackedSample = false
        var needsRearm = false
        var rearmSamples = 0
    }

    private let profile: HandMappingProfile
    private var left = HandState()
    private var right = HandState()

    public init(profile: HandMappingProfile = .v1) {
        self.profile = profile
    }

    public func reset() {
        left = HandState()
        right = HandState()
    }

    public func update(
        leftSnapshot: HandSnapshot?,
        rightSnapshot: HandSnapshot?,
        headPosition: Vec3,
        now: Timestamp = .now()
    ) -> (left: HandSignals, right: HandSignals) {
        let leftSignals = updateHand(.left, snapshot: leftSnapshot, headPosition: headPosition, now: now)
        let rightSignals = updateHand(.right, snapshot: rightSnapshot, headPosition: headPosition, now: now)
        return (leftSignals, rightSignals)
    }

    private func updateHand(
        _ chirality: HandChirality,
        snapshot: HandSnapshot?,
        headPosition: Vec3,
        now: Timestamp
    ) -> HandSignals {
        var state = chirality == .left ? left : right
        defer {
            if chirality == .left { left = state } else { right = state }
        }

        guard let snapshot,
              snapshot.chirality == chirality,
              snapshot.quality != .invalid,
              snapshot.joints.count == HandJointName.count,
              !snapshot.timestamp.isOlder(than: now, byMilliseconds: profile.staleMs),
              let features = HandFeatures.compute(
                snapshot,
                headPosition: headPosition,
                palmNormalSign: profile.normalSign(for: chirality),
                palmUpThreshold: profile.palmUpPress
              )
        else {
            resetHand(&state)
            return .released(chirality, timestamp: now)
        }

        let dt: Float
        if let previousTimestamp = state.previousTimestamp {
            dt = max(0, min(Float(snapshot.timestamp.distance(to: previousTimestamp)) / 1_000_000_000, 0.2))
        } else {
            dt = 0
        }
        if state.needsRearm {
            state.rearmSamples += 1
            if state.rearmSamples < 3 {
                state.previousFeatures = features
                state.previousTimestamp = snapshot.timestamp
                return .released(chirality, timestamp: snapshot.timestamp)
            }
            state.needsRearm = false
            state.rearmSamples = 0
        }

        let linearVelocity: Vec3
        let angularVelocity: Vec3
        if let previous = state.previousFeatures, dt > 0.001 {
            linearVelocity = (features.palmCenter - previous.palmCenter) / dt
            let yawDelta = normalizedAngle(features.handYaw - previous.handYaw)
            angularVelocity = Vec3(0, yawDelta / dt, 0)
        } else {
            linearVelocity = .zero
            angularVelocity = .zero
        }

        let indexPinch = updatePinch(
            &state.pinchIndex,
            raw: features.pinchIndex,
            press: profile.pinchIndexPress,
            release: profile.pinchIndexRelease,
            debounceMs: profile.pinchDebounceMs,
            now: snapshot.timestamp
        )
        let middlePinch = updatePinch(
            &state.pinchMiddle,
            raw: features.pinchMiddle,
            press: profile.pinchMiddlePress,
            release: profile.pinchMiddleRelease,
            debounceMs: profile.pinchDebounceMs,
            now: snapshot.timestamp
        )
        let ringPinch = updatePinch(
            &state.pinchRing,
            raw: features.pinchRing,
            press: profile.pinchRingPress,
            release: profile.pinchRingRelease,
            debounceMs: profile.pinchDebounceMs,
            now: snapshot.timestamp
        )

        // Fist uses curl, not a pinch distance; keep the same hysteresis state machine.
        let fistSignal = updateScalar(
            &state.fist,
            raw: features.curl,
            press: profile.fistPress,
            release: profile.fistRelease,
            debounceMs: profile.fistDebounceMs,
            now: snapshot.timestamp,
            inverted: false
        )

        let ringEdge = ringPinch.pressed && !state.previousRing
        state.previousRing = ringPinch.pressed
        state.previousFeatures = features
        state.previousTimestamp = snapshot.timestamp
        state.hasTrackedSample = true

        let palmToFace = features.facingHead && features.palmDistanceToHead >= 0.15 && features.palmDistanceToHead <= 0.60
        let palmDownLow = features.palmDown && features.palmCenter.y < headPosition.y - 0.25

        return HandSignals(
            chirality: chirality,
            timestamp: snapshot.timestamp,
            tracked: true,
            degraded: snapshot.quality == .degraded,
            controllerPose: features.controllerPose,
            palmCenter: features.palmCenter,
            palmNormal: features.palmNormal,
            handYaw: features.handYaw,
            trigger: indexPinch.value,
            triggerPressed: indexPinch.pressed,
            usePressed: middlePinch.pressed,
            grip: fistSignal.value,
            gripPressed: fistSignal.pressed,
            ringPinchEdge: ringEdge,
            palmUp: features.palmUp,
            palmToFace: palmToFace,
            palmDownLow: palmDownLow,
            linearVelocity: linearVelocity,
            angularVelocity: angularVelocity
        )
    }

    private func resetHand(_ state: inout HandState) {
        state = HandState()
        state.needsRearm = true
    }

    private struct ScalarSignal {
        var value: Float
        var pressed: Bool
    }

    private func updatePinch(
        _ state: inout PinchState,
        raw: Float,
        press: Float,
        release: Float,
        debounceMs: Double,
        now: Timestamp
    ) -> ScalarSignal {
        let analog = max(0, min(1, (release - raw) / max(0.001, release - press)))
        if !state.pressed {
            if raw < press {
                if state.candidateSince == nil { state.candidateSince = now }
                if let since = state.candidateSince,
                   doubleMilliseconds(from: since, to: now) >= debounceMs {
                    state.pressed = true
                }
            } else {
                state.candidateSince = nil
            }
        } else if raw > release {
            state.pressed = false
            state.candidateSince = nil
        }
        state.value = state.pressed ? max(analog, 0.15) : analog
        state.lastValue = raw
        return ScalarSignal(value: state.value, pressed: state.pressed)
    }

    private func updateScalar(
        _ state: inout PinchState,
        raw: Float,
        press: Float,
        release: Float,
        debounceMs: Double,
        now: Timestamp,
        inverted: Bool
    ) -> ScalarSignal {
        let value = inverted ? 1 - raw : raw
        let pressed = !state.pressed ? value > press : value >= release
        if pressed && !state.pressed {
            if state.candidateSince == nil { state.candidateSince = now }
            if let since = state.candidateSince,
               doubleMilliseconds(from: since, to: now) >= debounceMs {
                state.pressed = true
            }
        } else if !pressed {
            state.pressed = false
            state.candidateSince = nil
        }
        state.value = min(max(value, 0), 1)
        state.lastValue = raw
        return ScalarSignal(value: state.value, pressed: state.pressed)
    }

    private func doubleMilliseconds(from start: Timestamp, to end: Timestamp) -> Double {
        Double(end.distance(to: start)) / 1_000_000
    }

    private func normalizedAngle(_ angle: Float) -> Float {
        var value = angle
        while value > .pi { value -= 2 * .pi }
        while value < -.pi { value += 2 * .pi }
        return value
    }
}
