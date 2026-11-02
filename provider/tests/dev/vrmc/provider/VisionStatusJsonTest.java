package dev.vrmc.provider;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Host test: vrmc-status.json must be strictly valid JSON and round-trip fields (EV-0144 regression). */
public final class VisionStatusJsonTest {
    private static int checks;
    private static int failures;
    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) {
        VisionStatusJson.Data data = new VisionStatusJson.Data(
            "2026-01-01T00:00:00Z", 3, true, true, 2L, 4466, false, true, true, true, true,
            "visionOS \"27\\2\"", "seated=false \"quoted\" \\ back", 0.18F,
            "pinch=0.030/0.045 swipe=true", "nominal", "notify", false, false, 11.5F, 18.25F, 4,
            true, true, 0.42F, true, true, true, "L:pinch R:middle");
        String json = VisionStatusJson.build(data, Instant.EPOCH);
        Map<String, Object> parsed = null;
        try {
            parsed = TestJson.parseObject(json);
        } catch (Throwable t) {
            System.out.println("  JSON parse failed: " + t);
        }
        check("valid JSON", parsed != null);
        if (parsed != null) {
            check("abi", parsed.get("abi") instanceof Number
                && ((Number) parsed.get("abi")).intValue() == 3);
            check("trackedFrames", parsed.get("trackedFrames") instanceof Number
                && ((Number) parsed.get("trackedFrames")).intValue() == 4466);
            check("seated false", Boolean.FALSE.equals(parsed.get("seated")));
            check("handLeft true", Boolean.TRUE.equals(parsed.get("handLeftTracked")));
            check("escaped runningOnVisionOS", ("visionOS \"27\\2\"").equals(parsed.get("runningOnVisionOS")),
                String.valueOf(parsed.get("runningOnVisionOS")));
            check("escaped runtimeSettings", ("seated=false \"quoted\" \\ back").equals(parsed.get("runtimeSettings")));
            check("hotbarRange number", parsed.get("hotbarRange") instanceof Double);
            check("thermalState", "nominal".equals(parsed.get("thermalState")));
            check("adaptiveApplied key", Boolean.FALSE.equals(parsed.get("adaptiveFramerateApplied")));
            check("frameP50Ms", parsed.get("frameP50Ms") instanceof Number
                && Math.abs(((Number) parsed.get("frameP50Ms")).doubleValue() - 11.5) < 1e-6);
            check("frameP95Ms", parsed.get("frameP95Ms") instanceof Number
                && Math.abs(((Number) parsed.get("frameP95Ms")).doubleValue() - 18.25) < 1e-6);
            check("missed90Frames", parsed.get("missed90Frames") instanceof Number
                && ((Number) parsed.get("missed90Frames")).intValue() == 4);
            check("bowActive", Boolean.TRUE.equals(parsed.get("bowActive")));
            check("bowNotched", Boolean.TRUE.equals(parsed.get("bowNotched")));
            check("bowDrawPercent", parsed.get("bowDrawPercent") instanceof Number
                && Math.abs(((Number) parsed.get("bowDrawPercent")).doubleValue() - 0.42) < 1e-6);
            check("climbGrabbing", Boolean.TRUE.equals(parsed.get("climbGrabbing")));
            check("climbeyClimb", Boolean.TRUE.equals(parsed.get("climbeyClimb")));
            check("climbActive", Boolean.TRUE.equals(parsed.get("climbActive")));
            check("gestures round-trip", "L:pinch R:middle".equals(parsed.get("gestures")));
        }
        // Regression shape: the last field must not carry a trailing comma/quote (EV-0144 bug).
        String trimmed = json.trim();
        check("ends with closing brace", trimmed.endsWith("}"));
        check("no comma before closing brace", !trimmed.matches("(?s).*,\\s*}$"));
        System.out.println("[m5-status-json-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m5-status-json-test] PASS" : "[m5-status-json-test] FAIL");
        if (failures != 0) System.exit(1);
    }

}
