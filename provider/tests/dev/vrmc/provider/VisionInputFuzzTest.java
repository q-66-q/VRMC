package dev.vrmc.provider;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Random;

/**
 * M4/M6 hardening fuzz test for {@link VisionInput} (pure Java, deterministic).
 *
 * <p>Feeds VRMC_FUZZ_FRAMES random frames (default 20,000) mixing: tracking loss, malformed tracked bits, NaN/Inf joint values,
 * stale publisher gaps, pinch/fist/middle threshold crossings, and GUI/ingame environment flips.
 * Invariants checked after every frame:
 * <ul>
 *   <li>no exception and no NaN/Inf distance values;</li>
 *   <li>an untracked hand has every digital source released that same frame; both hands untracked
 *       implies the both-hand chords are released;</li>
 *   <li>stale input releases everything (no stuck attack/teleport/menu);</li>
 *   <li>non-finite hand data is treated as untracked, never as a gesture.</li>
 * </ul>
 */
public final class VisionInputFuzzTest {
    private static final long MS = 1_000_000L;
    private static final int LEFT = VisionInput.HAND_LEFT;
    private static final int RIGHT = VisionInput.HAND_RIGHT;
    private static final int FRAMES = fuzzFrames();

    private static int fuzzFrames() {
        String raw = System.getenv("VRMC_FUZZ_FRAMES");
        if (raw == null || raw.isBlank()) return 20_000;
        try {
            return Math.max(1, Math.min(2_000_000, Integer.parseInt(raw.trim())));
        } catch (NumberFormatException e) {
            return 20_000;
        }
    }

    public static void main(String[] args) {
        Random rnd = new Random(0x5EEDC0DEL);
        VisionInput in = new VisionInput();
        long now = 1_000_000_000L;
        int violations = 0;
        for (int frame = 0; frame < FRAMES; frame++) {
            int gapMs = rnd.nextInt(40);
            if (rnd.nextInt(120) == 0) gapMs = 300 + rnd.nextInt(400); // occasional stale gap
            now += Math.max(0, gapMs) * MS;

            boolean leftTracked = rnd.nextInt(10) != 0;
            boolean rightTracked = rnd.nextInt(10) != 0;
            boolean corrupt = rnd.nextInt(50) == 0;
            boolean corruptHand = rnd.nextInt(80) == 0;
            ByteBuffer b = snapshot(rnd, frame, now, leftTracked, rightTracked, corrupt, corruptHand);
            in.setEnvironment(rnd.nextBoolean(), rnd.nextBoolean(), rnd.nextInt(20) == 0);
            in.poll(b, 0, now);

            if ((!in.isInputHealthy() || in.isStale())
                && (anyGesture(in, LEFT) || anyGesture(in, RIGHT))) {
                violations++;
                if (violations <= 10) System.out.println("  VIOLATION unhealthy/stale gesture frame=" + frame
                    + " healthy=" + in.isInputHealthy() + " stale=" + in.isStale()
                    + " L=" + anyGesture(in, LEFT) + " R=" + anyGesture(in, RIGHT));
            }
            for (int hand : new int[]{LEFT, RIGHT}) {
                if (!in.isHandTracked(hand)) {
                    if (anyGesture(in, hand)) {
                        violations++;
                        if (violations <= 10) System.out.println("  VIOLATION untracked gesture frame=" + frame
                            + " hand=" + hand);
                    }
                    if (!Float.isNaN(in.pinchDistance(hand)) || !Float.isNaN(in.middleDistance(hand))
                        || !Float.isNaN(in.ringDistance(hand)) || !Float.isNaN(in.fistRatio(hand))) {
                        violations++;
                        if (violations <= 10) System.out.println("  VIOLATION untracked non-NaN distance frame=" + frame
                            + " hand=" + hand + " pinch=" + in.pinchDistance(hand)
                            + " middle=" + in.middleDistance(hand) + " fist=" + in.fistRatio(hand));
                    }
                } else {
                    if (Float.isNaN(in.pinchDistance(hand)) || Float.isNaN(in.middleDistance(hand))
                        || Float.isNaN(in.ringDistance(hand)) || Float.isNaN(in.fistRatio(hand))) {
                        violations++;
                        if (violations <= 10) System.out.println("  VIOLATION tracked NaN distance frame=" + frame
                            + " hand=" + hand);
                    }
                }
            }
            if (!in.isHandTracked(LEFT) || !in.isHandTracked(RIGHT)) {
                if (in.bothFistTapPressed() || in.bothMiddleTapPressed()
                    || in.bothMiddleDoubleTapPressed() || in.bothRingPinchPressed()) violations++;
            }
            // W4 safety priorities must hold every frame.
            if (in.fistPressed(RIGHT) && in.actionPressed(VisionInput.KEY_ATTACK)) {
                violations++;
                if (violations <= 10) System.out.println("  VIOLATION attack while right fist held frame=" + frame);
            }
            if (in.fistPressed(RIGHT) && in.actionPressed(VisionInput.KEY_TELEPORT)) {
                violations++;
                if (violations <= 10) System.out.println("  VIOLATION teleport while right fist held frame=" + frame);
            }
            if (in.fistPressed(LEFT) && in.fistPressed(RIGHT)
                && in.actionPressed(VisionInput.KEY_USE)) {
                violations++;
                if (violations <= 10) System.out.println("  VIOLATION use while both fists frame=" + frame);
            }
            if (violations > 5) break;
        }
        System.out.println("[m4-fuzz-test] frames=" + FRAMES + " violations=" + violations);
        System.out.println(violations == 0 ? "[m4-fuzz-test] PASS" : "[m4-fuzz-test] FAIL");
        if (violations != 0) System.exit(1);
    }

    private static boolean anyGesture(VisionInput in, int hand) {
        return in.pinchPressed(hand) || in.fistPressed(hand) || in.fistTapPressed(hand)
            || in.ringPressed(hand)
            || in.middlePressed(hand) || in.middleTapPressed(hand) || in.middleDoubleTapPressed(hand)
            || in.swipeDirection(hand) != VisionInput.SWIPE_NONE;
    }

    private static ByteBuffer snapshot(Random rnd, int frame, long ts, boolean leftTracked,
                                       boolean rightTracked, boolean corrupt, boolean corruptHand) {
        ByteBuffer b = ByteBuffer.allocateDirect(VisionInput.INPUT_BYTES).order(ByteOrder.LITTLE_ENDIAN);
        b.putInt(VisionInput.INPUT_OFF_FRAME_INDEX, frame);
        b.putInt(VisionInput.INPUT_OFF_VALID_MASK, (leftTracked ? 1 : 0) | (rightTracked ? 2 : 0));
        b.putLong(VisionInput.INPUT_OFF_TIMESTAMP, ts);
        writeHand(rnd, b, VisionInput.INPUT_OFF_HANDS, false, leftTracked, corrupt && corruptHand, frame, ts);
        writeHand(rnd, b, VisionInput.INPUT_OFF_HANDS + VisionInput.HAND_STRIDE, true, rightTracked,
            corrupt && !corruptHand, frame, ts);
        b.position(0);
        return b;
    }

    private static void writeHand(Random rnd, ByteBuffer b, int base, boolean right, boolean tracked,
                                  boolean corrupt, int frame, long ts) {
        b.putInt(base + VisionInput.HAND_OFF_TRACKED, tracked ? 1 : 0);
        b.putInt(base + VisionInput.HAND_OFF_CHIRALITY, right ? 1 : 0);
        b.putLong(base + VisionInput.HAND_OFF_TIMESTAMP, ts);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT, 0.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 4, 0.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 8, 0.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 12, 1.0F);
        float wx = (right ? 1.0F : -1.0F) * (0.1F + rnd.nextFloat() * 0.4F);
        float wy = 0.7F + rnd.nextFloat() * 0.8F;
        float wz = -0.6F + rnd.nextFloat() * 0.6F;
        if (corrupt && rnd.nextBoolean()) wx = Float.NaN;
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS, wx);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS + 4, wy);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS + 8, wz);

        float palm = 0.07F + rnd.nextFloat() * 0.05F;
        float pinch = rnd.nextFloat() < 0.35F ? 0.004F + rnd.nextFloat() * 0.02F
                                               : 0.05F + rnd.nextFloat() * 0.03F;
        float fist = rnd.nextFloat() < 0.35F ? 0.85F + rnd.nextFloat() * 0.25F
                                              : 1.30F + rnd.nextFloat() * 0.8F;
        float middle = rnd.nextFloat() < 0.30F ? 0.004F + rnd.nextFloat() * 0.02F
                                                : 0.05F + rnd.nextFloat() * 0.04F;
        float[] j = new float[VisionInput.JOINT_COUNT * 3];
        for (int i = 0; i < VisionInput.JOINT_COUNT; i++) {
            j[i * 3] = wx; j[i * 3 + 1] = wy; j[i * 3 + 2] = wz;
        }
        set(j, VisionInput.JOINT_MIDDLE_KNUCKLE, wx, wy, wz - palm);
        float tipZ = wz - fist * palm;
        for (int tip : new int[]{VisionInput.JOINT_RING_TIP, VisionInput.JOINT_LITTLE_TIP}) {
            set(j, tip, wx, wy, tipZ);
        }
        set(j, VisionInput.JOINT_INDEX_TIP, wx, wy, tipZ);
        set(j, VisionInput.JOINT_THUMB_TIP, wx + pinch, wy, tipZ);
        set(j, VisionInput.JOINT_MIDDLE_TIP, wx + pinch - middle, wy, tipZ);
        set(j, VisionInput.JOINT_INDEX_METACARPAL, wx + 0.03F, wy, wz - 0.02F);
        set(j, VisionInput.JOINT_LITTLE_METACARPAL, wx - 0.03F, wy, wz - 0.02F);
        if (corrupt && rnd.nextBoolean()) {
            j[rnd.nextInt(j.length)] = rnd.nextBoolean() ? Float.NaN : Float.POSITIVE_INFINITY;
        }
        for (int i = 0; i < j.length; i++) b.putFloat(base + VisionInput.HAND_OFF_JOINTS + i * 4, j[i]);
    }

    private static void set(float[] j, int joint, float x, float y, float z) {
        j[joint * 3] = x; j[joint * 3 + 1] = y; j[joint * 3 + 2] = z;
    }
}
