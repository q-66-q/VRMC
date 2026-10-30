import Foundation
import VRMCore

/// Synthetic two-hand source for the simulator and for input-path testing without ARKit.
/// It intentionally exercises pinch, fist, and locomotion poses.
final class SyntheticHands: @unchecked Sendable {
    typealias Update = @Sendable (HandSnapshot?, HandSnapshot?, Pose, TrackingQuality) -> Void

    private let update: Update
    private var timer: DispatchSourceTimer?
    private var startTime = Timestamp.now()

    init(update: @escaping Update) {
        self.update = update
    }

    func start() {
        guard timer == nil else { return }
        startTime = .now()
        let queue = DispatchQueue(label: "dev.vrmc.synthetic-hands", qos: .userInteractive)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(11))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let now = Timestamp.now()
        let elapsed = max(0, Double(now.distance(to: startTime)) / 1_000_000_000)
        let phase = Int(elapsed / 3) % 4
        let sway = Float(sin(elapsed * 0.8)) * 0.04
        let leftBase = Vec3(-0.18 + sway, 1.02, -0.36)
        let rightBase = Vec3(0.18 - sway, 1.02, -0.36)
        let head = Pose(
            position: Vec3(0, 1.6, 0),
            orientation: Quat.yaw(Float(sin(elapsed * 0.35)) * 0.18)
        )
        let left = makeHand(
            .left, base: leftBase,
            palmUp: phase == 2, fist: phase == 3,
            indexPinch: false, middlePinch: false,
            timestamp: now
        )
        let right = makeHand(
            .right, base: rightBase,
            palmUp: false, fist: phase == 1,
            indexPinch: phase == 0, middlePinch: phase == 2,
            timestamp: now
        )
        update(left, right, head, .tracked)
    }

    private func makeHand(
        _ chirality: HandChirality,
        base: Vec3,
        palmUp: Bool,
        fist: Bool,
        indexPinch: Bool,
        middlePinch: Bool,
        timestamp: Timestamp
    ) -> HandSnapshot {
        var joints = Array(repeating: HandJoint(position: base, orientation: .identity, radius: 0), count: 27)
        func set(_ name: HandJointName, _ position: Vec3) {
            joints[Int(name.rawValue)] = HandJoint(position: position, orientation: .identity, radius: 0.01)
        }
        let sign: Float = palmUp ? 1 : -1
        set(.wrist, base)
        set(.forearmWrist, base + Vec3(0, 0.01, 0.04))
        set(.forearmArm, base + Vec3(0, 0.01, 0.14))
        set(.indexKnuckle, base + Vec3(0.03 * sign, 0.02, -0.08))
        set(.middleKnuckle, base + Vec3(0, 0.02, -0.09))
        set(.ringKnuckle, base + Vec3(-0.02 * sign, 0.02, -0.085))
        set(.littleKnuckle, base + Vec3(-0.03 * sign, 0.02, -0.08))
        set(.indexMetacarpal, base + Vec3(0.025 * sign, 0.01, -0.04))
        set(.middleMetacarpal, base + Vec3(0, 0.01, -0.04))
        set(.ringMetacarpal, base + Vec3(-0.02 * sign, 0.01, -0.04))
        set(.littleMetacarpal, base + Vec3(-0.027 * sign, 0.01, -0.04))
        set(.thumbKnuckle, base + Vec3(0.04, 0.02, -0.03))
        set(.thumbIntermediateBase, base + Vec3(0.055, 0.03, -0.055))
        set(.thumbIntermediateTip, base + Vec3(0.06, 0.035, -0.08))
        set(.thumbTip, base + Vec3(0.06, 0.035, -0.10))

        let extensionDistance: Float = fist ? 0.025 : 0.16
        let indexTip = base + Vec3(0.03 * sign, 0.02, -extensionDistance)
        let middleTip = base + Vec3(0, 0.02, -extensionDistance - 0.01)
        let ringTip = base + Vec3(-0.02 * sign, 0.02, -extensionDistance)
        let littleTip = base + Vec3(-0.03 * sign, 0.02, -extensionDistance + 0.01)
        set(.indexIntermediateBase, base + Vec3(0.03 * sign, 0.02, -0.06))
        set(.indexIntermediateTip, base + Vec3(0.03 * sign, 0.02, -0.11))
        set(.indexTip, indexTip)
        set(.middleIntermediateBase, base + Vec3(0, 0.02, -0.06))
        set(.middleIntermediateTip, base + Vec3(0, 0.02, -0.12))
        set(.middleTip, middleTip)
        set(.ringIntermediateBase, base + Vec3(-0.02 * sign, 0.02, -0.06))
        set(.ringIntermediateTip, base + Vec3(-0.02 * sign, 0.02, -0.115))
        set(.ringTip, ringTip)
        set(.littleIntermediateBase, base + Vec3(-0.03 * sign, 0.02, -0.06))
        set(.littleIntermediateTip, base + Vec3(-0.03 * sign, 0.02, -0.11))
        set(.littleTip, littleTip)
        if indexPinch { set(.thumbTip, indexTip) }
        if middlePinch { set(.thumbTip, middleTip) }

        return HandSnapshot(
            chirality: chirality,
            timestamp: timestamp,
            quality: .tracked,
            sampleId: UInt32((timestamp.nanoseconds / 1_000_000) & 0xFFFF_FFFF),
            joints: joints
        )
    }
}
