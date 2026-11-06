package dev.vrmc.provider;

/** Host test for the M5 frame-stats reporter. */
public final class VisionFrameStatsTest {
    private static int checks;
    private static int failures;
    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) {
        VisionFrameStats stats = new VisionFrameStats(32);
        VisionFrameStats.Snapshot empty = stats.snapshotAndReset();
        check("empty snapshot", empty.meanMs == 0.0 && empty.p50Ms == 0.0 && empty.missed90HzFrames == 0);

        for (int i = 0; i < 90; i++) stats.record(11_111_111L);
        VisionFrameStats.Snapshot sn = stats.snapshotAndReset();
        check("90 Hz mean ~11.1 ms", Math.abs(sn.meanMs - 11.111) < 0.01, String.valueOf(sn.meanMs));
        check("90 Hz p50/p95 ~11.1 ms", Math.abs(sn.p50Ms - 11.111) < 0.01 && Math.abs(sn.p95Ms - 11.111) < 0.01,
            sn.p50Ms + "/" + sn.p95Ms);
        check("90 Hz no missed frames", sn.missed90HzFrames == 0);
        check("snapshot resets window", stats.snapshotAndReset().meanMs == 0.0);

        for (int i = 0; i < 99; i++) stats.record(10_000_000L);
        stats.record(50_000_000L); // one long frame
        VisionFrameStats.Snapshot mixed = stats.snapshotAndReset();
        check("p50 remains 10 ms", Math.abs(mixed.p50Ms - 10.0) < 0.01, String.valueOf(mixed.p50Ms));
        check("max reflects outlier", Math.abs(mixed.maxMs - 50.0) < 0.01, String.valueOf(mixed.maxMs));
        check("outlier counted as missed", mixed.missed90HzFrames == 1, String.valueOf(mixed.missed90HzFrames));

        stats.record(0L);
        stats.record(-5L);
        check("non-positive intervals ignored", stats.snapshotAndReset().meanMs == 0.0);

        VisionFrameStats small = new VisionFrameStats(4);
        for (int i = 0; i < 10; i++) small.record(5_000_000L + i);
        check("ring capacity bounded", small.snapshotAndReset().meanMs > 0.0);

        // M8: target-interval scoring (measured display cadence, e.g. 120 Hz) + sample count.
        VisionFrameStats hz = new VisionFrameStats(64);
        for (int i = 0; i < 30; i++) hz.record(8_333_333L);   // 120 Hz
        VisionFrameStats.Snapshot fast = hz.snapshotAndReset(1000.0 / 120.0);
        check("120 Hz cadence not missed", fast.missed90HzFrames == 0 && fast.samples == 30,
            fast.missed90HzFrames + "/" + fast.samples);
        for (int i = 0; i < 30; i++) hz.record(8_333_333L);
        for (int i = 0; i < 3; i++) hz.record(20_000_000L);  // repeated frames at 120 Hz
        VisionFrameStats.Snapshot slow = hz.snapshotAndReset(1000.0 / 120.0);
        check("120 Hz repeats scored against 8.33 ms",
            slow.missedTargetFrames == 3 && slow.samples == 33,
            slow.missedTargetFrames + "/" + slow.samples);
        // 13 ms intervals are within the 90 Hz budget (16.67 ms) but late for 120 Hz (12.5 ms): the
        // stable missed90 count must stay 0 while missedTarget reports every one of them.
        VisionFrameStats hz13 = new VisionFrameStats(32);
        for (int i = 0; i < 10; i++) hz13.record(13_000_000L);
        VisionFrameStats.Snapshot mid = hz13.snapshotAndReset(1000.0 / 120.0);
        check("13 ms: 90 Hz count stays 0, 120 Hz target count is 10",
            mid.missed90HzFrames == 0 && mid.missedTargetFrames == 10,
            mid.missed90HzFrames + "/" + mid.missedTargetFrames);
        hz.record(20_000_000L);
        VisionFrameStats.Snapshot fallback = hz.snapshotAndReset(Double.NaN);
        check("invalid target falls back to 90 Hz",
            fallback.missed90HzFrames == 1 && fallback.missedTargetFrames == 1,
            fallback.missed90HzFrames + "/" + fallback.missedTargetFrames);

        System.out.println("[m5-frame-stats-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m5-frame-stats-test] PASS" : "[m5-frame-stats-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
