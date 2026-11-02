package dev.vrmc.provider;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;

/**
 * M5/M6 thermal awareness: reads the shell-written local thermal state and decides whether it is a
 * pressure state worth surfacing in-game. Pure Java + filesystem; host-tested.
 *
 * <p>The file is written by the visionOS shell's thermal monitor as key=value lines (no network).
 */
public final class VisionThermalState {
    public static final String FILE_NAME = "vrmc-thermal-state.txt";

    private VisionThermalState() {}

    /** @return normalized state (nominal/fair/serious/critical/unknown); missing file = unknown. */
    public static String readState(Path gameDir) {
        if (gameDir == null) return "unknown";
        Path path = gameDir.resolve(FILE_NAME);
        if (!Files.isRegularFile(path)) return "unknown";
        try {
            for (String line : Files.readAllLines(path)) {
                String trimmed = line.trim();
                if (trimmed.startsWith("state=")) {
                    String value = trimmed.substring("state=".length()).trim().toLowerCase(Locale.ROOT);
                    if (value.equals("nominal") || value.equals("fair") || value.equals("serious")
                        || value.equals("critical")) return value;
                    return "unknown";
                }
            }
        } catch (Throwable ignored) {
            // fall through
        }
        return "unknown";
    }

    public static boolean isPressure(String state) {
        return "serious".equals(state) || "critical".equals(state);
    }

    /** One-line chat-safe message for a pressure state. */
    public static String advisory(String state) {
        if ("critical".equals(state)) {
            return "[VRMC] thermal critical: take a break/cool down; consider lower render distance/frame limit in launcher.";
        }
        if ("serious".equals(state)) {
            return "[VRMC] thermal pressure: performance may reduce; consider lower render distance/frame limit.";
        }
        return null;
    }
}
