import Foundation
import ARKit
import QuartzCore
import simd
import VRMCore

@available(visionOS 26.0, *)
final class HandTrackingService: @unchecked Sendable {
    typealias Update = @Sendable (HandSnapshot?, HandSnapshot?, Pose, TrackingQuality) -> Void

    private let session = ARKitSession()
    private let hands = HandTrackingProvider()
    private let world = WorldTrackingProvider()
    private let update: Update
    private let onStatus: @Sendable (String) -> Void
    private var task: Task<Void, Never>?
    private var latestLeft: HandSnapshot?
    private var latestRight: HandSnapshot?
    private let lock = NSLock()

    init(
        update: @escaping Update,
        onStatus: @escaping @Sendable (String) -> Void
    ) {
        self.update = update
        self.onStatus = onStatus
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            let authorization = await session.requestAuthorization(for: [.handTracking, .worldSensing])
            guard authorization[.handTracking] == .allowed else {
                onStatus("Hand tracking permission denied. Enable it in Settings → Privacy & Security.")
                return
            }
            guard HandTrackingProvider.isSupported else {
                onStatus("Hand tracking is not supported on this device.")
                return
            }
            do {
                try await session.run([hands, world])
            } catch {
                onStatus("Tracking failed to start: \(error.localizedDescription)")
                return
            }
            onStatus("Hand tracking running")
            for await anchorUpdate in hands.anchorUpdates {
                let anchor = anchorUpdate.anchor
                let snapshot = Self.snapshot(from: anchor)
                let pair = recordAndRead(snapshot: snapshot, chirality: anchor.chirality)
                let head = headPose()
                update(pair.left, pair.right, head.pose, head.quality)
            }
        }
    }

    private func recordAndRead(snapshot: HandSnapshot, chirality: HandAnchor.Chirality) -> (left: HandSnapshot?, right: HandSnapshot?) {
        lock.lock()
        defer { lock.unlock() }
        if chirality == .left {
            latestLeft = snapshot
        } else {
            latestRight = snapshot
        }
        return (latestLeft, latestRight)
    }

    func stop() {
        task?.cancel()
        task = nil
        session.stop()
    }

    private func headPose() -> (pose: Pose, quality: TrackingQuality) {
        let timestamp = CACurrentMediaTime()
        guard let anchor = world.queryDeviceAnchor(atTimestamp: timestamp) else {
            return (.identity, .invalid)
        }
        guard anchor.isTracked else { return (.identity, .invalid) }
        let pose = Pose(
            position: Vec3(anchor.originFromAnchorTransform.columns.3.x,
                           anchor.originFromAnchorTransform.columns.3.y,
                           anchor.originFromAnchorTransform.columns.3.z),
            orientation: Self.quaternion(from: anchor.originFromAnchorTransform).normalized()
        )
        let quality: TrackingQuality = anchor.trackingState == .tracked ? .tracked : .degraded
        return (pose, quality)
    }

    private static func snapshot(from anchor: HandAnchor) -> HandSnapshot {
        let chirality: HandChirality = anchor.chirality == .left ? .left : .right
        let timestamp = Timestamp(seconds: anchor.timestamp)
        guard let skeleton = anchor.handSkeleton, anchor.isTracked else {
            return .empty(chirality: chirality, timestamp: timestamp, quality: .invalid)
        }
        var joints = Array(repeating: HandJoint.unavailable, count: HandJointName.count)
        var availableCount = 0
        for joint in skeleton.allJoints {
            guard let name = mapJoint(joint.name) else { continue }
            let transform = simd_mul(anchor.originFromAnchorTransform, joint.anchorFromJointTransform)
            let position = Vec3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let orientation = quaternion(from: transform).normalized()
            let radius: Float = joint.isTracked ? 0.01 : 0
            if joint.isTracked { availableCount += 1 }
            joints[Int(name.rawValue)] = HandJoint(
                position: position, orientation: orientation, radius: radius
            )
        }
        let quality: TrackingQuality = availableCount >= 20 ? .tracked : availableCount > 0 ? .degraded : .invalid
        return HandSnapshot(
            chirality: chirality,
            timestamp: timestamp,
            quality: quality,
            sampleId: UInt32((timestamp.nanoseconds / 1_000_000) & 0xFFFF_FFFF),
            joints: joints
        )
    }

    private static func mapJoint(_ name: HandSkeleton.JointName) -> HandJointName? {
        switch name {
        case .wrist: return .wrist
        case .thumbKnuckle: return .thumbKnuckle
        case .thumbIntermediateBase: return .thumbIntermediateBase
        case .thumbIntermediateTip: return .thumbIntermediateTip
        case .thumbTip: return .thumbTip
        case .indexFingerMetacarpal: return .indexMetacarpal
        case .indexFingerKnuckle: return .indexKnuckle
        case .indexFingerIntermediateBase: return .indexIntermediateBase
        case .indexFingerIntermediateTip: return .indexIntermediateTip
        case .indexFingerTip: return .indexTip
        case .middleFingerMetacarpal: return .middleMetacarpal
        case .middleFingerKnuckle: return .middleKnuckle
        case .middleFingerIntermediateBase: return .middleIntermediateBase
        case .middleFingerIntermediateTip: return .middleIntermediateTip
        case .middleFingerTip: return .middleTip
        case .ringFingerMetacarpal: return .ringMetacarpal
        case .ringFingerKnuckle: return .ringKnuckle
        case .ringFingerIntermediateBase: return .ringIntermediateBase
        case .ringFingerIntermediateTip: return .ringIntermediateTip
        case .ringFingerTip: return .ringTip
        case .littleFingerMetacarpal: return .littleMetacarpal
        case .littleFingerKnuckle: return .littleKnuckle
        case .littleFingerIntermediateBase: return .littleIntermediateBase
        case .littleFingerIntermediateTip: return .littleIntermediateTip
        case .littleFingerTip: return .littleTip
        case .forearmWrist: return .forearmWrist
        case .forearmArm: return .forearmArm
        @unknown default: return nil
        }
    }

    private static func quaternion(from matrix: simd_float4x4) -> Quat {
        let m00 = matrix.columns.0.x, m01 = matrix.columns.1.x, m02 = matrix.columns.2.x
        let m10 = matrix.columns.0.y, m11 = matrix.columns.1.y, m12 = matrix.columns.2.y
        let m20 = matrix.columns.0.z, m21 = matrix.columns.1.z, m22 = matrix.columns.2.z
        let trace = m00 + m11 + m22
        var q: Quat
        if trace > 0 {
            let s = sqrt(trace + 1) * 2
            q = Quat((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s)
        } else if m00 > m11 && m00 > m22 {
            let s = sqrt(1 + m00 - m11 - m22) * 2
            q = Quat(0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s)
        } else if m11 > m22 {
            let s = sqrt(1 + m11 - m00 - m22) * 2
            q = Quat((m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s)
        } else {
            let s = sqrt(1 + m22 - m00 - m11) * 2
            q = Quat((m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s)
        }
        q = q.normalized()
        return q.w < 0 ? Quat(-q.x, -q.y, -q.z, -q.w) : q
    }
}
