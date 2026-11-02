package dev.vrmc.provider;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

/** Host test for the M5 thermal-state reader/advisory. */
public final class VisionThermalStateTest {
    private static int checks;
    private static int failures;
    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) throws Exception {
        Path dir = Files.createTempDirectory("vrmc-thermal");
        check("missing file unknown", "unknown".equals(VisionThermalState.readState(dir)));
        Files.writeString(dir.resolve(VisionThermalState.FILE_NAME), "state=serious\nlowPower=false\n");
        check("serious parsed", "serious".equals(VisionThermalState.readState(dir)));
        check("serious is pressure", VisionThermalState.isPressure("serious"));
        check("serious advisory", VisionThermalState.advisory("serious") != null);
        Files.writeString(dir.resolve(VisionThermalState.FILE_NAME), "state=critical\n");
        check("critical advisory", VisionThermalState.advisory("critical") != null
            && VisionThermalState.advisory("critical").contains("critical"));
        Files.writeString(dir.resolve(VisionThermalState.FILE_NAME), "state=bogus\n");
        check("bogus unknown", "unknown".equals(VisionThermalState.readState(dir)));
        Files.writeString(dir.resolve(VisionThermalState.FILE_NAME), "other=x\n");
        check("no state unknown", "unknown".equals(VisionThermalState.readState(dir)));
        check("nominal not pressure", !VisionThermalState.isPressure("nominal"));
        Files.deleteIfExists(dir.resolve(VisionThermalState.FILE_NAME));
        Files.deleteIfExists(dir);
        System.out.println("[m5-thermal-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m5-thermal-test] PASS" : "[m5-thermal-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
