package dev.vrmc.provider;

/**
 * Regression tests for the release-hardening gesture fixes:
 *  - a posture change (sitting down, slouching) must not leave the head-drop sneak latched forever;
 *  - seated play (CTX_NO_HEAD_GESTURES) disables head jump/sneak but keeps the hands working;
 *  - a curled-finger pinch must not be read as a fist tap of the same hand (surprise menu / use).
 */
public final class VisionM7RegressionTest {
    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok) {
        checks++;
        if (!ok) failures++;
        System.out.println("  " + (ok ? "ok  " : "FAIL") + " " + name);
    }

    private static final long DT = 11_000_000L;
    private static final long CLOCK_BASE_NS = 100_000_000_000L;
    private static final float HEAD_Y = 1.50F;

    /** 27 joints; {@code ext} = fingertip extension from the knuckle (0.085 open, 0.015 fist). */
    private static float[] hand(float ext, float wx, float wy, float wz) {
        float[] j = new float[27 * 3];
        set(j, 0, wx, wy, wz);
        float[][] knuckles = {
            {wx - 0.04F, wy + 0.07F, wz - 0.01F},
            {wx, wy + 0.08F, wz},
            {wx + 0.04F, wy + 0.07F, wz + 0.01F},
            {wx + 0.08F, wy + 0.06F, wz + 0.02F}
        };
        int[] ki = {6, 11, 16, 21};
        int[] ti = {9, 14, 19, 24};
        for (int i = 0; i < 4; i++) {
            set(j, ki[i], knuckles[i][0], knuckles[i][1], knuckles[i][2]);
            set(j, ti[i], knuckles[i][0], knuckles[i][1] + ext, knuckles[i][2]);
        }
        set(j, 4, wx + 0.03F, wy + 0.06F, wz - 0.04F);
        return j;
    }

    private static void set(float[] j, int index, float x, float y, float z) {
        int o = index * 3;
        j[o] = x; j[o + 1] = y; j[o + 2] = z;
    }

    private static final float OPEN = 0.085F;
    /** Curl ~0.50: below the fist-on threshold (0.55) but not a confirmed grip (0.45). */
    private static final float CURLED_PINCH = 0.040F;

    private static float[] left(float ext, float headY) { return hand(ext, -0.25F, headY - 0.20F, -0.30F); }
    private static float[] right(float ext, float headY) { return hand(ext, 0.25F, headY - 0.20F, -0.30F); }

    private static void step(VisionM7Gesture g, long[] t, float[] l, float[] r, float pinchL,
                             float pinchR, int ctx, float headY) {
        stepPitch(g, t, l, r, pinchL, pinchR, ctx, headY, 0.0F);
    }

    /** As {@link #step}, with the head forward vector's Y (pitch) made explicit. */
    private static void stepPitch(VisionM7Gesture g, long[] t, float[] l, float[] r, float pinchL,
                                  float pinchR, int ctx, float headY, float fwdY) {
        t[0] += DT;
        if (t[0] < CLOCK_BASE_NS) t[0] += CLOCK_BASE_NS;
        float fwdZ = (float) -Math.sqrt(Math.max(0.0F, 1.0F - fwdY * fwdY));
        g.update(true, l, true, r, pinchL, pinchR, 0.0F, headY, 0.0F,
            1.0F, 0.0F, 0.0F, 0.0F, fwdY, fwdZ, t[0], ctx);
    }

    private static int frames(double seconds) { return (int) Math.round(seconds * 1.0e9 / DT); }

    /** Hold the head at {@code headY} (hands follow the head) for {@code seconds}. */
    private static void hold(VisionM7Gesture g, long[] t, float headY, double seconds, int ctx) {
        for (int i = 0; i < frames(seconds); i++) {
            step(g, t, left(OPEN, headY), right(OPEN, headY), 0.20F, 0.20F, ctx, headY);
        }
    }

    /** Move the head linearly from {@code from} to {@code to} over {@code seconds}. */
    private static void move(VisionM7Gesture g, long[] t, float from, float to, double seconds, int ctx) {
        int n = Math.max(1, frames(seconds));
        for (int i = 1; i <= n; i++) {
            float y = from + (to - from) * i / n;
            step(g, t, left(OPEN, y), right(OPEN, y), 0.20F, 0.20F, ctx, y);
        }
    }

    public static void main(String[] args) {
        testSitDownRecovers();
        testLookDownDoesNotLearnPosture();
        testCrouchStillHolds();
        testSlouchRecoversSlowly();
        testStandUpDoesNotBreakSneak();
        testResetHeadBaseline();
        testStandUpAfterSitDoesNotJump();
        testJumpStillWorksAfterPostureRecovery();
        testSeatedPlayHeadGesturesOff();
        testCurledPinchIsNotFistTap();
        testPlainFistTapsStillWork();

        System.out.println("[m7-regression-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m7-regression-test] PASS" : "[m7-regression-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    // ---- posture --------------------------------------------------------------------------------

    private static void testSitDownRecovers() {
        System.out.println("[m7-regression-test] sitting down re-baselines (no permanent sneak)");
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {0L};
        hold(g, t, HEAD_Y, 1.0, 0);
        move(g, t, HEAD_Y, HEAD_Y - 0.40F, 0.6, 0);
        hold(g, t, HEAD_Y - 0.40F, 0.9, 0);
        check("large head drop sneaks at first (same as a crouch)", g.sneak());
        hold(g, t, HEAD_Y - 0.40F, 2.0, 0);
        check("sitting still for ~2 s releases the sneak", !g.sneak());
        check("baseline follows the seated head height",
            Math.abs(g.headBaseline() - (HEAD_Y - 0.40F)) < 0.03F);
        hold(g, t, HEAD_Y - 0.40F, 5.0, 0);
        check("sneak stays released while seated", !g.sneak());
    }

    /**
     * A steep look-down lowers the tracked head by ~0.10-0.13 m. Learning that as a resting height
     * made looking back up fire the head-rise jump (regression on the posture-recovery slow drift:
     * look down 5-10 s, look up = jump). The baseline must stay at the standing height.
     */
    private static void testLookDownDoesNotLearnPosture() {
        System.out.println("[m7-regression-test] a held look-down is not learned as a posture");
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {0L};
        for (int i = 0; i < frames(1.0); i++) {
            stepPitch(g, t, left(OPEN, HEAD_Y), right(OPEN, HEAD_Y), 0.20F, 0.20F, 0, HEAD_Y, 0.0F);
        }
        float downY = HEAD_Y - 0.13F;
        int downFrames = frames(0.5);
        for (int i = 1; i <= downFrames; i++) {
            float f = i / (float) downFrames;
            stepPitch(g, t, left(OPEN, HEAD_Y - 0.13F * f), right(OPEN, HEAD_Y - 0.13F * f),
                0.20F, 0.20F, 0, HEAD_Y - 0.13F * f, -0.90F * f);
        }
        for (int i = 0; i < frames(10.0); i++) {
            stepPitch(g, t, left(OPEN, downY), right(OPEN, downY), 0.20F, 0.20F, 0, downY, -0.90F);
        }
        boolean jumped = false;
        int upFrames = frames(0.30);
        for (int i = 1; i <= upFrames; i++) {
            float f = i / (float) upFrames;
            float y = downY + 0.13F * f;
            stepPitch(g, t, left(OPEN, y), right(OPEN, y), 0.20F, 0.20F, 0, y, -0.90F * (1.0F - f));
            jumped |= g.jump();
        }
        check("looking back up after a held look-down does not jump", !jumped);
        check("look-down is not learned as a resting height",
            Math.abs(g.headBaseline() - HEAD_Y) < 0.02F);
    }

    private static void testCrouchStillHolds() {
        System.out.println("[m7-regression-test] a deliberate crouch still holds for seconds");
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {0L};
        hold(g, t, HEAD_Y, 1.0, 0);
        move(g, t, HEAD_Y, HEAD_Y - 0.22F, 0.35, 0);
        hold(g, t, HEAD_Y - 0.22F, 0.8, 0);
        check("crouch latches sneak", g.sneak());
        hold(g, t, HEAD_Y - 0.22F, 7.0, 0);
        check("crouch still sneaking after 8 s", g.sneak());
        move(g, t, HEAD_Y - 0.22F, HEAD_Y, 0.35, 0);
        hold(g, t, HEAD_Y, 0.6, 0);
        check("standing back up releases sneak", !g.sneak());
    }

    private static void testSlouchRecoversSlowly() {
        System.out.println("[m7-regression-test] a small lasting slouch recovers by itself");
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {0L};
        hold(g, t, HEAD_Y, 1.0, 0);
        move(g, t, HEAD_Y, HEAD_Y - 0.15F, 0.5, 0);
        hold(g, t, HEAD_Y - 0.15F, 1.0, 0);
        check("slouch past the sneak threshold sneaks", g.sneak());
        hold(g, t, HEAD_Y - 0.15F, 40.0, 0);
        check("slouch held for 40 s no longer sneaks", !g.sneak());
    }

    private static void testStandUpDoesNotBreakSneak() {
        System.out.println("[m7-regression-test] standing up from a chair then crouching still sneaks");
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {0L};
        float seatedY = 1.15F;
        hold(g, t, seatedY, 1.0, 0);
        move(g, t, seatedY, HEAD_Y, 0.7, 0);
        hold(g, t, HEAD_Y, 2.5, 0);
        check("baseline follows the standing head height", Math.abs(g.headBaseline() - HEAD_Y) < 0.03F);
        move(g, t, HEAD_Y, HEAD_Y - 0.20F, 0.35, 0);
        hold(g, t, HEAD_Y - 0.20F, 0.8, 0);
        check("crouch after standing up sneaks", g.sneak());
    }

    private static void testResetHeadBaseline() {
        System.out.println("[m7-regression-test] recenter/calibrate resets the head baseline");
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {0L};
        hold(g, t, HEAD_Y, 1.0, 0);
        move(g, t, HEAD_Y, HEAD_Y - 0.20F, 0.35, 0);
        hold(g, t, HEAD_Y - 0.20F, 0.8, 0);
        check("crouch sneaks before the reset", g.sneak());
        g.resetHeadBaseline();
        check("reset drops the sneak immediately", !g.sneak());
        hold(g, t, HEAD_Y - 0.20F, 1.5, 0);
        check("no sneak at the new resting height", !g.sneak());
        check("baseline is the new resting height", Math.abs(g.headBaseline() - (HEAD_Y - 0.20F)) < 0.02F);
        boolean jumped = false;
        for (int i = 0; i < frames(0.3); i++) {
            float y = HEAD_Y - 0.20F;
            step(g, t, left(OPEN, y), right(OPEN, y), 0.20F, 0.20F, 0, y);
            jumped |= g.jump();
        }
        check("reset does not fire a jump", !jumped);
    }

    /**
     * A stand-up from a posture that recovery re-baselined low (sat down, knelt) must not fire the
     * head-rise jump. Regression: posture recovery made "sit down, wait, stand up" jump.
     */
    private static void testStandUpAfterSitDoesNotJump() {
        System.out.println("[m7-regression-test] standing up after sitting does not fire a jump");
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {0L};
        hold(g, t, HEAD_Y, 1.0, 0);
        move(g, t, HEAD_Y, HEAD_Y - 0.40F, 0.6, 0);
        hold(g, t, HEAD_Y - 0.40F, 3.0, 0);
        check("posture recovery re-baselined at the seated height",
            Math.abs(g.headBaseline() - (HEAD_Y - 0.40F)) < 0.03F);
        boolean jumped = false;
        int n = frames(0.6);
        for (int i = 1; i <= n; i++) {
            float y = (HEAD_Y - 0.40F) + 0.40F * i / n;
            step(g, t, left(OPEN, y), right(OPEN, y), 0.20F, 0.20F, 0, y);
            jumped |= g.jump();
        }
        check("stand-up rise does not fire the head jump", !jumped);
        hold(g, t, HEAD_Y, 2.5, 0);
        check("baseline recovers to the standing height",
            Math.abs(g.headBaseline() - HEAD_Y) < 0.03F);
    }

    /** After standing back up has re-baselined, a deliberate rise must still jump. */
    private static void testJumpStillWorksAfterPostureRecovery() {
        System.out.println("[m7-regression-test] deliberate head rise still jumps after a posture change");
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {0L};
        hold(g, t, HEAD_Y, 1.0, 0);
        move(g, t, HEAD_Y, HEAD_Y - 0.40F, 0.6, 0);
        hold(g, t, HEAD_Y - 0.40F, 3.0, 0);
        move(g, t, HEAD_Y - 0.40F, HEAD_Y, 0.6, 0);
        hold(g, t, HEAD_Y, 2.5, 0);
        boolean jumped = false;
        int n = frames(0.3);
        for (int i = 1; i <= n; i++) {
            float y = HEAD_Y + 0.16F * i / n;
            step(g, t, left(OPEN, y), right(OPEN, y), 0.20F, 0.20F, 0, y);
            jumped |= g.jump();
        }
        check("a deliberate rise still jumps after posture recovery", jumped);
    }

    // ---- seated play ----------------------------------------------------------------------------

    private static void testSeatedPlayHeadGesturesOff() {
        System.out.println("[m7-regression-test] seated play: head gestures off, hands on");
        int ctx = VisionM7Gesture.CTX_NO_HEAD_GESTURES;
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {0L};
        hold(g, t, HEAD_Y, 1.0, ctx);
        move(g, t, HEAD_Y, HEAD_Y - 0.25F, 0.35, ctx);
        boolean sneaked = false;
        for (int i = 0; i < frames(2.0); i++) {
            float y = HEAD_Y - 0.25F;
            step(g, t, left(OPEN, y), right(OPEN, y), 0.20F, 0.20F, ctx, y);
            sneaked |= g.sneak();
        }
        check("head drop never sneaks in seated play", !sneaked);
        boolean jumped = false;
        int n = frames(0.25);
        for (int i = 1; i <= n; i++) {
            float y = HEAD_Y - 0.25F + 0.40F * i / n;
            step(g, t, left(OPEN, y), right(OPEN, y), 0.20F, 0.20F, ctx, y);
            jumped |= g.jump();
        }
        check("fast head rise never jumps in seated play", !jumped);

        // Hands still work: a short raised right pinch places, a left pinch hold engages.
        VisionM7Gesture h = new VisionM7Gesture();
        long[] ht = {0L};
        hold(h, ht, HEAD_Y, 0.5, ctx);
        for (int i = 0; i < frames(0.15); i++) {
            step(h, ht, left(OPEN, HEAD_Y), right(OPEN, HEAD_Y), 0.20F, 0.010F, ctx, HEAD_Y);
        }
        check("right pinch engages in seated play", h.rightPinchHeld());
        boolean placed = false;
        for (int i = 0; i < frames(0.15); i++) {
            step(h, ht, left(OPEN, HEAD_Y), right(OPEN, HEAD_Y), 0.20F, 0.20F, ctx, HEAD_Y);
            placed |= h.place();
        }
        check("short right pinch places in seated play", placed);
        for (int i = 0; i < frames(0.3); i++) {
            step(h, ht, left(OPEN, HEAD_Y), right(OPEN, HEAD_Y), 0.010F, 0.20F, ctx, HEAD_Y);
        }
        check("left pinch (move stick) engages in seated play", h.leftPinchHeld());
    }

    // ---- fist tap vs pinch ----------------------------------------------------------------------

    private static void testCurledPinchIsNotFistTap() {
        System.out.println("[m7-regression-test] curled-finger pinch is not a fist tap");
        // Left: a short move-stick pinch made with curled fingers must not open the game menu.
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {0L};
        hold(g, t, HEAD_Y, 1.0, 0);
        boolean pinched = false;
        for (int i = 0; i < frames(0.25); i++) {
            step(g, t, left(CURLED_PINCH, HEAD_Y), right(OPEN, HEAD_Y), 0.010F, 0.20F, 0, HEAD_Y);
            pinched |= g.leftPinchHeld();
        }
        check("curled left pinch is a real pinch", pinched);
        boolean menu = false;
        for (int i = 0; i < frames(0.4); i++) {
            step(g, t, left(OPEN, HEAD_Y), right(OPEN, HEAD_Y), 0.20F, 0.20F, 0, HEAD_Y);
            menu |= g.menu();
        }
        check("releasing a curled left pinch does not open the menu", !menu);

        // Left, in a GUI: the same release must not close the screen.
        VisionM7Gesture gui = new VisionM7Gesture();
        long[] gt = {0L};
        hold(gui, gt, HEAD_Y, 1.0, VisionM7Gesture.CTX_GUI);
        for (int i = 0; i < frames(0.25); i++) {
            step(gui, gt, left(CURLED_PINCH, HEAD_Y), right(OPEN, HEAD_Y), 0.010F, 0.20F,
                VisionM7Gesture.CTX_GUI, HEAD_Y);
        }
        boolean close = false;
        for (int i = 0; i < frames(0.4); i++) {
            step(gui, gt, left(OPEN, HEAD_Y), right(OPEN, HEAD_Y), 0.20F, 0.20F,
                VisionM7Gesture.CTX_GUI, HEAD_Y);
            close |= gui.leftFistTap();
        }
        check("releasing a curled left pinch does not close a GUI", !close);

        // Right: a short place pinch with curled fingers must not also fire the fist-tap "use".
        VisionM7Gesture r = new VisionM7Gesture();
        long[] rt = {0L};
        hold(r, rt, HEAD_Y, 1.0, 0);
        boolean rightPinched = false;
        for (int i = 0; i < frames(0.20); i++) {
            step(r, rt, left(OPEN, HEAD_Y), right(CURLED_PINCH, HEAD_Y), 0.20F, 0.010F, 0, HEAD_Y);
            rightPinched |= r.rightPinchHeld();
        }
        check("curled right pinch is a real pinch", rightPinched);
        boolean use = false;
        for (int i = 0; i < frames(0.4); i++) {
            step(r, rt, left(OPEN, HEAD_Y), right(OPEN, HEAD_Y), 0.20F, 0.20F, 0, HEAD_Y);
            use |= r.rightFistTap();
        }
        check("releasing a curled right pinch does not fire the fist-tap use", !use);
    }

    private static void testPlainFistTapsStillWork() {
        System.out.println("[m7-regression-test] plain fist taps still work");
        float fist = 0.015F;
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {0L};
        hold(g, t, HEAD_Y, 1.0, 0);
        for (int i = 0; i < frames(0.2); i++) {
            step(g, t, left(fist, HEAD_Y), right(OPEN, HEAD_Y), 0.20F, 0.20F, 0, HEAD_Y);
        }
        boolean menu = false;
        for (int i = 0; i < frames(0.3); i++) {
            step(g, t, left(OPEN, HEAD_Y), right(OPEN, HEAD_Y), 0.20F, 0.20F, 0, HEAD_Y);
            menu |= g.menu();
        }
        check("left fist tap still opens the menu", menu);

        VisionM7Gesture r = new VisionM7Gesture();
        long[] rt = {0L};
        hold(r, rt, HEAD_Y, 1.0, 0);
        for (int i = 0; i < frames(0.2); i++) {
            step(r, rt, left(OPEN, HEAD_Y), right(fist, HEAD_Y), 0.20F, 0.20F, 0, HEAD_Y);
        }
        boolean use = false;
        for (int i = 0; i < frames(0.3); i++) {
            step(r, rt, left(OPEN, HEAD_Y), right(OPEN, HEAD_Y), 0.20F, 0.20F, 0, HEAD_Y);
            use |= r.rightFistTap();
        }
        check("right fist tap still fires use", use);

        // A pinch long before the fist tap must not suppress it.
        VisionM7Gesture late = new VisionM7Gesture();
        long[] lt = {0L};
        hold(late, lt, HEAD_Y, 1.0, 0);
        for (int i = 0; i < frames(0.2); i++) {
            step(late, lt, left(OPEN, HEAD_Y), right(OPEN, HEAD_Y), 0.010F, 0.20F, 0, HEAD_Y);
        }
        hold(late, lt, HEAD_Y, 1.0, 0);
        for (int i = 0; i < frames(0.2); i++) {
            step(late, lt, left(fist, HEAD_Y), right(OPEN, HEAD_Y), 0.20F, 0.20F, 0, HEAD_Y);
        }
        boolean lateMenu = false;
        for (int i = 0; i < frames(0.3); i++) {
            step(late, lt, left(OPEN, HEAD_Y), right(OPEN, HEAD_Y), 0.20F, 0.20F, 0, HEAD_Y);
            lateMenu |= late.menu();
        }
        check("left fist tap 1 s after a pinch still opens the menu", lateMenu);
    }
}
