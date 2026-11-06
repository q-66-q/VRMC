package dev.vrmc.provider;

/**
 * M8 content-first quality governor (opt-in: game dir {@code vrmc-content-first.txt} = on|off).
 *
 * When the target cadence is not being met, the default policy lowers the eye-target resolution.
 * With content-first enabled the provider instead reduces scene cost first (render distance, then
 * simulation distance, then a second render-distance step) so the 4K-class eye target is preserved
 * for as long as possible; resolution is only reduced after the content reductions are exhausted.
 * This is the resolution-vs-frame-rate tradeoff that matters for the "4K in both eyes at 120 Hz"
 * objective: fewer pixels lost, cheaper frames gained.
 *
 * Pure policy: the renderer passes the current distances and a "struggling" flag; {@link #decide}
 * returns the new {render, simulation} distances to apply, or {@code null} for "no change".
 * Hysteresis: two consecutive struggling windows are required, at most one reduction is applied per
 * window, a one-window cooldown separates reductions, and at most three reductions happen per
 * session (never below the configured minimums).
 */
public final class VisionContentGovernor {
    public static final int MIN_RENDER_DISTANCE = 6;
    public static final int MIN_SIMULATION_DISTANCE = 6;
    public static final int STEP = 2;
    public static final int REQUIRED_STRUGGLING_WINDOWS = 2;
    public static final int MAX_REDUCTIONS = 3;
    public static final int COOLDOWN_WINDOWS = 1;

    private boolean enabled;
    private int strugglingStreak;
    private int cooldown;
    private int reductions;
    private int renderReductions;
    private int simulationReductions;

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
        if (!enabled) {
            this.strugglingStreak = 0;
            this.cooldown = 0;
        }
    }

    public boolean enabled() { return this.enabled; }
    public int reductions() { return this.reductions; }
    public int renderReductions() { return this.renderReductions; }
    public int simulationReductions() { return this.simulationReductions; }

    /** Parse the knob: 1 = on, 0 = off, -1 = invalid. */
    public static int parse(String text) {
        if (text == null) return 0;
        String value = text.trim();
        if (value.isEmpty()) return 0;
        if (value.equalsIgnoreCase("on") || value.equalsIgnoreCase("true") || value.equals("1")) return 1;
        if (value.equalsIgnoreCase("off") || value.equalsIgnoreCase("false") || value.equals("0")) return 0;
        return -1;
    }

    /**
     * Evaluate one auto-policy window.
     *
     * @param struggling whether this window missed the target cadence (renderer policy)
     * @param renderDistance current render distance (<= 0 when unknown)
     * @param simulationDistance current simulation distance (<= 0 when unknown)
     * @return new {renderDistance, simulationDistance} to apply, or null for no change
     */
    public int[] decide(boolean struggling, int renderDistance, int simulationDistance) {
        if (!this.enabled) {
            this.strugglingStreak = 0;
            this.cooldown = 0;
            return null;
        }
        if (!struggling) {
            this.strugglingStreak = 0;
            if (this.cooldown > 0) this.cooldown--;
            return null;
        }
        this.strugglingStreak++;
        if (this.cooldown > 0) {
            this.cooldown--;
            return null;
        }
        if (this.strugglingStreak < REQUIRED_STRUGGLING_WINDOWS || this.reductions >= MAX_REDUCTIONS) {
            return null;
        }
        boolean renderRoom = renderDistance - STEP >= MIN_RENDER_DISTANCE;
        boolean simulationRoom = simulationDistance - STEP >= MIN_SIMULATION_DISTANCE;
        if (!renderRoom && !simulationRoom) return null;
        int newRender = renderDistance;
        int newSimulation = simulationDistance;
        // Prefer render distance, then simulation distance, then a second render step.
        boolean reduceRender = renderRoom && this.renderReductions <= this.simulationReductions;
        if (reduceRender) {
            newRender -= STEP;
        } else if (simulationRoom) {
            newSimulation -= STEP;
        } else {
            newRender -= STEP;
        }
        if (newRender == renderDistance && newSimulation == simulationDistance) return null;
        this.reductions++;
        this.strugglingStreak = 0;
        this.cooldown = COOLDOWN_WINDOWS;
        if (newRender != renderDistance) this.renderReductions++;
        if (newSimulation != simulationDistance) this.simulationReductions++;
        return new int[]{newRender, newSimulation};
    }
}
