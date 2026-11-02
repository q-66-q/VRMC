package dev.vrmc.provider;

import java.util.Arrays;

/**
 * M5 performance diagnostics: a small rolling window of provider poll intervals with P50/P95/max and
 * a 90 Hz missed-frame count. Pure Java, allocation-free on the record path (one sort per report).
 *
 * <p>The provider poll runs once per rendered frame, so interval stats are a useful proxy for frame
 * pacing when the compositor/renderer do not expose GPU timestamps to Java. A "missed 90 Hz frame" is
 * an interval longer than 1.5 × 11.111 ms; that is a deliberately simple, documented threshold rather
 * than a claim of rendered-frame drops.
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

    public Snapshot snapshotAndReset() {
        if (this.count == 0) {
            Snapshot empty = new Snapshot(0, 0.0, 0.0, 0.0, 0);
            return empty;
        }
        long[] copy = Arrays.copyOf(this.samples, this.count);
        Arrays.sort(copy);
        double meanMs = 0.0;
        int missed = 0;
        for (long v : copy) {
            meanMs += v * 1.0E-6;
            if (v > NINETY_HZ_MS * 1.5 * 1.0E6) missed++;
        }
        meanMs /= copy.length;
        double p50 = copy[(int) Math.floor((copy.length - 1) * 0.50)] * 1.0E-6;
        double p95 = copy[(int) Math.floor((copy.length - 1) * 0.95)] * 1.0E-6;
        double max = copy[copy.length - 1] * 1.0E-6;
        reset();
        return new Snapshot(meanMs, p50, p95, max, missed);
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
        public final int missed90HzFrames;

        Snapshot(double meanMs, double p50Ms, double p95Ms, double maxMs, int missed90HzFrames) {
            this.meanMs = meanMs;
            this.p50Ms = p50Ms;
            this.p95Ms = p95Ms;
            this.maxMs = maxMs;
            this.missed90HzFrames = missed90HzFrames;
        }
    }
}
