package dev.vrmc.provider;

/**
 * Host test for the M8 target-cadence knob and the frame-budget policy helper (no game/device).
 *
 *   parseTargetHz:       "auto"/"" -> 0 (follow measured display), 60..120 -> Hz, else -1.
 *   targetIntervalMsFor: override -> 1000/override; no override -> measured display interval; and the
 *                        same fallback the provider uses when the measured cadence is not finite.
 */
public final class VisionTargetCadenceTest {
    private static int checks = 0;
    private static int failures = 0;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    private static boolean close(double a, double b, double eps) {
        return Math.abs(a - b) <= eps;
    }

    public static void main(String[] args) {
        // ---- parseTargetHz ----------------------------------------------------------------
        check("null -> auto", VisionRenderSettings.parseTargetHz(null) == 0);
        check("empty -> auto", VisionRenderSettings.parseTargetHz("") == 0);
        check("blank -> auto", VisionRenderSettings.parseTargetHz("   ") == 0);
        check("auto -> auto", VisionRenderSettings.parseTargetHz("auto") == 0);
        check("AUTO -> auto", VisionRenderSettings.parseTargetHz("AUTO") == 0);
        check("90 -> 90", VisionRenderSettings.parseTargetHz("90") == 90);
        check("96 -> 96", VisionRenderSettings.parseTargetHz("96") == 96);
        check("100 -> 100", VisionRenderSettings.parseTargetHz("100") == 100);
        check("120 -> 120", VisionRenderSettings.parseTargetHz("120") == 120);
        check("whitespace 120 -> 120", VisionRenderSettings.parseTargetHz(" 120 ") == 120);
        check("59 rejected", VisionRenderSettings.parseTargetHz("59") == -1);
        check("121 rejected", VisionRenderSettings.parseTargetHz("121") == -1);
        check("0 rejected", VisionRenderSettings.parseTargetHz("0") == -1);
        check("text rejected", VisionRenderSettings.parseTargetHz("fast") == -1);
        check("float rejected", VisionRenderSettings.parseTargetHz("120.0") == -1);
        check("negative rejected", VisionRenderSettings.parseTargetHz("-120") == -1);

        // ---- targetIntervalMsFor ----------------------------------------------------------
        check("override 120 -> 8.333 ms", close(VisionRenderSettings.targetIntervalMsFor(90.0f, 120), 8.333, 0.002));
        check("override 96 -> 10.417 ms", close(VisionRenderSettings.targetIntervalMsFor(120.0f, 96), 10.417, 0.002));
        check("override 60 -> 16.667 ms", close(VisionRenderSettings.targetIntervalMsFor(120.0f, 60), 16.667, 0.002));
        check("auto uses display 90 -> 11.111 ms", close(VisionRenderSettings.targetIntervalMsFor(90.0f, 0), 11.111, 0.002));
        check("auto uses display 120 -> 8.333 ms", close(VisionRenderSettings.targetIntervalMsFor(120.0f, 0), 8.333, 0.002));
        check("auto NaN display -> fallback", close(VisionRenderSettings.targetIntervalMsFor(Float.NaN, 0),
            1000.0 / 90.0, 0.002));
        check("invalid override -1 -> measured display", close(VisionRenderSettings.targetIntervalMsFor(100.0f, -1), 10.0, 0.002));
        check("invalid override 240 -> measured display", close(VisionRenderSettings.targetIntervalMsFor(100.0f, 240), 10.0, 0.002));

        // ---- budget boundary consistency with nextAutoScale ------------------------------
        // At 120 Hz the 8.333 ms budget means a 9 ms p50 is already over budget; at 90 Hz it is fine.
        double budget120 = VisionRenderSettings.targetIntervalMsFor(90.0f, 120);
        double budget90 = VisionRenderSettings.targetIntervalMsFor(90.0f, 0);
        check("9 ms over 120 Hz budget", 9.0 > budget120 * 1.05);
        check("9 ms inside 90 Hz budget", 9.0 < budget90 * 0.85);
        check("120 Hz override more strict", budget120 < budget90);

        System.out.println("[m8-target-test] " + checks + " checks, " + failures + " failed");
        if (failures > 0) { System.out.println("[m8-target-test] FAIL"); System.exit(1); }
        System.out.println("[m8-target-test] PASS");
    }
}
