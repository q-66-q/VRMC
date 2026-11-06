package dev.vrmc.provider;

import java.util.Locale;

/**
 * M8 frame trace (CSV): one row per auto-policy window (every 240 rendered frames), appended to the
 * game directory. It gives a device pull a time series of the resolution/refresh trade (eye target,
 * scale, resizes, measured display Hz, target override, missed deadlines, frame times, foveation,
 * content-first state) instead of only the last line of each log; no interpretation happens here.
 *
 * Pure formatting so the host test can check the schema without a game.
 */
public final class VisionTrace {
    public static final String FILE_NAME = "vrmc-m8-trace.csv";
    public static final int MAX_ROWS = 20000;
    public static final String HEADER =
        "frame,timestamp_ms,display_hz,target_hz,eye_w,eye_h,scale,resizes,missed_target,samples,"
            + "p50_ms,p95_ms,foveation,rate_maps,quality,max_quality,content_first,reductions";

    private VisionTrace() {}

    /** Format one row; non-finite numbers become 0 so the CSV stays parseable. */
    public static String row(long frame, long timestampMs, double displayHz, int targetHz,
                             int eyeWidth, int eyeHeight, float scale, int resizes,
                             int missedTarget, int samples, double p50Ms, double p95Ms,
                             int foveation, int rateMaps, float quality, float maxQuality,
                             int contentFirst, int reductions) {
        return String.format(Locale.ROOT,
            "%d,%d,%.2f,%d,%d,%d,%.2f,%d,%d,%d,%.2f,%.2f,%d,%d,%.2f,%.2f,%d,%d",
            frame, timestampMs, finite(displayHz), targetHz, eyeWidth, eyeHeight, finite(scale),
            resizes, missedTarget, samples, finite(p50Ms), finite(p95Ms), foveation, rateMaps,
            finite(quality), finite(maxQuality), contentFirst, reductions);
    }

    /** Number of columns in the header/row schema. */
    public static int columnCount() {
        return HEADER.split(",", -1).length;
    }

    private static double finite(double value) {
        return Double.isFinite(value) ? value : 0.0;
    }
}
