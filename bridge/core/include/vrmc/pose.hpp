#pragma once

#include "vrmc/protocol.hpp"

#include <algorithm>
#include <cmath>

namespace vrmc {
namespace pose_math {

inline Quat multiply(const Quat& a, const Quat& b) {
    return Quat{
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    };
}

inline Quat normalized(Quat value) {
    const float length = std::sqrt(value.x * value.x + value.y * value.y +
                                   value.z * value.z + value.w * value.w);
    if (!(length > 1e-6f)) return Quat{};
    value.x /= length; value.y /= length; value.z /= length; value.w /= length;
    return value;
}

inline Vec3 rotate(const Quat& q, const Vec3& v) {
    const Quat n = normalized(q);
    const Vec3 u{n.x, n.y, n.z};
    const Vec3 uv{
        u.y * v.z - u.z * v.y,
        u.z * v.x - u.x * v.z,
        u.x * v.y - u.y * v.x,
    };
    const Vec3 uuv{
        u.y * uv.z - u.z * uv.y,
        u.z * uv.x - u.x * uv.z,
        u.x * uv.y - u.y * uv.x,
    };
    return Vec3{
        v.x + 2 * (n.w * uv.x + uuv.x),
        v.y + 2 * (n.w * uv.y + uuv.y),
        v.z + 2 * (n.w * uv.z + uuv.z),
    };
}

inline Quat fromAxisAngle(const Vec3& axis, float radians) {
    const float length = std::sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z);
    if (!(length > 1e-6f)) return Quat{};
    const float half = radians * 0.5f;
    const float s = std::sin(half) / length;
    return normalized(Quat{axis.x * s, axis.y * s, axis.z * s, std::cos(half)});
}

inline Quat angularVelocity(const Vec3& velocity, float seconds) {
    const float speed = std::sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z);
    if (!(speed > 1e-6f) || !std::isfinite(seconds) || seconds <= 0) return Quat{};
    return fromAxisAngle(velocity, speed * std::min(seconds, 0.05f));
}

inline Pose predict(const Pose& pose, const Vec3& linear, const Vec3& angular, float seconds,
                    float maxSeconds = 0.05f) {
    if (!(seconds > 0) || !std::isfinite(seconds)) return pose;
    const float horizon = std::min(seconds, maxSeconds);
    const Quat delta = angularVelocity(angular, horizon);
    return Pose{
        Vec3{pose.position.x + linear.x * horizon,
             pose.position.y + linear.y * horizon,
             pose.position.z + linear.z * horizon},
        normalized(multiply(delta, pose.orientation)),
    };
}

inline float yaw(const Quat& q) {
    const Vec3 forward = rotate(q, Vec3{0, 0, -1});
    return std::atan2(-forward.x, -forward.z);
}

} // namespace pose_math
} // namespace vrmc
