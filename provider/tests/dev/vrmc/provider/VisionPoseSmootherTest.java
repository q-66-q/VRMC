package dev.vrmc.provider;

import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;

/** Host test for the M4-W2 One-Euro hand-pose smoother (pure Java, JOML only). */
public final class VisionPoseSmootherTest {
    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) {
            failures++;
            System.out.println("  FAIL " + name + " " + detail);
        }
    }

    private static Matrix4f pose(float x, float y, float z, float yawDeg) {
        return new Matrix4f()
            .rotation(new Quaternionf().rotateY((float) Math.toRadians(yawDeg)))
            .setTranslation(x, y, z);
    }

    private static float posDelta(Matrix4f a, Matrix4f b) {
        return new Vector3f(a.m30(), a.m31(), a.m32()).distance(new Vector3f(b.m30(), b.m31(), b.m32()));
    }

    public static void main(String[] args) {
        // ---- disabled: exact passthrough ----
        VisionPoseSmoother.Config off = new VisionPoseSmoother.Config();
        off.enabled = false;
        VisionPoseSmoother pass = new VisionPoseSmoother(off);
        Matrix4f raw = pose(0.2F, 1.1F, -0.4F, 15.0F);
        Matrix4f copy = new Matrix4f(raw);
        pass.apply(raw, 1_000L);
        check("disabled passthrough", raw.equals(copy, 1.0E-6F), "");

        // ---- step response: first frame moves less than raw, then converges without runaway ----
        VisionPoseSmoother.Config cfg = new VisionPoseSmoother.Config();
        cfg.enabled = true;
        VisionPoseSmoother s = new VisionPoseSmoother(cfg);
        long ns = 1_000_000_000L;
        Matrix4f start = pose(0.0F, 1.2F, -0.3F, 0.0F);
        s.apply(start, ns);
        Matrix4f first = pose(0.30F, 1.2F, -0.3F, 0.0F);
        s.apply(first, ns + 11_111_111L);
        float firstMove = Math.abs(first.m30());
        check("first frame damped", firstMove > 0.0F && firstMove < 0.30F, "firstMove=" + firstMove);
        check("no NaN", Float.isFinite(first.m30()) && Float.isFinite(first.m31()) && Float.isFinite(first.m32()), "");

        // Hold the raw target for 60 frames at 90 Hz; the filtered pose must converge close to it.
        Matrix4f out = new Matrix4f();
        for (int i = 0; i < 60; i++) {
            out = pose(0.30F, 1.2F, -0.3F, 0.0F);
            s.apply(out, ns + (long) (11_111_111L * (i + 2)));
        }
        check("converges to target", posDelta(out, pose(0.30F, 1.2F, -0.3F, 0.0F)) < 0.01F,
            "delta=" + posDelta(out, pose(0.30F, 1.2F, -0.3F, 0.0F)));

        // ---- fast motion is more responsive than slow motion ----
        VisionPoseSmoother fast = new VisionPoseSmoother(cfg);
        Matrix4f p0 = pose(0.0F, 0.0F, 0.0F, 0.0F);
        fast.apply(p0, ns);
        // A large jump on the second frame gives a high filtered velocity -> higher cutoff -> larger alpha.
        Matrix4f jump = pose(1.0F, 0.0F, 0.0F, 0.0F);
        fast.apply(jump, ns + 11_111_111L);
        float fastMove = Math.abs(jump.m30());

        VisionPoseSmoother slow = new VisionPoseSmoother(cfg);
        slow.apply(pose(0.0F, 0.0F, 0.0F, 0.0F), ns);
        Matrix4f tiny = pose(0.01F, 0.0F, 0.0F, 0.0F);
        slow.apply(tiny, ns + 11_111_111L);
        float slowFraction = Math.abs(tiny.m30()) / 0.01F;
        check("fast motion more responsive", fastMove / 1.0F > slowFraction,
            "fastFraction=" + (fastMove / 1.0F) + " slowFraction=" + slowFraction);

        // ---- rotation: step is damped and converges ----
        VisionPoseSmoother rot = new VisionPoseSmoother(cfg);
        rot.apply(pose(0.0F, 0.0F, 0.0F, 0.0F), ns);
        Matrix4f yaw = pose(0.0F, 0.0F, 0.0F, 90.0F);
        rot.apply(yaw, ns + 11_111_111L);
        Quaternionf q = yaw.getNormalizedRotation(new Quaternionf());
        float angle = 2.0F * (float) Math.acos(Math.min(1.0F, Math.abs(q.w)));
        check("rotation damped", angle > 0.0F && angle < Math.toRadians(90.0) * 0.99F,
            "angleDeg=" + Math.toDegrees(angle));
        Matrix4f rotOut = new Matrix4f();
        for (int i = 0; i < 60; i++) {
            rotOut = pose(0.0F, 0.0F, 0.0F, 90.0F);
            rot.apply(rotOut, ns + (long) (11_111_111L * (i + 2)));
        }
        Quaternionf finalQ = rotOut.getNormalizedRotation(new Quaternionf());
        float finalAngle = 2.0F * (float) Math.acos(Math.min(1.0F, Math.abs(finalQ.w)));
        // Convergence means the filtered yaw approaches the raw 90 degrees (not zero!).
        check("rotation converges", finalAngle > Math.toRadians(88.0), "finalAngleDeg=" + Math.toDegrees(finalAngle));
        check("rotation first-frame damped below 89 deg", angle < Math.toRadians(89.0), "firstFrameAngleDeg=" + Math.toDegrees(angle));

        // ---- reset drops history (tracking loss must not lag a teleporting hand) ----
        Matrix4f resetRaw = pose(2.0F, 0.0F, 0.0F, 0.0F);
        rot.apply(resetRaw, ns + 10_000_000_000L);
        float beforeReset = Math.abs(resetRaw.m30() - 2.0F);
        check("teleport rejected before reset", beforeReset > 0.0F, "");
        rot.reset();
        Matrix4f afterReset = pose(2.0F, 0.0F, 0.0F, 0.0F);
        rot.apply(afterReset, ns + 10_100_000_000L);
        check("reset passes new pose", Math.abs(afterReset.m30() - 2.0F) < 1.0E-5F,
            "x=" + afterReset.m30());

        // ---- missing/degenerate timestamps use the fallback dt and stay finite ----
        VisionPoseSmoother weird = new VisionPoseSmoother(cfg);
        Matrix4f w = pose(0.1F, 0.1F, 0.1F, 0.0F);
        weird.apply(w, 0L);
        weird.apply(w, 0L);
        weird.apply(w, -5L);
        check("weird timestamps finite", Float.isFinite(w.m30()) && Float.isFinite(w.m31()) && Float.isFinite(w.m32()), "");

        System.out.println("[m4-smoother-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m4-smoother-test] PASS" : "[m4-smoother-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
