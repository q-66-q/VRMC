import Foundation

/// Maps the ARKit world (origin at the user's initial eye position) into a SteamVR-like
/// standing frame: origin on the floor, +Y up, user facing -Z at session start.
public struct TrackingCalibration: Sendable {
    public var originYaw: Float
    public var originPosition: Vec3
    public var userHeight: Float

    public init(head: Pose, userHeight: Float = 1.62) {
        self.originYaw = head.orientation.yaw
        self.originPosition = head.position
        self.userHeight = userHeight
    }

    public func pose(_ raw: Pose) -> Pose {
        let yaw = Quat.yaw(-originYaw)
        let rotatedPosition = yaw.rotate(raw.position - originPosition)
        let position = Vec3(rotatedPosition.x, rotatedPosition.y + userHeight, rotatedPosition.z)
        return Pose(position: position, orientation: (yaw * raw.orientation).normalized())
    }

    public func hand(_ raw: HandSnapshot) -> HandSnapshot {
        let yaw = Quat.yaw(-originYaw)
        var joints = raw.joints
        for index in joints.indices {
            let rotated = yaw.rotate(joints[index].position - originPosition)
            joints[index].position = Vec3(rotated.x, rotated.y + userHeight, rotated.z)
            joints[index].orientation = (yaw * joints[index].orientation).normalized()
        }
        return HandSnapshot(
            chirality: raw.chirality,
            timestamp: raw.timestamp,
            quality: raw.quality,
            sampleId: raw.sampleId,
            joints: joints,
            palmPosition: pose(Pose(position: raw.palmPosition, orientation: raw.palmOrientation)).position,
            palmOrientation: (yaw * raw.palmOrientation).normalized()
        )
    }
}
