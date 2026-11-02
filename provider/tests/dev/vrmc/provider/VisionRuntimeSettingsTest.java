package dev.vrmc.provider;

import java.util.HashMap;
import java.util.Map;

/** Host test for the M5 vrmc-runtime.properties parser (no game classes). */
public final class VisionRuntimeSettingsTest {
    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) {
        VisionRuntimeSettings none = VisionRuntimeSettings.defaults();
        check("defaults apply nothing", !none.hasSeated && !none.hasSeatedFreeMove && !none.hasSeatedUseHMD
            && !none.hasWorldRotationIncrement && !none.hasRenderDistance && !none.hasSimulationDistance
            && !none.hasFramerateLimit && !none.hasVsync && none.preset.equals("none")
            && none.diagnosticPeriodSeconds == 30, none.summary());

        Map<String, String> explicit = new HashMap<>();
        explicit.put("comfort.seated", "true");
        explicit.put("comfort.seatedFreeMove", "true");
        explicit.put("comfort.worldRotationIncrement", "45");
        explicit.put("performance.renderDistance", "10");
        explicit.put("performance.simulationDistance", "8");
        explicit.put("performance.framerateLimit", "72");
        explicit.put("performance.vsync", "false");
        explicit.put("diagnostics.periodSeconds", "15");
        explicit.put("comfort.seatedHmdPointer", "true");
        explicit.put("comfort.worldScale", "1.25");
        explicit.put("comfort.manualHeight", "1.70");
        VisionRuntimeSettings v = VisionRuntimeSettings.parse(explicit);
        check("explicit seated", v.hasSeated && v.seated);
        check("explicit seated free move", v.hasSeatedFreeMove && v.seatedFreeMove);
        check("explicit snap angle", v.hasWorldRotationIncrement && v.worldRotationIncrement == 45.0F);
        check("explicit render distance", v.hasRenderDistance && v.renderDistance == 10);
        check("explicit simulation distance", v.hasSimulationDistance && v.simulationDistance == 8);
        check("explicit framerate", v.hasFramerateLimit && v.framerateLimit == 72);
        check("explicit vsync", v.hasVsync && !v.vsync);
        check("diagnostics period", v.diagnosticPeriodSeconds == 15);
        check("explicit seated hmd pointer", v.hasSeatedHmdPointer && v.seatedHmdPointer);
        check("explicit world scale", v.hasWorldScale && Math.abs(v.worldScale - 1.25F) < 1.0E-4F);
        check("explicit manual height", v.hasManualHeight && Math.abs(v.manualHeight - 1.70F) < 1.0E-4F);
        check("no warnings", v.warnings.isEmpty(), String.valueOf(v.warnings));

        VisionRuntimeSettings perf = VisionRuntimeSettings.parse(Map.of("performance.preset", "performance"));
        check("performance preset", perf.hasRenderDistance && perf.renderDistance == 8
            && perf.hasSimulationDistance && perf.simulationDistance == 8
            && perf.hasFramerateLimit && perf.framerateLimit == 90 && !perf.vsync, perf.summary());
        VisionRuntimeSettings overridden = VisionRuntimeSettings.parse(Map.of(
            "performance.preset", "performance", "performance.renderDistance", "10"));
        check("explicit key wins over preset", overridden.renderDistance == 10, overridden.summary());

        VisionRuntimeSettings bad = VisionRuntimeSettings.parse(Map.of(
            "comfort.seated", "yes please",
            "comfort.worldRotationIncrement", "999",
            "performance.renderDistance", "999",
            "performance.framerateLimit", "abc",
            "performance.preset", "ultra"));
        check("invalid booleans ignored", !bad.hasSeated);
        check("invalid rotation ignored", !bad.hasWorldRotationIncrement);
        check("out-of-range render distance ignored", !bad.hasRenderDistance);
        check("invalid framerate ignored", !bad.hasFramerateLimit);
        check("auto height accepted", VisionRuntimeSettings.parse(Map.of("comfort.manualHeight", "-1")).manualHeight == -1.0F);
        check("invalid world scale ignored", !VisionRuntimeSettings.parse(Map.of("comfort.worldScale", "9")).hasWorldScale);
        check("unknown preset falls back to none", bad.preset.equals("none"));
        check("warnings report every invalid value", bad.warnings.size() >= 5, String.valueOf(bad.warnings));

        System.out.println("[m5-settings-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m5-settings-test] PASS" : "[m5-settings-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
