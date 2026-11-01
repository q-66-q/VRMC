package dev.vrmc.provider.bridge;

import java.nio.ByteBuffer;

/**
 * JNI wrapper over the VRMC native bridge ABI v1 (bridge/abi/vrmc_abi.h).
 * Only scalars and preallocated direct buffers cross the boundary; fail closed on load/init errors.
 */
public final class VrmcBridge {
    public static final int ABI_VERSION = 1;
    /** sizeof(vrmc_tracking_state): u64 + head(28) + 2*controller(28) + f32. */
    public static final int TRACKING_BYTES = 8 + 28 + 28 + 28 + 4;
    /** sizeof(vrmc_frame_timing_t): u64 + i64*4 + u32 (+ padding kept explicit below). */
    public static final int FRAME_TIMING_BYTES = 8 + 32 + 4 + 4;

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
    public static native int nativeSubmitEyes(long leftTexture, long rightTexture, int frameIndex, int width, int height);
    public static native int nativeFrameTiming(ByteBuffer out);

    public static int abiVersion() { return nativeAbiVersion(); }
    public static int init(String capsJson) { return nativeInit(capsJson); }
    public static String lastError() { return nativeLastError(); }
    public static int getTracking(ByteBuffer out) { return nativeGetTracking(out); }
    public static int submitEyes(long left, long right, int frameIndex, int width, int height) {
        return nativeSubmitEyes(left, right, frameIndex, width, height);
    }
    public static int frameTiming(ByteBuffer out) { return nativeFrameTiming(out); }
}
