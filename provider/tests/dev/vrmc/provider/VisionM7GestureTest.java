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
        testAdjacentPriorities();
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
        // Pinch closed (two frames: debounce window).
        update(g, l, r, true, true, 0.02F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        update(g, l, r, true, true, 0.02F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 20_000_000L, false, false);
        update(g, l, r, true, true, 0.02F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 60_000_000L, false, false);
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
        update(h, l, r, true, true, 0.02F, 0.02F, HEAD[0], HEAD[1], HEAD[2], u + 20_000_000L, false, false);
        update(h, l, r, true, true, 0.02F, 0.02F, HEAD[0], HEAD[1], HEAD[2], u + 60_000_000L, false, false);
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
        update(g, l, r, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 80_000_000L, true, false);
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

    private static void testAdjacentPriorities() {
        long t = 12_000_000_000L;
        float[] bothL = joints(true, -0.12F, 1.2F, -0.2F);
        float[] bothR = joints(true, 0.12F, 1.2F, -0.2F);
        float[] openL = joints(false, -0.12F, 1.2F, -0.2F);
        float[] openR = joints(false, 0.12F, 1.2F, -0.2F);

        // GUI open + both fists must not open inventory.
        VisionM7Gesture gui = new VisionM7Gesture();
        update(gui, bothL, bothR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, true, false);
        update(gui, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 100_000_000L, true, false);
        check("GUI + both fists suppresses inventory", !gui.inventory());
        check("GUI + both fists suppresses walk", !gui.walkActive());

        // Bow + both fists must not open inventory.
        VisionM7Gesture bow = new VisionM7Gesture();
        float[] bowL = joints(true, -0.35F, 1.25F, -0.1F);
        float[] bowR = joints(true, 0.35F, 1.15F, -0.1F);
        update(bow, bowL, bowR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        update(bow, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 80_000_000L, false, false);
        check("bow + both fists suppresses inventory", !bow.inventory());
        check("bow + both fists suppresses walk", !bow.walkActive());
        check("bow release fires", bow.bowFire());

        // Climb + both fists must not open inventory.
        VisionM7Gesture climb = new VisionM7Gesture();
        float[] climbL = joints(true, -0.25F, 1.62F, -0.2F);
        float[] climbR = joints(true, 0.25F, 1.62F, -0.2F);
        update(climb, climbL, climbR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        update(climb, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 80_000_000L, false, false);
        check("climb + both fists suppresses inventory", !climb.inventory());
        check("climb + both fists suppresses walk", !climb.walkActive());

        // Sustained walk + both fists must not open inventory on release.
        VisionM7Gesture walk = new VisionM7Gesture();
        long w = 13_000_000_000L;
        for (int i = 0; i < 30; i++) {
            float phase = (i % 10) < 5 ? 1.0F : -1.0F;
            update(walk, joints(true, -0.15F, 1.2F, -0.2F + 0.18F * phase),
                joints(true, 0.15F, 1.2F, -0.2F - 0.18F * phase),
                true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], w, false, false);
            w += 50_000_000L;
        }
        update(walk, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], w, false, false);
        check("walk + both fists suppresses inventory", !walk.inventory());

        // Inventory tap must not start walk.
        VisionM7Gesture inv = new VisionM7Gesture();
        update(inv, bothL, bothR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        update(inv, bothL, bothR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 120_000_000L, false, false);
        update(inv, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 200_000_000L, false, false);
        check("inventory tap does not start walk", !inv.walkActive());

        // Place/break boundary: 349 ms release = place; 350 ms held = break, no place.
        VisionM7Gesture p349 = new VisionM7Gesture();
        update(p349, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        update(p349, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 20_000_000L, false, false);
        update(p349, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 60_000_000L, false, false);
        update(p349, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 349_000_000L, false, false);
        update(p349, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 349_000_000L, false, false);
        check("pinch 349 ms releases place", p349.place());
        check("pinch 349 ms is short", !p349.breakHeld());
        VisionM7Gesture p351 = new VisionM7Gesture();
        update(p351, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        update(p351, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 20_000_000L, false, false);
        update(p351, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 60_000_000L, false, false);
        update(p351, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 351_000_000L, false, false);
        check("pinch 351 ms is break", p351.breakHeld());
        update(p351, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 351_000_000L, false, false);
        check("pinch 351 ms does not place", !p351.place());

        VisionM7Gesture p350 = new VisionM7Gesture();
        update(p350, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        update(p350, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 20_000_000L, false, false);
        update(p350, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 60_000_000L, false, false);
        update(p350, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 350_000_000L, false, false);
        check("pinch 350 ms is break", p350.breakHeld());
        update(p350, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 350_000_000L, false, false);
        check("pinch 350 ms does not place", !p350.place());

        // A single noisy pinch frame must not fire place/click (pinch debounce).
        VisionM7Gesture jitter = new VisionM7Gesture();
        update(jitter, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        update(jitter, openL, openR, true, true, 0.2F, 0.02F, HEAD[0], HEAD[1], HEAD[2], t + 16_000_000L, false, false);
        update(jitter, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 32_000_000L, false, false);
        check("single-frame pinch jitter does not place", !jitter.place());
        check("single-frame pinch jitter does not break", !jitter.breakHeld());

        // A left-fist tap immediately after a both-fist tap must not open the menu (inventory close path).
        VisionM7Gesture invMenu = new VisionM7Gesture();
        float[] leftFist = joints(true, -0.12F, 1.2F, -0.2F);
        update(invMenu, bothL, bothR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        update(invMenu, bothL, bothR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 120_000_000L, false, false);
        update(invMenu, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 180_000_000L, false, false);
        update(invMenu, leftFist, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 220_000_000L, false, false);
        update(invMenu, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 280_000_000L, false, false);
        check("left-fist tap after inventory does not open menu", !invMenu.menu());

        // A hotbar tap candidate immediately after a both-fist tap must be suppressed.
        VisionM7Gesture hotAfterInv = new VisionM7Gesture();
        update(hotAfterInv, bothL, bothR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t, false, false);
        update(hotAfterInv, bothL, bothR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 100_000_000L, false, false);
        update(hotAfterInv, openL, openR, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 160_000_000L, false, false);
        float[] tip = joints(false, 0.2F, 1.3F, -0.2F);
        moveIndexTip(tip, 0.2F, 1.3F, -0.6F);
        update(hotAfterInv, openL, tip, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], t + 200_000_000L, false, false);
        check("hotbar tap after both-fist is suppressed", !hotAfterInv.hotbarNext() && !hotAfterInv.hotbarPrev());

        // Hotbar vs attack: a fast wrist swing must attack and must not cycle the hotbar.
        VisionM7Gesture sw = new VisionM7Gesture();
        long s = 14_000_000_000L;
        float[] prev = joints(false, 0.2F, 1.3F, -0.2F);
        update(sw, openL, prev, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], s, false, false);
        float[] fast = joints(false, 0.2F, 1.3F, -0.2F);
        moveIndexTip(fast, 0.2F, 1.3F, -0.8F);
        // Move the whole hand quickly as well, as a swing does.
        set(fast, 0, 0.2F, 1.3F, -0.8F);
        set(fast, 6, 0.16F, 1.37F, -0.81F);
        set(fast, 11, 0.2F, 1.38F, -0.8F);
        set(fast, 16, 0.24F, 1.37F, -0.79F);
        set(fast, 21, 0.28F, 1.36F, -0.78F);
        update(sw, openL, fast, true, true, 0.2F, 0.2F, HEAD[0], HEAD[1], HEAD[2], s + 16_000_000L, false, false);
        check("fast wrist swing attacks", sw.attack());
        check("attack swing does not cycle hotbar", !sw.hotbarNext() && !sw.hotbarPrev());
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
