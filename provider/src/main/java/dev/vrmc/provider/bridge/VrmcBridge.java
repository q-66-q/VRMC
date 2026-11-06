package dev.vrmc.provider.bridge;

import java.nio.ByteBuffer;

/**
 * JNI wrapper over the VRMC native bridge ABI v3 (bridge/abi/vrmc_abi.h) plus the native-shared
 * eye-frame / input handoff (bridge/abi/vrmc_native_shared.h).
 * Only scalars and preallocated direct buffers cross the boundary; fail closed on load/init errors.
 *
 * <p>ABI v3 (M4-W1) adds the immersive input channel: the compositor publishes one
 * {@code vrmc_input_state} per frame (ARKit 27-joint hand tracking, device space) and the provider
 * polls it into ONE preallocated direct buffer with {@link #pollInput(ByteBuffer)}. The struct
 * sizes/offsets below are part of the contract and are mirrored by the native static asserts in
 * bridge/tests/bridge_input_test.c and by provider/tests/.../VisionInputLayoutTest.java.
 */
public final class VrmcBridge {
    public static final int ABI_VERSION = 3;

    /**
     * Caps advertised to {@code vrmc_init}. The bridge fails closed on any other ABI major or a
     * missing required capability (see bridge/abi/vrmc_abi.h evolution policy).
     */
    public static final String CAPS_JSON = "{\"abi\":3,\"eyes\":2,\"hands\":2,\"input\":1}";

    /** sizeof(vrmc_tracking_state): u64 + head(28) + 2*controller(28) + f32. */
    public static final int TRACKING_BYTES = 8 + 28 + 28 + 28 + 4;
    /** sizeof(vrmc_frame_timing_t): u64 + i64*4 + u32 (+ padding kept explicit below). */
    public static final int FRAME_TIMING_BYTES = 8 + 32 + 4 + 4;
    /** Per-eye tangents(4) + eye-to-head matrix(16) for both eyes + ipd. */
    public static final int DISPLAY_VIEWS_BYTES = (4 + 16 + 4 + 16 + 1) * 4;

    // ---- vrmc_render_settings (M8 native-shared channel; no Java ABI bump) --------------------
    /**
     * M8 render feedback published by the compositor (native-shared channel, NOT part of the Java
     * vrmc_abi.h struct contract): per-eye LOGICAL display size at the current render quality, the
     * PHYSICAL foveated drawable extent, foveation/rate-map state, the current/max render quality and
     * the measured display cadence. The provider sizes its stereo eye targets from this instead of a
     * hardcoded 1024x1024. sizeof(vrmc_render_settings) = 68 (all fields 4 bytes, little-endian).
     */
    public static final int RENDER_SETTINGS_BYTES = 68;
    public static final int RS_OFF_VERSION = 0;            /* u32 */
    public static final int RS_OFF_VALID = 4;              /* u32: 1 = fields valid */
    public static final int RS_OFF_FRAME_INDEX = 8;        /* u32 compositor frame */
    public static final int RS_OFF_FOVEATION = 12;         /* u32: 1 = rate maps active */
    public static final int RS_OFF_RATE_MAP_COUNT = 16;    /* u32 */
    public static final int RS_OFF_LEFT_LOGICAL_W = 20;    /* u32 per-eye logical size (display px) */
    public static final int RS_OFF_LEFT_LOGICAL_H = 24;
    public static final int RS_OFF_RIGHT_LOGICAL_W = 28;
    public static final int RS_OFF_RIGHT_LOGICAL_H = 32;
    public static final int RS_OFF_DRAWABLE_W = 36;        /* u32 physical drawable extent */
    public static final int RS_OFF_DRAWABLE_H = 40;
    public static final int RS_OFF_RENDER_QUALITY = 44;    /* f32 current runtime quality [0,1] */
    public static final int RS_OFF_MAX_RENDER_QUALITY = 48;/* f32 configured maximum [0,1] */
    public static final int RS_OFF_DISPLAY_HZ = 52;        /* f32 measured display cadence */
    public static final int RS_OFF_FRAME_TIME_MS = 56;     /* f32 measured app frame interval */
    public static final int RS_OFF_PROVIDER_EYE_W = 60;    /* u32 compositor recommendation (0=derive) */
    public static final int RS_OFF_PROVIDER_EYE_H = 64;

    // ---- vrmc_input_state (ABI v3, M4-W1) ----------------------------------------------------
    /** sizeof(vrmc_input_state), 8-byte aligned: 16 + 2 * 368. */
    public static final int INPUT_BYTES = 752;
    public static final int INPUT_OFF_FRAME_INDEX = 0;   /* u32 */
    public static final int INPUT_OFF_VALID_MASK = 4;    /* u32: bit0 = left tracked, bit1 = right tracked */
    public static final int INPUT_OFF_TIMESTAMP = 8;     /* u64 predicted anchor time */
    public static final int INPUT_OFF_HANDS = 16;        /* vrmc_hand_state[2] */
    /** sizeof(vrmc_hand_state), 8-byte aligned. */
    public static final int HAND_STATE_BYTES = 368;
    /** Distance between hands[] entries inside vrmc_input_state (== sizeof(vrmc_hand_state)). */
    public static final int HAND_STRIDE = HAND_STATE_BYTES;
    public static final int HAND_OFF_TRACKED = 0;        /* u32 */
    public static final int HAND_OFF_CHIRALITY = 4;      /* u32: 0 = left, 1 = right */
    public static final int HAND_OFF_TIMESTAMP = 8;      /* u64 */
    public static final int HAND_OFF_WRIST_QUAT = 16;    /* vrmc_quat */
    public static final int HAND_OFF_WRIST_POS = 32;     /* vrmc_vec3 */
    public static final int HAND_OFF_JOINTS = 44;        /* vrmc_vec3[27] */
    public static final int JOINT_STRIDE = 12;           /* sizeof(vrmc_vec3) */
    public static final int JOINT_COUNT = 27;

    // Indices inside the ARKit 27-joint array that the provider consumes (design §3.1).
    public static final int JOINT_WRIST = 0;
    public static final int JOINT_THUMB_TIP = 4;
    public static final int JOINT_INDEX_METACARPAL = 5;
    public static final int JOINT_INDEX_TIP = 9;
    public static final int JOINT_MIDDLE_KNUCKLE = 11;
    public static final int JOINT_MIDDLE_TIP = 14;
    public static final int JOINT_RING_TIP = 19;
    public static final int JOINT_LITTLE_METACARPAL = 20;
    public static final int JOINT_LITTLE_TIP = 24;

    private static boolean loaded;

    private VrmcBridge() {}

    public static synchronized void load() {
        if (loaded) return;
        String explicit = System.getProperty("vrmc.bridge.lib");
        if (explicit != null && !explicit.isEmpty()) {
            System.load(explicit);
        } else {
            System.loadLibrary("vrmc_bridge");
        }
        loaded = true;
    }

    public static native int nativeAbiVersion();
    public static native int nativeInit(String capsJson);
    public static native String nativeLastError();
    public static native int nativeGetTracking(ByteBuffer out);
    public static native int nativeSubmitEyes(long leftTexture, long rightTexture, int frameIndex, int width, int height,
                                              float halfFovRad);
    /**
     * Additive native-shared eye submission with a GPU timeline sync pair (bridge/abi/
     * vrmc_native_shared.h): publishes the eye textures together with the exported MTLSharedEvent and
     * the timeline value the compositor must wait on before sampling. Used only when the flag-gated
     * provider-side GPU sync is enabled (docs/analysis/provider-gpu-sync.md); the Java ABI version and
     * all vrmc_abi.h structs are unchanged.
     */
    public static native int nativeSubmitEyesSynced(long leftTexture, long rightTexture, int frameIndex,
                                                    int width, int height, float halfFovRad,
                                                    long sharedEvent, long signalValue);
    public static native int nativeFrameTiming(ByteBuffer out);
    public static native long nativeExportMTLTexture(long vkImage);
    public static native long nativeGetDisplayViews(ByteBuffer out);
    public static native void nativeClearEyeTextures();
    public static native void nativeSignalGameStopping();
    /** M4-W2 gaze mailbox: 1 = event written (tile u64 @0, phase u32 @8, kind u32 @12, ts u64 @16). */
    public static native int nativePollGazeEvent(ByteBuffer out);

    /**
     * ABI v3: copy the latest {@code vrmc_input_state} into the direct buffer (capacity must be at
     * least {@link #INPUT_BYTES}). Returns 0 on success; before the compositor ever published it
     * returns 0 with a zeroed snapshot ("safe, no hands"), and fails closed (nonzero) on a short
     * buffer / uninitialized bridge. Never allocates.
     */
    public static native int nativePollInput(ByteBuffer out);

    /**
     * M8: copy the compositor's latest render feedback into the direct buffer (capacity must be at
     * least {@link #RENDER_SETTINGS_BYTES}). Returns 0 on success; the payload's valid flag is 0 until
     * the compositor publishes (never an error). Fails closed (-4/-5/-6) on a null/non-direct/short
     * buffer. Never allocates.
     */
    public static native int nativePollRenderSettings(ByteBuffer out);

    public static int abiVersion() { return nativeAbiVersion(); }
    public static int init(String capsJson) { return nativeInit(capsJson); }
    public static String lastError() { return nativeLastError(); }
    public static int getTracking(ByteBuffer out) { return nativeGetTracking(out); }
    /** Submit both eye textures; both eyes use a symmetric frustum with the given half-angle (radians). */
    public static int submitEyes(long left, long right, int frameIndex, int width, int height, float halfFovRad) {
        return nativeSubmitEyes(left, right, frameIndex, width, height, halfFovRad);
    }

    /**
     * Submit both eye textures plus the GPU sync pair exported from a timeline VkSemaphore
     * ({@code sharedEvent} = opaque id&lt;MTLSharedEvent&gt;, {@code signalValue} = timeline value that is
     * signalled when this frame's GPU work completes). Passing a zero event/value falls back to an
     * unsynchronized publication inside the bridge.
     */
    public static int submitEyesSynced(long left, long right, int frameIndex, int width, int height,
                                       float halfFovRad, long sharedEvent, long signalValue) {
        return nativeSubmitEyesSynced(left, right, frameIndex, width, height, halfFovRad, sharedEvent,
            signalValue);
    }
    public static int frameTiming(ByteBuffer out) { return nativeFrameTiming(out); }
    /** Export a Metal texture handle from a VkImage owned by the game's MoltenVK device (0 = failure). */
    public static long exportMTLTexture(long vkImage) { return nativeExportMTLTexture(vkImage); }
    /** Latest headset display views (CompositorServices projection + eye transforms) generation. */
    public static long getDisplayViews(ByteBuffer out) { return nativeGetDisplayViews(out); }
    /** Provider/game teardown: drop stored eye textures so the compositor stops sampling stale handles. */
    public static void clearEyeTextures() { nativeClearEyeTextures(); }
    /** Provider/game teardown: tell the compositor/shell the game is going away (dismiss stale immersive). */
    public static void signalGameStopping() { nativeSignalGameStopping(); }
    /** M4-W2 gaze event buffer size/offsets (matches vrmc_gaze_event + nativePollGazeEvent). */
    public static final int GAZE_EVENT_BYTES = 32;
    public static final int GAZE_OFF_TILE = 0;
    public static final int GAZE_OFF_PHASE = 8;
    public static final int GAZE_OFF_KIND = 12;
    public static final int GAZE_OFF_GRID_W = 16;
    public static final int GAZE_OFF_GRID_H = 20;
    public static final int GAZE_OFF_TIMESTAMP = 24;
    /** Poll one gaze activation event; 1 = available, 0 = none, <0 = bridge error. */
    public static int pollGazeEvent(ByteBuffer out) { return nativePollGazeEvent(out); }
    public static final int GAZE_PHASE_ACTIVE = 1;
    public static final int GAZE_PHASE_ENDED = 2;
    public static final int GAZE_PHASE_CANCELLED = 3;
    public static final int GAZE_KIND_INDIRECT_PINCH = 1;
    /** ABI v3: poll the latest published hand/input snapshot (see {@link #nativePollInput(ByteBuffer)}). */
    public static int pollInput(ByteBuffer out) { return nativePollInput(out); }
    /** M8: poll the compositor's render feedback (see {@link #nativePollRenderSettings(ByteBuffer)}). */
    public static int pollRenderSettings(ByteBuffer out) { return nativePollRenderSettings(out); }
}
