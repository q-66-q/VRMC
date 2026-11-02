package dev.vrmc.provider;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.util.List;

/**
 * M5 runtime command file: a tiny, explicit control channel for the launcher/shell and diagnostics.
 *
 * <p>The shell writes {@code vrmc-command.txt} into the game directory; the provider polls it (at most
 * twice per second), consumes it, executes one known command and appends a line to
 * {@code vrmc-command-result.txt}. Unknown commands are rejected (never guessed/executed) and
 * reported. This is intentionally not a general scripting interface.
 *
 * <p>Pure Java + filesystem only; host-tested by {@link VisionCommandFileTest}.
 */
public final class VisionCommandFile {
    public static final String FILE_NAME = "vrmc-command.txt";
    public static final String RESULT_FILE_NAME = "vrmc-command-result.txt";
    public static final List<String> COMMANDS = List.of(
        "recenter", "calibrate-height", "reload-settings", "diag", "status");

    private VisionCommandFile() {}

    /** Read and delete the command file; returns a recognized command or null when absent/IO error. */
    public static String take(Path gameDir, java.util.function.Consumer<String> log) {
        if (gameDir == null) return null;
        Path path = gameDir.resolve(FILE_NAME);
        if (!Files.isRegularFile(path)) return null;
        String raw;
        try {
            raw = Files.readString(path).trim().toLowerCase(java.util.Locale.ROOT);
            Files.deleteIfExists(path);
        } catch (Throwable t) {
            if (log != null) log.accept("[VRMC-M5][WARN] command file read/delete failed: " + t);
            return null;
        }
        if (raw.isEmpty()) return null;
        String first = raw.split("\\s+")[0];
        if (!COMMANDS.contains(first)) {
            appendResult(gameDir, first, "REJECTED unknown command (known: " + COMMANDS + ")", log);
            return null;
        }
        return first;
    }

    /** Append one result line; never throws into game code. */
    public static void appendResult(Path gameDir, String command, String detail,
                                    java.util.function.Consumer<String> log) {
        if (gameDir == null) return;
        try {
            String line = Instant.now() + " command=" + command + " " + detail + System.lineSeparator();
            Files.writeString(gameDir.resolve(RESULT_FILE_NAME), line,
                StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (Throwable t) {
            if (log != null) log.accept("[VRMC-M5][WARN] command result write failed: " + t);
        }
    }
}
