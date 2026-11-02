package dev.vrmc.provider;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Map;

/** Host test for the M4-W4 ring-pinch hotbar-wheel modifier. */
public final class VisionRingChordTest {
    private static final long MS = 1_000_000L;
    private static final long T0 = 4_000_000_000L;
    private static int checks;
    private static int failures;
    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) {
        Rig rig = new Rig(new VisionInput());
        rig.poll(); rig.pollMs(150);
        rig.lRing = 0.006F; rig.rRing = 0.006F;
        rig.pollMs(16);
        check("both ring pinch chord after arming", rig.in.bothRingPinchPressed());
        check("ring distance parsed", Math.abs(rig.in.ringDistance(VisionInput.HAND_LEFT) - 0.006F) < 1e-4F);
        rig.lRing = 0.064F; rig.rRing = 0.064F;
        rig.pollMs(16);
        check("ring release", !rig.in.bothRingPinchPressed());
        rig.lRing = 0.006F; rig.rRing = 0.064F;
        rig.pollMs(16);
        check("one-hand ring is not the chord", !rig.in.bothRingPinchPressed());
        rig.rRing = 0.006F; rig.pollMs(16);
        check("chord returns when both close", rig.in.bothRingPinchPressed());
        rig.rTracked = false; rig.pollMs(16);
        check("tracking loss releases ring chord", !rig.in.bothRingPinchPressed());
        check("tracking loss leaves ring distance NaN", Float.isNaN(rig.in.ringDistance(VisionInput.HAND_RIGHT)));

        VisionInput disabled = new VisionInput(Map.of(VisionInput.TUNE_RING_ENABLED, "false"));
        Rig off = new Rig(disabled);
        off.poll(); off.pollMs(150);
        off.lRing = 0.002F; off.rRing = 0.002F; off.pollMs(30);
        check("ring.enabled=false disables the chord", !off.in.bothRingPinchPressed());

        System.out.println("[m4-ring-chord-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m4-ring-chord-test] PASS" : "[m4-ring-chord-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    private static final class Rig {
        final VisionInput in;
        int frame;
        long now = T0;
        boolean lTracked = true, rTracked = true;
        float lRing = 0.064F, rRing = 0.064F;
        Rig(VisionInput in) { this.in = in; }
        void poll() { pollMs(0); }
        void pollMs(long ms) {
            now += ms * MS;
            in.poll(snapshot(frame++, now, lTracked, rTracked, lRing, rRing), 0, now);
        }
    }

    private static ByteBuffer snapshot(int frame, long ts, boolean lt, boolean rt, float lRing, float rRing) {
        ByteBuffer b = ByteBuffer.allocateDirect(VisionInput.INPUT_BYTES).order(ByteOrder.LITTLE_ENDIAN);
        b.putInt(VisionInput.INPUT_OFF_FRAME_INDEX, frame);
        b.putInt(VisionInput.INPUT_OFF_VALID_MASK, (lt ? 1 : 0) | (rt ? 2 : 0));
        b.putLong(VisionInput.INPUT_OFF_TIMESTAMP, ts);
        writeHand(b, VisionInput.INPUT_OFF_HANDS, false, lt, lRing);
        writeHand(b, VisionInput.INPUT_OFF_HANDS + VisionInput.HAND_STRIDE, true, rt, rRing);
        b.position(0);
        return b;
    }

    private static void writeHand(ByteBuffer b, int base, boolean right, boolean tracked, float ring) {
        b.putInt(base + VisionInput.HAND_OFF_TRACKED, tracked ? 1 : 0);
        b.putInt(base + VisionInput.HAND_OFF_CHIRALITY, right ? 1 : 0);
        b.putLong(base + VisionInput.HAND_OFF_TIMESTAMP, 0L);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT, 0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 4, 0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 8, 0F);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_QUAT + 12, 1F);
        float wx = right ? 0.18F : -0.18F, wy = 1.2F, wz = -0.4F;
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS, wx);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS + 4, wy);
        b.putFloat(base + VisionInput.HAND_OFF_WRIST_POS + 8, wz);
        float[] j = new float[VisionInput.JOINT_COUNT * 3];
        for (int i = 0; i < VisionInput.JOINT_COUNT; i++) { j[i*3]=wx; j[i*3+1]=wy; j[i*3+2]=wz; }
        float tipZ = wz - 0.15F;
        set(j, VisionInput.JOINT_MIDDLE_KNUCKLE, wx, wy, wz - 0.09F);
        set(j, VisionInput.JOINT_INDEX_TIP, wx + 0.05F, wy, tipZ);
        set(j, VisionInput.JOINT_MIDDLE_TIP, wx + 0.05F, wy, tipZ);
        set(j, VisionInput.JOINT_LITTLE_TIP, wx - 0.05F, wy, tipZ);
        set(j, VisionInput.JOINT_THUMB_TIP, wx, wy, tipZ);
        set(j, VisionInput.JOINT_RING_TIP, wx + ring, wy, tipZ);
        set(j, VisionInput.JOINT_INDEX_METACARPAL, wx + 0.03F, wy, wz - 0.02F);
        set(j, VisionInput.JOINT_LITTLE_METACARPAL, wx - 0.03F, wy, wz - 0.02F);
        for (int i = 0; i < j.length; i++) b.putFloat(base + VisionInput.HAND_OFF_JOINTS + i * 4, j[i]);
    }

    private static void set(float[] j, int joint, float x, float y, float z) {
        j[joint*3]=x; j[joint*3+1]=y; j[joint*3+2]=z;
    }
}
