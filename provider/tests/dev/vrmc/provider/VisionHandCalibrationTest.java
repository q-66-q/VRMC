package dev.vrmc.provider;

/** Host test for the M4-W5 guided calibration phases/suggestions/report. */
public final class VisionHandCalibrationTest {
    private static int checks;
    private static int failures;
    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) {
        long t0 = 1_000_000_000_000L;
        VisionHandCalibration c = new VisionHandCalibration();
        check("not active before begin", !c.active(t0));
        c.begin(t0);
        check("open phase", c.phaseAt(t0) == 0);
        check("fist phase", c.phaseAt(t0 + VisionHandCalibration.OPEN_MS * 1_000_000L + 1) == 1);
        check("pinch phase", c.phaseAt(t0 + (VisionHandCalibration.OPEN_MS + VisionHandCalibration.FIST_MS) * 1_000_000L + 1) == 2);
        check("done phase", c.phaseAt(t0 + VisionHandCalibration.TOTAL_MS * 1_000_000L + 1) == VisionHandCalibration.PHASE_DONE);
        check("not enough data", !c.hasEnoughData());
        // Open: pinch open ~0.09, fist ratio ~1.05; fists: ratio ~1.9; pinch closed ~0.015.
        for (int i = 0; i < 20; i++) c.record(0, 0.09F, 1.05F);
        for (int i = 0; i < 20; i++) c.record(1, 0.08F, 1.90F);
        for (int i = 0; i < 20; i++) c.record(2, 0.015F, 1.70F);
        check("enough data", c.hasEnoughData());
        check("pinch on separates", c.suggestedPinchOn() > 0.015F && c.suggestedPinchOn() < 0.09F,
            String.valueOf(c.suggestedPinchOn()));
        check("pinch off > on", c.suggestedPinchOff() > c.suggestedPinchOn() + 0.007F);
        check("fist on separates", c.suggestedFistOn() > 1.05F && c.suggestedFistOn() < 1.90F,
            String.valueOf(c.suggestedFistOn()));
        check("fist off > on", c.suggestedFistOff() > c.suggestedFistOn() + 0.049F);
        String report = c.report(t0 + VisionHandCalibration.TOTAL_MS * 1_000_000L);
        check("report valid", report.contains("valid=yes"), report);
        check("report contains suggested keys", report.contains("pinch.on=") && report.contains("fist.on="));
        check("NaN samples ignored", ignored());
        check("prompts exist", VisionHandCalibration.promptFor(0).contains("OPEN")
            && VisionHandCalibration.promptFor(1).contains("FIST")
            && VisionHandCalibration.promptFor(2).contains("PINCH"));
        System.out.println("[m4-hand-calibration-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m4-hand-calibration-test] PASS" : "[m4-hand-calibration-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    private static boolean ignored() {
        VisionHandCalibration c = new VisionHandCalibration();
        c.begin(0);
        c.record(0, Float.NaN, Float.NaN);
        c.record(0, Float.POSITIVE_INFINITY, 1.0F);
        c.record(1, 0.09F, Float.NaN);
        return !c.hasEnoughData();
    }
}
