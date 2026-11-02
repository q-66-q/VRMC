package dev.vrmc.provider;

import java.util.Random;
import org.joml.Matrix4f;
import org.joml.Vector3f;

/**
 * Host fuzz for {@link VisionHandPose} numerical robustness: random finite/degenerate joints, quats
 * and translations must always produce a finite orthonormal controller basis (or a finite identity
 * fallback), never NaN/Inf, and tip/gaze helpers must stay finite.
 */
public final class VisionHandPoseFuzzTest {
    private static final int CASES = 200_000;

    public static void main(String[] args) {
        Random rnd = new Random(0x1BADB002DEL);
        Matrix4f pose = new Matrix4f();
        float[] m = new float[16];
        int violations = 0;
        long nonFiniteSeen = 0;
        for (int i = 0; i < CASES; i++) {
            float[] joints = new float[VisionInput.JOINT_COUNT * 3];
            for (int j = 0; j < joints.length; j++) joints[j] = value(rnd);
            float qx = value(rnd), qy = value(rnd), qz = value(rnd), qw = value(rnd);
            float wx = value(rnd), wy = value(rnd), wz = value(rnd);
            VisionHandPose.handPose(joints, qx, qy, qz, qw, wx, wy, wz, pose);
            pose.get(m);
            boolean finite = true;
            for (float v : m) if (!Float.isFinite(v)) { finite = false; break; }
            if (!finite) {
                nonFiniteSeen++;
                if (++violations <= 5) System.out.println("  VIOLATION non-finite pose case=" + i);
                continue;
            }
            if (m[12] != wx || m[13] != wy || m[14] != wz) {
                if (++violations <= 5) System.out.println("  VIOLATION translation case=" + i);
            }
            float x0 = m[0], x1 = m[1], x2 = m[2];
            float y0 = m[4], y1 = m[5], y2 = m[6];
            float z0 = m[8], z1 = m[9], z2 = m[10];
            float nx = x0*x0 + x1*x1 + x2*x2;
            float ny = y0*y0 + y1*y1 + y2*y2;
            float nz = z0*z0 + z1*z1 + z2*z2;
            if (Math.abs(nx - 1f) > 2e-3f || Math.abs(ny - 1f) > 2e-3f || Math.abs(nz - 1f) > 2e-3f) {
                if (++violations <= 5) System.out.println("  VIOLATION basis non-unit case=" + i
                    + " norms=" + nx + "," + ny + "," + nz);
            }
            float dotXY = x0*y0 + x1*y1 + x2*y2;
            float dotXZ = x0*z0 + x1*z1 + x2*z2;
            float dotYZ = y0*z0 + y1*z1 + y2*z2;
            if (Math.abs(dotXY) > 2e-3f || Math.abs(dotXZ) > 2e-3f || Math.abs(dotYZ) > 2e-3f) {
                if (++violations <= 5) System.out.println("  VIOLATION basis non-orthogonal case=" + i);
            }
            float det = x0*(y1*z2 - y2*z1) - x1*(y0*z2 - y2*z0) + x2*(y0*z1 - y1*z0);
            if (det < 0.99f || det > 1.01f) {
                if (++violations <= 5) System.out.println("  VIOLATION determinant case=" + i + " det=" + det);
            }
            Vector3f tip = new Vector3f();
            VisionHandPose.tipOffset(joints, pose, tip);
            if (!Float.isFinite(tip.x) || !Float.isFinite(tip.y) || !Float.isFinite(tip.z)) {
                if (++violations <= 5) System.out.println("  VIOLATION non-finite tipOffset case=" + i);
            }
            Matrix4f fallback = new Matrix4f();
            VisionHandPose.gazeFallback(pose, (i & 1) == 0, fallback);
            fallback.get(m);
            for (float v : m) if (!Float.isFinite(v)) {
                if (++violations <= 5) System.out.println("  VIOLATION non-finite gazeFallback case=" + i);
                break;
            }
            if (violations > 10) break;
        }
        System.out.println("[m4-pose-fuzz-test] cases=" + CASES + " nonFiniteSeen=" + nonFiniteSeen
            + " violations=" + violations);
        System.out.println(violations == 0 ? "[m4-pose-fuzz-test] PASS" : "[m4-pose-fuzz-test] FAIL");
        if (violations != 0) System.exit(1);
    }

    /** Finite random float with occasional extreme/degenerate magnitudes. */
    private static float value(Random rnd) {
        switch (rnd.nextInt(8)) {
            case 0: return 0.0F;
            case 1: return 1.0E-30F * rnd.nextFloat();
            case 2: return 1.0E20F * rnd.nextFloat();
            case 3: return -1.0E20F * rnd.nextFloat();
            case 4: return rnd.nextFloat() - 0.5F;
            default: return (rnd.nextFloat() - 0.5F) * 200.0F;
        }
    }
}
