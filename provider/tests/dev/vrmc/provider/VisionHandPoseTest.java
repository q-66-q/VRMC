package dev.vrmc.provider;

import org.joml.Matrix4f;
import org.joml.Matrix4fc;
import org.joml.Vector3f;

/**
 * Host unit test for the M4-W1 hand-pose math {@link VisionHandPose} (JOML only, no game instance).
 *
 * <p>Proves the design §5.2 contract: translation = wrist position, {@code R * (0,0,-1) == aim},
 * orthonormal right-handed basis, the gaze/shoulder fallback for untracked hands (left/right
 * offsets), and graceful degenerate-joint fallback (never NaN). Run by provider/tests/run_tests.sh.
 */
public final class VisionHandPoseTest {
    private static final float EPS = 1.0E-4F;
    private static int failures;
    private static int checks;

    /** Joint indices used by VisionHandPose (same ARKit mapping as bridge/abi/vrmc_abi.h). */
    private static final int WRIST = 0;
    private static final int INDEX_META = 5;
    private static final int INDEX_TIP = 9;
    private static final int LITTLE_META = 20;

    public static void main(String[] args) {
        System.out.println("[m4-pose-test] VisionHandPose (JOML-only; host unit test)");
        try {
            jointBasisAimAndOrthonormality();
            bothHandsAndWristTranslation();
            gazeFallbackShoulderOffsets();
            degenerateJointsFallBackSafely();
            deterministicAndJitterStable();
        } catch (Throwable t) {
            t.printStackTrace();
            failures++;
        }
        System.out.println();
        System.out.printf("[m4-pose-test] %d checks, %d failed%n", checks, failures);
        System.out.println(failures == 0 ? "[m4-pose-test] PASS" : "[m4-pose-test] FAIL");
        System.exit(failures == 0 ? 0 : 1);
    }

    // ------------------------------------------------------------------------------------------
    private static void jointBasisAimAndOrthonormality() {
        section("joint basis: R*(0,0,-1)=aim, orthonormal, right-handed");
        Vector3f aim = new Vector3f(0.3F, 0.4F, -0.5F).normalize();
        Vector3f side = new Vector3f(0.8F, -0.2F, 0.3F);
        Vector3f wrist = new Vector3f(0.12F, 1.35F, -0.42F);
        float[] joints = handJoints(wrist, aim, side);
        Matrix4f pose = new Matrix4f();
        VisionHandPose.handPose(joints, 0.0F, 0.0F, 0.0F, 1.0F, wrist.x, wrist.y, wrist.z, pose);

        check("uses the joint-derived basis", VisionHandPose.hasUsableJointBasis(joints));
        checkClose("translation == wrist x", pose.m30(), wrist.x);
        checkClose("translation == wrist y", pose.m31(), wrist.y);
        checkClose("translation == wrist z", pose.m32(), wrist.z);
        Vector3f forward = pose.transformDirection(new Vector3f(0.0F, 0.0F, -1.0F));
        checkVec("R*(0,0,-1) == aim", forward, aim);

        Vector3f x = pose.getColumn(0, new Vector3f());
        Vector3f up = pose.getColumn(1, new Vector3f());
        Vector3f z = pose.getColumn(2, new Vector3f());
        checkClose("|x| == 1", x.length(), 1.0F);
        checkClose("|up| == 1", up.length(), 1.0F);
        checkClose("|z| == 1", z.length(), 1.0F);
        checkClose("x . up == 0", x.dot(up), 0.0F);
        checkClose("x . z == 0", x.dot(z), 0.0F);
        checkClose("up . z == 0", up.dot(z), 0.0F);
        Vector3f cross = new Vector3f(x).cross(up);
        checkVec("right-handed: x cross up == z", cross, z);
        checkClose("z == -aim (x)", z.x, -aim.x);
        checkClose("z == -aim (y)", z.y, -aim.y);
        checkClose("z == -aim (z)", z.z, -aim.z);
        checkClose("basis determinant +1", x.dot(new Vector3f(up).cross(z)), 1.0F);
    }

    // ------------------------------------------------------------------------------------------
    private static void bothHandsAndWristTranslation() {
        section("both hands: same aim convention, wrist translation only");
        Vector3f aim = new Vector3f(-0.2F, -0.1F, -0.97F).normalize();
        Vector3f side = new Vector3f(0.0F, 1.0F, 0.2F);
        for (int hand = 0; hand < 2; hand++) {
            boolean right = hand == 1;
            Vector3f wrist = new Vector3f(right ? 0.18F : -0.18F, 1.2F, -0.4F);
            float[] joints = handJoints(wrist, aim, side);
            Matrix4f pose = new Matrix4f();
            VisionHandPose.handPose(joints, 0.0F, 0.0F, 0.0F, 1.0F, wrist.x, wrist.y, wrist.z, pose);
            Vector3f forward = pose.transformDirection(new Vector3f(0.0F, 0.0F, -1.0F));
            checkVec((right ? "right" : "left") + " hand R*(0,0,-1) == aim", forward, aim);
            checkClose((right ? "right" : "left") + " hand translation x", pose.m30(), wrist.x);
        }
    }

    // ------------------------------------------------------------------------------------------
    private static void gazeFallbackShoulderOffsets() {
        section("gaze/shoulder fallback for untracked hands");
        Matrix4f hmd = new Matrix4f().rotationY(0.7F).setTranslation(0.10F, 1.60F, 0.20F);
        Vector3f hmdForward = hmd.transformDirection(new Vector3f(0.0F, 0.0F, -1.0F));

        Matrix4f right = new Matrix4f();
        VisionHandPose.gazeFallback(hmd, true, right);
        checkClose("RIGHT shoulder x = hmd.x - 0.2", right.m30(), 0.10F + VisionHandPose.SHOULDER_RIGHT_X);
        checkClose("RIGHT shoulder y = hmd.y - 0.2", right.m31(), 1.60F + VisionHandPose.SHOULDER_Y);
        checkClose("RIGHT shoulder z = hmd.z - 0.05", right.m32(), 0.20F + VisionHandPose.SHOULDER_Z);
        checkVec("RIGHT fallback keeps head orientation", right.transformDirection(new Vector3f(0.0F, 0.0F, -1.0F)),
            hmdForward);
        checkMatrix3("RIGHT fallback 3x3 == head 3x3", right, hmd);

        Matrix4f left = new Matrix4f();
        VisionHandPose.gazeFallback(hmd, false, left);
        checkClose("LEFT shoulder x = hmd.x + 0.2", left.m30(), 0.10F + VisionHandPose.SHOULDER_LEFT_X);
        checkClose("LEFT shoulder y = hmd.y - 0.2", left.m31(), 1.60F + VisionHandPose.SHOULDER_Y);
        checkClose("LEFT shoulder z = hmd.z - 0.05", left.m32(), 0.20F + VisionHandPose.SHOULDER_Z);
        checkVec("LEFT fallback keeps head orientation", left.transformDirection(new Vector3f(0.0F, 0.0F, -1.0F)),
            hmdForward);
        checkMatrix3("LEFT fallback 3x3 == head 3x3", left, hmd);
        checkClose("fallback offsets are distinct (no coincident hands)", left.m30() - right.m30(), 0.4F);
    }

    // ------------------------------------------------------------------------------------------
    private static void degenerateJointsFallBackSafely() {
        section("degenerate joints: quaternion fallback, then identity; never NaN");
        Vector3f wrist = new Vector3f(0.0F, 1.0F, -0.5F);
        float[] collapsed = new float[27 * 3];
        for (int i = 0; i < 27; i++) {
            collapsed[i * 3] = wrist.x;
            collapsed[i * 3 + 1] = wrist.y;
            collapsed[i * 3 + 2] = wrist.z;
        }
        check("collapsed joints are not a usable basis", !VisionHandPose.hasUsableJointBasis(collapsed));

        Matrix4f pose = new Matrix4f();
        VisionHandPose.handPose(collapsed, 0.0F, 0.0F, 0.0F, 1.0F, wrist.x, wrist.y, wrist.z, pose);
        check("identity quat fallback -> identity rotation", matrixClose(pose, new Matrix4f().setTranslation(wrist), EPS));
        check("fallback keeps the wrist translation", Math.abs(pose.m31() - wrist.y) < EPS);

        // 90 deg about +Y: (0,0,-1) -> (-1,0,0)
        float s = (float) Math.sin(Math.PI / 4.0);
        float c = (float) Math.cos(Math.PI / 4.0);
        Matrix4f quatPose = new Matrix4f();
        VisionHandPose.handPose(collapsed, 0.0F, s, 0.0F, c, wrist.x, wrist.y, wrist.z, quatPose);
        Vector3f rotated = quatPose.transformDirection(new Vector3f(0.0F, 0.0F, -1.0F));
        checkVec("wrist-quaternion fallback rotates the aim", rotated, new Vector3f(-1.0F, 0.0F, 0.0F));
        check("quaternion fallback is finite", allFinite(quatPose));

        // invalid (zero) quaternion -> identity, still finite
        Matrix4f zeroPose = new Matrix4f();
        VisionHandPose.handPose(collapsed, 0.0F, 0.0F, 0.0F, 0.0F, wrist.x, wrist.y, wrist.z, zeroPose);
        check("zero quaternion fallback is identity", matrixClose(zeroPose, new Matrix4f().setTranslation(wrist), EPS));

        // side parallel to aim -> degenerate up vector -> fallback (not NaN)
        float[] parallel = handJoints(wrist, new Vector3f(0.0F, 0.0F, -1.0F), new Vector3f(0.0F, 0.0F, -1.0F));
        Matrix4f parallelPose = new Matrix4f();
        VisionHandPose.handPose(parallel, 0.0F, 0.0F, 0.0F, 1.0F, wrist.x, wrist.y, wrist.z, parallelPose);
        check("parallel side/aim falls back to identity (finite)", allFinite(parallelPose));
        check("parallel side/aim does not use the joint basis", !VisionHandPose.hasUsableJointBasis(parallel));
    }

    // ------------------------------------------------------------------------------------------
    private static void deterministicAndJitterStable() {
        section("determinism + orthonormality under joint jitter");
        Vector3f aim = new Vector3f(0.1F, 0.7F, -0.7F).normalize();
        Vector3f side = new Vector3f(0.9F, 0.1F, 0.4F);
        Vector3f wrist = new Vector3f(0.2F, 1.3F, -0.3F);
        float[] joints = handJoints(wrist, aim, side);
        // deterministic jitter on every joint that must not change the derived aim
        for (int i = 0; i < 27; i++) {
            joints[i * 3] += 0.002F * (float) Math.sin(i);
            joints[i * 3 + 1] += 0.002F * (float) Math.cos(i);
            joints[i * 3 + 2] += 0.001F * (float) Math.sin(i * 0.5);
        }
        Matrix4f first = new Matrix4f();
        Matrix4f second = new Matrix4f();
        VisionHandPose.handPose(joints, 0.0F, 0.0F, 0.0F, 1.0F, wrist.x, wrist.y, wrist.z, first);
        VisionHandPose.handPose(joints, 0.0F, 0.0F, 0.0F, 1.0F, wrist.x, wrist.y, wrist.z, second);
        check("same input -> same matrix", matrixClose(first, second, 0.0F));
        Vector3f x = first.getColumn(0, new Vector3f());
        Vector3f up = first.getColumn(1, new Vector3f());
        Vector3f z = first.getColumn(2, new Vector3f());
        checkClose("jittered |x| == 1", x.length(), 1.0F);
        checkClose("jittered |up| == 1", up.length(), 1.0F);
        checkClose("jittered |z| == 1", z.length(), 1.0F);
        checkClose("jittered x . up == 0", x.dot(up), 0.0F);
        checkClose("jittered x . z == 0", x.dot(z), 0.0F);
        checkClose("jittered up . z == 0", up.dot(z), 0.0F);
        check("jittered pose is finite", allFinite(first));
    }

    // ------------------------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------------------------

    /** Build 27 device-space joints: wrist at {@code wrist}, index tip along {@code aim}, palm side along {@code side}. */
    private static float[] handJoints(Vector3f wrist, Vector3f aim, Vector3f side) {
        float[] joints = new float[27 * 3];
        for (int i = 0; i < 27; i++) {
            joints[i * 3] = wrist.x;
            joints[i * 3 + 1] = wrist.y;
            joints[i * 3 + 2] = wrist.z;
        }
        Vector3f tip = new Vector3f(aim).mul(0.10F).add(wrist);
        setJoint(joints, INDEX_TIP, tip);
        Vector3f indexMeta = new Vector3f(side).mul(0.02F).add(wrist);
        Vector3f littleMeta = new Vector3f(side).mul(-0.02F).add(wrist);
        setJoint(joints, INDEX_META, indexMeta);
        setJoint(joints, LITTLE_META, littleMeta);
        return joints;
    }

    private static void setJoint(float[] joints, int joint, Vector3f value) {
        joints[joint * 3] = value.x;
        joints[joint * 3 + 1] = value.y;
        joints[joint * 3 + 2] = value.z;
    }

    private static boolean allFinite(Matrix4f m) {
        float[] values = new float[16];
        m.get(values);
        for (float v : values) {
            if (!Float.isFinite(v)) return false;
        }
        return true;
    }

    private static boolean matrixClose(Matrix4f actual, Matrix4fc expected, float epsilon) {
        float[] a = new float[16];
        float[] b = new float[16];
        actual.get(a);
        expected.get(b);
        for (int i = 0; i < 16; i++) {
            if (Math.abs(a[i] - b[i]) > epsilon) return false;
        }
        return true;
    }

    private static void checkMatrix3(String label, Matrix4f actual, Matrix4f expected) {
        float[] a = new float[16];
        float[] b = new float[16];
        actual.get(a);
        expected.get(b);
        boolean ok = true;
        // JOML stores column-major: element (row r, column c) is index c*4 + r
        for (int c = 0; c < 3 && ok; c++) {
            for (int r = 0; r < 3 && ok; r++) {
                if (Math.abs(a[c * 4 + r] - b[c * 4 + r]) > EPS) ok = false;
            }
        }
        check(label, ok);
    }

    private static void checkVec(String label, Vector3f actual, Vector3f expected) {
        checkClose(label + " (x)", actual.x, expected.x);
        checkClose(label + " (y)", actual.y, expected.y);
        checkClose(label + " (z)", actual.z, expected.z);
    }

    private static void section(String name) {
        System.out.println();
        System.out.println("== " + name + " ==");
    }

    private static void check(String label, boolean ok) {
        checks++;
        if (!ok) failures++;
        System.out.printf("  %-78s %s%n", label, ok ? "ok" : "FAIL");
    }

    private static void checkClose(String label, float actual, float expected) {
        check(label + " (actual=" + actual + " expected=" + expected + ")",
            Float.isFinite(actual) && Math.abs(actual - expected) <= EPS);
    }
}
