package dev.vrmc.provider;

import dev.vrmc.provider.bridge.VrmcBridge;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Host test for the ABI v3 input layout constants (design §3.4 / bridge/abi/vrmc_abi.h).
 *
 * <p>Every size/offset here is a literal from the documented struct tables - NOT copied from the
 * constants under test - so a drift between the C contract, {@link VrmcBridge} and {@link VisionInput}
 * fails loudly. It also round-trips a synthetic snapshot written at the documented absolute byte
 * offsets through the real parser, which catches an offset/order mistake even if the constants were
 * "consistently wrong". Run by provider/tests/run_tests.sh.
 */
public final class VisionInputLayoutTest {
    private static int failures;
    private static int checks;

    // Literals from docs/analysis/immersive-input.md §3.1/§3.2/§3.4 and bridge/abi/vrmc_abi.h.
    private static final int L_INPUT_BYTES = 752;
    private static final int L_OFF_FRAME_INDEX = 0;
    private static final int L_OFF_VALID_MASK = 4;
    private static final int L_OFF_TIMESTAMP = 8;
    private static final int L_OFF_HANDS = 16;
    private static final int L_HAND_STATE_BYTES = 368;
    private static final int L_HAND_STRIDE = 368;
    private static final int L_HAND0 = 16;
    private static final int L_HAND1 = 384;
    private static final int L_TRACKED = 0;
    private static final int L_CHIRALITY = 4;
    private static final int L_HAND_TIMESTAMP = 8;
    private static final int L_WRIST_QUAT = 16;
    private static final int L_WRIST_POS = 32;
    private static final int L_JOINTS = 44;
    private static final int L_JOINT_STRIDE = 12;
    private static final int L_JOINT_COUNT = 27;

    public static void main(String[] args) {
        System.out.println("[m4-layout-test] ABI v3 input layout (literal contract table)");
        try {
            constantsMatchTheDocumentedTable();
            arithmeticIdentities();
            parseRoundTripAtLiteralOffsets();
            capsAndHandshakeContract();
        } catch (Throwable t) {
            t.printStackTrace();
            failures++;
        }
        System.out.println();
        System.out.printf("[m4-layout-test] %d checks, %d failed%n", checks, failures);
        System.out.println(failures == 0 ? "[m4-layout-test] PASS" : "[m4-layout-test] FAIL");
        System.exit(failures == 0 ? 0 : 1);
    }

    // ------------------------------------------------------------------------------------------
    private static void constantsMatchTheDocumentedTable() {
        section("ABI v3 constants == documented table");
        checkEq("ABI_VERSION", VrmcBridge.ABI_VERSION, 3);
        checkEq("INPUT_BYTES", VrmcBridge.INPUT_BYTES, L_INPUT_BYTES);
        checkEq("INPUT_OFF_FRAME_INDEX", VrmcBridge.INPUT_OFF_FRAME_INDEX, L_OFF_FRAME_INDEX);
        checkEq("INPUT_OFF_VALID_MASK", VrmcBridge.INPUT_OFF_VALID_MASK, L_OFF_VALID_MASK);
        checkEq("INPUT_OFF_TIMESTAMP", VrmcBridge.INPUT_OFF_TIMESTAMP, L_OFF_TIMESTAMP);
        checkEq("INPUT_OFF_HANDS", VrmcBridge.INPUT_OFF_HANDS, L_OFF_HANDS);
        checkEq("HAND_STATE_BYTES", VrmcBridge.HAND_STATE_BYTES, L_HAND_STATE_BYTES);
        checkEq("HAND_STRIDE", VrmcBridge.HAND_STRIDE, L_HAND_STRIDE);
        checkEq("HAND_OFF_TRACKED", VrmcBridge.HAND_OFF_TRACKED, L_TRACKED);
        checkEq("HAND_OFF_CHIRALITY", VrmcBridge.HAND_OFF_CHIRALITY, L_CHIRALITY);
        checkEq("HAND_OFF_TIMESTAMP", VrmcBridge.HAND_OFF_TIMESTAMP, L_HAND_TIMESTAMP);
        checkEq("HAND_OFF_WRIST_QUAT", VrmcBridge.HAND_OFF_WRIST_QUAT, L_WRIST_QUAT);
        checkEq("HAND_OFF_WRIST_POS", VrmcBridge.HAND_OFF_WRIST_POS, L_WRIST_POS);
        checkEq("HAND_OFF_JOINTS", VrmcBridge.HAND_OFF_JOINTS, L_JOINTS);
        checkEq("JOINT_STRIDE", VrmcBridge.JOINT_STRIDE, L_JOINT_STRIDE);
        checkEq("JOINT_COUNT", VrmcBridge.JOINT_COUNT, L_JOINT_COUNT);
        // VisionInput re-exports the same contract for the gesture engine and the host tests.
        checkEq("VisionInput.INPUT_BYTES", VisionInput.INPUT_BYTES, L_INPUT_BYTES);
        checkEq("VisionInput.INPUT_OFF_HANDS", VisionInput.INPUT_OFF_HANDS, L_OFF_HANDS);
        checkEq("VisionInput.HAND_STATE_BYTES", VisionInput.HAND_STATE_BYTES, L_HAND_STATE_BYTES);
        checkEq("VisionInput.HAND_OFF_JOINTS", VisionInput.HAND_OFF_JOINTS, L_JOINTS);
        checkEq("VisionInput.JOINT_COUNT", VisionInput.JOINT_COUNT, L_JOINT_COUNT);
        // Consumer joint indices (design §3.1 / ARKit order).
        checkEq("JOINT_WRIST", VrmcBridge.JOINT_WRIST, 0);
        checkEq("JOINT_THUMB_TIP", VrmcBridge.JOINT_THUMB_TIP, 4);
        checkEq("JOINT_INDEX_METACARPAL", VrmcBridge.JOINT_INDEX_METACARPAL, 5);
        checkEq("JOINT_INDEX_TIP", VrmcBridge.JOINT_INDEX_TIP, 9);
        checkEq("JOINT_MIDDLE_KNUCKLE", VrmcBridge.JOINT_MIDDLE_KNUCKLE, 11);
        checkEq("JOINT_MIDDLE_TIP", VrmcBridge.JOINT_MIDDLE_TIP, 14);
        checkEq("JOINT_RING_TIP", VrmcBridge.JOINT_RING_TIP, 19);
        checkEq("JOINT_LITTLE_METACARPAL", VrmcBridge.JOINT_LITTLE_METACARPAL, 20);
        checkEq("JOINT_LITTLE_TIP", VrmcBridge.JOINT_LITTLE_TIP, 24);
    }

    // ------------------------------------------------------------------------------------------
    private static void arithmeticIdentities() {
        section("layout arithmetic (alignment/padding identities)");
        check("sizeof(hands[2]) fills the struct: 16 + 2*368 == 752",
            L_OFF_HANDS + 2 * L_HAND_STATE_BYTES == L_INPUT_BYTES);
        check("hands[1] offset == 384", L_OFF_HANDS + L_HAND_STRIDE == L_HAND1);
        check("hand_state: joints end == 368",
            L_JOINTS + L_JOINT_COUNT * L_JOINT_STRIDE == L_HAND_STATE_BYTES);
        check("vrmc_vec3 == 12 bytes", L_JOINT_STRIDE == 3 * Float.BYTES);
        check("input struct 8-byte aligned", L_INPUT_BYTES % 8 == 0);
        check("hand struct 8-byte aligned", L_HAND_STATE_BYTES % 8 == 0);
        check("u64 fields 8-byte aligned",
            L_OFF_TIMESTAMP % 8 == 0 && L_HAND_TIMESTAMP % 8 == 0);
        check("quat/vec3 alignment", L_WRIST_QUAT % 4 == 0 && L_WRIST_POS % 4 == 0 && L_JOINTS % 4 == 0);
        check("joint array has no implicit padding",
            L_JOINTS + 27 * 12 == 368 && 368 - L_JOINTS - 27 * 12 == 0);
        // unchanged layout of the pre-existing ABI structs (v3 must not disturb them)
        checkEq("TRACKING_BYTES (v2 contract)", VrmcBridge.TRACKING_BYTES, 8 + 28 + 28 + 28 + 4);
        checkEq("FRAME_TIMING_BYTES (v2 contract)", VrmcBridge.FRAME_TIMING_BYTES, 48);
        checkEq("DISPLAY_VIEWS_BYTES (v2 contract)", VrmcBridge.DISPLAY_VIEWS_BYTES, (4 + 16 + 4 + 16 + 1) * 4);
    }

    // ------------------------------------------------------------------------------------------
    private static void parseRoundTripAtLiteralOffsets() {
        section("round-trip snapshot written at literal documented offsets");
        ByteBuffer b = ByteBuffer.allocateDirect(L_INPUT_BYTES).order(ByteOrder.LITTLE_ENDIAN);
        b.putInt(L_OFF_FRAME_INDEX, 42);
        b.putInt(L_OFF_VALID_MASK, 1);          // bit0 = LEFT tracked only
        b.putLong(L_OFF_TIMESTAMP, 777L);
        int left = L_HAND0;
        b.putInt(left + L_TRACKED, 1);
        b.putInt(left + L_CHIRALITY, 0);
        b.putLong(left + L_HAND_TIMESTAMP, 111L);
        b.putFloat(left + L_WRIST_QUAT, 0.0F);
        b.putFloat(left + L_WRIST_QUAT + 4, 0.0F);
        b.putFloat(left + L_WRIST_QUAT + 8, 0.0F);
        b.putFloat(left + L_WRIST_QUAT + 12, 1.0F);
        b.putFloat(left + L_WRIST_POS, 1.5F);
        b.putFloat(left + L_WRIST_POS + 4, 2.5F);
        b.putFloat(left + L_WRIST_POS + 8, 3.5F);
        // deterministic joint fill so every joint is finite
        for (int i = 0; i < L_JOINT_COUNT; i++) {
            b.putFloat(left + L_JOINTS + i * L_JOINT_STRIDE, 0.01F * i);
            b.putFloat(left + L_JOINTS + i * L_JOINT_STRIDE + 4, 0.02F * i);
            b.putFloat(left + L_JOINTS + i * L_JOINT_STRIDE + 8, 0.03F * i);
        }
        int right = L_HAND1;
        b.putInt(right + L_TRACKED, 0);
        b.putInt(right + L_CHIRALITY, 1);
        b.putLong(right + L_HAND_TIMESTAMP, 222L);
        b.putFloat(right + L_WRIST_POS, 4.5F);
        b.putFloat(right + L_WRIST_POS + 4, 5.5F);
        b.putFloat(right + L_WRIST_POS + 8, 6.5F);
        for (int i = 0; i < L_JOINT_COUNT; i++) {
            b.putFloat(right + L_JOINTS + i * L_JOINT_STRIDE, -0.01F * i);
            b.putFloat(right + L_JOINTS + i * L_JOINT_STRIDE + 4, -0.02F * i);
            b.putFloat(right + L_JOINTS + i * L_JOINT_STRIDE + 8, -0.03F * i);
        }

        VisionInput in = new VisionInput();
        in.poll(b, 0, 1_000_000_000L);
        checkEq("frame_index", in.frameIndex(), 42);
        checkEq("valid_mask", in.validMask(), 1);
        checkEq("timestamp_ns", in.snapshotTimestampNs(), 777L);
        check("LEFT tracked", in.isHandTracked(VisionInput.HAND_LEFT));
        check("RIGHT untracked", !in.isHandTracked(VisionInput.HAND_RIGHT));
        checkEq("LEFT chirality", in.chirality(VisionInput.HAND_LEFT), 0);
        checkEq("RIGHT chirality (parsed even when untracked)", in.chirality(VisionInput.HAND_RIGHT), 1);
        checkClose("LEFT wrist x", in.wristX(VisionInput.HAND_LEFT), 1.5F);
        checkClose("LEFT wrist y", in.wristY(VisionInput.HAND_LEFT), 2.5F);
        checkClose("LEFT wrist z", in.wristZ(VisionInput.HAND_LEFT), 3.5F);
        checkClose("RIGHT wrist x (untracked data still parsed)", in.wristX(VisionInput.HAND_RIGHT), 4.5F);
        float[] joints = in.joints(VisionInput.HAND_LEFT);
        checkClose("joint 0 x at documented offset", joints[0], 0.0F);
        checkClose("joint 4 x at documented offset", joints[4 * 3], 0.04F);
        checkClose("joint 9 z at documented offset", joints[9 * 3 + 2], 0.27F);
        checkClose("joint 26 z at documented offset", joints[26 * 3 + 2], 0.78F);
        check("no hand data was flagged invalid", in.invalidHandMask() == 0);

        // hands[] must be indexed by slot (LEFT first) independently of the chirality field
        check("slot 0 is LEFT by contract", VisionInput.HAND_LEFT == 0);
        check("slot 1 is RIGHT by contract", VisionInput.HAND_RIGHT == 1);
        check("origins: 1 = LEFT, 2 = RIGHT",
            VisionInput.originForHand(VisionInput.HAND_LEFT) == 1L
                && VisionInput.originForHand(VisionInput.HAND_RIGHT) == 2L);
    }

    // ------------------------------------------------------------------------------------------
    private static void capsAndHandshakeContract() {
        section("ABI v3 caps/handshake contract");
        String expected = "{\"abi\":3,\"eyes\":2,\"hands\":2,\"input\":1}";
        check("caps JSON is exactly the design §3 value (actual=" + VrmcBridge.CAPS_JSON + ")",
            expected.equals(VrmcBridge.CAPS_JSON));
        check("caps advertise the input capability", VrmcBridge.CAPS_JSON.contains("\"input\":1"));
        check("caps advertise the v3 ABI", VrmcBridge.CAPS_JSON.contains("\"abi\":3"));
        check("caps advertise 2 hands", VrmcBridge.CAPS_JSON.contains("\"hands\":2"));
        check("provider poll wrapper exists (nativePollInput binding)",
            VrmcBridge.class.getDeclaredMethods().length > 0);
        check("pollInput(ByteBuffer) is a static wrapper", java.util.Arrays.stream(VrmcBridge.class.getMethods())
            .anyMatch(m -> m.getName().equals("pollInput") && m.getParameterCount() == 1
                && m.getParameterTypes()[0] == ByteBuffer.class));
        check("nativePollInput(ByteBuffer) is declared", java.util.Arrays.stream(VrmcBridge.class.getDeclaredMethods())
            .anyMatch(m -> m.getName().equals("nativePollInput") && m.getParameterCount() == 1
                && m.getParameterTypes()[0] == ByteBuffer.class));
    }

    // ------------------------------------------------------------------------------------------
    // Assertions
    // ------------------------------------------------------------------------------------------
    private static void section(String name) {
        System.out.println();
        System.out.println("== " + name + " ==");
    }

    private static void check(String label, boolean ok) {
        checks++;
        if (!ok) failures++;
        System.out.printf("  %-90s %s%n", label, ok ? "ok" : "FAIL");
    }

    private static void checkEq(String label, int actual, int expected) {
        check(label + " == " + expected + " (actual=" + actual + ")", actual == expected);
    }

    private static void checkEq(String label, long actual, long expected) {
        check(label + " == " + expected + " (actual=" + actual + ")", actual == expected);
    }

    private static void checkClose(String label, float actual, float expected) {
        check(label + " == " + expected + " (actual=" + actual + ")",
            Float.isFinite(actual) && Math.abs(actual - expected) <= 1.0E-6F);
    }
}
