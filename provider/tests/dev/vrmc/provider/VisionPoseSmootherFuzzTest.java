package dev.vrmc.provider;

import java.util.Random;
import org.joml.Matrix4f;
import org.joml.Quaternionf;

/**
 * Host fuzz for {@link VisionPoseSmoother}: random finite poses/timestamps (including huge translations,
 * zero/duplicate/regressing timestamps) must always remain finite and preserve an orthonormal rotation.
 */
public final class VisionPoseSmootherFuzzTest {
    private static final int CASES = 100_000;

    public static void main(String[] args) {
        Random rnd = new Random(0x51EADBEEFL);
        VisionPoseSmoother smoother = new VisionPoseSmoother(new VisionPoseSmoother.Config());
        Matrix4f pose = new Matrix4f();
        float[] m = new float[16];
        long timestamp = 0L;
        int violations = 0;
        for (int i = 0; i < CASES; i++) {
            Quaternionf q = new Quaternionf(rnd.nextFloat() - 0.5F, rnd.nextFloat() - 0.5F,
                rnd.nextFloat() - 0.5F, rnd.nextFloat() - 0.5F);
            if (q.lengthSquared() < 1.0E-6F) q.set(0.0F, 0.0F, 0.0F, 1.0F);
            q.normalize();
            float scale = (i % 10000 == 0) ? 1.0E20F : 1.0E4F;
            pose.rotation(q).setTranslation((rnd.nextFloat() - 0.5F) * scale,
                (rnd.nextFloat() - 0.5F) * scale, (rnd.nextFloat() - 0.5F) * scale);
            // Mostly forward timestamps, occasionally zero/duplicate/regressing.
            if (i % 97 == 0) timestamp += 0;
            else if (i % 211 == 0) timestamp = 0;
            else timestamp += 1_000_000L * (1 + rnd.nextInt(30));
            if (i % 5000 == 0) smoother.reset();
            smoother.apply(pose, timestamp);
            pose.get(m);
            boolean finite = true;
            for (float v : m) if (!Float.isFinite(v)) { finite = false; break; }
            if (!finite) {
                if (++violations <= 5) System.out.println("  VIOLATION non-finite smoothed pose case=" + i);
                continue;
            }
            float nx = m[0]*m[0] + m[1]*m[1] + m[2]*m[2];
            float ny = m[4]*m[4] + m[5]*m[5] + m[6]*m[6];
            float nz = m[8]*m[8] + m[9]*m[9] + m[10]*m[10];
            if (Math.abs(nx - 1f) > 2e-3f || Math.abs(ny - 1f) > 2e-3f || Math.abs(nz - 1f) > 2e-3f) {
                if (++violations <= 5) System.out.println("  VIOLATION smoothed rotation non-unit case=" + i);
            }
            if (violations > 10) break;
        }
        smoother.reset();
        System.out.println("[m4-smoother-fuzz-test] cases=" + CASES + " violations=" + violations);
        System.out.println(violations == 0 ? "[m4-smoother-fuzz-test] PASS" : "[m4-smoother-fuzz-test] FAIL");
        if (violations != 0) System.exit(1);
    }
}
