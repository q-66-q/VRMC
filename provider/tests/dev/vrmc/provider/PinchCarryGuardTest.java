package dev.vrmc.provider;

/**
 * Host test for the M7 right-pinch carry guard ({@link PinchCarryGuard}).
 *
 * <p>R1 (REVIEW_1.3 §5): the old inline guard only armed when the pinch was still held on the
 * GUI-transition frame. A pinch released on that exact frame produced a release pulse that the world
 * path treated as place/attack. These checks pin the carried-until-released behavior and the
 * released-on-the-transition-frame case.
 */
public final class PinchCarryGuardTest {
    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok) {
        checks++;
        if (!ok) failures++;
        System.out.println("  " + (ok ? "ok  " : "FAIL") + " " + name);
    }

    public static void main(String[] args) {
        normalPressReleaseIsNotCarried();
        holdAcrossGuiOpenIsIgnoredUntilReleased();
        holdAcrossGuiCloseIsIgnoredUntilReleased();
        releaseOnGuiCloseTransitionFrameIsCarried();
        releaseOnGuiOpenTransitionFrameIsCarried();
        pinchStartingOnTransitionFrameIsCarried();
        plainTransitionWithoutPinchDoesNotCarry();
        newPressAfterCarryReleaseWorks();
        resetClearsState();

        System.out.println("[m7-pinch-carry-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0
            ? "[m7-pinch-carry-test] PASS" : "[m7-pinch-carry-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    /** Reads one frame and reports whether the caller would fire a world release action. */
    private static boolean releaseAction(boolean heldPrevFrame, boolean heldThisFrame) {
        return !heldThisFrame && heldPrevFrame;
    }

    private static void normalPressReleaseIsNotCarried() {
        System.out.println("[m7-pinch-carry-test] a normal press/release keeps its release edge");
        PinchCarryGuard g = new PinchCarryGuard();
        boolean[] rawFrames = {false, false, true, true, true, false, false};
        boolean heldPrev = false;
        boolean pressed = false;
        boolean sawReleaseAction = false;
        for (boolean raw : rawFrames) {
            boolean held = g.update(false, raw);
            if (raw) pressed = true;
            if (g.carriedNow()) {
                // Caller contract: a carried frame forgets the previous press state.
                heldPrev = false;
                continue;
            }
            if (releaseAction(heldPrev, held)) sawReleaseAction = true;
            heldPrev = held;
        }
        check("world pinch press is not carried", pressed && !g.carrying());
        check("normal short pinch release still reaches the world path", sawReleaseAction);
    }

    private static void holdAcrossGuiOpenIsIgnoredUntilReleased() {
        System.out.println("[m7-pinch-carry-test] pinch held while the GUI opens is ignored until released");
        PinchCarryGuard g = new PinchCarryGuard();
        boolean held = g.update(false, true);
        check("pinch down in world", held);
        held = g.update(true, true); // GUI opens, pinch still down
        check("transition with the pinch held is carried", g.carriedNow() && !held && g.carrying());
        check("later frames while still held stay ignored", !g.update(true, true) && !g.carriedNow());
        check("release frame is still ignored, not a world action", !g.update(true, false));
        check("carry clears once the pinch is released", !g.carrying());
        check("a fresh pinch in the GUI is a real press", g.update(true, true));
    }

    private static void holdAcrossGuiCloseIsIgnoredUntilReleased() {
        System.out.println("[m7-pinch-carry-test] pinch held while the GUI closes is ignored until released");
        PinchCarryGuard g = new PinchCarryGuard();
        check("pinch down inside the GUI", !g.update(true, true));
        boolean held = g.update(false, true); // GUI closes, still pinching
        check("transition with the pinch held is carried", g.carriedNow() && !held && g.carrying());
        check("held frame after the close stays ignored", !g.update(false, true));
        check("release after the close is swallowed", !g.update(false, false));
        check("carry clears after the release", !g.carrying());
    }

    private static void releaseOnGuiCloseTransitionFrameIsCarried() {
        System.out.println("[m7-pinch-carry-test] R1: release on the exact GUI-close frame is carried");
        PinchCarryGuard g = new PinchCarryGuard();
        boolean heldPrev = g.update(true, true); // last GUI frame: pinch down
        // Next frame the GUI is closed AND the pinch is released. The old guard did not arm here.
        boolean held = g.update(false, false);
        boolean fired = !g.carriedNow() && releaseAction(heldPrev, held);
        check("release edge on the GUI-close transition frame is reported as carried", g.carriedNow());
        check("the carried frame cannot fire a world release action", !fired);
        check("the pinch is not held in world on that frame", !held);
        check("the carry is not left dangling (release already happened)", !g.carrying());
        check("the next world pinch works normally", g.update(false, true));
    }

    private static void releaseOnGuiOpenTransitionFrameIsCarried() {
        System.out.println("[m7-pinch-carry-test] release on the exact GUI-open frame is carried too");
        PinchCarryGuard g = new PinchCarryGuard();
        check("pinch down in world", g.update(false, true));
        boolean held = g.update(true, false); // GUI opens and the pinch is released this frame
        check("release on the GUI-open transition is carried", g.carriedNow() && !held);
        check("no world release can fire after the GUI took over", !g.carrying());
        check("GUI clicks stay suppressed for this frame (carry seen by the click path)", g.carriedNow());
    }

    private static void pinchStartingOnTransitionFrameIsCarried() {
        System.out.println("[m7-pinch-carry-test] a pinch starting on the transition frame is carried");
        PinchCarryGuard g = new PinchCarryGuard();
        boolean held = g.update(true, true); // GUI opens on the pinch-down frame
        check("a pinch beginning during the transition is not a world press",
            !held && g.carriedNow() && g.carrying());
        check("the next held frame stays ignored", !g.update(true, true) && g.carrying());
        check("its release is swallowed and clears the carry", !g.update(true, false) && !g.carrying());
    }

    private static void plainTransitionWithoutPinchDoesNotCarry() {
        System.out.println("[m7-pinch-carry-test] a GUI transition without a pinch changes nothing");
        PinchCarryGuard g = new PinchCarryGuard();
        g.update(false, false);
        g.update(true, false);
        check("no carry on a plain GUI transition", !g.carriedNow() && !g.carrying());
        g.update(false, false);
        check("no carry on a plain GUI close", !g.carriedNow() && !g.carrying());
        check("a later pinch press is a real press", g.update(false, true));
    }

    private static void newPressAfterCarryReleaseWorks() {
        System.out.println("[m7-pinch-carry-test] carry does not leak into the steady state");
        PinchCarryGuard g = new PinchCarryGuard();
        g.update(false, true);
        g.update(true, true);       // carried across the GUI open
        g.update(true, false);      // released inside the GUI
        g.update(false, false);     // first world frame after the close: no pinch
        boolean held = g.update(false, true); // fresh pinch in world
        check("fresh world pinch after a carried release is a real press", held);
        check("no carry reported on the fresh press", !g.carriedNow() && !g.carrying());
        check("and its release is visible again", !g.update(false, false) && !g.carrying());
    }

    private static void resetClearsState() {
        System.out.println("[m7-pinch-carry-test] reset clears the carry (tracking loss/release-input)");
        PinchCarryGuard g = new PinchCarryGuard();
        g.update(false, true);
        g.update(true, true);
        check("carrying before reset", g.carrying());
        g.reset();
        check("reset drops the carry", !g.carrying() && !g.carriedNow());
        check("next frame is a normal world frame", !g.update(false, false));
    }

}
