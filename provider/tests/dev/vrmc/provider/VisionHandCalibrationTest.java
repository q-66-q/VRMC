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
        // Real-hand orientation (VisionInput.fistRatio: lower = more curled): open hands ~1.90,
        // fists ~1.05; pinch open ~0.09 m, pinch closed ~0.015 m.
        for (int i = 0; i < 20; i++) c.record(0, 0.09F, 1.90F);
        for (int i = 0; i < 20; i++) c.record(1, 0.08F, 1.05F);
        for (int i = 0; i < 20; i++) c.record(2, 0.015F, 1.70F);
        check("enough data", c.hasEnoughData());
        check("pinch on separates", c.suggestedPinchOn() > 0.015F && c.suggestedPinchOn() < 0.09F,
            String.valueOf(c.suggestedPinchOn()));
        check("pinch off > on", c.suggestedPinchOff() > c.suggestedPinchOn() + 0.007F);
        check("fist on separates", c.suggestedFistOn() > 1.05F && c.suggestedFistOn() < 1.90F,
            String.valueOf(c.suggestedFistOn()));
        check("fist off > on", c.suggestedFistOff() > c.suggestedFistOn() + 0.049F);
        // Regression: thresholds must sit nearer the fist edge so an open hand (1.90) never presses
        // (press is metric < on) and a fist (1.05) always does.
        check("fist on below midpoint", c.suggestedFistOn() < (1.05F + 1.90F) / 2F,
            String.valueOf(c.suggestedFistOn()));
        check("fist off below open hand", c.suggestedFistOff() < 1.90F, String.valueOf(c.suggestedFistOff()));
        check("fist presses on observed fist", 1.05F < c.suggestedFistOn());
        String report = c.report(t0 + VisionHandCalibration.TOTAL_MS * 1_000_000L);
        check("report valid", report.contains("valid=yes"), report);
        check("report contains suggested keys", report.contains("pinch.on=") && report.contains("fist.on="));
        check("NaN samples ignored", ignored());
        check("prompts exist", VisionHandCalibration.promptFor(0).contains("OPEN")
            && VisionHandCalibration.promptFor(1).contains("FIST")
            && VisionHandCalibration.promptFor(2).contains("PINCH"));
        applyReportChecks();
        System.out.println("[m4-hand-calibration-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m4-hand-calibration-test] PASS" : "[m4-hand-calibration-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    private static void applyReportChecks() {
        try {
            java.nio.file.Path dir = java.nio.file.Files.createTempDirectory("vrmc-calib-apply");
            java.nio.file.Path tune = dir.resolve("vrmc-input-tune.properties");
            java.nio.file.Files.writeString(tune, "swipe.enabled=true\nmove.forwardScale=3.0\n");
            String noReport = VisionHandCalibration.applyReport(dir, tune, null);
            check("apply without report fails safely", noReport.contains("no valid"), noReport);
            java.nio.file.Files.writeString(dir.resolve(VisionHandCalibration.REPORT_FILE),
                "valid=yes\noneLine pinch=0.033/0.052 fist=1.42/1.68\n");
            String applied = VisionHandCalibration.applyReport(dir, tune, null);
            check("apply report returns applied", applied.startsWith("applied pinch=0.033/0.052 fist=1.42/1.68"),
                applied);
            java.util.Properties p = new java.util.Properties();
            try (java.io.InputStream in = java.nio.file.Files.newInputStream(tune)) { p.load(in); }
            check("applied pinch keys", "0.033".equals(p.getProperty("pinch.on"))
                && "0.052".equals(p.getProperty("pinch.off")));
            check("applied fist keys", "1.42".equals(p.getProperty("fist.on"))
                && "1.68".equals(p.getProperty("fist.off")));
            check("unrelated tune key preserved", "true".equals(p.getProperty("swipe.enabled"))
                && "3.0".equals(p.getProperty("move.forwardScale")));
            java.nio.file.Files.writeString(dir.resolve(VisionHandCalibration.REPORT_FILE),
                "oneLine pinch=0.02/0.01 fist=1.4/1.6\n");
            check("inverted suggestion rejected",
                VisionHandCalibration.applyReport(dir, tune, null).contains("no valid"));
            java.nio.file.Files.writeString(dir.resolve(VisionHandCalibration.REPORT_FILE),
                "oneLine pinch=NaN/0.05 fist=1.4/1.6\n");
            check("non-finite suggestion rejected",
                VisionHandCalibration.applyReport(dir, tune, null).contains("no valid"));
        } catch (Throwable t) {
            check("apply report checks did not throw", false, String.valueOf(t));
        }
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
