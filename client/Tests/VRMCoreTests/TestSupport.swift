import Foundation
@testable import VRMCore

enum SyntheticHand {
    static let headFar = Vec3(0, 1.8, 0)
    static let headNear = Vec3(0, 1.5, 0)

    static func make(
        chirality: HandChirality = .right,
        base: Vec3 = Vec3(0, 1.0, 0),
        palmUp: Bool = true,
        indexPinch: Bool = false,
        middlePinch: Bool = false,
        ringPinch: Bool = false,
        fist: Bool = false,
        indexExtended: Bool = true,
        timestamp: Timestamp,
        quality: TrackingQuality = .tracked
    ) -> HandSnapshot {
        var joints = Array(repeating: HandJoint(position: base, orientation: .identity, radius: 0.008), count: 27)
        func set(_ name: HandJointName, _ position: Vec3) {
            joints[Int(name.rawValue)] = HandJoint(position: position, orientation: .identity, radius: 0.008)
        }
        let normalSign: Float = palmUp ? 1 : -1
        let wrist = base
        set(.wrist, wrist)
        set(.forearmWrist, wrist + Vec3(0, 0.01, 0.04))
        set(.forearmArm, wrist + Vec3(0, 0.01, 0.14))

        // Palm frame: +X toward index knuckle, -Z toward fingers.
        set(.indexKnuckle, base + Vec3(0.03 * normalSign, 0.02, -0.08))
        set(.middleKnuckle, base + Vec3(0, 0.02, -0.09))
        set(.ringKnuckle, base + Vec3(-0.02 * normalSign, 0.02, -0.085))
        set(.littleKnuckle, base + Vec3(-0.03 * normalSign, 0.02, -0.08))
        set(.indexMetacarpal, base + Vec3(0.025 * normalSign, 0.01, -0.04))
        set(.middleMetacarpal, base + Vec3(0, 0.01, -0.04))
        set(.ringMetacarpal, base + Vec3(-0.02 * normalSign, 0.01, -0.04))
        set(.littleMetacarpal, base + Vec3(-0.027 * normalSign, 0.01, -0.04))

        set(.thumbKnuckle, base + Vec3(0.04, 0.02, -0.03))
        set(.thumbIntermediateBase, base + Vec3(0.055, 0.03, -0.055))
        set(.thumbIntermediateTip, base + Vec3(0.06, 0.035, -0.08))
        set(.thumbTip, base + Vec3(0.06, 0.035, -0.10))

        let extensionDistance: Float = fist ? 0.025 : 0.16
        let indexTip = base + Vec3(0.03 * normalSign, 0.02, -extensionDistance)
        let middleTip = base + Vec3(0, 0.02, -extensionDistance - 0.01)
        let ringTip = base + Vec3(-0.02 * normalSign, 0.02, -extensionDistance)
        let littleTip = base + Vec3(-0.03 * normalSign, 0.02, -extensionDistance + 0.01)
        set(.indexIntermediateBase, base + Vec3(0.03 * normalSign, 0.02, -0.06))
        set(.indexIntermediateTip, base + Vec3(0.03 * normalSign, 0.02, -0.11))
        set(.indexTip, indexTip)
        set(.middleIntermediateBase, base + Vec3(0, 0.02, -0.06))
        set(.middleIntermediateTip, base + Vec3(0, 0.02, -0.12))
        set(.middleTip, middleTip)
        set(.ringIntermediateBase, base + Vec3(-0.02 * normalSign, 0.02, -0.06))
        set(.ringIntermediateTip, base + Vec3(-0.02 * normalSign, 0.02, -0.115))
        set(.ringTip, ringTip)
        set(.littleIntermediateBase, base + Vec3(-0.03 * normalSign, 0.02, -0.06))
        set(.littleIntermediateTip, base + Vec3(-0.03 * normalSign, 0.02, -0.11))
        set(.littleTip, littleTip)

        if indexPinch {
            set(.thumbTip, indexTip)
        }
        if middlePinch {
            set(.thumbTip, middleTip)
        }
        if ringPinch {
            set(.thumbTip, ringTip)
        }
        if indexPinch && middlePinch {
            // Not a realistic pose; keep the index pinch authoritative.
            set(.thumbTip, indexTip)
        }

        return HandSnapshot(
            chirality: chirality,
            timestamp: timestamp,
            quality: quality,
            sampleId: UInt32(timestamp.nanoseconds / 1_000_000),
            joints: joints,
            palmPosition: (wrist + base + Vec3(0, 0.02, -0.09)) / 2,
            palmOrientation: .identity
        )
    }

    static func released(_ chirality: HandChirality, timestamp: Timestamp) -> HandSnapshot {
        .empty(chirality: chirality, timestamp: timestamp, quality: .invalid)
    }
}
