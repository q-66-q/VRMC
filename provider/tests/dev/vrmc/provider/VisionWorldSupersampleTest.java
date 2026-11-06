package dev.vrmc.provider;

/**
 * Host test for the M8 world-supersample knob (pure parsing/math; no game/device).
 *
 * Vivecraft's renderScaleFactor sizes the world render target at eye x sqrt(factor) per axis and
 * resolves it down to the eye target (SSAA). The knob is off by default (1.0) and bounded to 2.0 so a
 * typo cannot allocate an absurd render target.
 */
public final class VisionWorldSupersampleTest {
    private static int checks = 0;
    private static int failures = 0;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }
    private static boolean close(double a, double b) { return Math.abs(a - b) <= 1.0e-4; }

    public static void main(String[] args) {
        // ---- parse ------------------------------------------------------------------------
        check("null -> off", close(VisionWorldSupersample.parse(null), 1.0f));
        check("empty -> off", close(VisionWorldSupersample.parse(""), 1.0f));
        check("blank -> off", close(VisionWorldSupersample.parse("   "), 1.0f));
        check("off -> off", close(VisionWorldSupersample.parse("off"), 1.0f));
        check("OFF -> off", close(VisionWorldSupersample.parse("OFF"), 1.0f));
        check("1 -> off", close(VisionWorldSupersample.parse("1"), 1.0f));
        check("1.0 -> off", close(VisionWorldSupersample.parse("1.0"), 1.0f));
        check("1.44 -> 1.44", close(VisionWorldSupersample.parse("1.44"), 1.44f));
        check("2 -> 2", close(VisionWorldSupersample.parse("2"), 2.0f));
        check("2.0 -> 2", close(VisionWorldSupersample.parse("2.0"), 2.0f));
        check("whitespace 1.21 -> 1.21", close(VisionWorldSupersample.parse(" 1.21 "), 1.21f));
        check("0.9 rejected", VisionWorldSupersample.parse("0.9") == -1.0f);
        check("2.1 rejected", VisionWorldSupersample.parse("2.1") == -1.0f);
        check("text rejected", VisionWorldSupersample.parse("high") == -1.0f);
        check("negative rejected", VisionWorldSupersample.parse("-1") == -1.0f);
        check("NaN rejected", VisionWorldSupersample.parse("NaN") == -1.0f);

        // ---- axis scale -------------------------------------------------------------------
        check("axis 1.0 -> 1.0", close(VisionWorldSupersample.axisScale(1.0f), 1.0));
        check("axis 1.44 -> 1.2", close(VisionWorldSupersample.axisScale(1.44f), 1.2));
        check("axis 2.0 -> sqrt2", close(VisionWorldSupersample.axisScale(2.0f), Math.sqrt(2.0)));
        check("axis clamps low", close(VisionWorldSupersample.axisScale(0.0f), 1.0));
        check("axis clamps high", close(VisionWorldSupersample.axisScale(3.0f), Math.sqrt(2.0)));

        // ---- dimensions (eye 1832x1600 is the M8 device start target) ---------------------
        check("1024 at 1.0", VisionWorldSupersample.scaledDimension(1024, 1.0f) == 1024);
        check("1832 at 1.0", VisionWorldSupersample.scaledDimension(1832, 1.0f) == 1832);
        check("1832 at 1.44 -> 2199", VisionWorldSupersample.scaledDimension(1832, 1.44f) == 2199);
        // ceil() matches VRRenderer's (int)Math.ceil(eye * renderScale); 1600*sqrt(1.44) lands a hair
        // above 1920 in float/double arithmetic, so the real world target is 1921, not 1920.
        check("1600 at 1.44 -> 1921", VisionWorldSupersample.scaledDimension(1600, 1.44f) == 1921);
        check("1600 at 2.0 -> 2263", VisionWorldSupersample.scaledDimension(1600, 2.0f) == (int) Math.ceil(1600 * Math.sqrt(2.0)));
        check("zero dimension", VisionWorldSupersample.scaledDimension(0, 1.44f) == 0);
        check("negative dimension", VisionWorldSupersample.scaledDimension(-8, 1.44f) == 0);

        System.out.println("[m8-supersample-test] " + checks + " checks, " + failures + " failed");
        if (failures > 0) { System.out.println("[m8-supersample-test] FAIL"); System.exit(1); }
        System.out.println("[m8-supersample-test] PASS");
    }
}
