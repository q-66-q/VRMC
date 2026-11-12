package dev.vrmc.provider;

/**
 * Host test for the seated-play snap-turn decision ({@link SeatedTurnGesture}).
 *
 * <p>The vision input emits a single-tap pulse on the first tap even when a second tap follows (the
 * double-tap pulse arrives later), so acting immediately on the single tap made "double tap = turn
 * right" turn left and then right = net zero. These checks pin the deferral and the net-one-turn
 * behavior without a game instance.
 */
public final class SeatedTurnGestureTest {
    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok) {
        checks++;
        if (!ok) failures++;
        System.out.println("  " + (ok ? "ok  " : "FAIL") + " " + name);
    }

    /** Engine defaults: middle.tapMs=220, middle.doubleMs=320. */
    private static final long DOUBLE_WINDOW_NS = 320_000_000L;
    private static final long FRAME_NS = 11_000_000L;
    private static final long T0 = 100_000_000_000L;

    public static void main(String[] args) {
        singleTapDefersThenTurnsLeft();
        doubleTapTurnsRightOnly();
        twoFrameTapPulseDoesNotExtendDeadline();
        separateTapsTurnLeftTwice();
        disabledCancelsPending();
        doublePulseWithoutPendingTurnsRightOnce();

        System.out.println("[m7-seated-turn-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0
            ? "[m7-seated-turn-test] PASS" : "[m7-seated-turn-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    private static void singleTapDefersThenTurnsLeft() {
        System.out.println("[m7-seated-turn-test] a single tap turns left only after the double-tap window");
        SeatedTurnGesture g = new SeatedTurnGesture();
        long t = T0;
        check("first tap pulse produces no immediate turn",
            g.update(true, true, false, t, DOUBLE_WINDOW_NS) == SeatedTurnGesture.NONE && g.pending());
        t += FRAME_NS;
        check("second pulse frame still defers",
            g.update(true, false, false, t, DOUBLE_WINDOW_NS) == SeatedTurnGesture.NONE && g.pending());
        boolean left = false;
        boolean extra = false;
        // Stay quiet well past the decision deadline; exactly one LEFT must come out.
        for (int i = 0; i < 60; i++) {
            t += FRAME_NS;
            int d = g.update(true, false, false, t, DOUBLE_WINDOW_NS);
            if (d == SeatedTurnGesture.LEFT) left = true;
            if (d != SeatedTurnGesture.NONE && d != SeatedTurnGesture.LEFT) extra = true;
        }
        check("single tap fires one left turn", left && !extra);
        check("decision is recorded as not pending after it fires", !g.pending());
    }

    private static void doubleTapTurnsRightOnly() {
        System.out.println("[m7-seated-turn-test] a double tap nets exactly one right turn");
        SeatedTurnGesture g = new SeatedTurnGesture();
        long t = T0;
        check("first tap defers (left must not fire yet)",
            g.update(true, true, false, t, DOUBLE_WINDOW_NS) == SeatedTurnGesture.NONE && g.pending());
        t += FRAME_NS;
        check("second pulse frame still defers",
            g.update(true, false, false, t, DOUBLE_WINDOW_NS) == SeatedTurnGesture.NONE);
        // The second tap's release is reported as the double-tap pulse.
        t += 120_000_000L;
        int first = g.update(true, false, true, t, DOUBLE_WINDOW_NS);
        check("double tap pulse returns a single right turn",
            first == SeatedTurnGesture.RIGHT && !g.pending());
        boolean leftOrExtra = false;
        for (int i = 0; i < 80; i++) {
            t += FRAME_NS;
            int d = g.update(true, false, false, t, DOUBLE_WINDOW_NS);
            if (d == SeatedTurnGesture.LEFT || d == SeatedTurnGesture.RIGHT) leftOrExtra = true;
        }
        check("the deferred left turn is cancelled by the double tap", !leftOrExtra);
    }

    private static void twoFrameTapPulseDoesNotExtendDeadline() {
        System.out.println("[m7-seated-turn-test] the 2-frame tap pulse does not extend the deadline");
        SeatedTurnGesture g = new SeatedTurnGesture();
        long t = T0;
        long deadline = t + DOUBLE_WINDOW_NS + SeatedTurnGesture.DECISION_MARGIN_NS;
        g.update(true, true, false, t, DOUBLE_WINDOW_NS); // pulse frame 1 of the same tap
        t += FRAME_NS;
        g.update(true, true, false, t, DOUBLE_WINDOW_NS); // pulse frame 2 of the same tap
        boolean fired = false;
        boolean wrong = false;
        long firedAt = 0L;
        while (t < deadline + 10 * FRAME_NS) {
            t += FRAME_NS;
            int d = g.update(true, false, false, t, DOUBLE_WINDOW_NS);
            if (d == SeatedTurnGesture.LEFT) { fired = true; firedAt = t; break; }
            if (d != SeatedTurnGesture.NONE) wrong = true;
        }
        check("the tap fires one left turn", fired && !wrong);
        check("the second pulse frame did not push the deadline out",
            fired && firedAt <= deadline + 2 * FRAME_NS);
    }

    private static void separateTapsTurnLeftTwice() {
        System.out.println("[m7-seated-turn-test] two separate single taps turn left twice");
        SeatedTurnGesture g = new SeatedTurnGesture();
        long t = T0;
        int lefts = 0;
        // First tap.
        g.update(true, true, false, t, DOUBLE_WINDOW_NS);
        t += FRAME_NS;
        g.update(true, false, false, t, DOUBLE_WINDOW_NS);
        for (int i = 0; i < 40 && lefts == 0; i++) {
            t += FRAME_NS;
            if (g.update(true, false, false, t, DOUBLE_WINDOW_NS) == SeatedTurnGesture.LEFT) lefts++;
        }
        // Second tap, comfortably after the double-tap window (the engine cannot pair them).
        t += 500_000_000L;
        g.update(true, true, false, t, DOUBLE_WINDOW_NS);
        t += FRAME_NS;
        g.update(true, false, false, t, DOUBLE_WINDOW_NS);
        for (int i = 0; i < 40 && lefts < 2; i++) {
            t += FRAME_NS;
            if (g.update(true, false, false, t, DOUBLE_WINDOW_NS) == SeatedTurnGesture.LEFT) lefts++;
        }
        check("two separate taps produce two left turns", lefts == 2);
    }

    private static void disabledCancelsPending() {
        System.out.println("[m7-seated-turn-test] leaving seated/GUI cancels the deferred turn");
        SeatedTurnGesture g = new SeatedTurnGesture();
        long t = T0;
        g.update(true, true, false, t, DOUBLE_WINDOW_NS);
        t += FRAME_NS;
        check("pending before the context change", g.pending());
        check("disabled frame emits nothing", g.update(false, false, false, t, DOUBLE_WINDOW_NS) == SeatedTurnGesture.NONE);
        check("disabled frame clears the pending decision", !g.pending());
        boolean fired = false;
        for (int i = 0; i < 60; i++) {
            t += FRAME_NS;
            fired |= g.update(true, false, false, t, DOUBLE_WINDOW_NS) != SeatedTurnGesture.NONE;
        }
        check("no turn leaks after re-enabling", !fired);
    }

    private static void doublePulseWithoutPendingTurnsRightOnce() {
        System.out.println("[m7-seated-turn-test] a double-tap pulse alone still turns right once");
        SeatedTurnGesture g = new SeatedTurnGesture();
        long t = T0;
        check("double pulse turns right", g.update(true, false, true, t, DOUBLE_WINDOW_NS) == SeatedTurnGesture.RIGHT);
        t += FRAME_NS;
        check("the next frame is idle", g.update(true, false, false, t, DOUBLE_WINDOW_NS) == SeatedTurnGesture.NONE);
    }
}
