package dev.vrmc.provider;

/** Host test for the M4 direct hotbar wheel mapping. */
public final class VisionHotbarWheelTest {
    private static int checks;
    private static int failures;
    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) {
        float range = VisionHotbarWheel.DEFAULT_HALF_RANGE_METRES;
        check("far left = slot 1", VisionHotbarWheel.slotForDelta(-range, range) == 1);
        check("far right = slot 9", VisionHotbarWheel.slotForDelta(range, range) == 9);
        check("centre = slot 5", VisionHotbarWheel.slotForDelta(0.0F, range) == 5);
        check("quarter left = slot 3", VisionHotbarWheel.slotForDelta(-range * 0.5F, range) == 3);
        check("quarter right = slot 7", VisionHotbarWheel.slotForDelta(range * 0.5F, range) == 7);
        check("beyond range clamps", VisionHotbarWheel.slotForDelta(range * 5.0F, range) == 9
            && VisionHotbarWheel.slotForDelta(-range * 5.0F, range) == 1);
        check("NaN safe", VisionHotbarWheel.slotForDelta(Float.NaN, range) == 5);
        check("degenerate range safe", VisionHotbarWheel.slotForDelta(range, 0.0F) >= 1
            && VisionHotbarWheel.slotForDelta(range, 0.0F) <= 9);
        System.out.println("[m4-hotbar-wheel-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m4-hotbar-wheel-test] PASS" : "[m4-hotbar-wheel-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
