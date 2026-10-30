import XCTest
@testable import VRMCore

final class GestureMappingTests: XCTestCase {
    private let t0 = Timestamp(nanoseconds: 10_000_000_000)

    private func at(_ ms: Double) -> Timestamp {
        t0.adding(milliseconds: ms)
    }

    func testFeaturesForOpenPinchAndFist() throws {
        let open = SyntheticHand.make(timestamp: t0)
        let openFeatures = try XCTUnwrap(HandFeatures.compute(open, headPosition: SyntheticHand.headFar))
        XCTAssertTrue(openFeatures.palmUp)
        XCTAssertGreaterThan(openFeatures.palmWidth, 0.05)
        XCTAssertGreaterThan(openFeatures.pinchIndex, 0.8)
        XCTAssertLessThan(openFeatures.curl, 0.3)

        let pinch = SyntheticHand.make(indexPinch: true, timestamp: t0)
        let pinchFeatures = try XCTUnwrap(HandFeatures.compute(pinch, headPosition: SyntheticHand.headFar))
        XCTAssertLessThan(pinchFeatures.pinchIndex, 0.05)
        XCTAssertGreaterThan(pinchFeatures.pinchMiddle, 0.5)

        let fist = SyntheticHand.make(fist: true, timestamp: t0)
        let fistFeatures = try XCTUnwrap(HandFeatures.compute(fist, headPosition: SyntheticHand.headFar))
        XCTAssertGreaterThan(fistFeatures.curl, 0.75)
    }

    func testPinchDebounceAndRelease() {
        let recognizer = GestureRecognizer()
        let left = SyntheticHand.make(chirality: .left, timestamp: t0)
        var result = recognizer.update(
            leftSnapshot: left,
            rightSnapshot: SyntheticHand.make(timestamp: t0),
            headPosition: SyntheticHand.headFar,
            now: t0
        )
        XCTAssertFalse(result.right.triggerPressed)

        let pinch = SyntheticHand.make(indexPinch: true, timestamp: at(80))
        _ = recognizer.update(
            leftSnapshot: left,
            rightSnapshot: pinch,
            headPosition: SyntheticHand.headFar,
            now: at(80)
        )
        let pinchHeld = SyntheticHand.make(indexPinch: true, timestamp: at(160))
        result = recognizer.update(
            leftSnapshot: left,
            rightSnapshot: pinchHeld,
            headPosition: SyntheticHand.headFar,
            now: at(160)
        )
        XCTAssertTrue(result.right.triggerPressed)
        XCTAssertGreaterThan(result.right.trigger, 0.5)

        let released = SyntheticHand.make(indexPinch: false, timestamp: at(200))
        result = recognizer.update(
            leftSnapshot: left,
            rightSnapshot: released,
            headPosition: SyntheticHand.headFar,
            now: at(200)
        )
        XCTAssertFalse(result.right.triggerPressed)
    }

    func testGripAndUseMapping() {
        let mapper = ControllerMapper()
        let left = SyntheticHand.make(chirality: .left, timestamp: t0)
        let right = SyntheticHand.make(timestamp: t0)
        _ = mapper.update(leftSnapshot: left, rightSnapshot: right, headPose: .identity, now: t0)

        let use = SyntheticHand.make(middlePinch: true, timestamp: at(120))
        _ = mapper.update(leftSnapshot: left, rightSnapshot: use, headPose: .identity, now: at(120))
        let useHeld = SyntheticHand.make(middlePinch: true, timestamp: at(200))
        let output = mapper.update(leftSnapshot: left, rightSnapshot: useHeld, headPose: .identity, now: at(200))
        XCTAssertTrue(output.right.buttons.contains(.trackpadClick))

        let fist = SyntheticHand.make(fist: true, timestamp: at(300))
        _ = mapper.update(leftSnapshot: left, rightSnapshot: fist, headPose: .identity, now: at(300))
        let fistHeld = SyntheticHand.make(fist: true, timestamp: at(450))
        let gripOutput = mapper.update(leftSnapshot: left, rightSnapshot: fistHeld, headPose: .identity, now: at(450))
        XCTAssertTrue(gripOutput.right.buttons.contains(.gripClick))
        XCTAssertGreaterThan(gripOutput.right.grip, 0.5)
    }

    func testLocomotionPalmJoystick() {
        let mapper = ControllerMapper()
        let left = SyntheticHand.make(chirality: .left, timestamp: t0)
        let right = SyntheticHand.make(timestamp: t0)
        var output = mapper.update(leftSnapshot: left, rightSnapshot: right, headPose: .identity, now: t0)
        XCTAssertFalse(output.locomotionActive)

        let held = SyntheticHand.make(chirality: .left, timestamp: at(200))
        output = mapper.update(leftSnapshot: held, rightSnapshot: right, headPose: .identity, now: at(200))
        XCTAssertTrue(output.locomotionActive)
        XCTAssertEqual(output.left.stickX, 0, accuracy: 0.05)
        XCTAssertEqual(output.left.stickY, 0, accuracy: 0.05)

        let moved = SyntheticHand.make(chirality: .left, base: Vec3(0, 1.0, -0.15), timestamp: at(300))
        output = mapper.update(leftSnapshot: moved, rightSnapshot: right, headPose: .identity, now: at(300))
        XCTAssertGreaterThan(output.left.stickY, 0.7)

        let lost = SyntheticHand.released(.left, timestamp: at(400))
        output = mapper.update(leftSnapshot: lost, rightSnapshot: right, headPose: .identity, now: at(400))
        XCTAssertFalse(output.locomotionActive)
        XCTAssertEqual(output.left.stickX, 0)
        XCTAssertEqual(output.left.stickY, 0)
        XCTAssertEqual(output.left.quality, .invalid)
    }

    func testInventoryShortDwellAndMenuLongDwell() {
        let mapper = ControllerMapper()
        let leftNear = SyntheticHand.make(chirality: .left, base: Vec3(0, 1.2, -0.05), timestamp: t0)
        let right = SyntheticHand.make(timestamp: t0)
        _ = mapper.update(leftSnapshot: leftNear, rightSnapshot: right, headPose: Pose(position: SyntheticHand.headNear), now: t0)

        let still = SyntheticHand.make(chirality: .left, base: Vec3(0, 1.2, -0.05), timestamp: at(400))
        _ = mapper.update(leftSnapshot: still, rightSnapshot: right, headPose: Pose(position: SyntheticHand.headNear), now: at(400))
        let released = SyntheticHand.make(chirality: .left, base: Vec3(0, 1.2, -0.05), palmUp: false, timestamp: at(500))
        let output = mapper.update(leftSnapshot: released, rightSnapshot: right, headPose: Pose(position: SyntheticHand.headNear), now: at(500))
        XCTAssertTrue(output.left.buttons.contains(.a), "short palm-to-face should emit inventory")

        let mapper2 = ControllerMapper()
        _ = mapper2.update(leftSnapshot: leftNear, rightSnapshot: right, headPose: Pose(position: SyntheticHand.headNear), now: t0)
        let long = SyntheticHand.make(chirality: .left, base: Vec3(0, 1.2, -0.05), timestamp: at(950))
        let output2 = mapper2.update(leftSnapshot: long, rightSnapshot: right, headPose: Pose(position: SyntheticHand.headNear), now: at(950))
        XCTAssertTrue(output2.left.buttons.contains(.b), "long palm-to-face should emit menu")
    }

    func testTrackingLossReleasesEverything() {
        let recognizer = GestureRecognizer()
        let held = SyntheticHand.make(indexPinch: true, fist: true, timestamp: t0)
        _ = recognizer.update(leftSnapshot: held, rightSnapshot: held, headPosition: SyntheticHand.headFar, now: t0)
        let lost = recognizer.update(
            leftSnapshot: nil, rightSnapshot: nil,
            headPosition: SyntheticHand.headFar, now: t0.adding(milliseconds: 200)
        )
        XCTAssertFalse(lost.left.triggerPressed)
        XCTAssertFalse(lost.right.gripPressed)
        XCTAssertFalse(lost.left.tracked)
    }

    func testLeftHandedRolesMirror() {
        var profile = HandMappingProfile.v1
        profile.leftHanded = true
        let mapper = ControllerMapper(profile: profile)
        let left = SyntheticHand.make(chirality: .left, indexPinch: true, timestamp: t0)
        let right = SyntheticHand.make(chirality: .right, timestamp: t0)
        _ = mapper.update(leftSnapshot: left, rightSnapshot: right, headPose: .identity, now: t0)
        let left2 = SyntheticHand.make(chirality: .left, indexPinch: true, timestamp: at(100))
        let output = mapper.update(leftSnapshot: left2, rightSnapshot: right, headPose: .identity, now: at(100))
        XCTAssertEqual(output.right.hand, HandChirality.right)
        XCTAssertTrue(output.right.buttons.contains(.triggerClick) || output.left.buttons.contains(.triggerClick))
    }

    func testSessionStateMachineRecovery() {
        let machine = SessionStateMachine()
        _ = machine.handle(.connectRequested, now: t0)
        _ = machine.handle(.helloReceived, now: t0)
        _ = machine.handle(.authenticated, now: t0)
        _ = machine.handle(.configReceived, now: t0)
        _ = machine.handle(.streamStarted, now: t0)
        XCTAssertEqual(machine.phase, .streaming)
        let timeout = machine.poll(now: t0.adding(milliseconds: 300), timeoutMs: 250)
        XCTAssertEqual(timeout?.to, .degraded)
        XCTAssertTrue(timeout?.releaseInputs == true)
        let recovered = machine.handle(.mediaReceived, now: t0.adding(milliseconds: 350))
        XCTAssertEqual(recovered.to, .streaming)
        XCTAssertTrue(recovered.requestIDR)
    }
}
