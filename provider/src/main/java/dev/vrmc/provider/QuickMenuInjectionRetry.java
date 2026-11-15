package dev.vrmc.provider;

/**
 * Retry policy for the pause-screen "VRMC Quick Menu" button injection (R5).
 *
 * <p>{@code Screen.addRenderableWidget} is invoked reflectively, and the old code set a
 * {@code quickMenuInjectFailed} flag on the first Throwable that never reset: one transient failure
 * (e.g. a screen still initialising or a race with another mod) disabled the in-VR entry point for
 * the rest of the session. The launcher {@code quick-menu} command stayed as a fallback, but a
 * headset user should not need it.
 *
 * <p>The policy retries after a short cooldown on the same screen and immediately on a different
 * screen instance (a new/rebuild pause screen), so the button recovers without spamming the log.
 * Pure Java (the screen identity is passed as {@link Object}) so the host tests can pin it.
 */
final class QuickMenuInjectionRetry {
    /** Minimum time between two reflective attempts on the same screen instance. */
    static final long RETRY_DELAY_NS = 2_000_000_000L;
    /** Failures logged per screen before the policy goes quiet (it still retries). */
    static final int MAX_LOGGED_ATTEMPTS = 3;

    private Object screen;
    private int attempts;
    private long retryAtNs;

    /**
     * Call once per frame before attempting the injection. Resets the counters when the screen
     * instance changes; returns true when an attempt is allowed now.
     */
    boolean shouldAttempt(long nowNs, Object screenIdentity) {
        if (screenIdentity != this.screen) {
            this.screen = screenIdentity;
            this.attempts = 0;
            this.retryAtNs = 0L;
        }
        return nowNs >= this.retryAtNs;
    }

    /** The attempt threw; retry after the cooldown. */
    void recordFailure(long nowNs) {
        this.attempts++;
        this.retryAtNs = nowNs + RETRY_DELAY_NS;
    }

    /** The button was added; a later rebuild/screen change starts from a clean state. */
    void recordSuccess() {
        this.attempts = 0;
        this.retryAtNs = 0L;
    }

    /** Failures seen on the current screen instance (0 after success or a new screen). */
    int attempts() { return this.attempts; }

    /** True while a failure for this screen should still be logged (first few only). */
    boolean shouldLogFailure() { return this.attempts <= MAX_LOGGED_ATTEMPTS; }

    /** Forget everything (mode change / destroy). */
    void reset() {
        this.screen = null;
        this.attempts = 0;
        this.retryAtNs = 0L;
    }
}
