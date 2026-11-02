import org.joml.Matrix4f;
import org.joml.Vector4f;

/**
 * Offline check of the macstream-style display-view plumbing: the provider builds an asymmetric
 * off-axis frustum from the headset tangents; verify the near-plane corners land exactly on the NDC
 * corners and that the NDC centre round-trips (same projection used by the compositor's flat mapping).
 */
public final class DisplayViewsTest {
    private static int failures = 0;

    private static void check(String name, float actual, float expected, float eps) {
        boolean ok = Math.abs(actual - expected) <= eps;
        System.out.printf("  %-28s actual=% .6f expected=% .6f %s%n", name, actual, expected, ok ? "ok" : "FAIL");
        if (!ok) failures++;
    }

    private static Vector4f project(Matrix4f p, float x, float y, float z) {
        Vector4f v = new Vector4f(x, y, z, 1.0f).mul(p);
        return new Vector4f(v.x / v.w, v.y / v.w, v.z / v.w, 1.0f);
    }

    private static void eyeCase(String label, float left, float right, float up, float down) {
        final float near = 0.05f, far = 1000.0f;
        System.out.println("case " + label + " tangents l/r/u/d=" + left + "/" + right + "/" + up + "/" + down);
        Matrix4f p = new Matrix4f().frustum(left * near, right * near, down * near, up * near,
            near, far, true);
        Vector4f c0 = project(p, left * near, down * near, -near);
        Vector4f c1 = project(p, right * near, up * near, -near);
        check("bottom-left ndc.x", c0.x, -1.0f, 1e-5f);
        check("bottom-left ndc.y", c0.y, -1.0f, 1e-5f);
        check("top-right ndc.x", c1.x, 1.0f, 1e-5f);
        check("top-right ndc.y", c1.y, 1.0f, 1e-5f);
        // Straight-ahead (eye-space 0,0,-near) maps to the drawable's optical axis (NDC 0 only for a
        // symmetric frustum). For a lopsided headset frustum the expected NDC offset is
        // -(right+left)/(right-left), -(top+bottom)/(top-bottom). This is exactly why the provider
        // must render the display frustum instead of a symmetric 110 deg one.
        Vector4f centre = project(p, 0.0f, 0.0f, -near);
        check("centre ndc.x", centre.x, -(right + left) / (right - left), 1e-5f);
        check("centre ndc.y", centre.y, -(up + down) / (up - down), 1e-5f);
    }

    public static void main(String[] args) {
        System.out.println("[display-views-test] provider frustum from headset tangents (macstream math)");
        // Left/right display views from the EV-0086 device log (CompositorServices tangents).
        eyeCase("display-left", -1.732f, 1.000f, 1.000f, -1.192f);
        eyeCase("display-right", -1.000f, 1.732f, 1.000f, -1.192f);
        // Symmetric fallback (previous provider FOV) for comparison.
        eyeCase("symmetric-110", -1.428f, 1.428f, 1.428f, -1.428f);
        System.out.println(failures == 0 ? "[display-views-test] PASS" : "[display-views-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
