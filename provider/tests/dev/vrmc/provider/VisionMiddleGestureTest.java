package dev.vrmc.provider;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;

/** Host test for the M4-W3 middle-pinch gesture family (tap/double-tap/hold + W3 bindings). */
public final class VisionMiddleGestureTest {
    private static final long MS = 1_000_000L;
    private static final long T0 = 2_000_000_000L;
    private static final int LEFT = VisionInput.HAND_LEFT;
    private static final int RIGHT = VisionInput.HAND_RIGHT;
    private static final float OPEN_MIDDLE = 0.068F;
    private static final float PINCHED_MIDDLE = 0.004F;

    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }

    private static void check(String name, boolean ok) {
        check(name, ok, "");
    }

    public static void main(String[] args) {
        acquisitionArming();
        hysteresisAndLongHold();
        tapAndDoubleTap();
        bindingsAndActionSets();
        trackingLossReleases();
        System.out.println("[m4-middle-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m4-middle-test] PASS" : "[m4-middle-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    private static void acquisitionArming() {
        Rig rig = new Rig();
        rig.poll();
        check("acquisition middle raw", rig.in.hasSeenSnapshot());
        check("acquisition never presses middle", !rig.in.middlePressed(RIGHT) && !rig.in.middleTapPressed(RIGHT));
        rig.pollMs(150);
        rig.rMiddle = PINCHED_MIDDLE;
        rig.pollMs(300);
        check("held middle pinch presses after arming", rig.in.middlePressed(RIGHT));
    }

    private static void hysteresisAndLongHold() {
        Rig rig = new Rig();
        rig.poll(); rig.pollMs(150);
        rig.rMiddle = 0.034F; // below on
        rig.pollMs(16);
        check("middle on threshold", rig.in.middlePressed(RIGHT));
        rig.rMiddle = 0.048F; // between on/off, still held
        rig.pollMs(16);
        check("middle hysteresis hold", rig.in.middlePressed(RIGHT));
        rig.rMiddle = 0.051F; // above off
        rig.pollMs(16);
        check("middle release", !rig.in.middlePressed(RIGHT));
        rig.rMiddle = OPEN_MIDDLE;
        rig.pollMs(150);
        rig.rMiddle = PINCHED_MIDDLE;
        rig.pollMs(16);
        List<Boolean> taps = new ArrayList<>();
        for (int i = 0; i < 40; i++) { rig.pollMs(16); taps.add(rig.in.middleTapPressed(RIGHT)); }
        rig.rMiddle = OPEN_MIDDLE;
        rig.pollMs(16);
        // A >220 ms hold must not produce a tap; no tap frames while holding.
        boolean anyTapDuringHold = false;
        for (boolean b : taps) anyTapDuringHold |= b;
        check("long hold never emits a tap", !anyTapDuringHold);
    }

    private static void tapAndDoubleTap() {
        Rig rig = new Rig();
        rig.poll(); rig.pollMs(150);
        rig.rMiddle = PINCHED_MIDDLE;
        rig.pollMs(16);
        rig.rMiddle = OPEN_MIDDLE;
        rig.pollMs(16);
        int width = 0;
        for (int i = 0; i < 4; i++) {
            if (rig.in.middleTapPressed(RIGHT)) width++;
            rig.pollMs(16);
        }
        check("short press produces a tap pulse", width >= 1 && width <= 2);

        Rig dbl = new Rig();
        dbl.poll(); dbl.pollMs(150);
        dbl.rMiddle = PINCHED_MIDDLE; dbl.pollMs(16); dbl.rMiddle = OPEN_MIDDLE; dbl.pollMs(16);
        dbl.rMiddle = PINCHED_MIDDLE; dbl.pollMs(16); dbl.rMiddle = OPEN_MIDDLE; dbl.pollMs(16);
        boolean sawDouble = dbl.in.middleDoubleTapPressed(RIGHT);
        for (int i = 0; i < 3; i++) { dbl.pollMs(16); sawDouble |= dbl.in.middleDoubleTapPressed(RIGHT); }
        check("two quick taps produce a double-tap pulse", sawDouble);
    }

    private static void bindingsAndActionSets() {
        Rig hold = new Rig();
        hold.poll(); hold.pollMs(150);
        hold.rMiddle = PINCHED_MIDDLE;
        hold.pollMs(300);
        hold.in.setEnvironment(false, false, false);
        check("middle hold binds key.sneak (right)", hold.in.actionPressed(VisionInput.KEY_SNEAK));

        Rig tap = new Rig();
        tap.poll(); tap.pollMs(150);
        tap.rMiddle = PINCHED_MIDDLE; tap.pollMs(16); tap.rMiddle = OPEN_MIDDLE; tap.pollMs(16);
        tap.in.setEnvironment(false, false, false);
        boolean jump = tap.in.actionPressed(VisionInput.KEY_JUMP);
        for (int i = 0; i < 3; i++) { tap.pollMs(16); jump |= tap.in.actionPressed(VisionInput.KEY_JUMP); }
        check("middle tap binds key.jump (right)", jump);

        // Double-tap -> radial menu binding (right hand).
        Rig dbl = new Rig();
        dbl.poll(); dbl.pollMs(150);
        dbl.rMiddle = PINCHED_MIDDLE; dbl.pollMs(16); dbl.rMiddle = OPEN_MIDDLE; dbl.pollMs(16);
        dbl.rMiddle = PINCHED_MIDDLE; dbl.pollMs(16); dbl.rMiddle = OPEN_MIDDLE; dbl.pollMs(16);
        dbl.in.setEnvironment(false, false, false);
        boolean radial = dbl.in.actionPressed(VisionInput.KEY_RADIAL_MENU);
        for (int i = 0; i < 3; i++) { dbl.pollMs(16); radial |= dbl.in.actionPressed(VisionInput.KEY_RADIAL_MENU); }
        check("middle double-tap binds radial menu (right)", radial);

        // Both hands double-tap within 120 ms -> recenter chord, individual double-taps suppressed.
        Rig both = new Rig();
        both.poll(); both.pollMs(150);
        both.lMiddle = PINCHED_MIDDLE; both.rMiddle = PINCHED_MIDDLE; both.pollMs(16);
        both.lMiddle = OPEN_MIDDLE; both.rMiddle = OPEN_MIDDLE; both.pollMs(16);
        both.lMiddle = PINCHED_MIDDLE; both.rMiddle = PINCHED_MIDDLE; both.pollMs(16);
        both.lMiddle = OPEN_MIDDLE; both.rMiddle = OPEN_MIDDLE; both.pollMs(16);
        check("both-hand middle double-tap fires recenter chord", both.in.bothMiddleDoubleTapPressed());
        both.in.setEnvironment(false, false, false);
        check("recenter chord suppresses right radial double-tap",
            !both.in.actionPressed(VisionInput.KEY_RADIAL_MENU));

        tap.in.setEnvironment(true, false, false);
        check("GUI screen suppresses INGAME middle bindings",
            !tap.in.actionActive(VisionInput.KEY_SNEAK) && !tap.in.actionActive(VisionInput.KEY_JUMP));
    }

    private static void trackingLossReleases() {
        Rig rig = new Rig();
        rig.poll(); rig.pollMs(150);
        rig.rMiddle = PINCHED_MIDDLE;
        rig.pollMs(300);
        check("middle held before loss", rig.in.middlePressed(RIGHT));
        rig.rightTracked = false;
        rig.pollMs(16);
        check("tracking loss releases middle press", !rig.in.middlePressed(RIGHT));
        check("tracking loss clears middle tap", !rig.in.middleTapPressed(RIGHT));
    }

    private static final class Rig {
        final VisionInput in = new VisionInput();
        int frame;
        long now = T0;
        boolean leftTracked = true;
        boolean rightTracked = true;
        float lMiddle = OPEN_MIDDLE;
        float rMiddle = OPEN_MIDDLE;

        void poll() { pollMs(0); }

        void pollMs(long millis) {
            now += millis * MS;
            in.poll(snapshot(frame++, now, leftTracked, rightTracked, rMiddle, lMiddle), 0, now);
        }
    }

    private static ByteBuffer snapshot(int frame, long ts, boolean leftTracked, boolean rightTracked,
                                       float rightMiddle, float leftMiddle) {
        ByteBuffer b = ByteBuffer.allocateDirect(VisionInput.INPUT_BYTES).order(ByteOrder.LITTLE_ENDIAN);
        b.putInt(VisionInput.INPUT_OFF_FRAME_INDEX, frame);
        b.putInt(VisionInput.INPUT_OFF_VALID_MASK, (leftTracked ? 1 : 0) | (rightTracked ? 2 : 0));
        b.putLong(VisionInput.INPUT_OFF_TIMESTAMP, ts);
        writeHand(b, VisionInput.INPUT_OFF_HANDS + LEFT * VisionInput.HAND_STRIDE, false, leftTracked, leftMiddle);
        writeHand(b, VisionInput.INPUT_OFF_HANDS + RIGHT * VisionInput.HAND_STRIDE, true, rightTracked, rightMiddle);
        b.position(0);
        return b;
    }

    private static void writeHand(ByteBuffer b, int base, boolean right, boolean tracked, float middleDistance) {
        b.putInt(base + VisionInput.HAND_OFF_TRACKED, tracked ? 1 : 0);
        b.putInt(base + VisionInput.HAND_OFF_CHIRALITY, right ? 1 : 0);
        b.putLong(base + VisionInput.HAND_OFF_TIMESTAMP, 0L);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT, 0.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 4, 0.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 8, 0.0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 12, 1.0F);
        float wx = right ? 0.18F : -0.18F, wy = 1.2F, wz = -0.4F;
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS, wx);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS + 4, wy);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS + 8, wz);
        float[] j = new float[VisionInput.JOINT_COUNT * 3];
        for (int i = 0; i < VisionInput.JOINT_COUNT; i++) {
            j[i * 3] = wx; j[i * 3 + 1] = wy; j[i * 3 + 2] = wz;
        }
        // Fingers open (large wrist distance) except control of the thumb-middle pair.
        float tipZ = wz - 1.5F * 0.09F;
        for (int tip : new int[]{VisionInput.JOINT_INDEX_TIP, VisionInput.JOINT_RING_TIP,
            VisionInput.JOINT_LITTLE_TIP}) {
            set(j, tip, wx, wy, tipZ);
        }
        set(j, VisionInput.JOINT_MIDDLE_KNUCKLE, wx, wy, wz - 0.09F);
        // thumb tip at origin of a 1-D pair; middle tip at +middleDistance (same y/z).
        set(j, VisionInput.JOINT_THUMB_TIP, wx, wy, tipZ);
        set(j, VisionInput.JOINT_MIDDLE_TIP, wx + middleDistance, wy, tipZ);
        set(j, VisionInput.JOINT_INDEX_METACARPAL, wx + 0.03F, wy, wz - 0.02F);
        set(j, VisionInput.JOINT_LITTLE_METACARPAL, wx - 0.03F, wy, wz - 0.02F);
        for (int i = 0; i < j.length; i++) b.putFloat(base + VisionInput.HAND_OFF_JOINTS + i * 4, j[i]);
    }

    private static void set(float[] j, int joint, float x, float y, float z) {
        j[joint * 3] = x; j[joint * 3 + 1] = y; j[joint * 3 + 2] = z;
    }
}
