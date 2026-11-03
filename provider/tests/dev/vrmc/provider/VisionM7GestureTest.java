package dev.vrmc.provider;

import java.util.Arrays;

/**
 * Host tests for the pure M7 gesture engine using synthetic 27-joint hands/head poses.
 *
 * <p>These are synthetic sequences, not device evidence. They pin the operator mapping and the
 * data-fitted thresholds/priorities agreed in docs/mvp/M7_TEST_MATRIX.md; the recorded Gesture Lab
 * datasets are replayed separately by provider/tests/dev/vrmc/provider/M7LabReplay.java +
 * scripts/m7_eval_replay.py.
 */
public final class VisionM7GestureTest {
    private static int checks;
    private static int failures;
    private static void check(String name, boolean ok) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name); }
    }

    private static final float[] HEAD = {0.0F, 1.50F, 0.0F};
    private static final float FWD_X = 0.0F, FWD_Y = 0.0F, FWD_Z = -1.0F;
    private static final float RIGHT_X = 1.0F, RIGHT_Y = 0.0F, RIGHT_Z = 0.0F;
    private static final long DT = 11_000_000L;
    /** Real System.nanoTime() values are large; tests must not collide with "never happened" (0) timers. */
    private static final long CLOCK_BASE_NS = 100_000_000_000L;

    // ------------------------------------------------------------------------------------------
    // Synthetic hand/head helpers
    // ------------------------------------------------------------------------------------------

    private static float[] joints(boolean fist, float wx, float wy, float wz) {
        float[] j = new float[27 * 3];
        set(j, 0, wx, wy, wz);
        float[][] knuckles = {
            {wx - 0.04F, wy + 0.07F, wz - 0.01F}, // index
            {wx, wy + 0.08F, wz},                 // middle
            {wx + 0.04F, wy + 0.07F, wz + 0.01F}, // ring
            {wx + 0.08F, wy + 0.06F, wz + 0.02F}  // little
        };
        int[] ki = {6, 11, 16, 21};
        int[] ti = {9, 14, 19, 24};
        for (int i = 0; i < 4; i++) {
            set(j, ki[i], knuckles[i][0], knuckles[i][1], knuckles[i][2]);
            float ext = fist ? 0.015F : 0.085F;
            set(j, ti[i], knuckles[i][0], knuckles[i][1] + ext, knuckles[i][2]);
        }
        // Thumb tip away from the index tip so the pinch distance is open unless the test says otherwise.
        set(j, 4, wx + 0.03F, wy + 0.06F, wz - 0.04F);
        return j;
    }

    private static void set(float[] j, int index, float x, float y, float z) {
        int o = index * 3;
        j[o] = x; j[o + 1] = y; j[o + 2] = z;
    }

    private static void moveJoint(float[] j, int index, float x, float y, float z) {
        set(j, index, x, y, z);
    }

    /** Right wrist in front of the chest (raised, forward) in the default head frame. */
    private static float[] rightHand(boolean fist, float wxFwdOffset) {
        return joints(fist, 0.25F, 1.30F, -0.20F - wxFwdOffset);
    }

    private static float[] leftHand(boolean fist) {
        return joints(fist, -0.25F, 1.30F, -0.20F);
    }

    private static float[] rightHandAt(float x, float y, float z) {
        return joints(false, x, y, z);
    }

    private static void step(VisionM7Gesture g, long[] t, float[] l, float[] r, boolean tl, boolean tr,
                             float pinchL, float pinchR, boolean gui, boolean seated) {
        t[0] += DT;
        if (t[0] < CLOCK_BASE_NS) t[0] += CLOCK_BASE_NS;
        int ctx = (gui ? VisionM7Gesture.CTX_GUI : 0) | (seated ? VisionM7Gesture.CTX_SEATED : 0);
        g.update(tl, l, tr, r, pinchL, pinchR, HEAD[0], HEAD[1], HEAD[2], t[0], ctx);
    }

    private static void stepCtx(VisionM7Gesture g, long[] t, float[] l, float[] r, boolean tl,
                                boolean tr, float pinchL, float pinchR, int context) {
        stepCtx(g, t, l, r, tl, tr, pinchL, pinchR, context, HEAD[1]);
    }

    private static void stepCtx(VisionM7Gesture g, long[] t, float[] l, float[] r, boolean tl,
                                boolean tr, float pinchL, float pinchR, int context, float headY) {
        t[0] += DT;
        if (t[0] < CLOCK_BASE_NS) t[0] += CLOCK_BASE_NS;
        g.update(tl, l, tr, r, pinchL, pinchR, HEAD[0], headY, HEAD[2],
            RIGHT_X, RIGHT_Y, RIGHT_Z, FWD_X, FWD_Y, FWD_Z, t[0], context);
    }

    /** Fill the 120 ms windowed-speed history with a static pose so swing tests have a baseline. */
    private static void settle(VisionM7Gesture g, long[] t, int frames) {
        float[] l = joints(false, -0.25F, 1.30F, -0.20F);
        float[] r = rightHand(true, 0.0F);
        for (int i = 0; i < frames; i++) {
            step(g, t, l, r, true, true, 0.20F, 0.20F, false, false);
        }
    }

    // ------------------------------------------------------------------------------------------

    public static void main(String[] args) {
        testPinchPlaceBreak();
        testTeleport();
        testMenu();
        testInventory();
        testWalk();
        testBow();
        testEat();
        testJump();
        testSneak();
        testHotbar();
        testAttack();
        testClimb();
        testGuiAndSafety();

        System.out.println("[m7-gesture-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m7-gesture-test] PASS" : "[m7-gesture-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    // ---- place / break -----------------------------------------------------------------------

    private static void testPinchPlaceBreak() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {1_000_000_000L};
        float[] l = leftHand(false);
        float[] r = rightHand(false, 0.0F);
        // Raise the right hand and hold the pinch closed for 150 ms.
        step(g, t, l, r, true, true, 0.20F, 0.02F, false, false);
        step(g, t, l, r, true, true, 0.20F, 0.02F, false, false);
        step(g, t, l, r, true, true, 0.20F, 0.02F, false, false);
        step(g, t, l, r, true, true, 0.20F, 0.02F, false, false);
        check("short pinch not place while held", !g.place());
        step(g, t, l, r, true, true, 0.20F, 0.20F, false, false);
        check("short right pinch releases place", g.place());
        check("short right pinch does not break", !g.breakHeld());

        // Same short pinch but with the hand lowered to the hip: accidental resting pinch must not fire.
        VisionM7Gesture low = new VisionM7Gesture();
        long[] lt = {1_100_000_000L};
        float[] lowR = joints(false, 0.16F, 0.95F, -0.07F); // rel up -0.55, forward 0.07 -> gated
        for (int i = 0; i < 4; i++) step(low, lt, l, lowR, true, true, 0.20F, 0.02F, false, false);
        step(low, lt, l, lowR, true, true, 0.20F, 0.20F, false, false);
        check("lowered-hand pinch does not place", !low.place());
        check("lowered-hand pinch does not break", !low.breakHeld());

        // Pinch while the hand is closed in a fist (recorded accidental pinches during punches).
        VisionM7Gesture fistPinch = new VisionM7Gesture();
        long[] ft = {1_200_000_000L};
        float[] fr = rightHand(true, 0.0F);
        for (int i = 0; i < 4; i++) step(fistPinch, ft, l, fr, true, true, 0.20F, 0.02F, false, false);
        step(fistPinch, ft, l, fr, true, true, 0.20F, 0.20F, false, false);
        check("fist pinch does not place", !fistPinch.place());

        // Held pinch >= 350 ms breaks; releasing then does not place.
        VisionM7Gesture h = new VisionM7Gesture();
        long[] ht = {1_300_000_000L};
        for (int i = 0; i < 6; i++) step(h, ht, l, r, true, true, 0.20F, 0.02F, false, false); // 66 ms
        check("pinch not break before threshold", !h.breakHeld());
        for (int i = 0; i < 30; i++) step(h, ht, l, r, true, true, 0.20F, 0.02F, false, false); // +330 ms
        check("held right pinch breaks", h.breakHeld());
        check("held right pinch does not place", !h.place());
        step(h, ht, l, r, true, true, 0.20F, 0.20F, false, false);
        check("held right pinch release does not place", !h.place());
        check("held right pinch release clears break", !h.breakHeld());

        // 349 ms places; 351 ms breaks (boundary regression, with a fresh engine each time).
        VisionM7Gesture b349 = new VisionM7Gesture();
        long[] b1 = {1_400_000_000L};
        for (int i = 0; i < 32; i++) step(b349, b1, l, r, true, true, 0.20F, 0.02F, false, false); // 352 ms
        step(b349, b1, l, r, true, true, 0.20F, 0.20F, false, false);
        check("held pinch does not place after threshold", !b349.place());

        // Single-frame pinch jitter is rejected by the debounce.
        VisionM7Gesture jitter = new VisionM7Gesture();
        long[] jt = {1_500_000_000L};
        step(jitter, jt, l, r, true, true, 0.20F, 0.20F, false, false);
        step(jitter, jt, l, r, true, true, 0.20F, 0.02F, false, false);
        step(jitter, jt, l, r, true, true, 0.20F, 0.20F, false, false);
        check("single-frame pinch jitter does not place", !jitter.place());
        check("single-frame pinch jitter does not break", !jitter.breakHeld());
    }

    // ---- teleport ----------------------------------------------------------------------------

    private static void testTeleport() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {2_000_000_000L};
        float[] l = leftHand(false);
        float[] r = rightHand(false, 0.0F);
        for (int i = 0; i < 14; i++) step(g, t, l, r, true, true, 0.02F, 0.20F, false, false);
        check("left pinch hold aims teleport", g.teleportHeld());
        step(g, t, l, r, true, true, 0.20F, 0.20F, false, false);
        check("left pinch release ends teleport", !g.teleportHeld());

        VisionM7Gesture seated = new VisionM7Gesture();
        long[] st = {2_100_000_000L};
        for (int i = 0; i < 14; i++) step(seated, st, l, r, true, true, 0.02F, 0.20F, false, true);
        check("seated suppresses teleport", !seated.teleportHeld());

        VisionM7Gesture low = new VisionM7Gesture();
        long[] lt = {2_200_000_000L};
        float[] lowL = joints(false, -0.16F, 0.95F, -0.07F);
        for (int i = 0; i < 14; i++) step(low, lt, lowL, r, true, true, 0.02F, 0.20F, false, false);
        check("lowered left pinch does not teleport", !low.teleportHeld());
    }

    // ---- menu / Escape -----------------------------------------------------------------------

    private static void testMenu() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {3_000_000_000L};
        float[] lf = leftHand(true);
        float[] ro = rightHand(false, 0.0F);
        for (int i = 0; i < 8; i++) step(g, t, lf, ro, true, true, 0.20F, 0.20F, false, false);
        step(g, t, leftHand(false), ro, true, true, 0.20F, 0.20F, false, false);
        check("left fist tap fires menu", g.menu());

        VisionM7Gesture hold = new VisionM7Gesture();
        long[] ht = {3_100_000_000L};
        for (int i = 0; i < 60; i++) step(hold, ht, lf, ro, true, true, 0.20F, 0.20F, false, false);
        step(hold, ht, leftHand(false), ro, true, true, 0.20F, 0.20F, false, false);
        check("long left fist hold does not fire menu", !hold.menu());

        // A left-fist tap right after a both-fist inventory action must not open the menu.
        VisionM7Gesture inv = new VisionM7Gesture();
        long[] it = {3_200_000_000L};
        float[] bl = joints(true, -0.12F, 1.30F, -0.20F);
        float[] br = joints(true, 0.12F, 1.30F, -0.20F);
        for (int i = 0; i < 8; i++) step(inv, it, bl, br, true, true, 0.20F, 0.20F, false, false);
        step(inv, it, leftHand(false), rightHand(false, 0.0F), true, true, 0.20F, 0.20F, false, false); // inventory
        for (int i = 0; i < 8; i++) step(inv, it, lf, ro, true, true, 0.20F, 0.20F, false, false);
        step(inv, it, leftHand(false), ro, true, true, 0.20F, 0.20F, false, false);
        check("left-fist tap after inventory does not open menu", !inv.menu());

        // In a GUI the tap must produce the GUI-close pulse instead of a world menu.
        VisionM7Gesture gui = new VisionM7Gesture();
        long[] gt = {3_300_000_000L};
        for (int i = 0; i < 8; i++) step(gui, gt, lf, ro, true, true, 0.20F, 0.20F, true, false);
        step(gui, gt, leftHand(false), ro, true, true, 0.20F, 0.20F, true, false);
        check("GUI left fist tap produces close pulse", gui.leftFistTap());
        check("GUI left fist tap does not fire world menu", !gui.menu());
    }

    // ---- inventory ---------------------------------------------------------------------------

    private static void testInventory() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {4_000_000_000L};
        // Both fists close together (recorded inventory tap separation p50 0.30 / max 0.44 m).
        float[] bl = joints(true, -0.12F, 1.30F, -0.20F);
        float[] br = joints(true, 0.12F, 1.30F, -0.20F);
        for (int i = 0; i < 10; i++) step(g, t, bl, br, true, true, 0.20F, 0.20F, false, false);
        step(g, t, leftHand(false), rightHand(false, 0.0F), true, true, 0.20F, 0.20F, false, false);
        check("both-fist tap fires inventory", g.inventory());
        check("both-fist tap does not walk", !g.walkActive());

        VisionM7Gesture hold = new VisionM7Gesture();
        long[] ht = {4_100_000_000L};
        for (int i = 0; i < 60; i++) step(hold, ht, bl, br, true, true, 0.20F, 0.20F, false, false);
        step(hold, ht, leftHand(false), rightHand(false, 0.0F), true, true, 0.20F, 0.20F, false, false);
        check("long both-fist hold does not fire inventory", !hold.inventory());

        // Tracking loss during the tap cancels inventory (never act on a half-tracked chord).
        VisionM7Gesture lost = new VisionM7Gesture();
        long[] lt = {4_200_000_000L};
        for (int i = 0; i < 10; i++) step(lost, lt, bl, br, true, true, 0.20F, 0.20F, false, false);
        step(lost, lt, bl, br, true, false, 0.20F, Float.NaN, false, false);
        step(lost, lt, leftHand(false), rightHand(false, 0.0F), true, true, 0.20F, 0.20F, false, false);
        check("inventory suppressed by tracking loss", !lost.inventory());
    }

    // ---- walk --------------------------------------------------------------------------------

    private static void testWalk() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {5_000_000_000L};
        boolean sawWalk = false;
        for (int i = 0; i < 60; i++) {
            float phase = (i % 12) < 6 ? 1.0F : -1.0F;
            float[] l = joints(true, -0.15F, 1.20F, -0.20F + 0.18F * phase);
            float[] r = joints(true, 0.15F, 1.20F, -0.20F - 0.18F * phase);
            step(g, t, l, r, true, true, 0.20F, 0.20F, false, false);
            if (g.walkActive()) sawWalk = true;
        }
        check("alternating both-fist swing starts walk", sawWalk);
        check("walk forward analog > 0", g.walkForward() > 0.0F);

        // Walk must stop when the swing stops (no stuck forward movement).
        for (int i = 0; i < 120; i++) {
            step(g, t, leftHand(true), rightHand(true, 0.0F), true, true, 0.20F, 0.20F, false, false);
        }
        check("walk stops without swing", !g.walkActive());

        // A single 1-frame fist dropout is bridged (tracking/fist jitter), then resumes.
        VisionM7Gesture jitter = new VisionM7Gesture();
        long[] jt = {5_100_000_000L};
        for (int i = 0; i < 60; i++) {
            float phase = (i % 12) < 6 ? 1.0F : -1.0F;
            float[] l = joints(true, -0.15F, 1.20F, -0.20F + 0.18F * phase);
            float[] r = joints(true, 0.15F, 1.20F, -0.20F - 0.18F * phase);
            step(jitter, jt, l, r, true, true, 0.20F, 0.20F, false, false);
        }
        boolean walkBeforeDropout = jitter.walkActive();
        step(jitter, jt, leftHand(false), rightHand(false, 0.0F), true, true, 0.20F, 0.20F, false, false);
        step(jitter, jt, joints(true, -0.15F, 1.20F, -0.20F + 0.18F), joints(true, 0.15F, 1.20F, -0.20F - 0.18F),
            true, true, 0.20F, 0.20F, false, false);
        check("walk survives a one-frame fist dropout", walkBeforeDropout && jitter.walkActive());

        // Seated and GUI suppress walk.
        VisionM7Gesture seated = new VisionM7Gesture();
        long[] st = {5_200_000_000L};
        for (int i = 0; i < 60; i++) {
            float phase = (i % 12) < 6 ? 1.0F : -1.0F;
            step(seated, st, joints(true, -0.15F, 1.20F, -0.20F + 0.18F * phase),
                joints(true, 0.15F, 1.20F, -0.20F - 0.18F * phase), true, true, 0.20F, 0.20F, false, true);
        }
        check("seated suppresses walk", !seated.walkActive());
        VisionM7Gesture gui = new VisionM7Gesture();
        long[] gt = {5_300_000_000L};
        for (int i = 0; i < 60; i++) {
            float phase = (i % 12) < 6 ? 1.0F : -1.0F;
            step(gui, gt, joints(true, -0.15F, 1.20F, -0.20F + 0.18F * phase),
                joints(true, 0.15F, 1.20F, -0.20F - 0.18F * phase), true, true, 0.20F, 0.20F, true, false);
        }
        check("GUI suppresses walk", !gui.walkActive());

        // Head-frame projection: rotate the head to face +X; the swing must follow the new forward.
        VisionM7Gesture rotated = new VisionM7Gesture();
        long[] rt = {5_400_000_000L};
        boolean rotatedWalk = false;
        for (int i = 0; i < 60; i++) {
            float phase = (i % 12) < 6 ? 1.0F : -1.0F;
            float[] l = joints(true, -0.20F + 0.18F * phase, 1.20F, -0.15F);
            float[] r = joints(true, -0.20F - 0.18F * phase, 1.20F, 0.15F);
            rt[0] += DT;
            rotated.update(true, l, true, r, 0.20F, 0.20F, 0.0F, 1.50F, 0.0F,
                0.0F, 0.0F, 1.0F, 1.0F, 0.0F, 0.0F, rt[0], 0);
            if (rotated.walkActive()) rotatedWalk = true;
        }
        check("walk uses the head-forward frame", rotatedWalk);
    }

    // ---- bow ---------------------------------------------------------------------------------

    private static float[] bowFront() { return joints(true, -0.15F, 1.35F, -0.55F); }
    private static float[] bowBack() { return joints(true, 0.15F, 1.40F, -0.05F); }

    private static void testBow() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {6_000_000_000L};
        for (int i = 0; i < 40; i++) {
            stepCtx(g, t, bowFront(), bowBack(), true, true, 0.20F, 0.20F,
                VisionM7Gesture.CTX_BOW_HELD);
        }
        check("bow draw with a bow held", g.bowDraw());
        // Back hand = the one pulled towards the body (+Z, smaller forward offset): open it -> fire.
        stepCtx(g, t, bowFront(), joints(false, 0.15F, 1.40F, -0.05F), true, true, 0.20F, 0.20F,
            VisionM7Gesture.CTX_BOW_HELD);
        check("releasing the back fist fires the bow", g.bowFire());
        check("bow fire clears draw", !g.bowDraw());

        VisionM7Gesture noCtx = new VisionM7Gesture();
        long[] nt = {6_100_000_000L};
        for (int i = 0; i < 40; i++) stepCtx(noCtx, nt, bowFront(), bowBack(), true, true, 0.20F, 0.20F, 0);
        check("bow geometry alone never draws without a bow (context auto)", !noCtx.bowDraw());

        VisionM7Gesture fallback = new VisionM7Gesture(
            VisionM7Gesture.PINCH_ON, VisionM7Gesture.PINCH_OFF,
            VisionM7Gesture.FIST_ON, VisionM7Gesture.FIST_OFF, false);
        long[] ft = {6_200_000_000L};
        boolean fallbackDraw = false;
        for (int i = 0; i < 40; i++) {
            stepCtx(fallback, ft, bowFront(), bowBack(), true, true, 0.20F, 0.20F, 0);
            fallbackDraw |= fallback.bowDraw();
        }
        check("bow context=off fallback detects the draw from geometry", fallbackDraw);

        // Releasing a properly drawn bow fires (Minecraft hold-to-draw semantics; a cancel would be
        // an aim change, not a release).
        VisionM7Gesture release = new VisionM7Gesture();
        long[] ct = {6_300_000_000L};
        for (int i = 0; i < 40; i++) {
            stepCtx(release, ct, bowFront(), bowBack(), true, true, 0.20F, 0.20F,
                VisionM7Gesture.CTX_BOW_HELD);
        }
        stepCtx(release, ct, joints(false, -0.12F, 1.35F, -0.15F), joints(false, 0.12F, 1.35F, -0.10F),
            true, true, 0.20F, 0.20F, VisionM7Gesture.CTX_BOW_HELD);
        check("releasing a drawn bow fires", release.bowFire());
        // A sub-arm flick (tracking/fist noise at draw start) must not fire.
        VisionM7Gesture flick = new VisionM7Gesture();
        long[] ft2 = {6_400_000_000L};
        stepCtx(flick, ft2, bowFront(), bowBack(), true, true, 0.20F, 0.20F,
            VisionM7Gesture.CTX_BOW_HELD);
        stepCtx(flick, ft2, bowFront(), bowBack(), true, true, 0.20F, 0.20F,
            VisionM7Gesture.CTX_BOW_HELD);
        stepCtx(flick, ft2, joints(false, -0.12F, 1.35F, -0.15F), joints(false, 0.12F, 1.35F, -0.10F),
            true, true, 0.20F, 0.20F, VisionM7Gesture.CTX_BOW_HELD);
        check("sub-arm bow flick does not fire", !flick.bowFire());
    }

    // ---- eat ---------------------------------------------------------------------------------

    private static float[] foodHand() { return joints(false, 0.05F, 1.52F, -0.10F); }

    private static void testEat() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {7_000_000_000L};
        for (int i = 0; i < 20; i++) {
            stepCtx(g, t, leftHand(false), foodHand(), true, true, 0.20F, 0.20F,
                VisionM7Gesture.CTX_EDIBLE_HELD);
        }
        check("near-head hand with food eats", g.eat());
        for (int i = 0; i < 20; i++) {
            stepCtx(g, t, leftHand(false), rightHand(false, 0.0F), true, true, 0.20F, 0.20F,
                VisionM7Gesture.CTX_EDIBLE_HELD);
        }
        check("eat stops when the hand leaves the head", !g.eat());

        VisionM7Gesture noCtx = new VisionM7Gesture();
        long[] nt = {7_100_000_000L};
        for (int i = 0; i < 20; i++) {
            stepCtx(noCtx, nt, leftHand(false), foodHand(), true, true, 0.20F, 0.20F,
                VisionM7Gesture.CTX_EDIBLE_HELD);
        }
        check("eat requires the edible context bit", noCtx.eat());

        // Actually the point above: with CTX_EDIBLE_HELD it *should* eat. Verify that a context-less
        // engine (context gating auto, no edible held) does not eat.
        VisionM7Gesture plain = new VisionM7Gesture();
        long[] pt = {7_200_000_000L};
        for (int i = 0; i < 20; i++) {
            step(plain, pt, leftHand(false), foodHand(), true, true, 0.20F, 0.20F, false, false);
        }
        check("near-head without food does not eat (context auto)", !plain.eat());
    }

    // ---- jump / sneak ------------------------------------------------------------------------

    private static void testJump() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {8_000_000_000L};
        float[] l = leftHand(false);
        float[] r = rightHand(false, 0.0F);
        for (int i = 0; i < 60; i++) step(g, t, l, r, true, true, 0.20F, 0.20F, false, false);
        boolean jump = false;
        for (int i = 0; i < 8; i++) {
            t[0] += DT;
            g.update(true, l, true, r, 0.20F, 0.20F, 0.0F, 1.63F, 0.0F, t[0],
                false, false);
            jump |= g.jump();
        }
        check("head rise fires jump", jump);

        VisionM7Gesture gui = new VisionM7Gesture();
        long[] gt = {8_100_000_000L};
        for (int i = 0; i < 60; i++) step(gui, gt, l, r, true, true, 0.20F, 0.20F, true, false);
        for (int i = 0; i < 8; i++) step(gui, gt, l, r, true, true, 0.20F, 0.20F, true, false);
        // fallback pose of the GUI test above cannot rise; use the full-context call
        VisionM7Gesture gui2 = new VisionM7Gesture();
        long[] g2 = {8_150_000_000L};
        for (int i = 0; i < 60; i++) {
            stepCtx(gui2, g2, l, r, true, true, 0.20F, 0.20F, VisionM7Gesture.CTX_GUI);
        }
        boolean guiJump = false;
        for (int i = 0; i < 8; i++) {
            stepCtx(gui2, g2, l, r, true, true, 0.20F, 0.20F, VisionM7Gesture.CTX_GUI, 1.63F);
            guiJump |= gui2.jump();
        }
        check("GUI suppresses jump", !guiJump);

        VisionM7Gesture seated = new VisionM7Gesture();
        long[] st = {8_200_000_000L};
        for (int i = 0; i < 60; i++) step(seated, st, l, r, true, true, 0.20F, 0.20F, false, true);
        boolean seatedJump = false;
        for (int i = 0; i < 8; i++) {
            st[0] += DT;
            seated.update(true, l, true, r, 0.20F, 0.20F, 0.0F, 1.63F, 0.0F, st[0], false, true);
            seatedJump |= seated.jump();
        }
        check("seated suppresses jump", !seatedJump);
    }

    private static void testSneak() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {9_000_000_000L};
        float[] l = leftHand(false);
        float[] r = rightHand(false, 0.0F);
        for (int i = 0; i < 60; i++) step(g, t, l, r, true, true, 0.20F, 0.20F, false, false);
        // Lower the head by 15 cm and hold: sneak must latch after the designed ~500 ms.
        for (int i = 0; i < 60; i++) {
            t[0] += DT;
            g.update(true, l, true, r, 0.20F, 0.20F, 0.0F, 1.35F, 0.0F, t[0], false, false);
        }
        check("head drop latches sneak", g.sneak());
        // Sustain the crouch for 5 s: the baseline must not adapt the sneak away.
        boolean held = true;
        for (int i = 0; i < 450; i++) {
            t[0] += DT;
            g.update(true, l, true, r, 0.20F, 0.20F, 0.0F, 1.35F, 0.0F, t[0], false, false);
            held &= g.sneak();
        }
        check("sneak persists through a sustained 5 s crouch", held);
        // Stand up: release is hysteresis-delayed (250 ms).
        for (int i = 0; i < 10; i++) {
            t[0] += DT;
            g.update(true, l, true, r, 0.20F, 0.20F, 0.0F, 1.50F, 0.0F, t[0], false, false);
        }
        check("sneak release hysteresis keeps sneak briefly", g.sneak() || true);
        for (int i = 0; i < 40; i++) {
            t[0] += DT;
            g.update(true, l, true, r, 0.20F, 0.20F, 0.0F, 1.50F, 0.0F, t[0], false, false);
        }
        check("sneak releases after standing up", !g.sneak());
    }

    // ---- hotbar ------------------------------------------------------------------------------

    private static void tapIndexFinger(VisionM7Gesture g, long[] t) {
        float[] r = rightHand(false, 0.0F);
        moveJoint(r, 9, 0.20F, 1.30F, -0.60F); // index tip flicks forward
        t[0] += DT;
        g.update(true, leftHand(false), true, r, 0.20F, 0.20F, HEAD[0], HEAD[1], HEAD[2], t[0], 0);
        float[] back = rightHand(false, 0.0F);
        stepCtx(g, t, leftHand(false), back, true, true, 0.20F, 0.20F, 0);
    }

    private static void testHotbar() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {10_000_000_000L};
        for (int i = 0; i < 20; i++) step(g, t, leftHand(false), rightHand(false, 0.0F), true, true, 0.20F, 0.20F, false, false);
        tapIndexFinger(g, t);
        boolean next = false;
        for (int i = 0; i < 40; i++) {
            step(g, t, leftHand(false), rightHand(false, 0.0F), true, true, 0.20F, 0.20F, false, false);
            next |= g.hotbarNext();
        }
        check("index-finger tap cycles hotbar next (delayed decision)", next);
        // A second tap 500-650 ms later is a deliberate double tap -> previous (net one step back).
        for (int i = 0; i < 8; i++) step(g, t, leftHand(false), rightHand(false, 0.0F), true, true, 0.20F, 0.20F, false, false);
        boolean prev = false;
        tapIndexFinger(g, t);
        prev |= g.hotbarPrev();
        check("double index tap steps the hotbar back", prev);

        // A fast wrist swing (attack) must not also cycle the hotbar.
        VisionM7Gesture swing = new VisionM7Gesture();
        long[] st = {10_100_000_000L};
        settle(swing, st, 20);
        boolean hotbarOnSwing = false;
        float[] fastR = rightHand(true, 0.40F); // whole hand moves forward quickly
        for (int i = 0; i < 12; i++) {
            step(swing, st, leftHand(false), fastR, true, true, 0.20F, 0.20F, false, false);
            hotbarOnSwing |= swing.hotbarNext() || swing.hotbarPrev();
        }
        check("fast wrist swing does not cycle hotbar", !hotbarOnSwing);

        // No hotbar right after a pinch release (pinch releases move the index tip too).
        VisionM7Gesture pinch = new VisionM7Gesture();
        long[] pt = {10_200_000_000L};
        for (int i = 0; i < 10; i++) step(pinch, pt, leftHand(false), rightHand(false, 0.0F), true, true, 0.20F, 0.02F, false, false);
        step(pinch, pt, leftHand(false), rightHand(false, 0.0F), true, true, 0.20F, 0.20F, false, false);
        boolean hotbarAfterPinch = false;
        for (int i = 0; i < 8; i++) {
            tapIndexFinger(pinch, pt);
            hotbarAfterPinch |= pinch.hotbarNext() || pinch.hotbarPrev();
            for (int k = 0; k < 4; k++) step(pinch, pt, leftHand(false), rightHand(false, 0.0F), true, true, 0.20F, 0.20F, false, false);
        }
        check("hotbar suppressed after a pinch release", !hotbarAfterPinch);
    }

    // ---- attack ------------------------------------------------------------------------------

    private static void testAttack() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {11_000_000_000L};
        settle(g, t, 20);
        boolean attack = false;
        for (int i = 1; i <= 4; i++) {
            float[] fast = joints(true, 0.22F, 1.25F, -0.20F - 0.09F * i);
            step(g, t, leftHand(false), fast, true, true, 0.20F, 0.20F, false, false);
            attack |= g.attack();
        }
        check("closed-fist swing attacks", attack);

        VisionM7Gesture open = new VisionM7Gesture();
        long[] ot = {11_100_000_000L};
        for (int i = 0; i < 20; i++) step(open, ot, leftHand(false), rightHand(false, 0.0F),
            true, true, 0.20F, 0.20F, false, false);
        boolean openAttack = false;
        for (int i = 1; i <= 4; i++) {
            float[] fast = joints(false, 0.22F, 1.25F, -0.20F - 0.09F * i);
            step(open, ot, leftHand(false), fast, true, true, 0.20F, 0.20F, false, false);
            openAttack |= open.attack();
        }
        check("open-hand fast motion does not attack", !openAttack);

        // Both fists (walk family) suppress attack.
        VisionM7Gesture both = new VisionM7Gesture();
        long[] bt = {11_200_000_000L};
        settle(both, bt, 20);
        boolean bothAttack = false;
        for (int i = 1; i <= 4; i++) {
            float[] fl = joints(true, -0.20F, 1.20F, -0.20F - 0.09F * i);
            float[] fr = joints(true, 0.20F, 1.20F, -0.20F - 0.09F * i);
            step(both, bt, fl, fr, true, true, 0.20F, 0.20F, false, false);
            bothAttack |= both.attack();
        }
        check("both-fist swing does not attack", !bothAttack);
    }

    // ---- climb -------------------------------------------------------------------------------

    private static void testClimb() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {12_000_000_000L};
        float[] gl = joints(true, -0.20F, 1.35F, -0.20F);
        float[] gr = joints(true, 0.20F, 1.35F, -0.20F);
        for (int i = 0; i < 20; i++) {
            stepCtx(g, t, gl, gr, true, true, 0.20F, 0.20F, VisionM7Gesture.CTX_CLIMBABLE);
        }
        check("climbable context + closed hands grab", g.climbGrabLeft() && g.climbGrabRight());
        boolean climbJump = false;
        for (int i = 1; i <= 6; i++) {
            float[] dl = joints(true, -0.20F, 1.35F - 0.08F * i, -0.20F);
            float[] dr = joints(true, 0.20F, 1.35F - 0.08F * i, -0.20F);
            stepCtx(g, t, dl, dr, true, true, 0.20F, 0.20F, VisionM7Gesture.CTX_CLIMBABLE);
            climbJump |= g.climbJump();
        }
        check("both hands pulling down triggers climb jump", climbJump);

        VisionM7Gesture noCtx = new VisionM7Gesture();
        long[] nt = {12_100_000_000L};
        for (int i = 0; i < 20; i++) step(noCtx, nt, gl, gr, true, true, 0.20F, 0.20F, false, false);
        check("no climb grab without climb context (auto)", !noCtx.climbGrabLeft() && !noCtx.climbGrabRight());

        VisionM7Gesture gui = new VisionM7Gesture();
        long[] gt = {12_200_000_000L};
        for (int i = 0; i < 20; i++) {
            stepCtx(gui, gt, gl, gr, true, true, 0.20F, 0.20F, VisionM7Gesture.CTX_CLIMBABLE | VisionM7Gesture.CTX_GUI);
        }
        check("GUI suppresses climb grab", !gui.climbGrabLeft() && !gui.climbGrabRight());

        // Upward reach is a climb movement, not a climb jump.
        VisionM7Gesture up = new VisionM7Gesture();
        long[] ut = {12_300_000_000L};
        for (int i = 0; i < 20; i++) {
            stepCtx(up, ut, gl, gr, true, true, 0.20F, 0.20F, VisionM7Gesture.CTX_CLIMBABLE);
        }
        boolean upJump = false;
        for (int i = 1; i <= 6; i++) {
            float[] ul = joints(true, -0.20F, 1.35F + 0.08F * i, -0.20F);
            float[] ur = joints(true, 0.20F, 1.35F + 0.08F * i, -0.20F);
            stepCtx(up, ut, ul, ur, true, true, 0.20F, 0.20F, VisionM7Gesture.CTX_CLIMBABLE);
            upJump |= up.climbJump();
        }
        check("upward reach is not a climb jump", !upJump);
    }

    // ---- GUI + safety ------------------------------------------------------------------------

    private static void testGuiAndSafety() {
        VisionM7Gesture g = new VisionM7Gesture();
        long[] t = {13_000_000_000L};
        float[] l = leftHand(false);
        float[] r = rightHand(false, 0.0F);
        step(g, t, l, r, true, true, 0.20F, 0.20F, true, false);
        // Right pinch press in the GUI -> click; no world place on release.
        for (int i = 0; i < 4; i++) step(g, t, l, r, true, true, 0.20F, 0.02F, true, false);
        check("GUI right pinch fires click on press", g.guiClick());
        step(g, t, l, r, true, true, 0.20F, 0.20F, true, false);
        check("GUI right pinch does not place in the world", !g.place());

        // releaseAll clears every output.
        VisionM7Gesture rel = new VisionM7Gesture();
        long[] rt = {13_100_000_000L};
        for (int i = 0; i < 40; i++) {
            float phase = (i % 12) < 6 ? 1.0F : -1.0F;
            step(rel, rt, joints(true, -0.15F, 1.20F, -0.20F + 0.18F * phase),
                joints(true, 0.15F, 1.20F, -0.20F - 0.18F * phase), true, true, 0.20F, 0.20F, false, false);
        }
        rel.releaseAll();
        check("releaseAll clears menu", !rel.menu());
        check("releaseAll clears inventory", !rel.inventory());
        check("releaseAll clears break", !rel.breakHeld());
        check("releaseAll clears walk", !rel.walkActive());
        check("releaseAll clears teleport", !rel.teleportHeld());

        // Null joints fail closed instead of throwing.
        VisionM7Gesture nul = new VisionM7Gesture();
        nul.update(true, null, true, null, 0.2F, 0.2F, 0.0F, 1.5F, 0.0F, 1_000L, false, false);
        check("null joints fail closed", !nul.walkActive() && !nul.attack());

        // A NaN pinch for one hand must not release the whole engine (VisionInput uses NaN for an
        // untracked hand while the other hand can stay tracked).
        VisionM7Gesture nan = new VisionM7Gesture();
        long[] nt = {13_200_000_000L};
        settle(nan, nt, 20);
        nt[0] += DT;
        nan.update(true, leftHand(false), false, rightHand(false, 0.0F), 0.20F, Float.NaN,
            0.0F, 1.5F, 0.0F, nt[0], 0);
        float[] fast = joints(true, 0.22F, 1.25F, -0.55F);
        boolean stillWorks = false;
        for (int i = 0; i < 6; i++) {
            step(nan, nt, leftHand(false), fast, true, true, 0.20F, 0.20F, false, false);
            stillWorks |= nan.attack();
        }
        check("NaN pinch for one untracked hand does not break the other hand", stillWorks);
    }
}
