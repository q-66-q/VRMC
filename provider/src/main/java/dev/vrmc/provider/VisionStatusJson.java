package dev.vrmc.provider;

import java.time.Instant;

/**
 * M5 diagnostics status document (pure builder, host-tested). The launcher/diagnostics parse
 * {@code vrmc-status.json}; keeping generation in one tested place prevents invalid JSON regressions.
 */
public final class VisionStatusJson {
    private VisionStatusJson() {}

    public static final class Data {
        public final String generatedAt;
        public final int abi;
        public final boolean bridgeReady;
        public final boolean initialized;
        public final long displayViewsGen;
        public final int trackedFrames;
        public final boolean seated;
        public final boolean inputHealthy;
        public final boolean handLeftTracked;
        public final boolean handRightTracked;
        public final boolean playerPresent;
        public final String runningOnVisionOS;
        public final String runtimeSettings;
        public final float hotbarRange;
        public final String inputTuning;
        public final String thermalState;
        public final String thermalResponse;
        public final boolean adaptiveFramerate;
        public final boolean adaptiveFramerateApplied;
        public final float frameP50Ms;
        public final float frameP95Ms;
        public final int missed90Frames;
        public final String gestures;
        public final boolean bowActive;
        public final boolean bowNotched;
        public final float bowDrawPercent;
        public final boolean climbGrabbing;
        public final boolean climbeyClimb;
        public final boolean climbActive;

        public Data(String generatedAt, int abi, boolean bridgeReady, boolean initialized,
                    long displayViewsGen, int trackedFrames, boolean seated, boolean inputHealthy,
                    boolean handLeftTracked, boolean handRightTracked, boolean playerPresent,
                    String runningOnVisionOS, String runtimeSettings, float hotbarRange,
                    String inputTuning, String thermalState, String thermalResponse,
                    boolean adaptiveFramerate, boolean adaptiveFramerateApplied,
                    float frameP50Ms, float frameP95Ms, int missed90Frames,
                    boolean bowActive, boolean bowNotched, float bowDrawPercent,
                    boolean climbGrabbing, boolean climbeyClimb, boolean climbActive,
                    String gestures) {
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
        }
    }

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
        bool(json, "climbActive", d.climbActive, false);
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

    private static void rawNumber(StringBuilder out, String key, float value, boolean comma) {
        if (!Float.isFinite(value)) value = 0.0F;
        out.append("  \"").append(key).append("\": ").append(value).append(comma ? ",\n" : "\n");
    }

    private static void bool(StringBuilder out, String key, boolean value, boolean comma) {
        out.append("  \"").append(key).append("\": ").append(value).append(comma ? ",\n" : "\n");
    }

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
