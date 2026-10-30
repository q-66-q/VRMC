import XCTest
@testable import VRMCore

final class ReliabilityTests: XCTestCase {
    private let t0 = Timestamp(nanoseconds: 20_000_000_000)

    func testReacquireRequiresThreeConsecutiveSamples() {
        let recognizer = GestureRecognizer()
        let open = SyntheticHand.make(timestamp: t0)
        _ = recognizer.update(leftSnapshot: open, rightSnapshot: open, headPosition: SyntheticHand.headFar, now: t0)
        // Drop both hands.
        _ = recognizer.update(
            leftSnapshot: nil, rightSnapshot: nil,
            headPosition: SyntheticHand.headFar, now: t0.adding(milliseconds: 100)
        )
        // Reacquire with a pinch: the first two samples must not emit a press.
        for index in 1...2 {
            let timestamp = t0.adding(milliseconds: 100 + Double(index * 20))
            let left = SyntheticHand.make(chirality: .left, indexPinch: true, timestamp: timestamp)
            let right = SyntheticHand.make(chirality: .right, indexPinch: true, timestamp: timestamp)
            let result = recognizer.update(
                leftSnapshot: left, rightSnapshot: right,
                headPosition: SyntheticHand.headFar, now: timestamp
            )
            XCTAssertFalse(result.left.triggerPressed, "rearm sample \(index) must not fire")
            XCTAssertFalse(result.left.tracked, "rearm sample \(index) is not yet stable")
        }
        let thirdLeft = SyntheticHand.make(chirality: .left, indexPinch: true, timestamp: t0.adding(milliseconds: 170))
        let thirdRight = SyntheticHand.make(chirality: .right, indexPinch: true, timestamp: t0.adding(milliseconds: 170))
        var result = recognizer.update(
            leftSnapshot: thirdLeft, rightSnapshot: thirdRight,
            headPosition: SyntheticHand.headFar, now: t0.adding(milliseconds: 170)
        )
        XCTAssertTrue(result.left.tracked)

        let heldLeft = SyntheticHand.make(chirality: .left, indexPinch: true, timestamp: t0.adding(milliseconds: 250))
        let heldRight = SyntheticHand.make(chirality: .right, indexPinch: true, timestamp: t0.adding(milliseconds: 250))
        result = recognizer.update(
            leftSnapshot: heldLeft, rightSnapshot: heldRight,
            headPosition: SyntheticHand.headFar, now: t0.adding(milliseconds: 250)
        )
        XCTAssertTrue(result.left.triggerPressed)
    }

    func testTrackingCalibrationMovesHeadToStandingOrigin() {
        let head = Pose(position: Vec3(0.3, 1.6, -0.2), orientation: Quat.yaw(.pi / 2))
        let calibration = TrackingCalibration(head: head, userHeight: 1.62)
        let mapped = calibration.pose(head)
        XCTAssertEqual(mapped.position.x, 0, accuracy: 1e-5)
        XCTAssertEqual(mapped.position.y, 1.62, accuracy: 1e-5)
        XCTAssertEqual(mapped.position.z, 0, accuracy: 1e-5)
        XCTAssertEqual(mapped.orientation.yaw, 0, accuracy: 1e-5)
        let hand = SyntheticHand.make(base: Vec3(0.3, 1.0, -0.5), timestamp: t0)
        let mappedHand = calibration.hand(hand)
        XCTAssertEqual(mappedHand.joints[Int(HandJointName.wrist.rawValue)].position.y, 1.02, accuracy: 1e-4)
    }

    func testOneEuroFilterIsBounded() {
        var filter = OneEuroFilter3(minCutoff: 1.5, beta: 0.05)
        var value = Vec3.zero
        for index in 0..<100 {
            let timestamp = t0.adding(milliseconds: Double(index * 11))
            let noisy = Vec3(Float(sin(Double(index) * 0.7)) * 0.05 + 0.02, 1, 0)
            value = filter.filter(noisy, timestamp: timestamp)
            XCTAssertTrue(value.isFinite)
        }
        XCTAssertLessThan(abs(value.x), 0.2)
        XCTAssertEqual(value.y, 1, accuracy: 0.001)
    }

    func testLatencyTrackerPercentiles() {
        let tracker = LatencyTracker(capacity: 100)
        for value in [1.0, 2.0, 3.0, 4.0, 100.0] {
            tracker.record(.network, milliseconds: value)
        }
        let summary = tracker.summary(.network)
        XCTAssertEqual(summary.count, 5)
        XCTAssertEqual(summary.p50Ms, 3.0, accuracy: 0.001)
        XCTAssertEqual(summary.maxMs, 100.0, accuracy: 0.001)
    }

    func testInputDatagramRejectsWrongTypeAndTruncation() throws {
        let head = InputPayload.head(HeadInput())
        let datagram = try head.datagram(sessionId: 1, sequence: 1, timestampNs: 1)
        XCTAssertThrowsError(try InputPayload.parseDatagram(Data(datagram.prefix(datagram.count - 1))))
        var wrongType = datagram
        wrongType[3] = MediaPacketType.video.rawValue
        XCTAssertThrowsError(try InputPayload.parseDatagram(wrongType))
    }
}
