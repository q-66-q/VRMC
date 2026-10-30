import Foundation
import VRMCore

/// Bounded history of client-space head poses, used to look up the local pose that
/// corresponds to a frame's `clientHeadTimestampNs`. This keeps reprojection in one
/// coordinate system (ARKit world) instead of mixing it with SteamVR tracking space.
final class HeadPoseHistory: @unchecked Sendable {
    private struct Entry {
        var timestamp: Timestamp
        var pose: Pose
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let capacity: Int

    init(capacity: Int = 512) {
        self.capacity = capacity
    }

    func record(_ pose: Pose, at timestamp: Timestamp) {
        lock.lock()
        entries.append(Entry(timestamp: timestamp, pose: pose))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        lock.unlock()
    }

    func pose(at timestamp: Timestamp, toleranceMs: Double = 250) -> Pose? {
        guard timestamp.nanoseconds != 0 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        var best: Entry?
        var bestDistance = Int64.max
        for entry in entries {
            let distance = abs(entry.timestamp.distance(to: timestamp))
            if distance < bestDistance {
                bestDistance = distance
                best = entry
            }
        }
        guard let best, Double(bestDistance) / 1_000_000 <= toleranceMs else { return nil }
        return best.pose
    }

    func clear() {
        lock.lock(); entries.removeAll(keepingCapacity: true); lock.unlock()
    }
}
