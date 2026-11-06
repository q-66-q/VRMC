package dev.vrmc.provider;

/**
 * Host test for the M8 target-cadence guardrail (pure policy, no game/device).
 *
 * The operator can aim above the display's actual rate via vrmc-target-hz.txt. The guardrail counts
 * consecutive windows where the measured display cadence stays below the target and allows a revert
 * to auto after a bounded number of windows, so the provider never chases an unreachable cadence
 * forever (and never crushes the eye-target resolution for a rate the hardware does not provide).
 */
public final class VisionTargetGuardrailTest {
    private static int checks = 0;
    private static int failures = 0;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) {
        // ---- displayBelowTarget ----------------------------------------------------------
        check("120 target, 90 display -> below", VisionTargetGuardrail.displayBelowTarget(120, 90.0f));
        check("120 target, 119 display -> boundary not below", !VisionTargetGuardrail.displayBelowTarget(120, 119.0f));
        check("120 target, 120 display -> reached", !VisionTargetGuardrail.displayBelowTarget(120, 120.0f));
        check("120 target, 121 display -> reached", !VisionTargetGuardrail.displayBelowTarget(120, 121.0f));
        check("120 target, 119.5 display -> not below (within 1 Hz)", !VisionTargetGuardrail.displayBelowTarget(120, 119.5f));
        check("120 target, 118.9 display -> below", VisionTargetGuardrail.displayBelowTarget(120, 118.9f));
        check("120 target, NaN display -> no", !VisionTargetGuardrail.displayBelowTarget(120, Float.NaN));
        check("120 target, 0 display -> no", !VisionTargetGuardrail.displayBelowTarget(120, 0.0f));
        check("96 target, 90 display -> below", VisionTargetGuardrail.displayBelowTarget(96, 90.0f));
        check("100 target, 90 display -> below", VisionTargetGuardrail.displayBelowTarget(100, 90.0f));
        check("90 target, 88.9 display -> below", VisionTargetGuardrail.displayBelowTarget(90, 88.9f));
        check("90 target, 89.5 display -> not below (1 Hz tolerance)", !VisionTargetGuardrail.displayBelowTarget(90, 89.5f));
        check("auto target (0) never below", !VisionTargetGuardrail.displayBelowTarget(0, 60.0f));
        check("negative target never below", !VisionTargetGuardrail.displayBelowTarget(-1, 60.0f));

        // ---- shouldRevert ----------------------------------------------------------------
        check("window 1 no revert", !VisionTargetGuardrail.shouldRevert(1));
        check("window 4 no revert", !VisionTargetGuardrail.shouldRevert(4));
        check("window 7 no revert", !VisionTargetGuardrail.shouldRevert(7));
        check("window 8 reverts", VisionTargetGuardrail.shouldRevert(8));
        check("window 9 reverts", VisionTargetGuardrail.shouldRevert(9));
        check("window 0 no revert", !VisionTargetGuardrail.shouldRevert(0));
        check("window -1 no revert", !VisionTargetGuardrail.shouldRevert(-1));
        check("threshold is 8 windows", VisionTargetGuardrail.UNREACHABLE_WINDOWS == 8);
        check("threshold boundary", VisionTargetGuardrail.shouldRevert(
            VisionTargetGuardrail.UNREACHABLE_WINDOWS)
            && !VisionTargetGuardrail.shouldRevert(VisionTargetGuardrail.UNREACHABLE_WINDOWS - 1));

        System.out.println("[m8-target-guardrail-test] " + checks + " checks, " + failures + " failed");
        if (failures > 0) { System.out.println("[m8-target-guardrail-test] FAIL"); System.exit(1); }
        System.out.println("[m8-target-guardrail-test] PASS");
    }
}
