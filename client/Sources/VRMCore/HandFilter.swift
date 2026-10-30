import Foundation

/// One-euro filtering for a hand snapshot. Raw skeletons are preserved by callers when
/// diagnostics need them; gameplay uses the filtered positions/orientations.
public struct HandFilter: Sendable {
    private var positionFilters: [OneEuroFilter3]
    private var orientationFilters: [QuatSmoother]

    public init(minCutoff: Float = 1.5, beta: Float = 0.05, orientationAlpha: Float = 0.5) {
        positionFilters = Array(repeating: OneEuroFilter3(minCutoff: minCutoff, beta: beta), count: HandJointName.count)
        orientationFilters = Array(repeating: QuatSmoother(alpha: orientationAlpha), count: HandJointName.count)
    }

    public mutating func reset() {
        for index in positionFilters.indices { positionFilters[index].reset() }
        for index in orientationFilters.indices { orientationFilters[index].reset() }
    }

    public mutating func filter(_ snapshot: HandSnapshot) -> HandSnapshot {
        guard snapshot.joints.count == HandJointName.count else { return snapshot }
        var joints = snapshot.joints
        for index in joints.indices {
            joints[index].position = positionFilters[index].filter(joints[index].position, timestamp: snapshot.timestamp)
            joints[index].orientation = orientationFilters[index].filter(joints[index].orientation)
        }
        return HandSnapshot(
            chirality: snapshot.chirality,
            timestamp: snapshot.timestamp,
            quality: snapshot.quality,
            sampleId: snapshot.sampleId,
            joints: joints,
            palmPosition: snapshot.palmPosition,
            palmOrientation: snapshot.palmOrientation
        )
    }
}
