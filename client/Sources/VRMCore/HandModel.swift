import Foundation

public enum HandJointName: UInt8, CaseIterable, Sendable, Equatable, Codable {
    case wrist = 0
    case thumbKnuckle
    case thumbIntermediateBase
    case thumbIntermediateTip
    case thumbTip
    case indexMetacarpal
    case indexKnuckle
    case indexIntermediateBase
    case indexIntermediateTip
    case indexTip
    case middleMetacarpal
    case middleKnuckle
    case middleIntermediateBase
    case middleIntermediateTip
    case middleTip
    case ringMetacarpal
    case ringKnuckle
    case ringIntermediateBase
    case ringIntermediateTip
    case ringTip
    case littleMetacarpal
    case littleKnuckle
    case littleIntermediateBase
    case littleIntermediateTip
    case littleTip
    case forearmWrist
    case forearmArm

    public static let count = 27
}

public enum HandChirality: UInt8, Sendable, Equatable, Codable {
    case left = 0
    case right = 1

    public var opposite: HandChirality { self == .left ? .right : .left }
}

public enum TrackingQuality: UInt8, Sendable, Equatable, Codable {
    case invalid = 0
    case degraded = 1
    case tracked = 2
}

public struct HandJoint: Equatable, Sendable, Codable {
    public var position: Vec3
    public var orientation: Quat
    public var radius: Float

    public init(position: Vec3 = .zero, orientation: Quat = .identity, radius: Float = 0) {
        self.position = position
        self.orientation = orientation
        self.radius = radius
    }

    public var isAvailable: Bool { radius > 0 }

    public static let unavailable = HandJoint()
}

public struct HandSnapshot: Equatable, Sendable {
    public var chirality: HandChirality
    public var timestamp: Timestamp
    public var quality: TrackingQuality
    public var sampleId: UInt32
    public var joints: [HandJoint]
    public var palmPosition: Vec3
    public var palmOrientation: Quat

    public init(
        chirality: HandChirality,
        timestamp: Timestamp,
        quality: TrackingQuality = .tracked,
        sampleId: UInt32 = 0,
        joints: [HandJoint],
        palmPosition: Vec3? = nil,
        palmOrientation: Quat? = nil
    ) {
        self.chirality = chirality
        self.timestamp = timestamp
        self.quality = quality
        self.sampleId = sampleId
        self.joints = joints
        self.palmPosition = palmPosition ?? Self.defaultPalmPosition(joints)
        self.palmOrientation = palmOrientation ?? .identity
    }

    public static func empty(chirality: HandChirality, timestamp: Timestamp = .now(), quality: TrackingQuality = .invalid) -> HandSnapshot {
        HandSnapshot(
            chirality: chirality,
            timestamp: timestamp,
            quality: quality,
            sampleId: 0,
            joints: Array(repeating: .unavailable, count: HandJointName.count),
            palmPosition: .zero,
            palmOrientation: .identity
        )
    }

    public var isTracked: Bool { quality != .invalid }

    public func joint(_ name: HandJointName) -> HandJoint {
        let index = Int(name.rawValue)
        guard index >= 0, index < joints.count else { return .unavailable }
        return joints[index]
    }

    public func replacingJoint(_ name: HandJointName, with joint: HandJoint) -> HandSnapshot {
        var copy = self
        if copy.joints.count == HandJointName.count {
            copy.joints[Int(name.rawValue)] = joint
        }
        return copy
    }

    private static func defaultPalmPosition(_ joints: [HandJoint]) -> Vec3 {
        guard joints.count == HandJointName.count else { return .zero }
        let wrist = joints[Int(HandJointName.wrist.rawValue)].position
        let middle = joints[Int(HandJointName.middleKnuckle.rawValue)].position
        let ring = joints[Int(HandJointName.ringKnuckle.rawValue)].position
        return (wrist + middle + ring) / 3
    }
}

/// Geometric features used by gesture recognition. All distances are normalised by palm size.
public struct HandFeatures: Equatable, Sendable {
    public var chirality: HandChirality
    public var timestamp: Timestamp
    public var quality: TrackingQuality
    public var palmCenter: Vec3
    public var palmWidth: Float
    public var palmLength: Float
    public var palmNormal: Vec3
    public var forward: Vec3
    public var indexRay: Vec3
    public var aimDirection: Vec3
    public var pinchIndex: Float
    public var pinchMiddle: Float
    public var pinchRing: Float
    public var curl: Float
    public var indexCurl: Float
    public var palmUp: Bool
    public var palmDown: Bool
    public var facingHead: Bool
    public var palmDistanceToHead: Float
    public var handYaw: Float

    public static func compute(
        _ snapshot: HandSnapshot,
        headPosition: Vec3,
        palmNormalSign: Float = 1,
        palmUpThreshold: Float = 0.55,
        palmDownThreshold: Float = -0.55
    ) -> HandFeatures? {
        guard snapshot.joints.count == HandJointName.count else { return nil }
        let wrist = snapshot.joint(.wrist).position
        let indexKnuckle = snapshot.joint(.indexKnuckle).position
        let littleKnuckle = snapshot.joint(.littleKnuckle).position
        let middleKnuckle = snapshot.joint(.middleKnuckle).position
        let ringKnuckle = snapshot.joint(.ringKnuckle).position
        let thumbTip = snapshot.joint(.thumbTip).position
        let indexTip = snapshot.joint(.indexTip).position
        let middleTip = snapshot.joint(.middleTip).position
        let ringTip = snapshot.joint(.ringTip).position
        let littleTip = snapshot.joint(.littleTip).position

        let palmWidth = max(0.02, indexKnuckle.distance(to: littleKnuckle))
        let palmLength = max(0.02, middleKnuckle.distance(to: wrist))
        let palmCenter = (wrist + middleKnuckle + ringKnuckle) / 3
        var normal = indexKnuckle.subtract(wrist).cross(littleKnuckle.subtract(wrist))
        normal = normal.normalized(or: .up) * (palmNormalSign >= 0 ? 1 : -1)
        let forward = middleKnuckle.subtract(wrist).normalized(or: .forward)
        let indexExtended = curlFor(tip: indexTip, wrist: wrist, palmLength: palmLength) < 0.35
        let indexRay = indexExtended
            ? indexTip.subtract(indexKnuckle).normalized(or: forward)
            : forward

        let curls = [
            curlFor(tip: indexTip, wrist: wrist, palmLength: palmLength),
            curlFor(tip: middleTip, wrist: wrist, palmLength: palmLength),
            curlFor(tip: ringTip, wrist: wrist, palmLength: palmLength),
            curlFor(tip: littleTip, wrist: wrist, palmLength: palmLength),
        ]
        let curl = curls.reduce(0, +) / Float(curls.count)
        let toHead = headPosition.subtract(palmCenter).normalized(or: .zero)
        let facing = normal.dot(toHead)

        return HandFeatures(
            chirality: snapshot.chirality,
            timestamp: snapshot.timestamp,
            quality: snapshot.quality,
            palmCenter: palmCenter,
            palmWidth: palmWidth,
            palmLength: palmLength,
            palmNormal: normal,
            forward: forward,
            indexRay: indexRay,
            aimDirection: indexRay,
            pinchIndex: thumbTip.distance(to: indexTip) / palmWidth,
            pinchMiddle: thumbTip.distance(to: middleTip) / palmWidth,
            pinchRing: thumbTip.distance(to: ringTip) / palmWidth,
            curl: curl,
            indexCurl: curls[0],
            palmUp: normal.y > palmUpThreshold,
            palmDown: normal.y < palmDownThreshold,
            facingHead: facing > 0.60,
            palmDistanceToHead: palmCenter.distance(to: headPosition),
            handYaw: atan2(-forward.x, -forward.z)
        )
    }

    private static func curlFor(tip: Vec3, wrist: Vec3, palmLength: Float) -> Float {
        let ratio = tip.distance(to: wrist) / (palmLength * 1.8)
        return 1 - min(max(ratio, 0), 1)
    }

    /// Grip pose used for the virtual controller. -Z is the aim direction.
    public var controllerPose: Pose {
        let orientation = Quat.fromBasis(forward: aimDirection, up: palmNormal)
        return Pose(position: palmCenter + forward * 0.02, orientation: orientation)
    }
}

private extension Vec3 {
    func subtract(_ other: Vec3) -> Vec3 { self - other }
}
