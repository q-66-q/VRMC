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

        public Data(String generatedAt, int abi, boolean bridgeReady, boolean initialized,
                    long displayViewsGen, int trackedFrames, boolean seated, boolean inputHealthy,
                    boolean handLeftTracked, boolean handRightTracked, boolean playerPresent,
                    String runningOnVisionOS, String runtimeSettings, float hotbarRange,
                    String inputTuning, String thermalState, String thermalResponse,
                    boolean adaptiveFramerate, boolean adaptiveFramerateApplied) {
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
        bool(json, "adaptiveFramerateApplied", d.adaptiveFramerateApplied, false);
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
