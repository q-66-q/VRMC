package dev.vrmc.provider;

/**
 * Host test for {@link QuickMenuInjectionRetry} (R5).
 *
 * <p>The old code permanently disabled the quick-menu button after the first reflective injection
 * failure. The policy must retry (throttled on the same screen, immediately on a new screen) so a
 * transient failure cannot take the in-VR entry point away for the session.
 */
public final class QuickMenuInjectionRetryTest {
    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok) {
        checks++;
        if (!ok) failures++;
        System.out.println("  " + (ok ? "ok  " : "FAIL") + " " + name);
    }

    private static final long T0 = 1_000_000_000L;

    public static void main(String[] args) {
        firstAttemptAllowed();
        failureRetriesAfterCooldown();
        newScreenRetriesImmediately();
        successResets();
        loggingQuietensAfterFirstAttempts();
        resetClears();
        System.out.println("[m5-quick-menu-retry-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0
            ? "[m5-quick-menu-retry-test] PASS" : "[m5-quick-menu-retry-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    private static void firstAttemptAllowed() {
        QuickMenuInjectionRetry retry = new QuickMenuInjectionRetry();
        Object screen = new Object();
        check("first injection attempt on a screen is allowed", retry.shouldAttempt(T0, screen));
        check("no failures recorded yet", retry.attempts() == 0);
    }

    private static void failureRetriesAfterCooldown() {
        QuickMenuInjectionRetry retry = new QuickMenuInjectionRetry();
        Object screen = new Object();
        retry.shouldAttempt(T0, screen);
        retry.recordFailure(T0);
        check("a failure does not permanently disable the button", !retry.shouldAttempt(T0, screen));
        check("retry is throttled right after the failure",
            !retry.shouldAttempt(T0 + QuickMenuInjectionRetry.RETRY_DELAY_NS - 1, screen));
        check("retry is allowed after the cooldown",
            retry.shouldAttempt(T0 + QuickMenuInjectionRetry.RETRY_DELAY_NS, screen));
        retry.recordFailure(T0 + QuickMenuInjectionRetry.RETRY_DELAY_NS);
        check("attempts are counted", retry.attempts() == 2);
        check("a later cooldown window retries again",
            retry.shouldAttempt(T0 + 2 * QuickMenuInjectionRetry.RETRY_DELAY_NS, screen));
    }

    private static void newScreenRetriesImmediately() {
        QuickMenuInjectionRetry retry = new QuickMenuInjectionRetry();
        Object first = new Object();
        retry.shouldAttempt(T0, first);
        retry.recordFailure(T0);
        Object second = new Object();
        check("a new pause screen retries immediately (screen rebuilt/open again)",
            retry.shouldAttempt(T0, second));
        check("the new screen starts with a clean failure count", retry.attempts() == 0);
    }

    private static void successResets() {
        QuickMenuInjectionRetry retry = new QuickMenuInjectionRetry();
        Object screen = new Object();
        retry.shouldAttempt(T0, screen);
        retry.recordFailure(T0);
        retry.recordSuccess();
        check("success clears the failure count", retry.attempts() == 0);
        check("success allows the next attempt immediately", retry.shouldAttempt(T0, screen));
    }

    private static void loggingQuietensAfterFirstAttempts() {
        QuickMenuInjectionRetry retry = new QuickMenuInjectionRetry();
        Object screen = new Object();
        retry.shouldAttempt(T0, screen);
        boolean loggedOnFirstFew = true;
        for (int i = 0; i < QuickMenuInjectionRetry.MAX_LOGGED_ATTEMPTS; i++) {
            retry.recordFailure(T0 + i * QuickMenuInjectionRetry.RETRY_DELAY_NS);
            loggedOnFirstFew &= retry.shouldLogFailure();
        }
        check("the first few failures are logged", loggedOnFirstFew);
        retry.recordFailure(T0 + 10 * QuickMenuInjectionRetry.RETRY_DELAY_NS);
        check("further failures go quiet but the policy keeps retrying",
            !retry.shouldLogFailure() && retry.attempts() == QuickMenuInjectionRetry.MAX_LOGGED_ATTEMPTS + 1);
        check("retrying is still allowed after the quiet failures",
            retry.shouldAttempt(T0 + 11 * QuickMenuInjectionRetry.RETRY_DELAY_NS, screen));
    }

    private static void resetClears() {
        QuickMenuInjectionRetry retry = new QuickMenuInjectionRetry();
        Object screen = new Object();
        retry.shouldAttempt(T0, screen);
        retry.recordFailure(T0);
        retry.reset();
        check("reset forgets the screen and failures",
            retry.attempts() == 0 && retry.shouldAttempt(T0, screen));
    }
}
