package dev.vrmc.provider;

/**
 * Seated-play snap turn driven by the left middle-finger pinch taps.
 *
 * <p>{@link VisionInput} reports a single-tap pulse on the <em>first</em> tap even when a second tap
 * follows; a double tap therefore arrives as one single-tap pulse and later one double-tap pulse.
 * Acting on the single tap immediately would snap left and then the double-tap pulse would snap
 * right, so a double tap would net zero rotation (host-verified against the M4 middle-tap engine).
 * This helper defers the single-tap decision by the engine's middle double-tap window: a double tap
 * inside the window becomes exactly one right turn, anything else one left turn.
 *
 * <p>Pure Java (no game classes) so the host tests can pin both the single-tap latency and the
 * double-tap net-one-turn behavior.
 */
final class SeatedTurnGesture {
    static final int NONE = 0;
    /** Turn left (the same sign {@link VisionVR}'s rotate pulse uses for keyRotateLeft). */
    static final int LEFT = -1;
    static final int RIGHT = 1;

    /** Margin over the engine's double-tap window before the deferred single tap fires. */
    static final long DECISION_MARGIN_NS = 60_000_000L;

    private boolean pending;
    private long decisionNs;
    private boolean tapPrev;

    /**
     * One frame. Returns {@link #LEFT}, {@link #RIGHT} or {@link #NONE}. {@code doubleWindowNs} is
     * the middle double-tap window used by the vision input engine.
     */
    int update(boolean enabled, boolean tapPulse, boolean doublePulse, long nowNs, long doubleWindowNs) {
        if (!enabled) {
            reset();
            return NONE;
        }
        if (doublePulse) {
            // The second tap owns both taps: cancel the deferred left turn and turn right once.
            reset();
            return RIGHT;
        }
        if (tapPulse && !this.tapPrev) {
            // First frame of the pulse only: a 2-frame pulse must not extend the decision deadline.
            this.pending = true;
            this.decisionNs = nowNs + Math.max(0L, doubleWindowNs) + DECISION_MARGIN_NS;
        }
        this.tapPrev = tapPulse;
        if (this.pending && nowNs >= this.decisionNs) {
            reset();
            return LEFT;
        }
        return NONE;
    }

    /** True while a single-tap decision is waiting for the double-tap window to expire. */
    boolean pending() { return this.pending; }

    void reset() {
        this.pending = false;
        this.decisionNs = 0L;
        this.tapPrev = false;
    }
}
