package dev.vrmc.provider;

import java.util.Random;
import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector2f;
import org.joml.Vector3f;

/** Host fuzz for the gaze/tile→GUI math: invalid tiles/scales/rays must return null or finite in-range values. */
public final class VisionGazeMathFuzzTest {
    private static final int CASES = 500_000;

    public static void main(String[] args) {
        Random rnd = new Random(0x6A2E5EEDL);
        int violations = 0;
        for (int i = 0; i < CASES; i++) {
            long tile = rnd.nextInt(20) == 0 ? rnd.nextLong() : rnd.nextInt(5000) - 100;
            int gw = rnd.nextInt(20) == 0 ? rnd.nextInt(3) - 1 : 1 + rnd.nextInt(40);
            int gh = rnd.nextInt(20) == 0 ? rnd.nextInt(3) - 1 : 1 + rnd.nextInt(40);
            Vector2f ndc;
            try {
                ndc = VisionGazeMath.tileToNdc(tile, gw, gh);
            } catch (Throwable t) {
                if (++violations <= 5) System.out.println("  VIOLATION tileToNdc threw case=" + i + ": " + t);
                continue;
            }
            if (ndc != null) {
                if (!finite(ndc) || ndc.x < -1.0001F || ndc.x > 1.0001F
                    || ndc.y < -1.0001F || ndc.y > 1.0001F) {
                    if (++violations <= 5) System.out.println("  VIOLATION tileToNdc range case=" + i);
                }
                float l = -rand(rnd), r = rand(rnd), u = rand(rnd), d = -rand(rnd);
                Vector3f ray = VisionGazeMath.eyeRay(l, r, u, d, ndc);
                if (!finite(ray) || Math.abs(ray.length() - 1.0F) > 2e-3F) {
                    if (++violations <= 5) System.out.println("  VIOLATION eyeRay case=" + i);
                }
                Quaternionf q = new Quaternionf(rnd.nextFloat() - 0.5F, rnd.nextFloat() - 0.5F,
                    rnd.nextFloat() - 0.5F, rnd.nextFloat() - 0.5F);
                if (q.lengthSquared() < 1e-6F) q.set(0, 0, 0, 1);
                q.normalize();
                Matrix4f rot = new Matrix4f().rotation(q);
                Vector3f origin = new Vector3f(rand(rnd) * 10, rand(rnd) * 10, rand(rnd) * 10);
                float scale = rnd.nextInt(20) == 0 ? 0.0F : 0.05F + rnd.nextFloat() * 5.0F;
                float aspect = rnd.nextInt(20) == 0 ? 0.0F : 0.2F + rnd.nextFloat() * 3.0F;
                Vector2f uv;
                try {
                    uv = VisionGazeMath.intersectGuiPlane(origin, ray,
                        new Vector3f(rand(rnd), rand(rnd), rand(rnd)), rot, scale, aspect);
                } catch (Throwable t) {
                    if (++violations <= 5) System.out.println("  VIOLATION intersect threw case=" + i + ": " + t);
                    continue;
                }
                if (uv != null && (!finite(uv) || uv.x < 0F || uv.x > 1F || uv.y < 0F || uv.y > 1F)) {
                    if (++violations <= 5) System.out.println("  VIOLATION intersect range case=" + i);
                }
            }
            if (violations > 10) break;
        }
        System.out.println("[m4-gaze-fuzz-test] cases=" + CASES + " violations=" + violations);
        System.out.println(violations == 0 ? "[m4-gaze-fuzz-test] PASS" : "[m4-gaze-fuzz-test] FAIL");
        if (violations != 0) System.exit(1);
    }

    private static float rand(Random rnd) {
        return (rnd.nextFloat() - 0.5F) * 10.0F;
    }

    private static boolean finite(Vector2f v) { return Float.isFinite(v.x) && Float.isFinite(v.y); }
    private static boolean finite(Vector3f v) {
        return Float.isFinite(v.x) && Float.isFinite(v.y) && Float.isFinite(v.z);
    }
}
