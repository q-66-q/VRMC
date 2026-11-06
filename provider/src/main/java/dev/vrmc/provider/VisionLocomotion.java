package dev.vrmc.provider;

import org.joml.Vector2f;

/**
 * M4-W3 middle-pinch virtual-stick mapping (pure Java/JOML; host-testable).
 *
 * <p>While the left middle-finger pinch is held (thumb tip to middle tip, disjoint from the W1
 * thumb-index pinch), the left wrist's position relative to the head becomes a virtual stick:
 * pushing the hand forward walks forward, pulling it back walks backward, moving it right/left
 * strafes. The values feed Vivecraft's {@code keyFreeMoveStrafe} analog action, so MCVR's own
 * free-move rotation/comfort settings still decide whether movement is HMD- or controller-relative.
 *
 * <p>Conventions: device space (ARKit, metres, +x right, -z forward). {@code originZ} is the wrist's
 * neutral forward offset: at rest the hand is already slightly in front of the head, and a small
 * neutral band keeps tracking jitter from moving the player. Output is clamped to [-1, 1] after a
 * radial deadzone; a non-finite input yields (0,0) (never move the player on bad data).
 */
public final class VisionLocomotion {
    /** Tunable neutral forward offset (metres; wristZ at rest ≈ -0.05 m in device space). */
    public static final float DEFAULT_ORIGIN_Z = 0.05F;
    public static final float DEFAULT_FORWARD_SCALE = 3.0F;
    public static final float DEFAULT_STRAFE_SCALE = 3.0F;
    public static final float DEFAULT_DEADZONE = 0.10F;

    private VisionLocomotion() {}

    public static Vector2f axes(float wristX, float wristY, float wristZ,
                                float headX, float headY, float headZ,
                                float originZ, float forwardScale, float strafeScale, float deadzone) {
        Vector2f out = new Vector2f();
        axes(wristX, wristY, wristZ, headX, headY, headZ, originZ, forwardScale, strafeScale, deadzone, out);
        return out;
    }

    /**
     * Allocation-free variant for the per-frame game path. Always writes (never leaves stale values).
     */
    public static void axes(float wristX, float wristY, float wristZ,
                            float headX, float headY, float headZ,
                            float originZ, float forwardScale, float strafeScale, float deadzone,
                            Vector2f dest) {
        dest.set(0.0F, 0.0F);
        if (!Float.isFinite(wristX) || !Float.isFinite(wristY) || !Float.isFinite(wristZ)
            || !Float.isFinite(headX) || !Float.isFinite(headY) || !Float.isFinite(headZ)) {
            return;
        }
        float relX = wristX - headX;
        float relZ = wristZ - headZ;
        // -z is forward: a hand in front of its neutral point yields positive forward.
        float forward = (-relZ - originZ) * forwardScale;
        float strafe = relX * strafeScale;
        forward = clamp(forward);
        strafe = clamp(strafe);
        float magnitude = (float) Math.sqrt(forward * forward + strafe * strafe);
        float dead = Math.max(0.0F, deadzone);
        if (magnitude <= dead) return;
        // Rescale past the deadzone so full deflection still reaches 1.
        float scaled = Math.min(1.0F, (magnitude - dead) / Math.max(1.0E-4F, 1.0F - dead));
        float inv = scaled / magnitude;
        dest.set(strafe * inv, forward * inv);
    }

    /**
     * Player-relative M7 movement: the caller already projected the wrist-minus-head vector onto the
     * HMD's horizontal forward/right basis. {@code wristForward} is metres along the player's look
     * direction (positive = in front), {@code wristRight} is metres to the player's right.
     */
    public static void axesRelative(float wristForward, float wristRight,
                                    float originZ, float forwardScale, float strafeScale,
                                    float deadzone, Vector2f dest) {
        dest.set(0.0F, 0.0F);
        if (!Float.isFinite(wristForward) || !Float.isFinite(wristRight)) {
            return;
        }
        float forward = clamp((wristForward - originZ) * forwardScale);
        float strafe = clamp(wristRight * strafeScale);
        float magnitude = (float) Math.sqrt(forward * forward + strafe * strafe);
        float dead = Math.max(0.0F, deadzone);
        if (magnitude <= dead) return;
        float scaled = Math.min(1.0F, (magnitude - dead) / Math.max(1.0E-4F, 1.0F - dead));
        float inv = scaled / magnitude;
        dest.set(strafe * inv, forward * inv);
    }

    public static Vector2f axesRelative(float wristForward, float wristRight, float originZ,
                                        float forwardScale, float strafeScale, float deadzone) {
        Vector2f out = new Vector2f();
        axesRelative(wristForward, wristRight, originZ, forwardScale, strafeScale, deadzone, out);
        return out;
    }

    public static Vector2f axes(float wristX, float wristY, float wristZ,
                                float headX, float headY, float headZ) {
        return axes(wristX, wristY, wristZ, headX, headY, headZ,
            DEFAULT_ORIGIN_Z, DEFAULT_FORWARD_SCALE, DEFAULT_STRAFE_SCALE, DEFAULT_DEADZONE);
    }

    private static float clamp(float v) {
        return Math.max(-1.0F, Math.min(1.0F, v));
    }
}
