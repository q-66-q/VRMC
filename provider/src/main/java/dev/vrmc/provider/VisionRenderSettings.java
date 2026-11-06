package dev.vrmc.provider;

import dev.vrmc.provider.bridge.VrmcBridge;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * M8 render feedback: parses the compositor's {@code vrmc_render_settings} payload (native-shared
 * channel, written by the visionOS CompositorServices layer) and turns it into a stereo eye-target
 * size policy.
 *
 * <p><b>Pure Java by design</b> (no Minecraft/Vivecraft imports): host-unit-tested through synthetic
 * 68-byte snapshots by {@code VisionRenderSettingsTest}; {@link VisionRenderer} is the only game-side
 * consumer. All per-frame state is preallocated; {@link #parse(ByteBuffer)} allocates only the small
 * immutable snapshot object.
 *
 * <p>Why the provider needs this: the old M2 renderer created 1024x1024 eye targets regardless of the
 * display, so the compositor upscaled ~1.8x to a 1888x1792 per-eye viewport — the visible softness and
 * jaggedness. The layer tells us (a) the LOGICAL per-eye size at the current render quality, which is
 * the size that maps 1:1 to displayed pixels in the fovea, and (b) the measured display cadence
 * (90/120 Hz). The provider renders as close to the logical size as its performance budget allows and
 * adapts that scale from its own measured frame pacing.
 *
 * <p>Foveation note (honest contract): the compositor's foveation/rate-map state reduces the system
 * drawable memory and final compositing cost, not Minecraft's own render cost — MC renders a uniform
 * eye image. So the provider must still choose a scale it can sustain; the foveated display path makes
 * that uniform image look correct at native foveal density instead of being visibly upscaled.
 */
public final class VisionRenderSettings {
    /** Payload layout version (vrmc_native_shared.h VRMC_RENDER_SETTINGS_VERSION). */
    public static final int VERSION = 1;
    public static final int BYTES = VrmcBridge.RENDER_SETTINGS_BYTES;

    // Field offsets mirror the C struct 1:1 (asserted by VisionRenderSettingsTest).
    public static final int OFF_VERSION = VrmcBridge.RS_OFF_VERSION;
    public static final int OFF_VALID = VrmcBridge.RS_OFF_VALID;
    public static final int OFF_FRAME_INDEX = VrmcBridge.RS_OFF_FRAME_INDEX;
    public static final int OFF_FOVEATION = VrmcBridge.RS_OFF_FOVEATION;
    public static final int OFF_RATE_MAP_COUNT = VrmcBridge.RS_OFF_RATE_MAP_COUNT;
    public static final int OFF_LEFT_LOGICAL_W = VrmcBridge.RS_OFF_LEFT_LOGICAL_W;
    public static final int OFF_LEFT_LOGICAL_H = VrmcBridge.RS_OFF_LEFT_LOGICAL_H;
    public static final int OFF_RIGHT_LOGICAL_W = VrmcBridge.RS_OFF_RIGHT_LOGICAL_W;
    public static final int OFF_RIGHT_LOGICAL_H = VrmcBridge.RS_OFF_RIGHT_LOGICAL_H;
    public static final int OFF_DRAWABLE_W = VrmcBridge.RS_OFF_DRAWABLE_W;
    public static final int OFF_DRAWABLE_H = VrmcBridge.RS_OFF_DRAWABLE_H;
    public static final int OFF_RENDER_QUALITY = VrmcBridge.RS_OFF_RENDER_QUALITY;
    public static final int OFF_MAX_RENDER_QUALITY = VrmcBridge.RS_OFF_MAX_RENDER_QUALITY;
    public static final int OFF_DISPLAY_HZ = VrmcBridge.RS_OFF_DISPLAY_HZ;
    public static final int OFF_FRAME_TIME_MS = VrmcBridge.RS_OFF_FRAME_TIME_MS;
    public static final int OFF_PROVIDER_EYE_W = VrmcBridge.RS_OFF_PROVIDER_EYE_W;
    public static final int OFF_PROVIDER_EYE_H = VrmcBridge.RS_OFF_PROVIDER_EYE_H;

    /** Hard bounds for the provider's per-eye render target (sanity/memory guard). */
    public static final int MIN_EYE_DIMENSION = 512;
    public static final int MAX_EYE_DIMENSION = 4096;
    /** Render scale range relative to the logical display size. */
    public static final float MIN_SCALE = 0.25f;
    public static final float MAX_SCALE = 1.0f;
    /** Auto-scale starts below the logical size so the first seconds cannot blow the frame budget. */
    public static final float AUTO_INITIAL_SCALE = 0.5f;
    public static final float AUTO_STEP_UP = 0.05f;
    public static final float AUTO_STEP_DOWN = 0.10f;
    /** Only request a resize when a dimension moves more than this fraction (avoids thrash). */
    public static final float CHANGE_THRESHOLD = 0.06f;
    /** Fallback display cadence when the compositor has not measured one yet. */
    public static final double FALLBACK_DISPLAY_HZ = 90.0;
    /** Never resize before this many rendered frames of the session (warm-up/shaders). */
    public static final long MIN_RESIZE_FRAME = 60L;
    /** A loaded world must be stable this long before a resize may rebuild every render target. */
    public static final long MIN_LEVEL_STABLE_FRAMES = 120L;

    public final boolean valid;
    public final int frameIndex;
    public final boolean foveationEnabled;
    public final int rateMapCount;
    public final int leftLogicalWidth;
    public final int leftLogicalHeight;
    public final int rightLogicalWidth;
    public final int rightLogicalHeight;
    public final int drawableWidth;
    public final int drawableHeight;
    public final float renderQuality;
    public final float maxRenderQuality;
    public final float displayHz;
    public final float frameTimeMs;
    public final int providerEyeWidth;
    public final int providerEyeHeight;

    private VisionRenderSettings(boolean valid, int frameIndex, boolean foveationEnabled,
                                 int rateMapCount, int leftLogicalWidth, int leftLogicalHeight,
                                 int rightLogicalWidth, int rightLogicalHeight, int drawableWidth,
                                 int drawableHeight, float renderQuality, float maxRenderQuality,
                                 float displayHz, float frameTimeMs, int providerEyeWidth,
                                 int providerEyeHeight) {
        this.valid = valid;
        this.frameIndex = frameIndex;
        this.foveationEnabled = foveationEnabled;
        this.rateMapCount = rateMapCount;
        this.leftLogicalWidth = leftLogicalWidth;
        this.leftLogicalHeight = leftLogicalHeight;
        this.rightLogicalWidth = rightLogicalWidth;
        this.rightLogicalHeight = rightLogicalHeight;
        this.drawableWidth = drawableWidth;
        this.drawableHeight = drawableHeight;
        this.renderQuality = renderQuality;
        this.maxRenderQuality = maxRenderQuality;
        this.displayHz = displayHz;
        this.frameTimeMs = frameTimeMs;
        this.providerEyeWidth = providerEyeWidth;
        this.providerEyeHeight = providerEyeHeight;
    }

    /** A zeroed/invalid snapshot: the compositor has not published display geometry yet (not an error). */
    public static VisionRenderSettings none() {
        return new VisionRenderSettings(false, 0, false, 0, 0, 0, 0, 0, 0, 0,
            0.0f, 0.0f, 0.0f, 0.0f, 0, 0);
    }

    /**
     * Parse a 68-byte little-endian payload written by the bridge's nativePollRenderSettings. Never
     * throws: malformed/old payloads (wrong version, no valid flag, non-finite values, out-of-range
     * sizes) come back as {@link #none()} so the renderer keeps its current target.
     */
    public static VisionRenderSettings parse(ByteBuffer buffer) {
        if (buffer == null || buffer.capacity() < BYTES) return none();
        ByteOrder saved = buffer.order();
        buffer.order(ByteOrder.LITTLE_ENDIAN);
        try {
            final int base = 0;
            int version = buffer.getInt(base + OFF_VERSION);
            int validFlag = buffer.getInt(base + OFF_VALID);
            if (version != VERSION || validFlag != 1) return none();
            int leftWidth = buffer.getInt(base + OFF_LEFT_LOGICAL_W);
            int leftHeight = buffer.getInt(base + OFF_LEFT_LOGICAL_H);
            int rightWidth = buffer.getInt(base + OFF_RIGHT_LOGICAL_W);
            int rightHeight = buffer.getInt(base + OFF_RIGHT_LOGICAL_H);
            if (!saneDimension(leftWidth) || !saneDimension(leftHeight) ||
                !saneDimension(rightWidth) || !saneDimension(rightHeight)) {
                return none();
            }
            float quality = buffer.getFloat(base + OFF_RENDER_QUALITY);
            float maxQuality = buffer.getFloat(base + OFF_MAX_RENDER_QUALITY);
            float displayHz = buffer.getFloat(base + OFF_DISPLAY_HZ);
            float frameTimeMs = buffer.getFloat(base + OFF_FRAME_TIME_MS);
            if (!isFinite(quality) || quality < 0.0f || quality > 1.0f ||
                !isFinite(maxQuality) || maxQuality < quality - 1.0e-3f || maxQuality > 1.0f) {
                return none();
            }
            if (!isFinite(displayHz) || displayHz < 0.0f || displayHz > 240.0f ||
                !isFinite(frameTimeMs) || frameTimeMs < 0.0f || frameTimeMs > 1000.0f) {
                return none();
            }
            int foveation = buffer.getInt(base + OFF_FOVEATION) == 1 ? 1 : 0;
            int rateMaps = buffer.getInt(base + OFF_RATE_MAP_COUNT);
            int drawableWidth = buffer.getInt(base + OFF_DRAWABLE_W);
            int drawableHeight = buffer.getInt(base + OFF_DRAWABLE_H);
            int providerW = buffer.getInt(base + OFF_PROVIDER_EYE_W);
            int providerH = buffer.getInt(base + OFF_PROVIDER_EYE_H);
            return new VisionRenderSettings(true, buffer.getInt(base + OFF_FRAME_INDEX),
                foveation == 1, Math.max(0, rateMaps), leftWidth, leftHeight, rightWidth, rightHeight,
                Math.max(0, drawableWidth), Math.max(0, drawableHeight), quality, maxQuality,
                displayHz, frameTimeMs, Math.max(0, providerW), Math.max(0, providerH));
        } catch (RuntimeException malformed) {
            return none();
        } finally {
            buffer.order(saved);
        }
    }

    private static boolean saneDimension(int value) {
        return value >= 64 && value <= 16384;
    }

    private static boolean isFinite(float value) {
        return !Float.isNaN(value) && !Float.isInfinite(value);
    }

    /**
     * Provider eye target {@code {width, height}} for a render scale relative to the logical display
     * size, clamped to sane bounds and rounded up to an 8-pixel multiple (GPU alignment). Returns null
     * when no display geometry is available yet (the renderer keeps its current/default size).
     */
    public static int[] eyeTarget(VisionRenderSettings settings, float scale) {
        if (settings == null || !settings.valid) return null;
        if (settings.leftLogicalWidth <= 0 || settings.leftLogicalHeight <= 0) return null;
        float clampedScale = clamp(scale, MIN_SCALE, MAX_SCALE);
        int width = roundUp((int)Math.ceil(settings.leftLogicalWidth * (double)clampedScale));
        int height = roundUp((int)Math.ceil(settings.leftLogicalHeight * (double)clampedScale));
        width = clampInt(width, MIN_EYE_DIMENSION, MAX_EYE_DIMENSION);
        height = clampInt(height, MIN_EYE_DIMENSION, MAX_EYE_DIMENSION);
        return new int[]{width, height};
    }

    /** Target frame interval for the measured (or fallback) display cadence, in milliseconds. */
    public static double targetIntervalMs(float displayHz) {
        if (isFinite(displayHz) && displayHz >= 30.0f && displayHz <= 240.0f) {
            return 1000.0 / (double)displayHz;
        }
        return 1000.0 / FALLBACK_DISPLAY_HZ;
    }

    /**
     * M8 target-cadence knob ({"auto"} or a supported Hz value): the auto eye-scale policy normally
     * aims at the cadence the compositor measured (90/96/100/120 Hz, chosen by the system). The
     * override lets the operator aim at a higher rate instead (e.g. set 120 while the system still
     * reports 90) so the provider keeps frames inside the shorter deadline and the system can promote
     * the display; if the device cannot hold it, the eye scale settles lower. Returns 0 for "auto"
     * (follow the measured display), a positive Hz value for an override, or -1 for invalid input.
     */
    public static final int MIN_TARGET_HZ = 60;
    public static final int MAX_TARGET_HZ = 120;

    public static int parseTargetHz(String text) {
        if (text == null) return 0;
        String value = text.trim();
        if (value.isEmpty() || value.equalsIgnoreCase("auto")) return 0;
        try {
            int hz = Integer.parseInt(value);
            return (hz >= MIN_TARGET_HZ && hz <= MAX_TARGET_HZ) ? hz : -1;
        } catch (NumberFormatException malformed) {
            return -1;
        }
    }

    /**
     * Frame interval used by the auto eye-scale policy: the operator override when one is configured,
     * otherwise the cadence the compositor measured (with the usual fallback when it is not finite).
     */
    public static double targetIntervalMsFor(float displayHz, int overrideHz) {
        if (overrideHz >= MIN_TARGET_HZ && overrideHz <= MAX_TARGET_HZ) {
            return 1000.0 / (double)overrideHz;
        }
        return targetIntervalMs(displayHz);
    }

    /**
     * Auto render-scale decision from the provider's own measured frame pacing. One step per call,
     * with hysteresis: drop when repeated frames / slow p50; raise only with clear headroom. Pure and
     * deterministic so the host test can exhaustively check the bounds and monotonic behaviour.
     */
    public static float nextAutoScale(float currentScale, int missedFrames, int sampleCount,
                                      double p50Ms, double targetIntervalMs) {
        float scale = clamp(currentScale, MIN_SCALE, MAX_SCALE);
        if (sampleCount <= 0 || !(targetIntervalMs > 0.0) || !(p50Ms > 0.0) || Double.isNaN(p50Ms)) {
            return scale;
        }
        boolean struggling = missedFrames >= Math.max(3, sampleCount / 10) ||
            p50Ms > targetIntervalMs * 1.25;
        boolean headroom = missedFrames <= 1 && p50Ms < targetIntervalMs * 0.85;
        if (struggling) return Math.max(MIN_SCALE, scale - AUTO_STEP_DOWN);
        if (headroom) {
            // Strong headroom (well inside the frame budget on the measured cadence): take a bigger
            // step so a capable device reaches the native logical resolution in a few seconds, not a
            // minute. Conservative ramp stays 0.05 near the budget edge.
            boolean strongHeadroom = missedFrames == 0 && p50Ms < targetIntervalMs * 0.75;
            return Math.min(MAX_SCALE, scale + (strongHeadroom ? AUTO_STEP_UP * 2.0f : AUTO_STEP_UP));
        }
        return scale;
    }

    /**
     * Resize safety policy: rebuilding every render target (both eye VkImages + the world/menu/GUI
     * targets) during world loading is a visible hitch in the worst possible place, and resizing on
     * the very first frames races the initial render setup. Pure function so the host test covers the
     * decision table; VisionRenderer supplies the game state.
     *
     * @param levelLoaded           a level is loaded (in-world)
     * @param framesSinceLevelLoad  rendered frames since the level became non-null
     * @param inMenuRoom            Vivecraft's menu room (title/main menu) is active
     * @param frameIndex            rendered frames this session
     */
    public static boolean canResizeNow(boolean levelLoaded, long framesSinceLevelLoad,
                                       boolean inMenuRoom, long frameIndex) {
        if (frameIndex < MIN_RESIZE_FRAME) return false;
        if (levelLoaded) return framesSinceLevelLoad >= MIN_LEVEL_STABLE_FRAMES;
        return inMenuRoom;
    }

    /** True when a resize is worth the render-target rebuild (dimension moved > CHANGE_THRESHOLD). */
    public static boolean isChangeSignificant(int currentWidth, int currentHeight,
                                              int newWidth, int newHeight) {
        if (currentWidth <= 0 || currentHeight <= 0) return true;
        double dw = Math.abs((double)newWidth - (double)currentWidth) / (double)currentWidth;
        double dh = Math.abs((double)newHeight - (double)currentHeight) / (double)currentHeight;
        return dw > CHANGE_THRESHOLD || dh > CHANGE_THRESHOLD;
    }

    /** One-line diagnostic for the provider log (never null, never throws). */
    public String describe() {
        if (!valid) return "render settings: none (compositor has not published display geometry yet)";
        return String.format(java.util.Locale.ROOT,
            "render settings: logical L=%dx%d R=%dx%d drawable=%dx%d foveation=%d rateMaps=%d %s "
                + "quality=%.2f/%.2f displayHz=%.1f frame=%.2fms providerEye=%dx%d frameIndex=%d",
            leftLogicalWidth, leftLogicalHeight, rightLogicalWidth, rightLogicalHeight,
            drawableWidth, drawableHeight, foveationEnabled ? 1 : 0, rateMapCount,
            foveationEnabled ? "(foveated display path)" : "(uniform display path)",
            renderQuality, maxRenderQuality, displayHz, frameTimeMs, providerEyeWidth,
            providerEyeHeight, frameIndex);
    }

    private static int roundUp(int value) {
        return ((value + 7) / 8) * 8;
    }

    private static int clampInt(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static float clamp(float value, float min, float max) {
        if (Float.isNaN(value)) return min;
        return Math.max(min, Math.min(max, value));
    }
}
