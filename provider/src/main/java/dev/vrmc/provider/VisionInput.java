package dev.vrmc.provider;

import dev.vrmc.provider.bridge.VrmcBridge;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * M4-W1 gesture engine: parses the native {@code vrmc_input_state} snapshot (ABI v3), turns the
 * ARKit 27-joint hand tracking into per-hand digital gesture sources, and exposes them as the W1
 * Vivecraft action table.
 *
 * <p><b>Pure Java by design</b>: this class must not import Minecraft or Vivecraft types. It is
 * host-unit-tested through synthetic 752-byte snapshots (VisionInputTest, VisionInputLayoutTest) and
 * against the C-produced cross-language fixture (VisionInputFixtureTest); {@link VisionVR} is the
 * only game-side consumer. All per-frame state is preallocated; {@link #poll(ByteBuffer, int, long)}
 * allocates nothing.
 *
 * <p>Safety invariants (design §5.3, G4 minimum - the safety-critical failure is STUCK INPUT):
 * <ul>
 *   <li>a hand that is not tracked releases all of its sources on the same frame;</li>
 *   <li>input older than the stale timeout (compositor stopped/frozen) releases everything;</li>
 *   <li>each source must be continuously released for the arming time after acquisition before it may
 *       present a press (a relaxed/occluded hand can never boot as a stuck press);</li>
 *   <li>fist-tap and both-fist sources are 2-frame press edges, never latches;</li>
 *   <li>chord priority: while both fists are engaged the both-fist chord owns the gesture, so the
 *       per-hand fist taps are suppressed (a both-fists hold fires only the inventory action, never a
 *       simultaneous click + Escape + inventory); a consumed hold does not fire a deferred per-hand
 *       tap when one hand opens, and single-hand taps keep working while the other hand is open.</li>
 * </ul>
 *
 * <p>Origin convention (design §5.4, same as macstream's TouchPlusInput): {@code 1 = LEFT},
 * {@code 2 = RIGHT}; {@link VisionVR#getOriginName(long)} renders those to Vivecraft.
 */
public final class VisionInput {
    // ---- hand slots inside vrmc_input_state.hands[] (ABI order is explicit, not chirality) ----
    public static final int HAND_LEFT = 0;
    public static final int HAND_RIGHT = 1;
    public static final int HAND_COUNT = 2;
    /** No specific hand (both-fist source). */
    public static final int HAND_NONE = -1;

    /** Origin handles exposed through MCVR.getOrigins / getLastOrigin (1 = LEFT, 2 = RIGHT). */
    public static final long ORIGIN_LEFT = 1L;
    public static final long ORIGIN_RIGHT = 2L;

    // ---- ABI v3 layout aliases (the contract lives in VrmcBridge; asserted by VisionInputLayoutTest) ----
    public static final int INPUT_BYTES = VrmcBridge.INPUT_BYTES;
    public static final int INPUT_OFF_FRAME_INDEX = VrmcBridge.INPUT_OFF_FRAME_INDEX;
    public static final int INPUT_OFF_VALID_MASK = VrmcBridge.INPUT_OFF_VALID_MASK;
    public static final int INPUT_OFF_TIMESTAMP = VrmcBridge.INPUT_OFF_TIMESTAMP;
    public static final int INPUT_OFF_HANDS = VrmcBridge.INPUT_OFF_HANDS;
    public static final int HAND_STATE_BYTES = VrmcBridge.HAND_STATE_BYTES;
    public static final int HAND_STRIDE = VrmcBridge.HAND_STRIDE;
    public static final int HAND_OFF_TRACKED = VrmcBridge.HAND_OFF_TRACKED;
    public static final int HAND_OFF_CHIRALITY = VrmcBridge.HAND_OFF_CHIRALITY;
    public static final int HAND_OFF_TIMESTAMP = VrmcBridge.HAND_OFF_TIMESTAMP;
    public static final int HAND_OFF_WRIST_QUAT = VrmcBridge.HAND_OFF_WRIST_QUAT;
    public static final int HAND_OFF_WRIST_POS = VrmcBridge.HAND_OFF_WRIST_POS;
    public static final int HAND_OFF_JOINTS = VrmcBridge.HAND_OFF_JOINTS;
    public static final int JOINT_STRIDE = VrmcBridge.JOINT_STRIDE;
    public static final int JOINT_COUNT = VrmcBridge.JOINT_COUNT;
    // Consumer joint indices (ARKit order, design §3.1).
    public static final int JOINT_WRIST = VrmcBridge.JOINT_WRIST;
    public static final int JOINT_THUMB_TIP = VrmcBridge.JOINT_THUMB_TIP;
    public static final int JOINT_INDEX_METACARPAL = VrmcBridge.JOINT_INDEX_METACARPAL;
    public static final int JOINT_INDEX_TIP = VrmcBridge.JOINT_INDEX_TIP;
    public static final int JOINT_MIDDLE_KNUCKLE = VrmcBridge.JOINT_MIDDLE_KNUCKLE;
    public static final int JOINT_MIDDLE_TIP = VrmcBridge.JOINT_MIDDLE_TIP;
    public static final int JOINT_RING_TIP = VrmcBridge.JOINT_RING_TIP;
    public static final int JOINT_LITTLE_METACARPAL = VrmcBridge.JOINT_LITTLE_METACARPAL;
    public static final int JOINT_LITTLE_TIP = VrmcBridge.JOINT_LITTLE_TIP;
    private static final int FLOATS_PER_JOINT = 3;
    private static final int JOINT_FLOATS = JOINT_COUNT * FLOATS_PER_JOINT;

    // ---- W1 action names: the EXACT KeyMapping names MCVR.getInputAction(String) is keyed by ----
    public static final String KEY_ATTACK = "key.attack";
    public static final String KEY_USE = "key.use";
    public static final String KEY_INVENTORY = "key.inventory";
    // M4-W3 middle-pinch family (thumb tip to middle tip; disjoint from the thumb-index pinch).
    public static final String KEY_JUMP = "key.jump";
    public static final String KEY_SNEAK = "key.sneak";
    public static final String KEY_TELEPORT = "vivecraft.key.teleport";
    public static final String KEY_VR_INTERACT = "vivecraft.key.vrInteract";
    public static final String KEY_CLIMBEY_GRAB = "vivecraft.key.climbeyGrab";
    public static final String KEY_GUI_LEFT_CLICK = "vivecraft.key.guiLeftClick";
    public static final String KEY_GUI_RIGHT_CLICK = "vivecraft.key.guiRightClick";
    public static final String KEY_GUI_SHIFT = "vivecraft.key.guiShift";
    public static final String KEY_INGAME_MENU = "vivecraft.key.ingameMenuButton";

    // ---- default tuning (design §5.3); overridable via vrmc-input-tune.properties / -D ----
    public static final String TUNE_FILE = "vrmc-input-tune.properties";
    public static final String TUNE_PROPERTY_PREFIX = "vrmc.input.";
    public static final String TUNE_PINCH_ON = "pinch.on";
    public static final String TUNE_PINCH_OFF = "pinch.off";
    public static final String TUNE_FIST_ON = "fist.on";
    public static final String TUNE_FIST_OFF = "fist.off";
    public static final String TUNE_MIDDLE_ON = "middle.on";
    public static final String TUNE_MIDDLE_OFF = "middle.off";
    public static final String TUNE_MIDDLE_TAP_MS = "middle.tapMs";
    public static final String TUNE_MIDDLE_DOUBLE_MS = "middle.doubleMs";
    /** A/B safety switch: the whole M4-W3 middle-pinch family (default ON; set false to keep W1-only). */
    public static final String TUNE_MIDDLE_ENABLED = "middle.enabled";
    public static final String TUNE_FIST_HOLD_MS = "fist.hold.ms";
    public static final String TUNE_ARM_MS = "arm.ms";
    public static final String TUNE_STALE_MS = "stale.ms";
    public static final String TUNE_TAP_FRAMES = "tap.frames";

    public static final float DEFAULT_PINCH_ON = 0.030F;
    public static final float DEFAULT_PINCH_OFF = 0.045F;
    public static final float DEFAULT_FIST_ON = 1.25F;
    public static final float DEFAULT_FIST_OFF = 1.55F;
    /** Middle-pinch thresholds (metres, thumb tip to middle tip). */
    public static final float DEFAULT_MIDDLE_ON = 0.035F;
    public static final float DEFAULT_MIDDLE_OFF = 0.050F;
    public static final long DEFAULT_MIDDLE_TAP_MS = 220L;
    public static final long DEFAULT_MIDDLE_DOUBLE_MS = 320L;
    public static final long DEFAULT_FIST_HOLD_MS = 400L;
    public static final long DEFAULT_ARM_MS = 100L;
    public static final long DEFAULT_STALE_MS = 250L;
    public static final int DEFAULT_TAP_FRAMES = 2;

    private static final float EPSILON = 1.0E-6F;

    /** Vivecraft action sets this provider binds into (mirrors VRInputActionSet names). */
    public enum ActionSet {
        INGAME, GUI, GLOBAL, CONTEXTUAL, KEYBOARD
    }

    private static final int SRC_PINCH = 0;
    private static final int SRC_FIST_TAP = 1;
    private static final int SRC_BOTH_FIST_TAP = 2;
    private static final int SRC_MIDDLE_PINCH = 3;
    private static final int SRC_MIDDLE_TAP = 4;
    private static final int SRC_MIDDLE_DOUBLE_TAP = 5;

    /** One row of the design §5.4 binding table. */
    private static final class BindingDef {
        final String action;
        final int hand;
        final int source;
        final ActionSet set;

        BindingDef(String action, int hand, int source, ActionSet set) {
            this.action = action;
            this.hand = hand;
            this.source = source;
            this.set = set;
        }
    }

    /** W1 binding table, design §5.4 (vivecraft Oculus-profile parity for the actions W1 needs). */
    private static final BindingDef[] BINDINGS = {
        new BindingDef(KEY_ATTACK, HAND_RIGHT, SRC_PINCH, ActionSet.INGAME),
        new BindingDef(KEY_USE, HAND_RIGHT, SRC_FIST_TAP, ActionSet.INGAME),
        new BindingDef(KEY_TELEPORT, HAND_LEFT, SRC_PINCH, ActionSet.INGAME),
        new BindingDef(KEY_VR_INTERACT, HAND_LEFT, SRC_PINCH, ActionSet.CONTEXTUAL),
        new BindingDef(KEY_VR_INTERACT, HAND_RIGHT, SRC_PINCH, ActionSet.CONTEXTUAL),
        new BindingDef(KEY_CLIMBEY_GRAB, HAND_LEFT, SRC_PINCH, ActionSet.CONTEXTUAL),
        new BindingDef(KEY_CLIMBEY_GRAB, HAND_RIGHT, SRC_PINCH, ActionSet.CONTEXTUAL),
        new BindingDef(KEY_GUI_LEFT_CLICK, HAND_RIGHT, SRC_PINCH, ActionSet.GUI),
        new BindingDef(KEY_GUI_RIGHT_CLICK, HAND_RIGHT, SRC_FIST_TAP, ActionSet.GUI),
        new BindingDef(KEY_GUI_SHIFT, HAND_LEFT, SRC_PINCH, ActionSet.GUI),
        new BindingDef(KEY_INGAME_MENU, HAND_LEFT, SRC_FIST_TAP, ActionSet.GLOBAL),
        new BindingDef(KEY_INVENTORY, HAND_NONE, SRC_BOTH_FIST_TAP, ActionSet.GLOBAL),
        // M4-W3: middle-pinch family (left movement/snap handled as analog by VisionVR).
        new BindingDef(KEY_JUMP, HAND_RIGHT, SRC_MIDDLE_TAP, ActionSet.INGAME),
        new BindingDef(KEY_SNEAK, HAND_RIGHT, SRC_MIDDLE_PINCH, ActionSet.INGAME),
    };

    /** Unique action names in binding-table order (used to resolve VRInputActions once). */
    public static final String[] ACTION_NAMES;
    private static final long[] BINDING_ORIGIN;
    private static final Map<String, List<Long>> ORIGINS_BY_ACTION;

    static {
        List<String> names = new ArrayList<>();
        Map<String, List<Long>> origins = new LinkedHashMap<>();
        BINDING_ORIGIN = new long[BINDINGS.length];
        for (int i = 0; i < BINDINGS.length; i++) {
            BindingDef b = BINDINGS[i];
            long origin = originForHand(b.hand);
            BINDING_ORIGIN[i] = origin;
            if (!names.contains(b.action)) names.add(b.action);
            List<Long> list = origins.computeIfAbsent(b.action, n -> new ArrayList<>(2));
            if (b.hand == HAND_NONE) {
                // both-fist (key.inventory): either hand is a valid origin; data is stamped with the
                // main-hand origin (2) because non-handed actions only carry one activeOrigin.
                if (!list.contains(ORIGIN_LEFT)) list.add(ORIGIN_LEFT);
                if (!list.contains(ORIGIN_RIGHT)) list.add(ORIGIN_RIGHT);
            } else if (!list.contains(origin)) {
                list.add(origin);
            }
        }
        ACTION_NAMES = names.toArray(new String[0]);
        Map<String, List<Long>> frozen = new LinkedHashMap<>();
        for (Map.Entry<String, List<Long>> e : origins.entrySet()) {
            frozen.put(e.getKey(), Collections.unmodifiableList(e.getValue()));
        }
        ORIGINS_BY_ACTION = Collections.unmodifiableMap(frozen);
    }

    private static final class Hand {
        boolean tracked;
        int chirality;
        long timestampNs;
        float qx, qy, qz, qw;
        float wx, wy, wz;
        final float[] joints = new float[JOINT_FLOATS];
        float pinchDistance = Float.NaN;
        float fistRatio = Float.NaN;

        // --- per-source gesture state machine (released-state arming + hysteresis) ---
        boolean pinchRaw;
        boolean pinchArmed;
        boolean pinchPressed;
        long pinchReleasedSinceNs;

        boolean fistRaw;
        boolean fistArmed;
        boolean fistPressed;
        long fistReleasedSinceNs;

        // --- fist tap hold detector / 2-frame pulse ---
        boolean fistHeld;
        long fistHoldStartNs;
        boolean fistTapFired;
        int fistTapFrames;
        boolean fistTapPressed;

        // --- M4-W3 middle-pinch gesture (thumb tip 4 <-> middle tip 14) ---
        float middleDistance = Float.NaN;
        boolean middleRaw;
        boolean middleArmed;
        boolean middlePressed;
        long middleReleasedSinceNs;
        boolean middlePressCandidate;
        long middlePressStartNs;
        long lastMiddleTapNs;
        int middleTapFrames;
        int middleDoubleTapFrames;
        boolean middleTapPressed;
        boolean middleDoubleTapPressed;
    }

    private final Hand[] hands = {new Hand(), new Hand()};

    private final float pinchOn;
    private final float pinchOff;
    private final float fistOn;
    private final float fistOff;
    private final boolean middleEnabled;
    private final float middleOn;
    private final float middleOff;
    private final long middleTapNanos;
    private final long middleDoubleNanos;
    private final long fistHoldNanos;
    private final long armNanos;
    private final long staleNanos;
    private final int tapFrames;

    // snapshot state
    private boolean hasSnapshot;
    private int frameIndex;
    private int validMask;
    private long snapshotTimestampNs;
    private long lastFrameIndex;
    private long lastSnapshotTimestampNs;
    private long lastChangeNs;
    private long lastPollNs;
    private boolean stale;
    private boolean inputHealthy;
    private boolean publishEvidence;
    private int invalidHandMask;

    // both-fist tap (global / key.inventory)
    private boolean bothFistHeld;
    private long bothFistHoldStartNs;
    private boolean bothFistFired;
    private int bothFistTapFrames;
    private boolean bothFistTapPressed;

    // action-set environment (MCOpenVR.updateActiveActionSets equivalent; set by VisionVR each frame)
    private boolean screenOpen;
    private boolean ingameBindingsInGui;
    private boolean keyboardShowing;

    public VisionInput() {
        this(Map.of());
    }

    /**
     * @param fileTuning values read from {@code vrmc-input-tune.properties} in the game directory
     *                   (may be empty); individual {@code -Dvrmc.input.*} system properties override it.
     */
    public VisionInput(Map<String, String> fileTuning) {
        Map<String, String> tune = fileTuning == null ? Map.of() : fileTuning;
        this.pinchOn = tuneFloat(tune, TUNE_PINCH_ON, DEFAULT_PINCH_ON);
        this.pinchOff = tuneFloat(tune, TUNE_PINCH_OFF, DEFAULT_PINCH_OFF);
        this.fistOn = tuneFloat(tune, TUNE_FIST_ON, DEFAULT_FIST_ON);
        this.fistOff = tuneFloat(tune, TUNE_FIST_OFF, DEFAULT_FIST_OFF);
        this.middleEnabled = tuneBool(tune, TUNE_MIDDLE_ENABLED, true);
        this.middleOn = tuneFloat(tune, TUNE_MIDDLE_ON, DEFAULT_MIDDLE_ON);
        this.middleOff = tuneFloat(tune, TUNE_MIDDLE_OFF, DEFAULT_MIDDLE_OFF);
        this.middleTapNanos = tuneLong(tune, TUNE_MIDDLE_TAP_MS, DEFAULT_MIDDLE_TAP_MS) * 1_000_000L;
        this.middleDoubleNanos = tuneLong(tune, TUNE_MIDDLE_DOUBLE_MS, DEFAULT_MIDDLE_DOUBLE_MS) * 1_000_000L;
        this.fistHoldNanos = tuneLong(tune, TUNE_FIST_HOLD_MS, DEFAULT_FIST_HOLD_MS) * 1_000_000L;
        this.armNanos = tuneLong(tune, TUNE_ARM_MS, DEFAULT_ARM_MS) * 1_000_000L;
        this.staleNanos = tuneLong(tune, TUNE_STALE_MS, DEFAULT_STALE_MS) * 1_000_000L;
        this.tapFrames = (int) tuneLong(tune, TUNE_TAP_FRAMES, DEFAULT_TAP_FRAMES);
    }

    // ------------------------------------------------------------------------------------------
    // Tuning
    // ------------------------------------------------------------------------------------------

    private static float tuneFloat(Map<String, String> tune, String key, float def) {
        String raw = tuneValue(tune, key);
        if (raw == null) return def;
        try {
            float v = Float.parseFloat(raw.trim());
            return Float.isFinite(v) && v > 0.0F ? v : def;
        } catch (NumberFormatException e) {
            return def;
        }
    }

    private static boolean tuneBool(Map<String, String> tune, String key, boolean def) {
        String raw = tuneValue(tune, key);
        if (raw == null) return def;
        return "true".equalsIgnoreCase(raw.trim()) || "1".equals(raw.trim());
    }

    private static long tuneLong(Map<String, String> tune, String key, long def) {
        String raw = tuneValue(tune, key);
        if (raw == null) return def;
        try {
            long v = Long.parseLong(raw.trim());
            return v > 0L ? v : def;
        } catch (NumberFormatException e) {
            return def;
        }
    }

    private static String tuneValue(Map<String, String> tune, String key) {
        String v = System.getProperty(TUNE_PROPERTY_PREFIX + key);
        if (v == null || v.isBlank()) v = tune.get(key);
        return (v == null || v.isBlank()) ? null : v;
    }

    public float pinchOn() { return this.pinchOn; }
    public float pinchOff() { return this.pinchOff; }
    public float fistOn() { return this.fistOn; }
    public float fistOff() { return this.fistOff; }
    public boolean middleEnabled() { return this.middleEnabled; }
    public float middleOn() { return this.middleOn; }
    public float middleOff() { return this.middleOff; }
    public long middleTapMillis() { return this.middleTapNanos / 1_000_000L; }
    public long middleDoubleMillis() { return this.middleDoubleNanos / 1_000_000L; }
    public long fistHoldMillis() { return this.fistHoldNanos / 1_000_000L; }
    public long armMillis() { return this.armNanos / 1_000_000L; }
    public long staleMillis() { return this.staleNanos / 1_000_000L; }
    public int tapFrames() { return this.tapFrames; }

    // ------------------------------------------------------------------------------------------
    // Per-frame poll + gesture engine
    // ------------------------------------------------------------------------------------------

    /**
     * Parse one raw {@code vrmc_input_state} and run one gesture-engine frame.
     *
     * @param snapshot preallocated native-order buffer positioned at the record start (the single
     *                 752-byte snapshot or one record inside a concatenated fixture sequence)
     * @param nativeRc result of {@code VrmcBridge.pollInput}: 0 = success, nonzero = rejected
     *                 (malformed/short/uninitialized/broken channel) -> treated as untracked
     * @param nowNs    monotonic nanoseconds ({@link System#nanoTime()} in game; a test clock otherwise)
     * @return true when the snapshot was structurally accepted
     */
    public boolean poll(ByteBuffer snapshot, int nativeRc, long nowNs) {
        this.lastPollNs = nowNs;
        if (nativeRc != 0 || snapshot == null) {
            this.inputHealthy = false;
            this.stale = false;
            releaseEverything();
            return false;
        }
        if (snapshot.capacity() < INPUT_BYTES || snapshot.position() < 0
            || snapshot.capacity() - snapshot.position() < INPUT_BYTES) {
            this.inputHealthy = false;
            this.stale = false;
            releaseEverything();
            return false;
        }

        ByteOrder savedOrder = snapshot.order();
        snapshot.order(ByteOrder.LITTLE_ENDIAN);
        try {
            int base = snapshot.position();
            int frame = snapshot.getInt(base + INPUT_OFF_FRAME_INDEX);
            int mask = snapshot.getInt(base + INPUT_OFF_VALID_MASK);
            long timestamp = snapshot.getLong(base + INPUT_OFF_TIMESTAMP);

            boolean changed = !this.hasSnapshot || frame != this.frameIndex || timestamp != this.snapshotTimestampNs;
            this.hasSnapshot = true;
            this.frameIndex = frame;
            this.validMask = mask;
            this.snapshotTimestampNs = timestamp;
            if (changed) {
                this.lastChangeNs = nowNs;
            }
            if (timestamp != 0L || mask != 0) {
                this.publishEvidence = true;
            }

            // Read every hand first (also detects silent tracking loss if the bits drop).
            boolean anyTracked = false;
            int invalid = 0;
            for (int hand = 0; hand < HAND_COUNT; hand++) {
                boolean ok = parseHand(hand, snapshot, base + INPUT_OFF_HANDS + hand * HAND_STRIDE, mask, nowNs);
                if (!ok) invalid |= 1 << hand;
                anyTracked |= this.hands[hand].tracked;
            }
            this.invalidHandMask = invalid;

            // Staleness: the compositor stopped republishing (or froze the frame index). Ignore the
            // frozen payload and release everything; recover on the next observed publish.
            if (this.hasSnapshot && nowNs - this.lastChangeNs > this.staleNanos) {
                this.stale = true;
                this.inputHealthy = false;
                releaseEverything();
                return true;
            }
            this.stale = false;
            this.inputHealthy = true;

            updateGestures(nowNs);
            return true;
        } finally {
            snapshot.order(savedOrder);
        }
    }

    /** @return true when the hand slot was accepted and is tracked. */
    private boolean parseHand(int handIndex, ByteBuffer b, int off, int validMask, long nowNs) {
        Hand h = this.hands[handIndex];
        int trackedWord = b.getInt(off + HAND_OFF_TRACKED);
        int chirality = b.getInt(off + HAND_OFF_CHIRALITY);
        long timestamp = b.getLong(off + HAND_OFF_TIMESTAMP);
        float qx = b.getFloat(off + HAND_OFF_WRIST_QUAT);
        float qy = b.getFloat(off + HAND_OFF_WRIST_QUAT + 4);
        float qz = b.getFloat(off + HAND_OFF_WRIST_QUAT + 8);
        float qw = b.getFloat(off + HAND_OFF_WRIST_QUAT + 12);
        float wx = b.getFloat(off + HAND_OFF_WRIST_POS);
        float wy = b.getFloat(off + HAND_OFF_WRIST_POS + 4);
        float wz = b.getFloat(off + HAND_OFF_WRIST_POS + 8);

        boolean finite = isFinite(qx) && isFinite(qy) && isFinite(qz) && isFinite(qw)
            && isFinite(wx) && isFinite(wy) && isFinite(wz);
        for (int i = 0; i < JOINT_FLOATS && finite; i++) {
            float v = b.getFloat(off + HAND_OFF_JOINTS + i * 4);
            if (!isFinite(v)) {
                finite = false;
            } else {
                h.joints[i] = v;
            }
        }
        h.chirality = chirality;
        h.timestampNs = timestamp;
        h.qx = qx;
        h.qy = qy;
        h.qz = qz;
        h.qw = qw;
        h.wx = wx;
        h.wy = wy;
        h.wz = wz;

        boolean bit = ((validMask >> handIndex) & 1) != 0;
        boolean word = trackedWord != 0;
        boolean tracked = bit && word && finite;
        if (!tracked) {
            if (h.tracked) {
                h.tracked = false;
                resetGestures(h);
            }
            h.pinchDistance = Float.NaN;
            h.middleDistance = Float.NaN;
            h.fistRatio = Float.NaN;
            // "valid" return = the hand slot is a consistent untracked/valid record; mismatched
            // valid_mask bits vs the hand's own tracked word, or non-finite data, is malformed input
            // that VisionVR logs once (treated as untracked: fail safe).
            return finite && bit == word;
        }
        if (!h.tracked) {
            acquireHand(h, nowNs);
            h.tracked = true;
        }
        h.pinchDistance = distance(h.joints, VrmcBridge.JOINT_THUMB_TIP, VrmcBridge.JOINT_INDEX_TIP);
        h.middleDistance = distance(h.joints, VrmcBridge.JOINT_THUMB_TIP, VrmcBridge.JOINT_MIDDLE_TIP);
        h.fistRatio = fistRatio(h.joints);
        return true;
    }

    private static void acquireHand(Hand h, long nowNs) {
        h.pinchRaw = false;
        h.pinchArmed = false;
        h.pinchPressed = false;
        h.pinchReleasedSinceNs = nowNs;
        h.fistRaw = false;
        h.fistArmed = false;
        h.fistPressed = false;
        h.fistReleasedSinceNs = nowNs;
        h.fistHeld = false;
        h.fistTapFired = false;
        h.fistTapFrames = 0;
        h.fistTapPressed = false;
        h.middleDistance = Float.NaN;
        h.middleRaw = false;
        h.middleArmed = false;
        h.middlePressed = false;
        h.middleReleasedSinceNs = nowNs;
        h.middlePressCandidate = false;
        h.lastMiddleTapNs = 0L;
        h.middleTapFrames = 0;
        h.middleDoubleTapFrames = 0;
        h.middleTapPressed = false;
        h.middleDoubleTapPressed = false;
    }

    private static void resetGestures(Hand h) {
        h.pinchRaw = false;
        h.pinchArmed = false;
        h.pinchPressed = false;
        h.fistRaw = false;
        h.fistArmed = false;
        h.fistPressed = false;
        h.fistHeld = false;
        h.fistTapFired = false;
        h.fistTapFrames = 0;
        h.fistTapPressed = false;
        h.middleDistance = Float.NaN;
        h.middleRaw = false;
        h.middleArmed = false;
        h.middlePressed = false;
        h.middleReleasedSinceNs = 0L;
        h.middlePressCandidate = false;
        h.lastMiddleTapNs = 0L;
        h.middleTapFrames = 0;
        h.middleDoubleTapFrames = 0;
        h.middleTapPressed = false;
        h.middleDoubleTapPressed = false;
    }

    /** Release both hands, both-fist state and every source (tracking loss / stale / bad poll). */
    private void releaseEverything() {
        for (int hand = 0; hand < HAND_COUNT; hand++) {
            Hand h = this.hands[hand];
            h.tracked = false;
            resetGestures(h);
            h.pinchDistance = Float.NaN;
            h.middleDistance = Float.NaN;
            h.fistRatio = Float.NaN;
        }
        this.bothFistHeld = false;
        this.bothFistFired = false;
        this.bothFistTapFrames = 0;
        this.bothFistTapPressed = false;
    }

    private void updateGestures(long nowNs) {
        // Pass 1: pinch/fist source states for every hand (the chord decision needs both hands' fists).
        for (int hand = 0; hand < HAND_COUNT; hand++) {
            Hand h = this.hands[hand];
            if (!h.tracked) {
                resetGestures(h);
                continue;
            }
            updateSource(h, true, h.pinchDistance, nowNs);
            updateSource(h, false, h.fistRatio, nowNs);
            updateMiddleSource(h, nowNs);
        }
        // Both-fist chord priority (M4-W1 follow-up): while BOTH hands present the fist gesture the
        // chord owns the fist-tap gesture, so the per-hand taps are suppressed and a both-fists hold
        // fires ONLY key.inventory instead of simultaneously firing key.use/guiRightClick + Escape.
        boolean bothFistChord = this.hands[HAND_LEFT].fistPressed && this.hands[HAND_RIGHT].fistPressed;
        // Pass 2: chord-aware fist-tap hold detectors + the both-fist tap.
        for (int hand = 0; hand < HAND_COUNT; hand++) {
            Hand h = this.hands[hand];
            if (!h.tracked) {
                continue;
            }
            updateFistTap(h, nowNs, bothFistChord);
        }
        updateBothFistTap(bothFistChord, nowNs);
    }

    /**
     * Hysteresis + released-state arming for one source (pinch or fist).
     *
     * <p>Arming is evaluated BEFORE this frame's raw sample: if the source was released on the
     * previous frame and has been released continuously for {@link #armNanos}, it arms now and may
     * present this frame's press. A press attempted while unarmed is ignored and restarts the
     * continuous-release requirement when the hand finally opens.
     */
    private void updateSource(Hand h, boolean pinch, float metric, long nowNs) {
        boolean raw = pinch ? h.pinchRaw : h.fistRaw;
        boolean armed = pinch ? h.pinchArmed : h.fistArmed;
        long releasedSince = pinch ? h.pinchReleasedSinceNs : h.fistReleasedSinceNs;
        float on = pinch ? this.pinchOn : this.fistOn;
        float off = pinch ? this.pinchOff : this.fistOff;

        if (!armed && !raw && nowNs - releasedSince >= this.armNanos) {
            armed = true;
        }

        // press if metric < on; keep while metric <= off (design §5.3 hysteresis)
        boolean next = raw ? metric <= off : metric < on;
        boolean pressed = next && armed;

        if (!next) {
            if (raw) {
                // release edge: continuous release starts now
                releasedSince = nowNs;
            }
        } else if (!raw) {
            // press edge (armed or ignored)
        }
        if (next && !armed) {
            // ignored press attempt ends the continuous-release run used for arming
            releasedSince = nowNs;
        }

        if (pinch) {
            h.pinchRaw = next;
            h.pinchArmed = armed;
            h.pinchPressed = pressed;
            h.pinchReleasedSinceNs = releasedSince;
        } else {
            h.fistRaw = next;
            h.fistArmed = armed;
            h.fistPressed = pressed;
            h.fistReleasedSinceNs = releasedSince;
        }
    }

    /**
     * M4-W3 middle pinch: same hysteresis + released-state arming as pinch/fist, plus tap/double-tap
     * edge detection. A middle-pinch held longer than {@code middleTapNanos} can never produce a tap on
     * release (so the movement/sneak holds cannot accidentally snap-turn/jump); a short press yields a
     * 2-frame pulse, and two short presses within {@code middleDoubleNanos} yield a double-tap pulse.
     */
    private void updateMiddleSource(Hand h, long nowNs) {
        if (!this.middleEnabled) {
            h.middleRaw = false;
            h.middleArmed = false;
            h.middlePressed = false;
            h.middlePressCandidate = false;
            h.middleTapFrames = 0;
            h.middleDoubleTapFrames = 0;
            h.middleTapPressed = false;
            h.middleDoubleTapPressed = false;
            return;
        }
        boolean wasPressed = h.middlePressed;
        boolean raw = h.middleRaw;
        boolean armed = h.middleArmed;
        long releasedSince = h.middleReleasedSinceNs;

        if (!armed && !raw && nowNs - releasedSince >= this.armNanos) {
            armed = true;
        }
        boolean next = raw ? h.middleDistance <= this.middleOff : h.middleDistance < this.middleOn;
        boolean pressed = next && armed;

        if (next && !raw) {
            // press edge
            h.middlePressCandidate = true;
            h.middlePressStartNs = nowNs;
        }
        if (!next && raw && wasPressed) {
            // release edge: short press -> tap, and two taps -> double-tap
            if (h.middlePressCandidate && nowNs - h.middlePressStartNs <= this.middleTapNanos) {
                long last = h.lastMiddleTapNs;
                if (last != 0L && nowNs - last <= this.middleDoubleNanos) {
                    h.middleDoubleTapFrames = this.tapFrames;
                    h.lastMiddleTapNs = 0L;
                } else {
                    h.middleTapFrames = this.tapFrames;
                    h.lastMiddleTapNs = nowNs;
                }
            }
            h.middlePressCandidate = false;
        }
        if (pressed && h.middlePressCandidate && nowNs - h.middlePressStartNs > this.middleTapNanos) {
            h.middlePressCandidate = false;
        }
        if (next && !armed) {
            releasedSince = nowNs;
        } else if (!next && raw) {
            releasedSince = nowNs;
        }
        h.middleRaw = next;
        h.middleArmed = armed;
        h.middlePressed = pressed;
        h.middleReleasedSinceNs = releasedSince;
        h.middleTapPressed = h.middleTapFrames > 0;
        if (h.middleTapFrames > 0) h.middleTapFrames--;
        h.middleDoubleTapPressed = h.middleDoubleTapFrames > 0;
        if (h.middleDoubleTapFrames > 0) h.middleDoubleTapFrames--;
    }

    /**
     * Fist-tap: one 2-frame pulse after a continuous armed fist hold; re-armed on fist release.
     *
     * <p>Chord priority: while the both-fist chord is active ({@code chordActive}) the chord owns the
     * fist gesture - per-hand pulses are suppressed and any in-flight per-hand pulse is cancelled, so
     * a both-fists hold fires only the inventory action. The hold is still marked consumed
     * ({@code fistTapFired}) so opening one hand afterwards does not release a deferred per-hand tap
     * from the hand that is still held; a later separate hold fires normally.
     */
    private void updateFistTap(Hand h, long nowNs, boolean chordActive) {
        if (h.fistPressed) {
            if (!h.fistHeld) {
                h.fistHeld = true;
                h.fistHoldStartNs = nowNs;
                h.fistTapFired = false;
            }
            if (chordActive) {
                h.fistTapFired = true;
                h.fistTapFrames = 0;
            } else if (!h.fistTapFired && nowNs - h.fistHoldStartNs >= this.fistHoldNanos) {
                h.fistTapFired = true;
                h.fistTapFrames = this.tapFrames;
            }
        } else if (h.fistHeld) {
            h.fistHeld = false;
            h.fistTapFired = false; // re-armed on fist release
        }
        h.fistTapPressed = h.fistTapFrames > 0;
        if (h.fistTapFrames > 0) {
            h.fistTapFrames--;
        }
    }

    /** Both-fist tap: one 2-frame pulse per both-fist gesture (design §5.3). */
    private void updateBothFistTap(boolean both, long nowNs) {
        if (both) {
            if (!this.bothFistHeld) {
                this.bothFistHeld = true;
                this.bothFistHoldStartNs = nowNs;
                this.bothFistFired = false;
            }
            if (!this.bothFistFired && nowNs - this.bothFistHoldStartNs >= this.fistHoldNanos) {
                this.bothFistFired = true;
                this.bothFistTapFrames = this.tapFrames;
            }
        } else {
            this.bothFistHeld = false;
            this.bothFistFired = false;
        }
        this.bothFistTapPressed = this.bothFistTapFrames > 0;
        if (this.bothFistTapFrames > 0) {
            this.bothFistTapFrames--;
        }
    }

    private static boolean isFinite(float v) {
        return Float.isFinite(v);
    }

    private static float distance(float[] joints, int a, int b) {
        float dx = joints[a * FLOATS_PER_JOINT] - joints[b * FLOATS_PER_JOINT];
        float dy = joints[a * FLOATS_PER_JOINT + 1] - joints[b * FLOATS_PER_JOINT + 1];
        float dz = joints[a * FLOATS_PER_JOINT + 2] - joints[b * FLOATS_PER_JOINT + 2];
        return (float) Math.sqrt((double) (dx * dx + dy * dy + dz * dz));
    }

    private static float length(float[] joints, int joint, int origin) {
        float dx = joints[joint * FLOATS_PER_JOINT] - joints[origin * FLOATS_PER_JOINT];
        float dy = joints[joint * FLOATS_PER_JOINT + 1] - joints[origin * FLOATS_PER_JOINT + 1];
        float dz = joints[joint * FLOATS_PER_JOINT + 2] - joints[origin * FLOATS_PER_JOINT + 2];
        return (float) Math.sqrt((double) (dx * dx + dy * dy + dz * dz));
    }

    /**
     * Fist metric (design §5.3): {@code avg(|j9,j14,j19,j24 - j0|) / |j11 - j0|}. Lower = more
     * curled. A degenerate palm (|j11 - j0| ~ 0) can never present as a fist and yields +Infinity.
     */
    private static float fistRatio(float[] joints) {
        float palm = length(joints, VrmcBridge.JOINT_MIDDLE_KNUCKLE, VrmcBridge.JOINT_WRIST);
        if (!(palm > EPSILON) || !Float.isFinite(palm)) {
            return Float.POSITIVE_INFINITY;
        }
        float sum = length(joints, VrmcBridge.JOINT_INDEX_TIP, VrmcBridge.JOINT_WRIST)
            + length(joints, VrmcBridge.JOINT_MIDDLE_TIP, VrmcBridge.JOINT_WRIST)
            + length(joints, VrmcBridge.JOINT_RING_TIP, VrmcBridge.JOINT_WRIST)
            + length(joints, VrmcBridge.JOINT_LITTLE_TIP, VrmcBridge.JOINT_WRIST);
        return (sum * 0.25F) / palm;
    }

    // ------------------------------------------------------------------------------------------
    // Action-set gating (MCOpenVR.updateActiveActionSets shape; also macstream TouchPlusInput)
    // ------------------------------------------------------------------------------------------

    /**
     * Set the per-frame action-set environment. Mirrors MCOpenVR.updateActiveActionSets: INGAME when
     * no screen (or ingameBindingsInGui), CONTEXTUAL only when no screen, GUI while a screen is open,
     * KEYBOARD while the keyboard/radial overlay shows, everything else always.
     */
    public void setEnvironment(boolean screenOpen, boolean ingameBindingsInGui, boolean keyboardShowing) {
        this.screenOpen = screenOpen;
        this.ingameBindingsInGui = ingameBindingsInGui;
        this.keyboardShowing = keyboardShowing;
    }

    private boolean isSetActive(ActionSet set) {
        return switch (set) {
            case INGAME -> !this.screenOpen || this.ingameBindingsInGui;
            case CONTEXTUAL -> !this.screenOpen;
            case GUI -> this.screenOpen;
            case KEYBOARD -> this.keyboardShowing;
            default -> true; // GLOBAL
        };
    }

    // ------------------------------------------------------------------------------------------
    // Binding-table queries (consumed by VisionVR.processInputs and by the host tests)
    // ------------------------------------------------------------------------------------------

    public int bindingCount() { return BINDINGS.length; }
    public String bindingAction(int index) { return BINDINGS[index].action; }
    public int bindingHand(int index) { return BINDINGS[index].hand; }
    public ActionSet bindingActionSet(int index) { return BINDINGS[index].set; }
    public long bindingOrigin(int index) { return BINDING_ORIGIN[index]; }

    public boolean bindingActive(int index) { return isSetActive(BINDINGS[index].set); }
    public boolean bindingPressed(int index) {
        return bindingActive(index) && sourcePressed(BINDINGS[index].source, BINDINGS[index].hand);
    }

    private boolean sourcePressed(int source, int hand) {
        return switch (source) {
            case SRC_PINCH -> hand != HAND_NONE && this.hands[hand].pinchPressed;
            case SRC_FIST_TAP -> hand != HAND_NONE && this.hands[hand].fistTapPressed;
            case SRC_BOTH_FIST_TAP -> this.bothFistTapPressed;
            case SRC_MIDDLE_PINCH -> hand != HAND_NONE && this.hands[hand].middlePressed;
            case SRC_MIDDLE_TAP -> hand != HAND_NONE && this.hands[hand].middleTapPressed;
            case SRC_MIDDLE_DOUBLE_TAP -> hand != HAND_NONE && this.hands[hand].middleDoubleTapPressed;
            default -> false;
        };
    }

    /** @return true if any binding of this action is in an active set right now. */
    public boolean actionActive(String actionName) {
        for (int i = 0; i < BINDINGS.length; i++) {
            if (BINDINGS[i].action.equals(actionName) && bindingActive(i)) return true;
        }
        return false;
    }

    /** @return true if any hand-bound source of this action currently presents a press. */
    public boolean actionPressed(String actionName) {
        for (int i = 0; i < BINDINGS.length; i++) {
            if (BINDINGS[i].action.equals(actionName) && bindingPressed(i)) return true;
        }
        return false;
    }

    public boolean isBound(String actionName) {
        return ORIGINS_BY_ACTION.containsKey(actionName);
    }

    /** Bound origins for a KeyMapping name (1=LEFT, 2=RIGHT; immutable, empty if unbound). */
    public static List<Long> origins(String actionName) {
        return ORIGINS_BY_ACTION.getOrDefault(actionName, List.of());
    }

    /** Bound origins for a KeyMapping name with the action-set gating applied (same list). */
    public List<Long> originsOf(String actionName) {
        return origins(actionName);
    }

    public static long originForHand(int hand) {
        return switch (hand) {
            case HAND_LEFT -> ORIGIN_LEFT;
            case HAND_RIGHT -> ORIGIN_RIGHT;
            default -> ORIGIN_RIGHT; // both-fist (no specific hand): main hand
        };
    }

    public boolean isActionHanded(String actionName) {
        for (int i = 0; i < BINDINGS.length; i++) {
            if (BINDINGS[i].action.equals(actionName) && BINDINGS[i].hand != HAND_NONE) return true;
        }
        return false;
    }

    // ------------------------------------------------------------------------------------------
    // Diagnostics (used by VisionVR logging and the host tests)
    // ------------------------------------------------------------------------------------------

    public boolean hasSeenSnapshot() { return this.hasSnapshot; }
    /** True once the compositor published a non-zero snapshot (input really started flowing). */
    public boolean hasPublishEvidence() { return this.publishEvidence; }
    public boolean isStale() { return this.stale; }
    public boolean isInputHealthy() { return this.inputHealthy; }
    public int frameIndex() { return this.frameIndex; }
    public int validMask() { return this.validMask; }
    public long snapshotTimestampNs() { return this.snapshotTimestampNs; }
    /** Bit i set = hand i published tracked data that failed validation (treated as untracked). */
    public int invalidHandMask() { return this.invalidHandMask; }
    public long lastPollNanos() { return this.lastPollNs; }
    public long lastChangeNanos() { return this.lastChangeNs; }

    public boolean isHandTracked(int hand) { return this.hands[hand].tracked; }
    public int chirality(int hand) { return this.hands[hand].chirality; }
    public long handTimestampNs(int hand) { return this.hands[hand].timestampNs; }
    public float wristX(int hand) { return this.hands[hand].wx; }
    public float wristY(int hand) { return this.hands[hand].wy; }
    public float wristZ(int hand) { return this.hands[hand].wz; }
    public float wristQx(int hand) { return this.hands[hand].qx; }
    public float wristQy(int hand) { return this.hands[hand].qy; }
    public float wristQz(int hand) { return this.hands[hand].qz; }
    public float wristQw(int hand) { return this.hands[hand].qw; }
    /** Internal joint array ({@code joint * 3 + axis}, device space metres); read-only contract. */
    public float[] joints(int hand) { return this.hands[hand].joints; }
    public float pinchDistance(int hand) { return this.hands[hand].pinchDistance; }
    public float fistRatio(int hand) { return this.hands[hand].fistRatio; }
    public boolean pinchRaw(int hand) { return this.hands[hand].pinchRaw; }
    public boolean pinchPressed(int hand) { return this.hands[hand].pinchPressed; }
    public boolean fistRaw(int hand) { return this.hands[hand].fistRaw; }
    public boolean fistPressed(int hand) { return this.hands[hand].fistPressed; }
    public boolean fistTapPressed(int hand) { return this.hands[hand].fistTapPressed; }
    public boolean middlePressed(int hand) { return this.hands[hand].middlePressed; }
    public boolean middleTapPressed(int hand) { return this.hands[hand].middleTapPressed; }
    public boolean middleDoubleTapPressed(int hand) { return this.hands[hand].middleDoubleTapPressed; }
    public float middleDistance(int hand) { return this.hands[hand].middleDistance; }
    public boolean bothFistTapPressed() { return this.bothFistTapPressed; }
}
