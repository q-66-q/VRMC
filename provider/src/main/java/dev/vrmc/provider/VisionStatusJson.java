package dev.vrmc.provider;

import java.time.Instant;

/**
 * M5 diagnostics status document (pure builder, host-tested). The launcher/diagnostics parse
 * {@code vrmc-status.json}; keeping generation in one tested place prevents invalid JSON regressions.
 *
 * <p>Contract with the launcher: every key the shell reads ({@code obj["…"]} / {@code status["…"]} in runtime/native-shell/Sources) must be
 * written here; {@code scripts/check_status_fields.sh} fails the release check on drift. Prefer
 * adding keys to renaming them, so an older launcher can still read a newer provider's status.
 */
public final class VisionStatusJson {
    private VisionStatusJson() {}

    public static final class Data {
        /** ISO-8601 timestamp; null means "use the build time passed to {@link #build}". */
        public final String generatedAt;
        /** Native bridge ABI version the provider was compiled against. */
        public final int abi;
        public final boolean bridgeReady;
        public final boolean initialized;
        /** Generation of the compositor's per-eye display views last adopted; -1 before the first. */
        public final long displayViewsGen;
        /** Head-pose frames consumed since the session started. */
        public final int trackedFrames;
        public final boolean seated;
        public final boolean inputHealthy;
        public final boolean handLeftTracked;
        public final boolean handRightTracked;
        public final boolean playerPresent;
        /** Platform name from {@link #platformName} ("visionOS" on the headset; key name kept for launcher compatibility). */
        public final String runningOnVisionOS;
        /** One-line summary of the parsed vrmc-runtime.properties. */
        public final String runtimeSettings;
        /** Hotbar touch reach in metres. */
        public final float hotbarRange;
        /** One-line summary of the active gesture thresholds. */
        public final String inputTuning;
        public final String thermalState;
        public final String thermalResponse;
        public final boolean adaptiveFramerate;
        public final boolean adaptiveFramerateApplied;
        public final float frameP50Ms;
        public final float frameP95Ms;
        /** Frames in the last stats window that missed the 11.1 ms (90 Hz) budget. */
        public final int missed90Frames;
        /** Active gesture engine and enabled gesture families. */
        public final String gestures;
        public final boolean bowActive;
        public final boolean bowNotched;
        public final float bowDrawPercent;
        public final boolean climbGrabbing;
        /** Vivecraft "Climbey" mode (climb claws equipped / server allows it). */
        public final boolean climbeyClimb;
        public final boolean climbActive;
        /** M8 renderer/display summary (eye target, display logical size, foveation, cadence, resizes). */
        public final String render;

        public Data(String generatedAt, int abi, boolean bridgeReady, boolean initialized,
                    long displayViewsGen, int trackedFrames, boolean seated, boolean inputHealthy,
                    boolean handLeftTracked, boolean handRightTracked, boolean playerPresent,
                    String runningOnVisionOS, String runtimeSettings, float hotbarRange,
                    String inputTuning, String thermalState, String thermalResponse,
                    boolean adaptiveFramerate, boolean adaptiveFramerateApplied,
                    float frameP50Ms, float frameP95Ms, int missed90Frames,
                    boolean bowActive, boolean bowNotched, float bowDrawPercent,
                    boolean climbGrabbing, boolean climbeyClimb, boolean climbActive,
                    String gestures, String render) {
            this.generatedAt = generatedAt;
            this.abi = abi;
            this.bridgeReady = bridgeReady;
            this.initialized = initialized;
            this.displayViewsGen = displayViewsGen;
            this.trackedFrames = trackedFrames;
            this.seated = seated;
            this.inputHealthy = inputHealthy;
            this.handLeftTracked = handLeftTracked;
            this.handRightTracked = handRightTracked;
            this.playerPresent = playerPresent;
            this.runningOnVisionOS = runningOnVisionOS;
            this.runtimeSettings = runtimeSettings;
            this.hotbarRange = hotbarRange;
            this.inputTuning = inputTuning;
            this.thermalState = thermalState;
            this.thermalResponse = thermalResponse;
            this.adaptiveFramerate = adaptiveFramerate;
            this.adaptiveFramerateApplied = adaptiveFramerateApplied;
            this.frameP50Ms = frameP50Ms;
            this.frameP95Ms = frameP95Ms;
            this.missed90Frames = missed90Frames;
            this.bowActive = bowActive;
            this.bowNotched = bowNotched;
            this.bowDrawPercent = bowDrawPercent;
            this.climbGrabbing = climbGrabbing;
            this.climbeyClimb = climbeyClimb;
            this.climbActive = climbActive;
            this.gestures = gestures;
            this.render = render;
        }
    }

    /**
     * Value for the status document's {@code runningOnVisionOS} field. The provider only ships inside
     * the visionOS app; on the headset Java reports {@code os.name=Mac OS X} (Darwin kernel), which
     * made the diagnostic field say "Mac OS X" and look like a desktop run. Report visionOS for the
     * Apple platforms and keep the raw OS name as a safe fallback if this code ever runs elsewhere.
     */
    public static String platformName(String osName) {
        if (osName == null) return "visionOS";
        String trimmed = osName.trim();
        if (trimmed.isEmpty()) return "visionOS";
        if (trimmed.startsWith("Mac") || trimmed.startsWith("Darwin")) return "visionOS";
        return trimmed;
    }

    /** Pretty-printed, always-valid JSON; key order is stable so diffs of pulled status files stay readable. */
    public static String build(Data d, Instant now) {
        StringBuilder json = new StringBuilder(512);
        json.append("{\n");
        field(json, "generatedAt", d.generatedAt == null ? String.valueOf(now) : d.generatedAt, true);
        number(json, "abi", d.abi, true);
        bool(json, "bridgeReady", d.bridgeReady, true);
        bool(json, "initialized", d.initialized, true);
        rawLong(json, "displayViewsGen", d.displayViewsGen, true);
        number(json, "trackedFrames", d.trackedFrames, true);
        bool(json, "seated", d.seated, true);
        bool(json, "inputHealthy", d.inputHealthy, true);
        bool(json, "handLeftTracked", d.handLeftTracked, true);
        bool(json, "handRightTracked", d.handRightTracked, true);
        bool(json, "playerPresent", d.playerPresent, true);
        field(json, "runningOnVisionOS", d.runningOnVisionOS, true);
        field(json, "runtimeSettings", d.runtimeSettings, true);
        rawNumber(json, "hotbarRange", d.hotbarRange, true);
        field(json, "inputTuning", d.inputTuning, true);
        field(json, "thermalState", d.thermalState, true);
        field(json, "thermalResponse", d.thermalResponse, true);
        bool(json, "adaptiveFramerate", d.adaptiveFramerate, true);
        bool(json, "adaptiveFramerateApplied", d.adaptiveFramerateApplied, true);
        rawNumber(json, "frameP50Ms", d.frameP50Ms, true);
        rawNumber(json, "frameP95Ms", d.frameP95Ms, true);
        number(json, "missed90Frames", d.missed90Frames, true);
        field(json, "gestures", d.gestures, true);
        bool(json, "bowActive", d.bowActive, true);
        bool(json, "bowNotched", d.bowNotched, true);
        rawNumber(json, "bowDrawPercent", d.bowDrawPercent, true);
        bool(json, "climbGrabbing", d.climbGrabbing, true);
        bool(json, "climbeyClimb", d.climbeyClimb, true);
        bool(json, "climbActive", d.climbActive, true);
        field(json, "render", d.render, false);
        json.append("}\n");
        return json.toString();
    }

    private static void field(StringBuilder out, String key, String value, boolean comma) {
        out.append("  \"").append(key).append("\": \"");
        escape(out, value == null ? "" : value);
        out.append(comma ? "\",\n" : "\"\n");
    }

    private static void rawLong(StringBuilder out, String key, long value, boolean comma) {
        out.append("  \"").append(key).append("\": ").append(value).append(comma ? ",\n" : "\n");
    }

    private static void number(StringBuilder out, String key, int value, boolean comma) {
        out.append("  \"").append(key).append("\": ").append(value).append(comma ? ",\n" : "\n");
    }

    /** JSON has no NaN/Infinity literals; a non-finite stat (e.g. empty window) is written as 0. */
    private static void rawNumber(StringBuilder out, String key, float value, boolean comma) {
        if (!Float.isFinite(value)) value = 0.0F;
        out.append("  \"").append(key).append("\": ").append(value).append(comma ? ",\n" : "\n");
    }

    private static void bool(StringBuilder out, String key, boolean value, boolean comma) {
        out.append("  \"").append(key).append("\": ").append(value).append(comma ? ",\n" : "\n");
    }

    /** RFC 8259 string escaping: quotes, backslash and every control character below U+0020. */
    private static void escape(StringBuilder out, String value) {
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '"' -> out.append("\\\"");
                case '\\' -> out.append("\\\\");
                case '\n' -> out.append("\\n");
                case '\r' -> out.append("\\r");
                case '\t' -> out.append("\\t");
                default -> {
                    if (c < 0x20) out.append(String.format("\\u%04x", (int) c));
                    else out.append(c);
                }
            }
        }
    }
}
