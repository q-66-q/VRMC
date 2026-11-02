package dev.vrmc.provider;

import java.util.HashMap;
import java.util.Map;
import java.util.Random;

/** Host fuzz: arbitrary vrmc-runtime.properties maps must never throw and must yield bounded settings. */
public final class VisionRuntimeSettingsFuzzTest {
    private static final int CASES = 100_000;
    private static final String[] KEYS = {
        "comfort.seated", "comfort.seatedFreeMove", "comfort.seatedUseHMD", "comfort.seatedHmdPointer",
        "comfort.worldRotationIncrement", "comfort.worldScale", "comfort.manualHeight",
        "performance.preset", "performance.renderDistance", "performance.simulationDistance",
        "performance.framerateLimit", "performance.vsync", "performance.thermalResponse",
        "performance.adaptiveFramerate", "diagnostics.periodSeconds", "unknown.key", "another.key"
    };

    public static void main(String[] args) {
        Random rnd = new Random(0x5E771E5L);
        int violations = 0;
        for (int i = 0; i < CASES; i++) {
            Map<String, String> map = new HashMap<>();
            int entries = rnd.nextInt(10);
            for (int e = 0; e < entries; e++) {
                map.put(KEYS[rnd.nextInt(KEYS.length)], randomValue(rnd));
            }
            VisionRuntimeSettings s;
            try {
                s = VisionRuntimeSettings.parse(map);
            } catch (Throwable t) {
                if (++violations <= 5) System.out.println("  VIOLATION parse threw case=" + i + ": " + t);
                continue;
            }
            if (s == null || s.warnings == null || s.summary() == null) {
                if (++violations <= 5) System.out.println("  VIOLATION null result/warnings/summary case=" + i);
                continue;
            }
            if (!valid(s)) {
                if (++violations <= 5) System.out.println("  VIOLATION out-of-range settings case=" + i
                    + " " + s.summary());
            }
            if (violations > 10) break;
        }
        System.out.println("[m5-settings-fuzz-test] cases=" + CASES + " violations=" + violations);
        System.out.println(violations == 0 ? "[m5-settings-fuzz-test] PASS" : "[m5-settings-fuzz-test] FAIL");
        if (violations != 0) System.exit(1);
    }

    private static boolean valid(VisionRuntimeSettings s) {
        if (s.hasWorldRotationIncrement && (s.worldRotationIncrement < 0F || s.worldRotationIncrement > 180F)) return false;
        if (s.hasWorldScale && (s.worldScale < 0.1F || s.worldScale > 5.0F)) return false;
        if (s.hasManualHeight && s.manualHeight != -1F
            && (s.manualHeight < 1.0F || s.manualHeight > 2.2F)) return false;
        if (s.hasRenderDistance && (s.renderDistance < 2 || s.renderDistance > 32)) return false;
        if (s.hasSimulationDistance && (s.simulationDistance < 2 || s.simulationDistance > 32)) return false;
        if (s.hasFramerateLimit && (s.framerateLimit < 30 || s.framerateLimit > 260)) return false;
        if (s.diagnosticPeriodSeconds < 5 || s.diagnosticPeriodSeconds > 3600) return false;
        if (!s.thermalResponse.equals("notify") && !s.thermalResponse.equals("reduce")) return false;
        return s.preset.equals("none") || s.preset.equals("performance")
            || s.preset.equals("balanced") || s.preset.equals("quality");
    }

    private static String randomValue(Random rnd) {
        switch (rnd.nextInt(10)) {
            case 0: return "";
            case 1: return "true";
            case 2: return "false";
            case 3: return "NaN";
            case 4: return "Infinity";
            case 5: return "-1.0E30";
            case 6: return String.valueOf(rnd.nextInt(1000) - 200);
            case 7: return String.valueOf((rnd.nextDouble() - 0.5) * 1.0E6);
            case 8: return "quality";
            default: {
                int len = rnd.nextInt(12);
                StringBuilder b = new StringBuilder();
                for (int i = 0; i < len; i++) b.append((char) ('a' + rnd.nextInt(26)));
                return b.toString();
            }
        }
    }
}
