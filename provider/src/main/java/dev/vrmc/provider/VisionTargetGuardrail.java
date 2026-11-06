package dev.vrmc.provider;

/**
 * M8 target-cadence guardrail.
 *
 * The operator can aim the auto eye-scale policy at a cadence above the display's actual rate
 * ({@code vrmc-target-hz.txt}). If the compositor keeps reporting a lower display cadence the target is
 * unreachable: after a bounded number of consecutive low-display windows the provider reverts to the
 * measured cadence (auto) instead of chasing 120 Hz - and crushing resolution - forever on hardware
 * that never promotes. A change to the knob file clears the suppression so the operator can retry.
 *
 * Pure and deterministic so the host test can check the boundaries.
 */
public final class VisionTargetGuardrail {
    /** Consecutive auto-policy windows (one per 240 frames) with the display below the target. */
    public static final int UNREACHABLE_WINDOWS = 8;

    /** True when this window counts as "the display did not reach the configured target". */
    public static boolean displayBelowTarget(int targetHz, float displayHz) {
        return targetHz > 0 && displayHz > 0.0f && displayHz < (float) targetHz - 1.0f;
    }

    /** True when enough consecutive low-display windows justify reverting to the measured cadence. */
    public static boolean shouldRevert(int consecutiveLowWindows) {
        return consecutiveLowWindows >= UNREACHABLE_WINDOWS;
    }

    private VisionTargetGuardrail() {}
}
