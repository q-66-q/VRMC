package dev.vrmc.provider;

import org.joml.Matrix4f;
import org.joml.Matrix4fc;

/**
 * M4-W1 hand → controller-pose math (JOML only; no Minecraft/Vivecraft imports, host-unit-tested by
 * VisionHandPoseTest).
 *
 * <p>Design §5.2: for each tracked hand the controller pose is
 * <pre>
 *   translation = wrist_position (device space, metres)
 *   aim  = normalize(joint9 (index tip) - joint0 (wrist))
 *   side = normalize(joint20 (little metacarpal) - joint5 (index metacarpal))
 *   up   = normalize(cross(side, aim))
 *   z    = -aim
 *   x    = cross(up, z)
 *   rotation columns (x, up, z)   ->   R * (0,0,-1) == aim
 * </pre>
 * which is exactly what {@link net.vivecraft.client_vr.provider.MCVR#getAimVector(int)} expects
 * ({@code MathUtils.BACK} is {@code (0,0,-1)}). The joint-derived basis is handedness-agnostic:
 * the thumb/pinky metacarpal axis mirrors together with the hand, so the same formula yields the
 * same aim/roll convention for both hands.
 *
 * <p>When a hand is not tracked (or its joint layout is degenerate) the caller uses
 * {@link #gazeFallback(Matrix4fc, boolean, Matrix4f)}: the head pose translated to a shoulder offset
 * (RIGHT: -0.2 x, LEFT: +0.2 x, both -0.2 y / -0.05 z) with the head's orientation, so the GUI ray
 * and body-yaw estimation stay sane while no hand is visible. The caller keeps
 * {@code controllerTracking[c] = false} for the fallback (honest signal: a GUI click requires a
 * tracked hand).
 */
public final class VisionHandPose {
    /**
     * M4 visual-polish option: index-tip offset in controller-local space, from the current joints and
     * controller pose. Attaching the "tip" component here moves the held item/aim source to the finger
     * tip; aim rotation is unchanged. Optional (hand component mode "joints"); the default identity
     * behaviour remains the proven aim path.
     */
    public static void tipOffset(float[] joints, Matrix4fc controllerPose, org.joml.Vector3f out) {
        int wrist = JOINT_WRIST * 3;
        int tip = JOINT_INDEX_TIP * 3;
        org.joml.Vector3f tipDevice = new org.joml.Vector3f(
            joints[tip] - controllerPose.m30(), joints[tip + 1] - controllerPose.m31(),
            joints[tip + 2] - controllerPose.m32());
        org.joml.Matrix3f rot = new org.joml.Matrix3f(controllerPose);
        if (Math.abs(rot.determinant()) < 1.0E-6F) {
            out.set(0.0F);
            return;
        }
        rot.transpose().transform(tipDevice, out);
        if (!Float.isFinite(out.x) || !Float.isFinite(out.y) || !Float.isFinite(out.z)) out.set(0.0F);
    }

    /** Shoulder fallback offsets added to the HMD device-space position, metres (design §5.2). */
    public static final float SHOULDER_RIGHT_X = -0.2F;
    public static final float SHOULDER_LEFT_X = 0.2F;
    public static final float SHOULDER_Y = -0.2F;
    public static final float SHOULDER_Z = -0.05F;

    private static final float LENGTH_EPSILON = 1.0E-4F;

    // ARKit 27-joint indices this class consumes (bridge/abi/vrmc_abi.h §3.1). Kept local so this
    // class depends on java.* + JOML only; VisionInputLayoutTest pins the ABI values and
    // VisionHandPoseTest builds synthetic joints at these exact indices.
    private static final int JOINT_WRIST = 0;
    private static final int JOINT_INDEX_METACARPAL = 5;
    private static final int JOINT_INDEX_TIP = 9;
    private static final int JOINT_LITTLE_METACARPAL = 20;

    private VisionHandPose() {}

    /**
     * Build a controller pose from a tracked hand's device-space joints.
     *
     * @param joints flat 27*3 joint array ({@code joint * 3 + axis}); index order is the ARKit order
     *               documented in bridge/abi/vrmc_abi.h
     * @param qx/qy/qz/qw wrist_orientation, used only as a fallback when the joint basis is degenerate
     * @param wx/wy/wz    wrist_position (device space, metres), used verbatim as the translation
     * @param out         destination matrix (translation + orthonormal rotation, {@code R*(0,0,-1)=aim})
     */
    public static void handPose(float[] joints, float qx, float qy, float qz, float qw,
                                float wx, float wy, float wz, Matrix4f out) {
        int wrist = JOINT_WRIST * 3;
        int indexTip = JOINT_INDEX_TIP * 3;
        int indexMeta = JOINT_INDEX_METACARPAL * 3;
        int littleMeta = JOINT_LITTLE_METACARPAL * 3;

        float aimX = joints[indexTip] - joints[wrist];
        float aimY = joints[indexTip + 1] - joints[wrist + 1];
        float aimZ = joints[indexTip + 2] - joints[wrist + 2];
        float aimLen2 = aimX * aimX + aimY * aimY + aimZ * aimZ;
        if (!(aimLen2 > LENGTH_EPSILON * LENGTH_EPSILON) || !Float.isFinite(aimLen2)) {
            quaternionOrIdentity(qx, qy, qz, qw, out);
            out.setTranslation(wx, wy, wz);
            return;
        }
        float invAim = 1.0F / (float) Math.sqrt(aimLen2);
        aimX *= invAim;
        aimY *= invAim;
        aimZ *= invAim;

        float sideX = joints[littleMeta] - joints[indexMeta];
        float sideY = joints[littleMeta + 1] - joints[indexMeta + 1];
        float sideZ = joints[littleMeta + 2] - joints[indexMeta + 2];

        // up = normalize(cross(side, aim))
        float upX = sideY * aimZ - sideZ * aimY;
        float upY = sideZ * aimX - sideX * aimZ;
        float upZ = sideX * aimY - sideY * aimX;
        float upLen2 = upX * upX + upY * upY + upZ * upZ;
        if (!(upLen2 > LENGTH_EPSILON * LENGTH_EPSILON) || !Float.isFinite(upLen2)) {
            quaternionOrIdentity(qx, qy, qz, qw, out);
            out.setTranslation(wx, wy, wz);
            return;
        }
        float invUp = 1.0F / (float) Math.sqrt(upLen2);
        upX *= invUp;
        upY *= invUp;
        upZ *= invUp;

        // z = -aim
        float zX = -aimX;
        float zY = -aimY;
        float zZ = -aimZ;

        // x = normalize(cross(up, z))
        float xX = upY * zZ - upZ * zY;
        float xY = upZ * zX - upX * zZ;
        float xZ = upX * zY - upY * zX;
        float xLen2 = xX * xX + xY * xY + xZ * xZ;
        if (!(xLen2 > LENGTH_EPSILON * LENGTH_EPSILON) || !Float.isFinite(xLen2)) {
            quaternionOrIdentity(qx, qy, qz, qw, out);
            out.setTranslation(wx, wy, wz);
            return;
        }
        float invX = 1.0F / (float) Math.sqrt(xLen2);
        xX *= invX;
        xY *= invX;
        xZ *= invX;

        // Re-orthogonalize up = cross(z, x) so the basis is orthonormal to float precision.
        float up2X = zY * xZ - zZ * xY;
        float up2Y = zZ * xX - zX * xZ;
        float up2Z = zX * xY - zY * xX;

        // JOML's 16-arg set() takes column-major linear values: column 0 = basis x, column 1 = up,
        // column 2 = z. (Row-major arguments here would produce R^T and break R*(0,0,-1)=aim.)
        out.set(
            xX, xY, xZ, 0.0F,
            up2X, up2Y, up2Z, 0.0F,
            zX, zY, zZ, 0.0F,
            0.0F, 0.0F, 0.0F, 1.0F);
        out.setTranslation(wx, wy, wz);
    }

    /**
     * Opaque hand pose used while the hand is NOT tracked (design §5.2): the head pose translated to
     * a shoulder offset, same orientation as the head. Keeps the GUI pointer ray sane and prevents
     * two coincident controller origins; the caller keeps controllerTracking = false.
     *
     * @param hmdPose   head pose in device space (rotation + translation)
     * @param rightHand true = right hand/shoulder, false = left
     */
    public static void gazeFallback(Matrix4fc hmdPose, boolean rightHand, Matrix4f out) {
        out.set(hmdPose);
        float x = hmdPose.m30() + (rightHand ? SHOULDER_RIGHT_X : SHOULDER_LEFT_X);
        float y = hmdPose.m31() + SHOULDER_Y;
        float z = hmdPose.m32() + SHOULDER_Z;
        out.setTranslation(x, y, z);
    }

    /** True when {@link #handPose} would use the joint-derived basis (not the quaternion fallback). */
    public static boolean hasUsableJointBasis(float[] joints) {
        int wrist = JOINT_WRIST * 3;
        int indexTip = JOINT_INDEX_TIP * 3;
        float aimX = joints[indexTip] - joints[wrist];
        float aimY = joints[indexTip + 1] - joints[wrist + 1];
        float aimZ = joints[indexTip + 2] - joints[wrist + 2];
        if (!(aimX * aimX + aimY * aimY + aimZ * aimZ > LENGTH_EPSILON * LENGTH_EPSILON)) return false;
        int indexMeta = JOINT_INDEX_METACARPAL * 3;
        int littleMeta = JOINT_LITTLE_METACARPAL * 3;
        float sideX = joints[littleMeta] - joints[indexMeta];
        float sideY = joints[littleMeta + 1] - joints[indexMeta + 1];
        float sideZ = joints[littleMeta + 2] - joints[indexMeta + 2];
        // up = cross(side, aim); degenerate when side is parallel to aim
        float upX = sideY * aimZ - sideZ * aimY;
        float upY = sideZ * aimX - sideX * aimZ;
        float upZ = sideX * aimY - sideY * aimX;
        return upX * upX + upY * upY + upZ * upZ > LENGTH_EPSILON * LENGTH_EPSILON * aimX * aimX
            && upX * upX + upY * upY + upZ * upZ > LENGTH_EPSILON * LENGTH_EPSILON
            && Float.isFinite(upX + upY + upZ + aimX + aimY + aimZ);
    }

    /** Rotation-only result (translation handled by the caller): quat if usable, identity otherwise. */
    private static void quaternionOrIdentity(float qx, float qy, float qz, float qw, Matrix4f out) {
        float norm2 = qx * qx + qy * qy + qz * qz + qw * qw;
        if (!(norm2 > 1.0E-8F) || !Float.isFinite(norm2)) {
            out.identity();
            return;
        }
        float inv = 1.0F / (float) Math.sqrt(norm2);
        float x = qx * inv, y = qy * inv, z = qz * inv, w = qw * inv;
        float xx = x * x, yy = y * y, zz = z * z;
        float xy = x * y, xz = x * z, yz = y * z;
        float wx = w * x, wy = w * y, wz = w * z;
        // column-major argument order (column 0, then column 1, then column 2)
        out.set(
            1.0F - 2.0F * (yy + zz), 2.0F * (xy + wz), 2.0F * (xz - wy), 0.0F,
            2.0F * (xy - wz), 1.0F - 2.0F * (xx + zz), 2.0F * (yz + wx), 0.0F,
            2.0F * (xz + wy), 2.0F * (yz - wx), 1.0F - 2.0F * (xx + yy), 0.0F,
            0.0F, 0.0F, 0.0F, 1.0F);
    }
}