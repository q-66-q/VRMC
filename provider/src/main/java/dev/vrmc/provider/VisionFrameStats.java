package dev.vrmc.provider;

import java.util.Arrays;

/**
 * M5 performance diagnostics: a small rolling window of provider poll intervals with P50/P95/max and
 * a 90 Hz missed-frame count. Pure Java, allocation-free on the record path (one sort per report).
 *
 * <p>The provider poll runs once per rendered frame, so interval stats are a useful proxy for frame
 * pacing when the compositor/renderer do not expose GPU timestamps to Java. A "missed frame" is an
 * interval longer than 1.5 x the target interval; that is a deliberately simple, documented threshold
 * rather than a claim of rendered-frame drops. M8 render feedback added the target-interval overload
 * (the display may be 90 or 120 Hz): snapshotAndReset() keeps the original 90 Hz default for the
 * existing status/JSON consumers, snapshotAndReset(targetIntervalMs) scores against the measured
 * display cadence.
 */
public final class VisionFrameStats {
    public static final double NINETY_HZ_MS = 1000.0 / 90.0;
    private final long[] samples;
    private int count;
    private int writeIndex;

    public VisionFrameStats(int capacity) {
        this.samples = new long[Math.max(1, capacity)];
    }

    public void record(long intervalNs) {
        if (intervalNs <= 0L) return;
        this.samples[this.writeIndex] = intervalNs;
        this.writeIndex = (this.writeIndex + 1) % this.samples.length;
        if (this.count < this.samples.length) this.count++;
    }

    /** Original M5 behaviour: score missed frames against a 90 Hz display. */
    public Snapshot snapshotAndReset() {
        return snapshotAndReset(NINETY_HZ_MS);
    }

    /**
     * Snapshot scored against an arbitrary target frame interval (M8: the measured display cadence,
     * e.g. 8.333 ms at 120 Hz; non-positive/NaN falls back to the 90 Hz default).
     */
    public Snapshot snapshotAndReset(double targetIntervalMs) {
        final double targetMs = targetIntervalMs > 0.0 && !Double.isNaN(targetIntervalMs)
            ? targetIntervalMs : NINETY_HZ_MS;
        if (this.count == 0) {
            return new Snapshot(0, 0.0, 0.0, 0.0, 0, 0, 0);
        }
        long[] copy = Arrays.copyOf(this.samples, this.count);
        Arrays.sort(copy);
        double meanMs = 0.0;
        int missedTarget = 0;
        int missed90 = 0;
        for (long v : copy) {
            meanMs += v * 1.0E-6;
            if (v > targetMs * 1.5 * 1.0E6) missedTarget++;
            if (v > NINETY_HZ_MS * 1.5 * 1.0E6) missed90++;
        }
        meanMs /= copy.length;
        double p50 = copy[(int) Math.floor((copy.length - 1) * 0.50)] * 1.0E-6;
        double p95 = copy[(int) Math.floor((copy.length - 1) * 0.95)] * 1.0E-6;
        double max = copy[copy.length - 1] * 1.0E-6;
        final int sampleCount = copy.length;
        reset();
        return new Snapshot(meanMs, p50, p95, max, missed90, missedTarget, sampleCount);
    }

    public void reset() {
        this.count = 0;
        this.writeIndex = 0;
        Arrays.fill(this.samples, 0L);
    }

    /** Immutable report. */
    public static final class Snapshot {
        public final double meanMs;
        public final double p50Ms;
        public final double p95Ms;
        public final double maxMs;
        /** Intervals over 1.5x the 90 Hz interval (the original M5 metric; stable for old consumers). */
        public final int missed90HzFrames;
        /** Intervals over 1.5x the TARGET interval used for this snapshot (M8: measured cadence). */
        public final int missedTargetFrames;
        /** Number of intervals in this snapshot (0 for an empty window). */
        public final int samples;

        Snapshot(double meanMs, double p50Ms, double p95Ms, double maxMs, int missed90HzFrames,
                 int missedTargetFrames, int samples) {
            this.meanMs = meanMs;
            this.p50Ms = p50Ms;
            this.p95Ms = p95Ms;
            this.maxMs = maxMs;
            this.missed90HzFrames = missed90HzFrames;
            this.missedTargetFrames = missedTargetFrames;
            this.samples = samples;
        }
    }
}
