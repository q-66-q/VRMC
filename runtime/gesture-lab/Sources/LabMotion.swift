import Foundation
import ARKit
import simd

/// Deterministic features and a small live classifier used by the lab. These are deliberately simple
/// and provisional: the point is to label recordings and show whether the intended actions separate,
/// not to be the production gesture engine.
struct LabHandFeatures {
    var tracked = false
    /// Thumb-tip to index-tip distance, metres.
    var pinch: Float = 1
    /// Lab-only curl metric (fingertip→knuckle / wrist→knuckle, fist below 0.55). NOT the provider's
    /// `VisionInput.fistRatio` (fingertip→wrist / palm, fist below ~1.25): the two must not be mixed,
    /// which is why scripts/m7_lab_stats_hands.py recomputes the fist metric from raw joints.
    var fistRatio: Float = 1
    var isFist = false
    var isPinch = false
    var wristWorld = SIMD3<Float>(repeating: 0)
    var indexTipWorld = SIMD3<Float>(repeating: 0)
    /// Wrist speed in m/s (world space) and its vertical component (+ up).
    var speed: Float = 0
    var verticalSpeed: Float = 0
}

struct LabClassifierOutput {
    var label = "IDLE"
    var detail = ""
}

@MainActor
final class LabClassifier {
    /// Last wrist sample per hand ("L"/"R"), for finite-difference speeds.
    private var previous: [String: (position: SIMD3<Float>, time: TimeInterval)] = [:]

    func update(left: HandAnchor?, right: HandAnchor?, head: SIMD3<Float>?, time: TimeInterval) -> (LabHandFeatures, LabHandFeatures, LabClassifierOutput) {
        let lf = features(hand: left, key: "L", time: time)
        let rf = features(hand: right, key: "R", time: time)
        var out = LabClassifierOutput()
        var reasons: [String] = []
        if lf.isPinch { reasons.append("left pinch") }
        if rf.isPinch { reasons.append("right pinch") }
        if lf.isFist { reasons.append("left fist") }
        if rf.isFist { reasons.append("right fist") }
        // Precedence: both fists > single pinch > single fist; a fast right swing (> 1.4 m/s) overrides
        // everything below because a swing usually passes through pinch/fist-looking poses.
        if lf.isFist && rf.isFist {
            // Alternating vertical wrist motion (opposite directions, combined > 0.25 m/s) = walk.
            let alternating = abs(lf.verticalSpeed) + abs(rf.verticalSpeed) > 0.25
                && abs(lf.verticalSpeed - rf.verticalSpeed) > 0.10
            out.label = alternating ? "WALK_BOTH_FISTS" : "BOTH_FISTS"
        } else if lf.isPinch && !rf.isPinch {
            out.label = "LEFT_PINCH"
        } else if rf.isPinch && !lf.isPinch {
            out.label = "RIGHT_PINCH"
        } else if lf.isFist && !rf.isFist {
            out.label = "LEFT_FIST"
        } else if rf.isFist && !lf.isFist {
            out.label = "RIGHT_FIST"
        }
        if let head, rf.tracked {
            var headDistance = simd_distance(rf.wristWorld, head)
            headDistance = (headDistance * 10).rounded() / 10
            if out.label == "RIGHT_FIST" && headDistance < 0.30 { out.label = "RIGHT_HAND_AT_HEAD_\(headDistance)m" }
            if out.label == "IDLE" { out.label = "IDLE_right_to_head=\(headDistance)m" }
        }
        if rf.tracked && abs(rf.speed) > 1.4 { out.label = "RIGHT_SWING" }
        if lf.tracked && abs(lf.speed) > 1.4 { reasons.append("left swing") }
        out.detail = reasons.joined(separator: ", ")
        return (lf, rf, out)
    }

    private func features(hand: HandAnchor?, key: String, time: TimeInterval) -> LabHandFeatures {
        var f = LabHandFeatures()
        guard let hand, hand.isTracked, let skeleton = hand.handSkeleton else { return f }
        func joint(_ name: HandSkeleton.JointName) -> HandSkeleton.Joint? {
            skeleton.allJoints.first { $0.name == name }
        }
        func worldPosition(_ j: HandSkeleton.Joint?) -> SIMD3<Float>? {
            guard let j else { return nil }
            let m = simd_mul(hand.originFromAnchorTransform, j.anchorFromJointTransform)
            return SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        }
        guard let wrist = worldPosition(joint(.wrist)),
              let thumbTip = worldPosition(joint(.thumbTip)),
              let indexTip = worldPosition(joint(.indexFingerTip)),
              let middleTip = worldPosition(joint(.middleFingerTip)),
              let ringTip = worldPosition(joint(.ringFingerTip)),
              let littleTip = worldPosition(joint(.littleFingerTip)),
              let middleKnuckle = worldPosition(joint(.middleFingerKnuckle)),
              let indexKnuckle = worldPosition(joint(.indexFingerKnuckle)),
              let ringKnuckle = worldPosition(joint(.ringFingerKnuckle)),
              let littleKnuckle = worldPosition(joint(.littleFingerKnuckle)) else { return f }
        f.tracked = true
        f.wristWorld = wrist
        f.indexTipWorld = indexTip
        f.pinch = simd_distance(thumbTip, indexTip)
        f.isPinch = f.pinch < 0.030
        // Curl ratio: fingertip→knuckle distance divided by wrist→knuckle distance. Unlike a
        // palm-center/scale ratio this does not grow above 1 when the fist shortens the palm.
        let ratios = [
            simd_distance(indexTip, indexKnuckle) / max(0.02, simd_distance(wrist, indexKnuckle)),
            simd_distance(middleTip, middleKnuckle) / max(0.02, simd_distance(wrist, middleKnuckle)),
            simd_distance(ringTip, ringKnuckle) / max(0.02, simd_distance(wrist, ringKnuckle)),
            simd_distance(littleTip, littleKnuckle) / max(0.02, simd_distance(wrist, littleKnuckle))
        ]
        f.fistRatio = ratios.reduce(0, +) / Float(ratios.count)
        f.isFist = f.fistRatio < 0.55
        let previous = self.previous[key]
        if let previous {
            // Clamp dt: both hands' anchors can arrive in the same tick and would otherwise divide by ~0.
            let dt = max(1.0 / 240.0, time - previous.time)
            let delta = wrist - previous.position
            f.speed = simd_length(delta) / Float(dt)
            f.verticalSpeed = delta.y / Float(dt)
        }
        self.previous[key] = (wrist, time)
        return f
    }
}
