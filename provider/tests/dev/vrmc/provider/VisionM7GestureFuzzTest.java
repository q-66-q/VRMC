package dev.vrmc.provider;

import java.util.Random;

/**
 * Deterministic host fuzz for the pure M7 gesture engine: random tracked/untracked frames, NaN/Inf
 * pinch and joint values, time jumps, GUI/seated/context flips, release paths.
 *
 * <p>Invariants under test (G4 no-stuck-input is the sole safety mechanism for the hands-only path):
 * every update returns; malformed data fails closed to released actions; loss of both hands releases
 * all actions within a bounded number of frames; {@link VisionM7Gesture#releaseAll()} is idempotent
 * and complete; outputs never depend on wall-clock time (replay/diagnostic safe).
 */
public final class VisionM7GestureFuzzTest {
    private static int violations;

    private static void fail(String what, int frame, VisionM7Gesture g) {
        violations++;
        if (violations <= 20) {
            System.out.println("  VIOLATION frame=" + frame + " " + what + " summary=" + g.summary());
        }
    }

    private static String whichActions(VisionM7Gesture g) {
        StringBuilder b = new StringBuilder();
        if (g.walkActive()) b.append("walk ");
        if (g.jump()) b.append("jump ");
        if (g.sneak()) b.append("sneak ");
        if (g.teleportHeld()) b.append("teleport ");
        if (g.place()) b.append("place ");
        if (g.breakHeld()) b.append("break ");
        if (g.attack()) b.append("attack ");
        if (g.menu()) b.append("menu ");
        if (g.leftFistTap()) b.append("leftFistTap ");
        if (g.inventory()) b.append("inventory ");
        if (g.hotbarNext()) b.append("hotbarNext ");
        if (g.hotbarPrev()) b.append("hotbarPrev ");
        if (g.bowDraw()) b.append("bowDraw ");
        if (g.bowFire()) b.append("bowFire ");
        if (g.guiClick()) b.append("guiClick ");
        if (g.eat()) b.append("eat ");
        if (g.climbGrabLeft()) b.append("climbL ");
        if (g.climbGrabRight()) b.append("climbR ");
        if (g.climbJump()) b.append("climbJump ");
        return b.toString().trim();
    }

    private static boolean anyHandAction(VisionM7Gesture g) {
        return g.walkActive() || g.teleportHeld() || g.place() || g.breakHeld() || g.attack()
            || g.menu() || g.leftFistTap() || g.inventory() || g.hotbarNext() || g.hotbarPrev()
            || g.bowDraw() || g.bowFire() || g.guiClick() || g.eat()
            || g.climbGrabLeft() || g.climbGrabRight() || g.climbJump();
    }

    private static boolean anyAction(VisionM7Gesture g) {
        return g.walkActive() || g.jump() || g.sneak() || g.teleportHeld() || g.place()
            || g.breakHeld() || g.attack() || g.menu() || g.leftFistTap() || g.inventory()
            || g.hotbarNext() || g.hotbarPrev() || g.bowDraw() || g.bowFire() || g.guiClick()
            || g.eat() || g.climbGrabLeft() || g.climbGrabRight() || g.climbJump();
    }

    public static void main(String[] args) {
        Random rnd = new Random(0x4D3747E57L);
        VisionM7Gesture g = new VisionM7Gesture();
        long now = 1_000_000_000L;
        float[] jointsL = new float[81];
        float[] jointsR = new float[81];
        // A plausible open hand so curl/pinch math is exercised with real values.
        for (int i = 0; i < 27; i++) {
            jointsL[i * 3] = -0.2F + i * 0.005F;
            jointsL[i * 3 + 1] = 1.2F + i * 0.004F;
            jointsL[i * 3 + 2] = -0.2F + i * 0.003F;
            jointsR[i * 3] = 0.2F + i * 0.005F;
            jointsR[i * 3 + 1] = 1.2F + i * 0.004F;
            jointsR[i * 3 + 2] = -0.2F + i * 0.003F;
        }
        int frames = 200_000;
        for (int frame = 0; frame < frames; frame++) {
            int mode = rnd.nextInt(100);
            boolean tl = mode >= 8;
            boolean tr = mode >= 16;
            float pinchL = rnd.nextInt(10) == 0 ? Float.NaN : rnd.nextFloat() * 0.12F;
            if (rnd.nextInt(50) == 0) pinchL = Float.POSITIVE_INFINITY;
            float pinchR = rnd.nextInt(10) == 0 ? Float.NaN : rnd.nextFloat() * 0.12F;
            if (rnd.nextInt(50) == 0) pinchR = Float.NEGATIVE_INFINITY;
            float headY = 1.3F + rnd.nextFloat() * 0.5F;
            if (rnd.nextInt(200) == 0) headY = Float.NaN;
            // Occasionally scramble joints with non-finite values; tracked flag says the data is valid,
            // so the engine must still not throw.
            if (rnd.nextInt(100) == 0) {
                jointsL[rnd.nextInt(81)] = Float.NaN;
                jointsR[rnd.nextInt(81)] = Float.POSITIVE_INFINITY;
            }
            long step;
            int timeMode = rnd.nextInt(100);
            if (timeMode < 3) {
                step = -rnd.nextInt(50_000_000); // backwards timestamp: must be ignored
            } else if (timeMode < 6) {
                step = 0L; // duplicate timestamp
            } else if (timeMode < 8) {
                step = 500_000_000L + rnd.nextInt(1_500_000_000); // long gap (>=500 ms)
            } else {
                step = 8_000_000L + rnd.nextInt(12_000_000);
            }
            now += step;
            int ctx = 0;
            if (rnd.nextInt(20) == 0) ctx |= VisionM7Gesture.CTX_GUI;
            if (rnd.nextInt(20) == 0) ctx |= VisionM7Gesture.CTX_SEATED;
            if (rnd.nextInt(4) == 0) ctx |= VisionM7Gesture.CTX_BOW_HELD;
            if (rnd.nextInt(4) == 0) ctx |= VisionM7Gesture.CTX_EDIBLE_HELD;
            if (rnd.nextInt(5) == 0) ctx |= VisionM7Gesture.CTX_CLIMBABLE;
            try {
                g.update(tl, jointsL, tr, jointsR, pinchL, pinchR, 0.0F, headY, 0.0F, now, ctx);
            } catch (Throwable t) {
                fail("threw " + t, frame, g);
                break;
            }
            // Outputs are pure reads: two consecutive reads must match.
            boolean a = g.walkActive();
            boolean b = g.walkActive();
            if (a != b) fail("non-deterministic getter", frame, g);
            // After both hands are untracked for 10 consecutive frames no action may remain latched.
            if (!tl && !tr && frame % 37 == 0) {
                for (int k = 0; k < 10; k++) {
                    now += 11_000_000L;
                    g.update(false, jointsL, false, jointsR, Float.NaN, Float.NaN,
                        0.0F, 1.5F, 0.0F, now, 0);
                }
                // Jump/sneak are head-only gestures and may legitimately fire with no hands tracked;
                // every hand-driven action must be released, though.
                if (anyHandAction(g)) {
                    fail("hand actions latched after both hands lost: " + whichActions(g), frame, g);
                }
            }
            if (rnd.nextInt(4000) == 0) {
                g.releaseAll();
                if (anyAction(g)) fail("releaseAll left actions latched", frame, g);
            }
        }
        // releaseAll must be complete and idempotent.
        g.releaseAll();
        g.releaseAll();
        if (anyAction(g)) fail("releaseAll not complete", frames, g);
        // Null/malformed joint arrays fail closed, not throwing.
        try {
            g.update(true, null, true, null, 0.2F, 0.2F, 0.0F, 1.5F, 0.0F, now, 0);
            g.update(true, new float[3], true, new float[3], 0.2F, 0.2F, 0.0F, 1.5F, 0.0F,
                now + 1, 0);
        } catch (Throwable t) {
            fail("null/short joints threw " + t, frames, g);
        }
        if (anyAction(g)) fail("actions latched after malformed input", frames, g);

        System.out.println("[m7-fuzz-test] frames=" + frames + " violations=" + violations);
        System.out.println(violations == 0 ? "[m7-fuzz-test] PASS" : "[m7-fuzz-test] FAIL");
        if (violations != 0) System.exit(1);
    }
}
