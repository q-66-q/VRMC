package dev.vrmc.provider;

import java.nio.file.Files;
import java.nio.file.Path;

/** Host test for the M5 command-file take/validate/result contract (temp dir; no game). */
public final class VisionCommandFileTest {
    private static int checks;
    private static int failures;
    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) throws Exception {
        Path dir = Files.createTempDirectory("vrmc-command-test");
        check("no file -> null", VisionCommandFile.take(dir, null) == null);

        Files.writeString(dir.resolve(VisionCommandFile.FILE_NAME), "recenter\n");
        check("known command returned", "recenter".equals(VisionCommandFile.take(dir, null)));
        check("command file consumed", !Files.exists(dir.resolve(VisionCommandFile.FILE_NAME)));

        Files.writeString(dir.resolve(VisionCommandFile.FILE_NAME), "CALIBRATE-HEIGHT extra\n");
        check("case/extra whitespace normalized", "calibrate-height".equals(VisionCommandFile.take(dir, null)));

        Files.writeString(dir.resolve(VisionCommandFile.FILE_NAME), "do-something-dangerous\n");
        check("unknown command rejected", VisionCommandFile.take(dir, null) == null);
        String results = Files.readString(dir.resolve(VisionCommandFile.RESULT_FILE_NAME));
        check("unknown command result recorded", results.contains("REJECTED") && results.contains("do-something-dangerous"), results);
        check("unknown command file consumed", !Files.exists(dir.resolve(VisionCommandFile.FILE_NAME)));

        VisionCommandFile.appendResult(dir, "status", "ok bridgeReady=true", null);
        String all = Files.readString(dir.resolve(VisionCommandFile.RESULT_FILE_NAME));
        check("append result", all.contains("command=status") && all.contains("ok bridgeReady=true"), all);

        Files.writeString(dir.resolve(VisionCommandFile.FILE_NAME), "   \n");
        check("blank file -> null", VisionCommandFile.take(dir, null) == null);

        Files.deleteIfExists(dir.resolve(VisionCommandFile.RESULT_FILE_NAME));
        Files.deleteIfExists(dir.resolve(VisionCommandFile.FILE_NAME));
        Files.deleteIfExists(dir);
        System.out.println("[m5-command-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m5-command-test] PASS" : "[m5-command-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
