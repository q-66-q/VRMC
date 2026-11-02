package dev.vrmc.provider;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Map;

/** Host test for the M4-W4 opt-in open-hand swipe detector (hotbar/scroll). */
public final class VisionSwipeGestureTest {
    private static final long MS = 1_000_000L;
    private static final long T0 = 3_000_000_000L;
    private static final int RIGHT = VisionInput.HAND_RIGHT;

    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) {
        // Default OFF: even a fast open-hand motion produces no swipe.
        Rig off = new Rig(new VisionInput());
        off.poll(); off.pollMs(150);
        off.moveWrist(0.30F, 0.0F, 16); // 0.30 m in 16 ms = 18.75 m/s
        check("default OFF emits no swipe", off.in.swipeDirection(RIGHT) == VisionInput.SWIPE_NONE);

        Rig rig = new Rig(new VisionInput(Map.of(VisionInput.TUNE_SWIPE_ENABLED, "true")));
        rig.poll(); rig.pollMs(150);
        rig.moveWrist(-0.30F, 0.0F, 16);
        check("fast left swipe detected", rig.in.swipeDirection(RIGHT) == VisionInput.SWIPE_LEFT);
        // Pulse decays and cooldown suppresses a second immediate swipe.
        rig.pollMs(16);
        rig.moveWrist(0.30F, 0.0F, 16);
        check("cooldown suppresses immediate reverse swipe", rig.in.swipeDirection(RIGHT) == VisionInput.SWIPE_NONE);

        // Vertical swipe after the cooldown.
        rig.pollMs(400);
        rig.moveWrist(0.0F, 0.30F, 16);
        check("fast up swipe detected", rig.in.swipeDirection(RIGHT) == VisionInput.SWIPE_UP);

        // W4 bindings: right swipe right -> hotbar next; swipe left -> previous (INGAME only).
        Rig bound = new Rig(new VisionInput(Map.of(VisionInput.TUNE_SWIPE_ENABLED, "true")));
        bound.poll(); bound.pollMs(150);
        bound.in.setEnvironment(false, false, false);
        bound.moveWrist(0.30F, 0.0F, 16);
        boolean next = bound.in.actionPressed(VisionInput.KEY_HOTBAR_NEXT);
        for (int i = 0; i < 2; i++) { bound.pollMs(16); next |= bound.in.actionPressed(VisionInput.KEY_HOTBAR_NEXT); }
        check("right swipe binds hotbarNext", next);
        bound.pollMs(400);
        bound.in.setEnvironment(true, false, false);
        bound.moveWrist(-0.30F, 0.0F, 16);
        check("GUI suppresses swipe hotbar action", !bound.in.actionActive(VisionInput.KEY_HOTBAR_NEXT));
        check("right swipe raw direction still detected", bound.in.swipeDirection(RIGHT) == VisionInput.SWIPE_LEFT);

        // Closed fist never swipes.
        Rig fist = new Rig(new VisionInput(Map.of(VisionInput.TUNE_SWIPE_ENABLED, "true")));
        fist.poll(); fist.pollMs(150);
        fist.fist = 0.98F;
        fist.pollMs(16);
        fist.moveWrist(-0.30F, 0.0F, 16);
        check("closed fist cannot swipe", fist.in.swipeDirection(RIGHT) == VisionInput.SWIPE_NONE);

        // Slow motion below the speed threshold is not a swipe.
        Rig slow = new Rig(new VisionInput(Map.of(VisionInput.TUNE_SWIPE_ENABLED, "true")));
        slow.poll(); slow.pollMs(150);
        slow.moveWrist(-0.012F, 0.0F, 33);
        check("slow motion is not a swipe", slow.in.swipeDirection(RIGHT) == VisionInput.SWIPE_NONE);

        System.out.println("[m4-swipe-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m4-swipe-test] PASS" : "[m4-swipe-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    private static final class Rig {
        final VisionInput in;
        int frame;
        long now = T0;
        float wristX = 0.18F, wristY = 1.2F, wristZ = -0.4F;
        float fist = 1.79F;

        Rig(VisionInput in) { this.in = in; }

        void poll() { pollMs(0); }

        void pollMs(long millis) {
            now += millis * MS;
            in.poll(snapshot(frame++, now, wristX, wristY, wristZ, fist), 0, now);
        }

        void moveWrist(float dx, float dy, long millis) {
            wristX += dx;
            wristY += dy;
            pollMs(millis);
        }
    }

    private static ByteBuffer snapshot(int frame, long ts, float wx, float wy, float wz, float fist) {
        ByteBuffer b = ByteBuffer.allocateDirect(VisionInput.INPUT_BYTES).order(ByteOrder.LITTLE_ENDIAN);
        b.putInt(VisionInput.INPUT_OFF_FRAME_INDEX, frame);
        b.putInt(VisionInput.INPUT_OFF_VALID_MASK, 3);
        b.putLong(VisionInput.INPUT_OFF_TIMESTAMP, ts);
        writeHand(b, VisionInput.INPUT_OFF_HANDS, false, wx - 0.36F, wy, wz, 1.79F);
        writeHand(b, VisionInput.INPUT_OFF_HANDS + VisionInput.HAND_STRIDE, true, wx, wy, wz, fist);
        b.position(0);
        return b;
    }

    private static void writeHand(ByteBuffer b, int base, boolean right, float wx, float wy, float wz, float fist) {
        b.putInt(base + VisionInput.HAND_OFF_TRACKED, 1);
        b.putInt(base + VisionInput.HAND_OFF_CHIRALITY, right ? 1 : 0);
        b.putLong(base + VisionInput.HAND_OFF_TIMESTAMP, 0L);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT, 0.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 4, 0.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 8, 0.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 12, 1.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS, wx);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS + 4, wy);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS + 8, wz);
        float palm = 0.09F;
        float[] j = new float[VisionInput.JOINT_COUNT * 3];
        for (int i = 0; i < VisionInput.JOINT_COUNT; i++) {
            j[i * 3] = wx; j[i * 3 + 1] = wy; j[i * 3 + 2] = wz;
        }
        set(j, VisionInput.JOINT_MIDDLE_KNUCKLE, wx, wy, wz - palm);
        float tipZ = wz - fist * palm;
        for (int tip : new int[]{VisionInput.JOINT_INDEX_TIP, VisionInput.JOINT_MIDDLE_TIP,
            VisionInput.JOINT_RING_TIP, VisionInput.JOINT_LITTLE_TIP}) {
            set(j, tip, wx, wy, tipZ);
        }
        set(j, VisionInput.JOINT_THUMB_TIP, wx + 0.068F, wy, tipZ);
        set(j, VisionInput.JOINT_INDEX_METACARPAL, wx + 0.03F, wy, wz - 0.02F);
        set(j, VisionInput.JOINT_LITTLE_METACARPAL, wx - 0.03F, wy, wz - 0.02F);
        for (int i = 0; i < j.length; i++) b.putFloat(base + VisionInput.HAND_OFF_JOINTS + i * 4, j[i]);
    }

    private static void set(float[] j, int joint, float x, float y, float z) {
        j[joint * 3] = x; j[joint * 3 + 1] = y; j[joint * 3 + 2] = z;
    }
}
