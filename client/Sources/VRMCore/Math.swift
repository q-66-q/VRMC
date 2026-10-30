import Foundation
import simd

// MARK: - Vec3

public struct Vec3: Equatable, Sendable, Codable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(_ x: Float = 0, _ y: Float = 0, _ z: Float = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)
    public static let one = Vec3(1, 1, 1)
    public static let up = Vec3(0, 1, 0)
    public static let forward = Vec3(0, 0, -1)
    public static let right = Vec3(1, 0, 0)

    public var lengthSquared: Float { x * x + y * y + z * z }
    public var length: Float { sqrt(lengthSquared) }
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }

    public func normalized(or fallback: Vec3 = .zero) -> Vec3 {
        let length = length
        guard length > 1e-6, length.isFinite else { return fallback }
        return self / length
    }

    public func dot(_ other: Vec3) -> Float {
        x * other.x + y * other.y + z * other.z
    }

    public func cross(_ other: Vec3) -> Vec3 {
        Vec3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    public func clamped(min low: Vec3, max high: Vec3) -> Vec3 {
        Vec3(
            Swift.min(Swift.max(x, low.x), high.x),
            Swift.min(Swift.max(y, low.y), high.y),
            Swift.min(Swift.max(z, low.z), high.z)
        )
    }

    public func distance(to other: Vec3) -> Float {
        (self - other).length
    }

    public static func + (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    public static func - (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    public static prefix func - (value: Vec3) -> Vec3 {
        Vec3(-value.x, -value.y, -value.z)
    }

    public static func * (lhs: Vec3, rhs: Float) -> Vec3 {
        Vec3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }

    public static func * (lhs: Float, rhs: Vec3) -> Vec3 {
        rhs * lhs
    }

    public static func / (lhs: Vec3, rhs: Float) -> Vec3 {
        Vec3(lhs.x / rhs, lhs.y / rhs, lhs.z / rhs)
    }

    public static func += (lhs: inout Vec3, rhs: Vec3) {
        lhs = lhs + rhs
    }
}

// MARK: - Quaternion

/// Hamilton convention, `(x, y, z, w)`, right-handed, unit length.
public struct Quat: Equatable, Sendable, Codable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var w: Float

    public init(_ x: Float = 0, _ y: Float = 0, _ z: Float = 0, _ w: Float = 1) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public init(x: Float, y: Float, z: Float, w: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public static let identity = Quat()

    public var lengthSquared: Float { x * x + y * y + z * z + w * w }
    public var length: Float { sqrt(lengthSquared) }
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite && w.isFinite }

    public func normalized() -> Quat {
        let length = length
        guard length > 1e-6, length.isFinite else { return .identity }
        return Quat(x / length, y / length, z / length, w / length)
    }

    public var conjugate: Quat { Quat(-x, -y, -z, w) }

    /// Rotates `vector` by this quaternion.
    public func rotate(_ vector: Vec3) -> Vec3 {
        let q = normalized()
        let u = Vec3(q.x, q.y, q.z)
        let s = q.w
        let uv = u.cross(vector)
        let uuv = u.cross(uv)
        return vector + (uv * (2 * s)) + (uuv * 2)
    }

    public static func * (lhs: Quat, rhs: Quat) -> Quat {
        Quat(
            lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
            lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
            lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
            lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z
        )
    }

    public static func fromAxisAngle(axis: Vec3, radians: Float) -> Quat {
        let unit = axis.normalized(or: .up)
        let half = radians * 0.5
        let s = sin(half)
        return Quat(unit.x * s, unit.y * s, unit.z * s, cos(half)).normalized()
    }

    public static func fromAngularVelocity(_ velocity: Vec3, seconds: Float) -> Quat {
        let speed = velocity.length
        guard speed > 1e-6, speed.isFinite, seconds.isFinite else { return .identity }
        return fromAxisAngle(axis: velocity / speed, radians: speed * seconds)
    }

    /// Builds a rotation whose local -Z is `forward` and local +Y is approximately `up`.
    public static func fromBasis(forward: Vec3, up: Vec3) -> Quat {
        let f = forward.normalized(or: .forward)
        var r = f.cross(up)
        if r.lengthSquared < 1e-8 {
            r = f.cross(.up)
        }
        if r.lengthSquared < 1e-8 {
            r = f.cross(.right)
        }
        r = r.normalized(or: .right)
        let u = r.cross(f).normalized(or: .up)
        let z = -f

        // Rotation matrix columns: [r, u, z].
        let m00 = r.x, m01 = u.x, m02 = z.x
        let m10 = r.y, m11 = u.y, m12 = z.y
        let m20 = r.z, m21 = u.z, m22 = z.z
        let trace = m00 + m11 + m22
        var q: Quat
        if trace > 0 {
            let s = sqrt(trace + 1.0) * 2
            q = Quat((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s)
        } else if m00 > m11 && m00 > m22 {
            let s = sqrt(1.0 + m00 - m11 - m22) * 2
            q = Quat(0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s)
        } else if m11 > m22 {
            let s = sqrt(1.0 + m11 - m00 - m22) * 2
            q = Quat((m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s)
        } else {
            let s = sqrt(1.0 + m22 - m00 - m11) * 2
            q = Quat((m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s)
        }
        q = q.normalized()
        // Ensure a canonical sign to make tests deterministic.
        if q.w < 0 { q = Quat(-q.x, -q.y, -q.z, -q.w) }
        return q
    }

    public static func slerp(_ a: Quat, _ b: Quat, t: Float) -> Quat {
        var target = b
        var cosine = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
        if cosine < 0 {
            cosine = -cosine
            target = Quat(-b.x, -b.y, -b.z, -b.w)
        }
        if cosine > 0.9995 {
            return Quat(
                a.x + (target.x - a.x) * t,
                a.y + (target.y - a.y) * t,
                a.z + (target.z - a.z) * t,
                a.w + (target.w - a.w) * t
            ).normalized()
        }
        let theta0 = acos(Swift.min(Swift.max(cosine, -1), 1))
        let theta = theta0 * t
        let sinTheta0 = sin(theta0)
        let s0 = sin(theta0 - theta) / sinTheta0
        let s1 = sin(theta) / sinTheta0
        return Quat(
            a.x * s0 + target.x * s1,
            a.y * s0 + target.y * s1,
            a.z * s0 + target.z * s1,
            a.w * s0 + target.w * s1
        ).normalized()
    }

    /// Yaw around +Y, in radians, in the range (-pi, pi].
    public var yaw: Float {
        let q = normalized()
        let forward = q.rotate(Vec3(0, 0, -1))
        return atan2(-forward.x, -forward.z)
    }

    public static func yaw(_ radians: Float) -> Quat {
        fromAxisAngle(axis: .up, radians: radians)
    }
}

// MARK: - Pose / transform

public struct Pose: Equatable, Sendable, Codable {
    public var position: Vec3
    public var orientation: Quat

    public init(position: Vec3 = .zero, orientation: Quat = .identity) {
        self.position = position
        self.orientation = orientation
    }

    public static let identity = Pose()

    public func transformed(by other: Pose) -> Pose {
        Pose(
            position: position + other.orientation.rotate(self.position),
            orientation: (other.orientation * orientation).normalized()
        )
    }

    public var isFinite: Bool {
        position.isFinite && orientation.isFinite
    }
}

public struct PoseVelocity: Equatable, Sendable {
    public var linear: Vec3
    public var angular: Vec3

    public init(linear: Vec3 = .zero, angular: Vec3 = .zero) {
        self.linear = linear
        self.angular = angular
    }
}

// MARK: - Projection

/// Tangents of the half-angles at the near plane, as used by OpenVR/SteamVR.
public struct ProjectionTangents: Equatable, Sendable, Codable {
    public var left: Float
    public var right: Float
    public var top: Float
    public var bottom: Float

    public init(left: Float, right: Float, top: Float, bottom: Float) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public static let symmetric100 = ProjectionTangents(
        left: -tan(50 * .pi / 180),
        right: tan(50 * .pi / 180),
        top: tan(45 * .pi / 180),
        bottom: -tan(45 * .pi / 180)
    )

    public var isValid: Bool {
        left < right && bottom < top &&
            [left, right, top, bottom].allSatisfy { $0.isFinite }
    }

    /// Horizontal/vertical field of view in degrees.
    public var horizontalFOVDegrees: Float {
        (atan(right) - atan(left)) * 180 / .pi
    }

    public var verticalFOVDegrees: Float {
        (atan(top) - atan(bottom)) * 180 / .pi
    }

    /// Extracts tangents from a projection matrix by inverting NDC corner rays. This lets the
    /// renderer use the actual drawable projection instead of assuming the capture FOV.
    public static func from(projectionMatrix matrix: simd_float4x4) -> ProjectionTangents? {
        let inverse = simd_inverse(matrix)
        func eyeDirection(_ x: Float, _ y: Float) -> Vec3? {
            let clip = SIMD4<Float>(x, y, 1, 1)
            let eye = inverse * clip
            guard abs(eye.w) > 1e-6 else { return nil }
            let direction = Vec3(eye.x / eye.w, eye.y / eye.w, eye.z / eye.w)
            guard direction.z < -1e-6, direction.isFinite else { return nil }
            return direction
        }
        guard let left = eyeDirection(-1, 0), let right = eyeDirection(1, 0),
              let bottom = eyeDirection(0, -1), let top = eyeDirection(0, 1) else {
            return nil
        }
        let result = ProjectionTangents(
            left: left.x / -left.z,
            right: right.x / -right.z,
            top: top.y / -top.z,
            bottom: bottom.y / -bottom.z
        )
        return result.isValid ? result : nil
    }

    /// Maps a normalised device coordinate (-1...1) to a direction in eye space.
    public func direction(ndcX: Float, ndcY: Float) -> Vec3 {
        let x = left + (ndcX + 1) * 0.5 * (right - left)
        let y = bottom + (ndcY + 1) * 0.5 * (top - bottom)
        return Vec3(x, y, -1)
    }

    /// Maps an eye-space direction to normalised image coordinates (top-left origin).
    public func imageCoordinate(direction: Vec3) -> Vec3? {
        guard direction.z < -1e-6 else { return nil }
        let x = direction.x / -direction.z
        let y = direction.y / -direction.z
        let u = (x - left) / (right - left)
        let v = (top - y) / (top - bottom)
        return Vec3(u, v, 0)
    }
}

public enum ProjectionMath {
    /// Rotation-only reprojection: map a present eye direction to the capture eye image.
    public static func reproject(
        presentDirection: Vec3,
        captureToPresent: Quat,
        captureProjection: ProjectionTangents
    ) -> Vec2? {
        let captureDirection = captureToPresent.conjugate.rotate(presentDirection)
        guard let uv = captureProjection.imageCoordinate(direction: captureDirection) else { return nil }
        return Vec2(uv.x, uv.y)
    }

    /// Convenience for a screen NDC -> capture UV mapping.
    public static func reproject(
        ndcX: Float,
        ndcY: Float,
        presentProjection: ProjectionTangents,
        captureToPresent: Quat,
        captureProjection: ProjectionTangents
    ) -> Vec2? {
        let present = presentProjection.direction(ndcX: ndcX, ndcY: ndcY)
        return reproject(
            presentDirection: present,
            captureToPresent: captureToPresent,
            captureProjection: captureProjection
        )
    }
}

public struct Vec2: Equatable, Sendable, Codable {
    public var x: Float
    public var y: Float
    public init(_ x: Float = 0, _ y: Float = 0) {
        self.x = x
        self.y = y
    }
}
