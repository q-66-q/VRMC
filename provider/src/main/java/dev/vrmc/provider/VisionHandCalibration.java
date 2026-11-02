package dev.vrmc.provider;

import java.util.Locale;

/**
 * M4-W5 guided hand-threshold calibration (pure Java; host-tested).
 *
 * <p>Protocol: 3 s open hands, 3 s closed fists, 3 s thumb-index pinch. Samples are collected while the
 * provider runs the command; the result suggests pinch/fist thresholds with separation margins. This is
 * advisory only: the operator can copy the suggested keys into vrmc-input-tune.properties or use the
 * launcher sliders.
 */
public final class VisionHandCalibration {
    public static final long OPEN_MS = 3_000L;
    public static final long FIST_MS = 3_000L;
    public static final long PINCH_MS = 3_000L;
    public static final long TOTAL_MS = OPEN_MS + FIST_MS + PINCH_MS;
    public static final int PHASE_DONE = 3;

    private long startNs;
    private boolean started;
    private float openPinchMax = Float.NaN;
    private float openFistMin = Float.NaN;
    private float fistFistMax = Float.NaN;
    private float pinchPinchMin = Float.NaN;
    private int openSamples;
    private int fistSamples;
    private int pinchSamples;

    public void begin(long nowNs) {
        this.startNs = nowNs;
        this.started = true;
        this.openPinchMax = Float.NaN;
        this.openFistMin = Float.NaN;
        this.fistFistMax = Float.NaN;
        this.pinchPinchMin = Float.NaN;
        this.openSamples = 0;
        this.fistSamples = 0;
        this.pinchSamples = 0;
    }

    public boolean active(long nowNs) {
        return this.started && phaseAt(nowNs) != PHASE_DONE;
    }

    public int phaseAt(long nowNs) {
        if (!this.started) return PHASE_DONE;
        long elapsedMs = Math.max(0L, (nowNs - this.startNs) / 1_000_000L);
        if (elapsedMs < OPEN_MS) return 0;
        if (elapsedMs < OPEN_MS + FIST_MS) return 1;
        if (elapsedMs < TOTAL_MS) return 2;
        return PHASE_DONE;
    }

    public static String promptFor(int phase) {
        return switch (phase) {
            case 0 -> "[VRMC] hand calibration: OPEN both hands wide (3 s)";
            case 1 -> "[VRMC] hand calibration: CLOSE both FISTS (3 s)";
            case 2 -> "[VRMC] hand calibration: THUMB-INDEX PINCH both hands (3 s)";
            default -> "[VRMC] hand calibration complete";
        };
    }

    /** Record one tracked-hand sample for the current phase; non-finite values are ignored. */
    public void record(int phase, float pinchDistance, float fistRatio) {
        if (!Float.isFinite(pinchDistance) || !Float.isFinite(fistRatio) || pinchDistance <= 0F) return;
        switch (phase) {
            case 0 -> {
                this.openSamples++;
                this.openPinchMax = max(this.openPinchMax, pinchDistance);
                this.openFistMin = min(this.openFistMin, fistRatio);
            }
            case 1 -> {
                this.fistSamples++;
                this.fistFistMax = max(this.fistFistMax, fistRatio);
            }
            case 2 -> {
                this.pinchSamples++;
                this.pinchPinchMin = min(this.pinchPinchMin, pinchDistance);
            }
            default -> { }
        }
    }

    public boolean hasEnoughData() {
        return this.openSamples >= 10 && this.fistSamples >= 10 && this.pinchSamples >= 10
            && Float.isFinite(this.openPinchMax) && Float.isFinite(this.openFistMin)
            && Float.isFinite(this.fistFistMax) && Float.isFinite(this.pinchPinchMin);
    }

    public float suggestedPinchOn() {
        float range = Math.max(0.005F, this.openPinchMax - this.pinchPinchMin);
        return clamp(this.pinchPinchMin + 0.25F * range, 0.010F, 0.080F);
    }

    public float suggestedPinchOff() {
        float range = Math.max(0.005F, this.openPinchMax - this.pinchPinchMin);
        return clamp(Math.max(suggestedPinchOn() + 0.008F, this.pinchPinchMin + 0.55F * range),
            suggestedPinchOn() + 0.008F, 0.120F);
    }

    public float suggestedFistOn() {
        float range = Math.max(0.05F, this.fistFistMax - this.openFistMin);
        return clamp(this.openFistMin + 0.25F * range, 0.60F, 2.00F);
    }

    public float suggestedFistOff() {
        float range = Math.max(0.05F, this.fistFistMax - this.openFistMin);
        return clamp(Math.max(suggestedFistOn() + 0.05F, this.openFistMin + 0.50F * range),
            suggestedFistOn() + 0.05F, 2.50F);
    }

    /** Human/machine readable report saved to the game directory for launcher/export review. */
    public String report(long nowNs) {
        StringBuilder b = new StringBuilder(512);
        b.append("# VRMC hand calibration report\n");
        b.append("# protocol: open 3s / fists 3s / pinch 3s; advisory only\n");
        b.append("openSamples=").append(this.openSamples)
            .append(" fistSamples=").append(this.fistSamples)
            .append(" pinchSamples=").append(this.pinchSamples).append('\n');
        b.append("openPinchMax=").append(fmt(this.openPinchMax))
            .append(" openFistMin=").append(fmt(this.openFistMin)).append('\n');
        b.append("fistFistMax=").append(fmt(this.fistFistMax))
            .append(" pinchPinchMin=").append(fmt(this.pinchPinchMin)).append('\n');
        if (!hasEnoughData()) {
            b.append("valid=no insufficient_samples (keep hands tracked in view; retry)\n");
            return b.toString();
        }
        b.append("valid=yes\n");
        b.append(String.format(Locale.ROOT, "suggested pinch.on=%.3f pinch.off=%.3f fist.on=%.2f fist.off=%.2f%n",
            suggestedPinchOn(), suggestedPinchOff(), suggestedFistOn(), suggestedFistOff()));
        b.append(String.format(Locale.ROOT, "oneLine pinch=%.3f/%.3f fist=%.2f/%.2f%n",
            suggestedPinchOn(), suggestedPinchOff(), suggestedFistOn(), suggestedFistOff()));
        return b.toString();
    }

    private static String fmt(float v) {
        return Float.isFinite(v) ? String.format(Locale.ROOT, "%.4f", v) : "n/a";
    }

    private static float max(float a, float b) { return Float.isNaN(a) || b > a ? b : a; }
    private static float min(float a, float b) { return Float.isNaN(a) || b < a ? b : a; }
    private static float clamp(float v, float lo, float hi) { return Math.max(lo, Math.min(hi, v)); }
}
