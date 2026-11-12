package dev.vrmc.provider;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.List;

/**
 * Minimal key=value updater for the launcher-owned settings files (vrmc-runtime.properties).
 *
 * <p>The in-VR quick menu changes a setting live and persists it here so the launcher window shows
 * the same value afterwards. Only the given key is touched: comments, unknown keys and ordering
 * are preserved, and the write is atomic (temp file + move) so a crash cannot truncate the file the
 * launcher and the next game start both read. Pure Java, host-testable.
 */
public final class VisionSettingsFile {
    public static final String RUNTIME_FILE = "vrmc-runtime.properties";

    private VisionSettingsFile() {}

    /** Set {@code key=value} in {@code file}; returns false (never throws) when the write fails. */
    public static boolean update(Path file, String key, String value) {
        if (file == null || key == null || key.isBlank() || value == null) return false;
        if (key.indexOf('\n') >= 0 || key.indexOf('=') >= 0 || value.indexOf('\n') >= 0
            || value.indexOf('\r') >= 0) {
            return false;
        }
        try {
            List<String> out = new ArrayList<>();
            boolean replaced = false;
            if (Files.isRegularFile(file)) {
                for (String line : Files.readAllLines(file, StandardCharsets.UTF_8)) {
                    String trimmed = line.trim();
                    int eq = trimmed.indexOf('=');
                    boolean comment = trimmed.startsWith("#") || trimmed.startsWith("!");
                    if (!comment && eq > 0 && trimmed.substring(0, eq).trim().equals(key)) {
                        if (!replaced) {
                            out.add(key + "=" + value);
                            replaced = true;
                        }
                        continue; // drop duplicate definitions of the same key
                    }
                    out.add(line);
                }
            }
            if (!replaced) out.add(key + "=" + value);
            Path parent = file.toAbsolutePath().getParent();
            if (parent != null) Files.createDirectories(parent);
            Path tmp = file.resolveSibling(file.getFileName() + ".tmp");
            Files.write(tmp, (String.join("\n", out) + "\n").getBytes(StandardCharsets.UTF_8));
            try {
                Files.move(tmp, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            } catch (IOException atomicUnsupported) {
                Files.move(tmp, file, StandardCopyOption.REPLACE_EXISTING);
            }
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    private static final float[] TURN_STEPS = {30.0F, 45.0F, 90.0F, 0.0F};

    /** Next snap-turn step after {@code current}: 30 -> 45 -> 90 -> smooth (0) -> 30. */
    public static float nextTurnStep(float current) {
        if (!Float.isFinite(current)) return TURN_STEPS[0];
        int nearest = 0;
        for (int i = 0; i < TURN_STEPS.length; i++) {
            if (Math.abs(TURN_STEPS[i] - current) < Math.abs(TURN_STEPS[nearest] - current)) nearest = i;
        }
        return TURN_STEPS[(nearest + 1) % TURN_STEPS.length];
    }

    private static final int[] RENDER_DISTANCES = {6, 8, 12, 16, 20, 24};

    /** Next render-distance step for the quick menu: 6 -> 8 -> 12 -> 16 -> 20 -> 24 -> 6. */
    public static int nextRenderDistance(int current) {
        int nearest = 0;
        for (int i = 0; i < RENDER_DISTANCES.length; i++) {
            if (Math.abs(RENDER_DISTANCES[i] - current)
                < Math.abs(RENDER_DISTANCES[nearest] - current)) nearest = i;
        }
        return RENDER_DISTANCES[(nearest + 1) % RENDER_DISTANCES.length];
    }

    private static final float[] WORLD_SCALES = {
        0.80F, 0.90F, 1.00F, 1.10F, 1.20F, 1.30F, 1.40F, 1.50F
    };

    /** Next world-scale step for the quick menu: 0.80 -> ... -> 1.50 -> 0.80. */
    public static float nextWorldScale(float current) {
        if (!Float.isFinite(current)) return WORLD_SCALES[0];
        int nearest = 0;
        for (int i = 0; i < WORLD_SCALES.length; i++) {
            if (Math.abs(WORLD_SCALES[i] - current)
                < Math.abs(WORLD_SCALES[nearest] - current)) nearest = i;
        }
        return WORLD_SCALES[(nearest + 1) % WORLD_SCALES.length];
    }

    /**
     * Comfort vignette levels shared by the quick menu and the compositor flag file. The compositor
     * clamps the flag value to 0..0.9 and the launcher slider spans 0.10..0.90, so 0.90 is the
     * strongest level: the old 4-level ladder stopped at 0.70 and displayed a launcher-written 0.90
     * as its "Strong" level (0.70), then the next press wrapped to Off (R2).
     */
    public static final float[] VIGNETTE_LEVELS = {0.0F, 0.30F, 0.50F, 0.70F, 0.90F};

    /** Quick-menu labels for {@link #VIGNETTE_LEVELS}; "Strong" is the compositor maximum (0.90). */
    public static final String[] VIGNETTE_NAMES = {"Off", "Light", "Medium", "High", "Strong"};

    /**
     * Nearest level index (0 = off) for a stored strength; missing/unparsable = off. A positive
     * strength always maps to at least Light, so an enabled launcher value never displays as Off.
     */
    public static int vignetteLevel(String stored) {
        if (stored == null) return 0;
        float value;
        try {
            value = Float.parseFloat(stored.trim());
        } catch (NumberFormatException e) {
            // The launcher writes a bare number; an empty legacy flag file meant the 0.5 default.
            return stored.isBlank() ? 2 : 0;
        }
        if (!Float.isFinite(value) || value <= 0.0F) return 0;
        int best = 1;
        for (int i = 1; i < VIGNETTE_LEVELS.length; i++) {
            if (Math.abs(VIGNETTE_LEVELS[i] - value) < Math.abs(VIGNETTE_LEVELS[best] - value)) best = i;
        }
        return best;
    }

    /**
     * The compositor's vignette flag lives in the app's Documents directory, two levels above the
     * default game directory (Documents/instances/default). Returns null when the game directory is
     * not laid out that way (host harness), so nothing is written outside the game directory.
     */
    public static Path vignetteFlag(Path gameDir) {
        if (gameDir == null) return null;
        Path abs = gameDir.toAbsolutePath().normalize();
        Path instances = abs.getParent();
        if (instances == null || instances.getFileName() == null
            || !"instances".equals(instances.getFileName().toString())) {
            return null;
        }
        Path documents = instances.getParent();
        return documents == null ? null : documents.resolve("vrmc-vignette.flag");
    }
}
