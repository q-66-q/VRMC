package dev.vrmc.provider;

import org.joml.Vector2f;

/** Host test for the M4-W3 middle-pinch virtual-stick mapping. */
public final class VisionLocomotionTest {
    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }

    public static void main(String[] args) {
        // Neutral band: a hand near its rest offset (~5 cm in front) must not move the player.
        Vector2f rest = VisionLocomotion.axes(0.0F, 0.0F, -0.05F, 0.0F, 0.0F, 0.0F,
            0.05F, 3.0F, 3.0F, 0.10F);
        check("neutral band", rest.x == 0.0F && rest.y == 0.0F, String.valueOf(rest));

        // Hand pushed forward: forward axis positive, strafe ~0.
        Vector2f fwd = VisionLocomotion.axes(0.0F, 0.0F, -0.40F, 0.0F, 0.0F, 0.0F,
            0.10F, 3.0F, 3.0F, 0.10F);
        check("forward", fwd.y > 0.4F && Math.abs(fwd.x) < 1e-5F, String.valueOf(fwd));

        // Hand pulled behind the neutral point: backward.
        Vector2f back = VisionLocomotion.axes(0.0F, 0.0F, 0.10F, 0.0F, 0.0F, 0.0F,
            0.10F, 3.0F, 3.0F, 0.10F);
        check("backward", back.y < -0.1F, String.valueOf(back));

        // Hand to the right: positive strafe.
        Vector2f right = VisionLocomotion.axes(0.20F, 0.0F, -0.30F, 0.0F, 0.0F, 0.0F,
            0.10F, 3.0F, 3.0F, 0.10F);
        check("strafe right", right.x > 0.2F, String.valueOf(right));

        // Diagonal magnitude is clamped to <= 1 after deadzone rescale.
        Vector2f diag = VisionLocomotion.axes(0.5F, 0.0F, -0.5F, 0.0F, 0.0F, 0.0F,
            0.10F, 3.0F, 3.0F, 0.10F);
        check("diagonal clamp", diag.length() <= 1.0001F, String.valueOf(diag));

        // Non-finite input never moves the player.
        Vector2f bad = VisionLocomotion.axes(Float.NaN, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F);
        check("non-finite safe", bad.x == 0.0F && bad.y == 0.0F, String.valueOf(bad));

        // Head motion changes the relative wrist position: moving the head forward while the hand is
        // fixed pulls the virtual stick back (expected: hand is the anchor, not world-fixed).
        Vector2f noHead = VisionLocomotion.axes(0.0F, 0.0F, -0.35F, 0.0F, 0.0F, 0.0F);
        Vector2f headFwd = VisionLocomotion.axes(0.0F, 0.0F, -0.35F, 0.0F, 0.0F, -0.25F);
        check("head-relative", headFwd.y < noHead.y, "noHead=" + noHead + " headFwd=" + headFwd);

        System.out.println("[m4-locomotion-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m4-locomotion-test] PASS" : "[m4-locomotion-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
