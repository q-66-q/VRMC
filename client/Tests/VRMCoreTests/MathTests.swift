import XCTest
@testable import VRMCore

final class MathTests: XCTestCase {
    func testBasisMapsForwardAndUp() {
        let forward = Vec3(0, 0, -1)
        let up = Vec3(0, 1, 0)
        let q = Quat.fromBasis(forward: forward, up: up)
        let mappedForward = q.rotate(Vec3(0, 0, -1))
        let mappedUp = q.rotate(Vec3(0, 1, 0))
        XCTAssertEqual(mappedForward.x, 0, accuracy: 1e-5)
        XCTAssertEqual(mappedForward.y, 0, accuracy: 1e-5)
        XCTAssertEqual(mappedForward.z, -1, accuracy: 1e-5)
        XCTAssertEqual(mappedUp.x, 0, accuracy: 1e-5)
        XCTAssertEqual(mappedUp.y, 1, accuracy: 1e-5)
        XCTAssertEqual(mappedUp.z, 0, accuracy: 1e-5)
    }

    func testQuaternionMultiplicationAndInverse() {
        let q = Quat.fromAxisAngle(axis: .up, radians: .pi / 2)
        let v = q.rotate(Vec3(1, 0, 0))
        XCTAssertEqual(v.x, 0, accuracy: 1e-5)
        XCTAssertEqual(v.z, -1, accuracy: 1e-5)
        let back = q.conjugate.rotate(v)
        XCTAssertEqual(back.x, 1, accuracy: 1e-5)
        XCTAssertEqual(back.z, 0, accuracy: 1e-5)
    }

    func testProjectionCenterRoundTrip() {
        let p = ProjectionTangents.symmetric100
        let direction = p.direction(ndcX: 0, ndcY: 0)
        let uv = p.imageCoordinate(direction: direction)
        XCTAssertNotNil(uv)
        XCTAssertEqual(uv!.x, 0.5, accuracy: 1e-5)
        XCTAssertEqual(uv!.y, 0.5, accuracy: 1e-5)
    }

    func testReprojectionIdentity() {
        let p = ProjectionTangents.symmetric100
        let uv = ProjectionMath.reproject(
            ndcX: 0.2, ndcY: -0.3,
            presentProjection: p,
            captureToPresent: .identity,
            captureProjection: p
        )
        XCTAssertNotNil(uv)
        XCTAssertEqual(uv!.x, 0.6, accuracy: 1e-5)
        XCTAssertEqual(uv!.y, 0.65, accuracy: 1e-5)
    }

    func testYawConvention() {
        let yaw = Quat.yaw(.pi / 2)
        XCTAssertEqual(yaw.yaw, .pi / 2, accuracy: 1e-5)
        let rotated = yaw.rotate(Vec3(0, 0, -1))
        XCTAssertEqual(rotated.x, -1, accuracy: 1e-5)
        XCTAssertEqual(rotated.z, 0, accuracy: 1e-5)
    }
}
