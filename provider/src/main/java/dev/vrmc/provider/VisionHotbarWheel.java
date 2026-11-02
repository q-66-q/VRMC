package dev.vrmc.provider;

/**
 * M4-W4 direct hotbar selection math (pure Java, host-tested).
 *
 * <p>Holding both-hand thumb-ring pinches enters a hotbar wheel: moving the left hand left/right from
 * the point where the chord started selects one of nine slots; releasing commits the slot. The mapping
 * is symmetric around the start position (slot 5 at centre) and clamps at slots 1/9.
 */
public final class VisionHotbarWheel {
    public static final int SLOTS = 9;
    public static final float DEFAULT_HALF_RANGE_METRES = 0.18F;

    private VisionHotbarWheel() {}

    /** @return 1..9 slot for a horizontal left-hand displacement from the chord start. */
    public static int slotForDelta(float deltaX, float halfRangeMetres) {
        if (!Float.isFinite(deltaX)) return 5;
        float range = Math.max(0.02F, halfRangeMetres);
        float t = deltaX / range;                 // -1..1 expected
        t = Math.max(-1.0F, Math.min(1.0F, t));
        float normalized = (t + 1.0F) * 0.5F;     // 0..1, left = slot 1, right = slot 9
        int slot = 1 + Math.round(normalized * (SLOTS - 1));
        return Math.max(1, Math.min(SLOTS, slot));
    }
}
