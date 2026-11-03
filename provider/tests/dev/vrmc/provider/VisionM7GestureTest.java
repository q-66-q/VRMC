package dev.vrmc.provider;

import java.util.Arrays;

/** Host tests for the pure M7 gesture engine using synthetic 27-joint hands/head poses. */
public final class VisionM7GestureTest {
    private static int checks;
    private static int failures;
    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    private static final float[] HEAD = {0.0F, 1.50F, 0.0F};

    private static float[] joints(boolean fist, float wx, float wy, float wz) {
        float[] j = new float[27 * 3];
        // Wrist.
        set(j, 0, wx, wy, wz);
        // Knuckles around a small palm.
        float[][] knuckles = {
            {wx - 0.04F, wy + 0.07F, wz - 0.01F}, // index
            {wx, wy + 0.08F, wz},                  // middle
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
        // Thumb tip: open a little so pinch is controlled by the caller.
        set(j, 4, wx + 0.03F, wy + 0.06F, wz - 0.04F);
        return j;
    }

    private static void set(float[] j, int index, float x, float y, float z) {
        int o = index * 3;
        j[o] = x; j[o + 1] = y; j[o + 2] = z;
    }

    private static void moveIndexTip(float[] j, float x, float y, float z) {
        set(j, 9, x, y, z);
    }

    private static void update(VisionM7Gesture g, float[] l, float[] r, boolean tl, boolean tr,
                               float pinchL, float pinchR, float hx, float hy, float hz,
                               long ns, boolean gui, boolean seated) {
        g.update(tl, l, tr, r, pinchL, pinchR, hx, hy, hz, ns, gui, seated);
    }

    public static void main(String[] args) {
        testPlaceVsBreak();
        testLeftFistMenu();
        testInventory();
        testWalk();
        testJumpAndSneak();
        testHotbar();
        testBowAndEat();
        testGui();
        testSeatedAndRelease();

        System.out.println("[m7-gesture-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m7-gesture-test] PASS" : "[m7-gesture-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    private static void testPlaceVsBreak() {
        VisionM7Gesture g = new VisionM7Gesture();
        float[] l = joints(false, -0.25F, 1.2F, -0.2F);
        float[] r = joints(false, 0.25F, 1.2F, -0.2F);
        long t = 1_000_000_000L;
        // Pinch closed.
        update(g, l, r, true, true, 0.02F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        check("short pinch not place while held", !g.place());
        // Release after 150 ms -> place pulse.
        t += 150_000_000L;
        update(g, l, r, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        check("short right pinch releases place", g.place());
        check("short right pinch does not break", !g.breakHeld());
        // New hold >350 ms -> break held, no place on release.
        VisionM7Gesture h = new VisionM7Gesture();
        long u = 2_000_000_000L;
        update(h, l, r, true, true, 0.02F, 0.02F, HEAD[0], HEAD[1], HEAD[2], u, false, false);
        u += 500_000_000L;
        update(h, l, r, true, true, 0.02F, 0.02F, HEAD[0], HEAD[1], HEAD[2], u, false, false);
        check("held right pinch breaks", h.breakHeld());
        update(h, l, r, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], u + 60_000_000L, false, false);
        check("held right pinch does not place", !h.place());
    }

    private static void testLeftFistMenu() {
        VisionM7Gesture g = new VisionM7Gesture();
        float[] l = joints(true, -0.25F, 1.2F, -0.2F);
        float[] r = joints(false, 0.25F, 1.2F, -0.2F);
        long t = 3_000_000_000L;
        update(g, l, r, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        t += 120_000_000L;
        update(g, l, r, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        // Open left fist.
        float[] openL = joints(false, -0.25F, 1.2F, -0.2F);
        update(g, openL, r, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 80_000_000L, false, false);
        check("left fist tap fires menu", g.menu());
    }

    private static void testInventory() {
        VisionM7Gesture g = new VisionM7Gesture();
        float[] l = joints(true, -0.12F, 1.2F, -0.2F);
        float[] r = joints(true, 0.12F, 1.2F, -0.2F);
        long t = 4_000_000_000L;
        update(g, l, r, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        t += 150_000_000L;
        update(g, l, r, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        update(g, joints(false, -0.12F, 1.2F, -0.2F), joints(false, 0.12F, 1.2F, -0.2F),
            true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 80_000_000L, false, false);
        check("both-fist tap fires inventory", g.inventory());
        check("both-fist tap does not walk", !g.walkActive());
    }

    private static void testWalk() {
        VisionM7Gesture g = new VisionM7Gesture();
        long t = 5_000_000_000L;
        boolean sawWalk = false;
        for (int i = 0; i < 40; i++) {
            float phase = (i % 10) < 5 ? 1.0F : -1.0F;
            float[] l = joints(true, -0.15F, 1.2F, -0.2F + 0.18F * phase);
            float[] r = joints(true, 0.15F, 1.2F, -0.2F - 0.18F * phase);
            update(g, l, r, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
            if (g.walkActive()) sawWalk = true;
            t += 50_000_000L;
        }
        check("alternating both-fist swing starts walk", sawWalk);
        check("walk forward analog > 0", g.walkForward() > 0.0F);
    }

    private static void testJumpAndSneak() {
        VisionM7Gesture g = new VisionM7Gesture();
        float[] l = joints(false, -0.25F, 1.2F, -0.2F);
        float[] r = joints(false, 0.25F, 1.2F, -0.2F);
        long t = 6_000_000_000L;
        for (int i = 0; i < 10; i++) {
            update(g, l, r, true, true, 0.2F, 0.2F, 0, 1.5F, 0, t, false, false);
            t += 16_000_000L;
        }
        boolean jump = false;
        for (int i = 0; i < 5; i++) {
            update(g, l, r, true, true, 0.2F, 0.2F, 0, 1.65F, 0, t, false, false);
            if (g.jump()) jump = true;
            t += 16_000_000L;
        }
        check("head rise fires jump", jump);
        // Lower and hold.
        VisionM7Gesture s = new VisionM7Gesture();
        long u = 7_000_000_000L;
        for (int i = 0; i < 10; i++) {
            update(s, l, r, true, true, 0.2F, 0.2F, 0, 1.5F, 0, u, false, false);
            u += 16_000_000L;
        }
        for (int i = 0; i < 30; i++) {
            update(s, l, r, true, true, 0.2F, 0.2F, 0, 1.30F, 0, u, false, false);
            u += 16_000_000L;
        }
        check("head drop latches sneak", s.sneak());
    }

    private static void testHotbar() {
        VisionM7Gesture g = new VisionM7Gesture();
        long t = 8_000_000_000L;
        for (int i = 0; i < 6; i++) {
            float[] r = joints(false, 0.2F, 1.3F, -0.2F);
            moveIndexTip(r, 0.2F + 0.10F * i, 1.3F, -0.2F);
            update(g, joints(false, -0.2F, 1.3F, -0.2F), r, true, true, 0.2F, 0.2F,
                HEAD[0], HEAD[1], HEAD[2], t, false, false);
            t += 16_000_000L;
        }
        check("index-finger tap fires hotbar next", g.hotbarNext());
    }

    private static void testBowAndEat() {
        VisionM7Gesture g = new VisionM7Gesture();
        float[] l = joints(true, -0.35F, 1.25F, -0.1F);
        float[] r = joints(true, 0.35F, 1.15F, -0.1F);
        update(g, l, r, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], 9_000_000_000L, false, false);
        check("wide both fists = bow draw", g.bowDraw());
        VisionM7Gesture e = new VisionM7Gesture();
        float[] er = joints(false, 0.05F, 1.52F, 0.10F);
        update(e, joints(false, -0.2F, 1.2F, -0.2F), er, true, true, 0.2F, 0.2F,
            HEAD[0], HEAD[1], HEAD[2], 9_100_000_000L, false, false);
        check("right hand near head = eat", e.eat());
    }

    private static void testGui() {
        VisionM7Gesture g = new VisionM7Gesture();
        long t = 10_000_000_000L;
        float[] l = joints(false, -0.25F, 1.2F, -0.2F);
        float[] r = joints(false, 0.25F, 1.2F, -0.2F);
        update(g, l, r, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, true, false);
        update(g, l, r, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 16_000_000L, true, false);
        check("GUI right pinch fires click", g.guiClick());
        check("GUI suppresses world place", !g.place());
        VisionM7Gesture m = new VisionM7Gesture();
        long u = 10_100_000_000L;
        update(m, joints(true, -0.25F, 1.2F, -0.2F), r, true, true, 0.2F, 0.2F,
            HEAD[0], HEAD[1], HEAD[2], u, true, false);
        update(m, joints(false, -0.25F, 1.2F, -0.2F), r, true, true, 0.2F, 0.2F,
            HEAD[0], HEAD[1], HEAD[2], u + 100_000_000L, true, false);
        check("GUI left fist taps menu/escape", m.menu());
    }

    private static void testSeatedAndRelease() {
        VisionM7Gesture g = new VisionM7Gesture();
        float[] l = joints(true, -0.2F, 1.2F, -0.2F);
        float[] r = joints(true, 0.2F, 1.2F, -0.2F);
        long t = 11_000_000_000L;
        for (int i = 0; i < 5; i++) {
            update(g, l, r, true, true, 0.02F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t, false, true);
            t += 50_000_000L;
        }
        check("seated suppresses walk", !g.walkActive());
        check("seated suppresses teleport", !g.teleportHeld());
        g.releaseAll();
        check("release clears menu", !g.menu());
        check("release clears inventory", !g.inventory());
        check("release clears break", !g.breakHeld());
    }
}
