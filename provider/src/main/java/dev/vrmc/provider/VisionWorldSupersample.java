package dev.vrmc.provider;

/**
 * M8 world-supersample knob (startup-only). Vivecraft's {@code renderScaleFactor} multiplies the world
 * render target size relative to the per-eye target: the world is rendered at eye x sqrt(factor) per
 * axis and then resolved down to the eye target, i.e. super-sampling / SSAA. With no MSAA in Minecraft
 * 26.2 this is the remaining software anti-aliasing lever for jagged edges. It is a pure pixel-cost
 * trade (off by default, 1.0..2.0), applied once before the first render-target creation and logged.
 */
public final class VisionWorldSupersample {
    public static final float MIN_FACTOR = 1.0f;
    public static final float MAX_FACTOR = 2.0f;

    /** Parse the knob: absent/empty/"off"/"1"/"1.0" -> 1.0 (off), 1.0..2.0 -> factor, else -1. */
    public static float parse(String text) {
        if (text == null) return 1.0f;
        String value = text.trim();
        if (value.isEmpty() || value.equalsIgnoreCase("off")) return 1.0f;
        try {
            float factor = Float.parseFloat(value);
            if (!(factor >= MIN_FACTOR && factor <= MAX_FACTOR)) return -1.0f;
            return factor;
        } catch (NumberFormatException malformed) {
            return -1.0f;
        }
    }

    /** Per-axis scale factor (Vivecraft applies sqrt(renderScaleFactor)). */
    public static double axisScale(float factor) {
        float clamped = Math.max(MIN_FACTOR, Math.min(MAX_FACTOR, factor));
        return Math.sqrt(clamped);
    }

    /** World render-target dimension for an eye dimension and factor (ceil, as VRRenderer does). */
    public static int scaledDimension(int eyeDimension, float factor) {
        if (eyeDimension <= 0) return 0;
        return (int) Math.ceil(eyeDimension * axisScale(factor));
    }

    private VisionWorldSupersample() {}
}
