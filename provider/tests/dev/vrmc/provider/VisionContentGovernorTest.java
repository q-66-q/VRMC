package dev.vrmc.provider;

/**
 * Host test for the M8 content-first governor (pure policy, no game/device).
 *
 * Verifies knob parsing, the two-consecutive-window hysteresis, the render -> simulation -> render
 * reduction preference, the per-session cap, cooldown, minimum bounds and reset behaviour. This is
 * the "keep 4K, cut scene cost first" policy used when aiming at 120 Hz on device.
 *
 * Reduction cadence (by design): after a reduction, one struggling window is absorbed by the
 * cooldown, the next struggling window is the second of the pair, so a reduction can follow every
 * other struggling window until the cap or the minimum distances are reached.
 */
public final class VisionContentGovernorTest {
    private static int checks = 0;
    private static int failures = 0;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    private static void checkReduce(String name, int[] got, int render, int simulation) {
        check(name, got != null && got.length == 2 && got[0] == render && got[1] == simulation,
            got == null ? "null" : ("{" + got[0] + "," + got[1] + "}"));
    }

    public static void main(String[] args) {
        // ---- parse ------------------------------------------------------------------------
        check("null -> off", VisionContentGovernor.parse(null) == 0);
        check("empty -> off", VisionContentGovernor.parse("") == 0);
        check("blank -> off", VisionContentGovernor.parse("   ") == 0);
        check("off -> off", VisionContentGovernor.parse("off") == 0);
        check("OFF -> off", VisionContentGovernor.parse("OFF") == 0);
        check("false -> off", VisionContentGovernor.parse("false") == 0);
        check("0 -> off", VisionContentGovernor.parse("0") == 0);
        check("on -> on", VisionContentGovernor.parse("on") == 1);
        check("ON -> on", VisionContentGovernor.parse("ON") == 1);
        check("true -> on", VisionContentGovernor.parse("true") == 1);
        check("1 -> on", VisionContentGovernor.parse("1") == 1);
        check("whitespace on -> on", VisionContentGovernor.parse("  on  ") == 1);
        check("maybe invalid", VisionContentGovernor.parse("maybe") == -1);
        check("2 invalid", VisionContentGovernor.parse("2") == -1);

        // ---- disabled: never reduces ------------------------------------------------------
        VisionContentGovernor gov = new VisionContentGovernor();
        check("disabled by default", !gov.enabled());
        for (int i = 0; i < 10; i++) {
            check("disabled window " + i + " no change", gov.decide(true, 16, 12) == null);
        }

        // ---- two consecutive struggling windows required ----------------------------------
        gov.setEnabled(true);
        check("enabled", gov.enabled());
        check("first struggling window no change", gov.decide(true, 16, 12) == null);
        checkReduce("second struggling window reduces render", gov.decide(true, 16, 12), 14, 12);
        check("one reduction recorded", gov.reductions() == 1);
        check("render reductions=1", gov.renderReductions() == 1);
        check("simulation reductions=0", gov.simulationReductions() == 0);

        // ---- cooldown window, then simulation step ----------------------------------------
        check("cooldown window no change", gov.decide(true, 14, 12) == null);
        checkReduce("next window reduces simulation", gov.decide(true, 14, 12), 14, 10);
        check("two reductions recorded", gov.reductions() == 2);

        // ---- third step prefers render again ----------------------------------------------
        check("cooldown again", gov.decide(true, 14, 10) == null);
        checkReduce("third reduction is render", gov.decide(true, 14, 10), 12, 10);
        check("cap reached", gov.reductions() == VisionContentGovernor.MAX_REDUCTIONS);

        // ---- per-session cap --------------------------------------------------------------
        for (int i = 0; i < 8; i++) {
            check("capped window " + i + " no change", gov.decide(true, 12, 10) == null);
        }

        // ---- bounds: never below the minimums ---------------------------------------------
        VisionContentGovernor low = new VisionContentGovernor();
        low.setEnabled(true);
        check("low first", low.decide(true, 7, 7) == null);
        check("low second has no room", low.decide(true, 7, 7) == null);
        check("low reductions stay 0", low.reductions() == 0);
        // 8 -> 6 is allowed (min 6); then render has no room and simulation steps down.
        VisionContentGovernor edge = new VisionContentGovernor();
        edge.setEnabled(true);
        check("edge first", edge.decide(true, 8, 8) == null);
        checkReduce("edge render 8->6", edge.decide(true, 8, 8), 6, 8);
        check("edge cooldown", edge.decide(true, 6, 8) == null);
        checkReduce("edge simulation 8->6", edge.decide(true, 6, 8), 6, 6);
        check("edge cooldown 2", edge.decide(true, 6, 6) == null);
        check("edge no room left", edge.decide(true, 6, 6) == null);
        check("edge reductions capped by room", edge.reductions() == 2);

        // ---- reset on non-struggling windows ---------------------------------------------
        VisionContentGovernor reset = new VisionContentGovernor();
        reset.setEnabled(true);
        check("reset first struggle", reset.decide(true, 16, 12) == null);
        check("reset calm window", reset.decide(false, 16, 12) == null);
        check("reset one struggle is not enough", reset.decide(true, 16, 12) == null);
        checkReduce("reset two struggles reduce", reset.decide(true, 16, 12), 14, 12);

        // ---- disabling resets the streak -------------------------------------------------
        VisionContentGovernor toggle = new VisionContentGovernor();
        toggle.setEnabled(true);
        check("toggle first", toggle.decide(true, 16, 12) == null);
        toggle.setEnabled(false);
        toggle.setEnabled(true);
        check("toggle re-enable needs two fresh windows", toggle.decide(true, 16, 12) == null);
        checkReduce("toggle then reduces", toggle.decide(true, 16, 12), 14, 12);

        // ---- unknown distances (<= 0) never reduce ---------------------------------------
        VisionContentGovernor unknown = new VisionContentGovernor();
        unknown.setEnabled(true);
        check("unknown first", unknown.decide(true, -1, -1) == null);
        check("unknown second no room", unknown.decide(true, -1, -1) == null);
        check("unknown reductions 0", unknown.reductions() == 0);

        System.out.println("[m8-content-first-test] " + checks + " checks, " + failures + " failed");
        if (failures > 0) { System.out.println("[m8-content-first-test] FAIL"); System.exit(1); }
        System.out.println("[m8-content-first-test] PASS");
    }
}
