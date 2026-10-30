import XCTest
import simd
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

    func testProjectionTangentsFromMatrix() {
        let p = ProjectionTangents.symmetric100
        let m00 = 2 / (p.right - p.left)
        let m11 = 2 / (p.top - p.bottom)
        let m20 = (p.right + p.left) / (p.right - p.left)
        let m21 = (p.top + p.bottom) / (p.top - p.bottom)
        let near: Float = 0.05
        let far: Float = 100
        var matrix = matrix_identity_float4x4
        matrix.columns.0 = SIMD4(m00, 0, 0, 0)
        matrix.columns.1 = SIMD4(0, m11, 0, 0)
        matrix.columns.2 = SIMD4(m20, m21, -(far + near) / (far - near), -1)
        matrix.columns.3 = SIMD4(0, 0, -2 * far * near / (far - near), 0)
        let extracted = ProjectionTangents.from(projectionMatrix: matrix)
        XCTAssertNotNil(extracted)
        XCTAssertEqual(extracted!.left, p.left, accuracy: 0.001)
        XCTAssertEqual(extracted!.right, p.right, accuracy: 0.001)
        XCTAssertEqual(extracted!.top, p.top, accuracy: 0.001)
        XCTAssertEqual(extracted!.bottom, p.bottom, accuracy: 0.001)
    }

    func testYawConvention() {
        let yaw = Quat.yaw(.pi / 2)
        XCTAssertEqual(yaw.yaw, .pi / 2, accuracy: 1e-5)
        let rotated = yaw.rotate(Vec3(0, 0, -1))
        XCTAssertEqual(rotated.x, -1, accuracy: 1e-5)
        XCTAssertEqual(rotated.z, 0, accuracy: 1e-5)
    }
}
