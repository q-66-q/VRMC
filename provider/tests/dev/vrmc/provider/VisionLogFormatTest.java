package dev.vrmc.provider;

/** Regression test for the startup printf IllegalFormatConversionException (EV-0209). */
public final class VisionLogFormatTest {
    private static int checks;
    private static int failures;
    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) {
        VisionInput in = new VisionInput();
        String line = null;
        try {
            line = VisionLogFormat.locomotionLine(in, 0.18F, 0.05F, 3.0F, 3.0F, 0.1F,
                120_000_000L);
        } catch (Throwable t) {
            check("locomotion line formats without exception", false, String.valueOf(t));
        }
        check("locomotion line produced", line != null);
        if (line != null) {
            check("contains hotbar", line.contains("hotbarRange=0.18"), line);
            check("contains rotate pulse", line.contains("rotatePulseMs=120"), line);
            check("contains middle thresholds", line.contains("middleOn=0.035")
                && line.contains("middleOff=0.050"), line);
            check("contains swipe cooldown", line.contains("swipeCoolMs=350"), line);
        }
        // Extreme/non-finite sizes must not change the argument types.
        try {
            VisionLogFormat.locomotionLine(new VisionInput(java.util.Map.of()), 0F, -1F, 1F, 1F, 0F, 0L);
            check("edge values format", true);
        } catch (Throwable t) {
            check("edge values format", false, String.valueOf(t));
        }
        System.out.println("[m4-log-format-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m4-log-format-test] PASS" : "[m4-log-format-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
