package dev.vrmc.provider;

import java.io.File;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Properties;

/**
 * M5 runtime/comfort/performance settings parsed from {@code vrmc-runtime.properties} in the game
 * directory (pure Java, host-testable).
 *
 * <p>Product rule: **no silent settings changes.** Every value is opt-in through the file; missing
 * keys keep Minecraft's/Vivecraft's current values. Invalid values are reported and ignored rather
 * than clamped silently. Presets expand to concrete values so the log states exactly what was applied.
 *
 * <p>Supported keys (all optional):
 * <pre>
 * comfort.seated=true|false
 * comfort.seatedFreeMove=true|false
 * comfort.seatedUseHMD=true|false
 * comfort.seatedHmdPointer=true|false  (use HMD aim for the GUI/controller pointer when seated and no hand tracked)
 * comfort.worldRotationIncrement=0|45|...   (0 = smooth rotation, &gt;0 = snap angle degrees)
 * comfort.worldScale=0.1..5
 * comfort.manualHeight=-1|1.0..2.2         (-1 = auto height)
 * performance.preset=none|performance|balanced|quality
 * performance.renderDistance=2..32
 * performance.simulationDistance=2..32
 * performance.framerateLimit=30..260
 * performance.vsync=true|false
 * diagnostics.periodSeconds=5..3600
 * </pre>
 */
public final class VisionRuntimeSettings {
    public static final String FILE_NAME = "vrmc-runtime.properties";

    public final boolean hasSeated;
    public final boolean seated;
    public final boolean hasSeatedFreeMove;
    public final boolean seatedFreeMove;
    public final boolean hasSeatedUseHMD;
    public final boolean seatedUseHMD;
    public final boolean hasWorldRotationIncrement;
    public final float worldRotationIncrement;
    public final boolean hasSeatedHmdPointer;
    public final boolean seatedHmdPointer;
    public final boolean hasWorldScale;
    public final float worldScale;
    public final boolean hasManualHeight;
    public final float manualHeight;
    public final boolean hasRenderDistance;
    public final int renderDistance;
    public final boolean hasSimulationDistance;
    public final int simulationDistance;
    public final boolean hasFramerateLimit;
    public final int framerateLimit;
    public final boolean hasVsync;
    public final boolean vsync;
    public final int diagnosticPeriodSeconds;
    public final String preset;
    public final List<String> warnings;

    private VisionRuntimeSettings(boolean hasSeated, boolean seated, boolean hasSeatedFreeMove,
                                  boolean seatedFreeMove, boolean hasSeatedUseHMD, boolean seatedUseHMD,
                                  boolean hasWorldRotationIncrement, float worldRotationIncrement,
                                  boolean hasSeatedHmdPointer, boolean seatedHmdPointer,
                                  boolean hasWorldScale, float worldScale,
                                  boolean hasManualHeight, float manualHeight,
                                  boolean hasRenderDistance, int renderDistance,
                                  boolean hasSimulationDistance, int simulationDistance,
                                  boolean hasFramerateLimit, int framerateLimit,
                                  boolean hasVsync, boolean vsync, int diagnosticPeriodSeconds,
                                  String preset, List<String> warnings) {
        this.hasSeated = hasSeated;
        this.seated = seated;
        this.hasSeatedFreeMove = hasSeatedFreeMove;
        this.seatedFreeMove = seatedFreeMove;
        this.hasSeatedUseHMD = hasSeatedUseHMD;
        this.seatedUseHMD = seatedUseHMD;
        this.hasWorldRotationIncrement = hasWorldRotationIncrement;
        this.worldRotationIncrement = worldRotationIncrement;
        this.hasSeatedHmdPointer = hasSeatedHmdPointer;
        this.seatedHmdPointer = seatedHmdPointer;
        this.hasWorldScale = hasWorldScale;
        this.worldScale = worldScale;
        this.hasManualHeight = hasManualHeight;
        this.manualHeight = manualHeight;
        this.hasRenderDistance = hasRenderDistance;
        this.renderDistance = renderDistance;
        this.hasSimulationDistance = hasSimulationDistance;
        this.simulationDistance = simulationDistance;
        this.hasFramerateLimit = hasFramerateLimit;
        this.framerateLimit = framerateLimit;
        this.hasVsync = hasVsync;
        this.vsync = vsync;
        this.diagnosticPeriodSeconds = diagnosticPeriodSeconds;
        this.preset = preset;
        this.warnings = List.copyOf(warnings);
    }

    /** Read the file if present; missing file returns defaults (nothing applied) with no error. */
    public static VisionRuntimeSettings load(File gameDir, java.util.function.Consumer<String> log) {
        if (gameDir == null) return defaults();
        Path path = gameDir.toPath().resolve(FILE_NAME);
        if (!Files.isRegularFile(path)) return defaults();
        Properties props = new Properties();
        try (InputStream in = Files.newInputStream(path)) {
            props.load(in);
        } catch (Throwable t) {
            if (log != null) log.accept("[VRMC-M5][WARN] could not read " + FILE_NAME + ": " + t);
            return defaults();
        }
        Map<String, String> map = new java.util.HashMap<>();
        for (String name : props.stringPropertyNames()) {
            map.put(name, props.getProperty(name));
        }
        VisionRuntimeSettings settings = parse(map);
        if (log != null) {
            for (String warning : settings.warnings) log.accept("[VRMC-M5][WARN] " + warning);
        }
        return settings;
    }

    public static VisionRuntimeSettings defaults() {
        return parse(Map.of());
    }

    /** Parse a property map (tests use this; {@link #load(File, Consumer)} reads the real file). */
    public static VisionRuntimeSettings parse(Map<String, String> raw) {
        Map<String, String> props = raw == null ? Map.of() : raw;
        List<String> warnings = new ArrayList<>();
        String preset = lower(trim(props.get("performance.preset")));
        if (preset.isEmpty()) preset = "none";
        if (!preset.equals("none") && !preset.equals("performance") && !preset.equals("balanced")
            && !preset.equals("quality")) {
            warnings.add("unknown performance.preset='" + preset + "' ignored (using none)");
            preset = "none";
        }

        Boolean seatedValue = boolOrNull(props, "comfort.seated", warnings);
        boolean hasSeated = seatedValue != null;
        boolean seated = Boolean.TRUE.equals(seatedValue);
        Boolean freeMoveValue = boolOrNull(props, "comfort.seatedFreeMove", warnings);
        boolean hasSeatedFreeMove = freeMoveValue != null;
        boolean seatedFreeMove = Boolean.TRUE.equals(freeMoveValue);
        Boolean useHmdValue = boolOrNull(props, "comfort.seatedUseHMD", warnings);
        boolean hasSeatedUseHMD = useHmdValue != null;
        boolean seatedUseHMD = Boolean.TRUE.equals(useHmdValue);
        Boolean seatedPointerValue = boolOrNull(props, "comfort.seatedHmdPointer", warnings);
        boolean hasSeatedHmdPointer = seatedPointerValue != null;
        boolean seatedHmdPointer = Boolean.TRUE.equals(seatedPointerValue);

        boolean hasRotation = props.containsKey("comfort.worldRotationIncrement");
        float rotation = 0.0F;
        if (hasRotation) {
            Float v = parseFloat(props.get("comfort.worldRotationIncrement"), warnings,
                "comfort.worldRotationIncrement");
            if (v == null || v < 0.0F || v > 180.0F) {
                if (v != null) warnings.add("comfort.worldRotationIncrement=" + v + " out of range 0..180; ignored");
                hasRotation = false;
            } else {
                rotation = v;
            }
        }

        boolean hasWorldScale = props.containsKey("comfort.worldScale");
        float worldScale = 1.0F;
        if (hasWorldScale) {
            Float v = parseFloat(props.get("comfort.worldScale"), warnings, "comfort.worldScale");
            if (v == null || v < 0.1F || v > 5.0F) {
                if (v != null) warnings.add("comfort.worldScale=" + v + " out of range 0.1..5; ignored");
                hasWorldScale = false;
            } else {
                worldScale = v;
            }
        }
        boolean hasManualHeight = props.containsKey("comfort.manualHeight");
        float manualHeight = -1.0F;
        if (hasManualHeight) {
            Float v = parseFloat(props.get("comfort.manualHeight"), warnings, "comfort.manualHeight");
            if (v == null || (v != -1.0F && (v < 1.0F || v > 2.2F))) {
                if (v != null) warnings.add("comfort.manualHeight=" + v + " must be -1 (auto) or 1.0..2.2; ignored");
                hasManualHeight = false;
            } else {
                manualHeight = v;
            }
        }

        // Preset values are defaults; explicit keys win.
        boolean presetActive = !preset.equals("none");
        boolean hasRender = props.containsKey("performance.renderDistance") || presetActive;
        int render = 12;
        boolean hasSim = props.containsKey("performance.simulationDistance") || presetActive;
        int sim = 12;
        boolean hasFps = props.containsKey("performance.framerateLimit") || presetActive;
        int fps = 90;
        boolean hasVsync = props.containsKey("performance.vsync") || presetActive;
        boolean vsync = false;
        switch (preset) {
            case "performance" -> { render = 8; sim = 8; fps = 90; vsync = false; }
            case "balanced" -> { render = 12; sim = 10; fps = 90; vsync = false; }
            case "quality" -> { render = 16; sim = 12; fps = 90; vsync = true; }
            default -> { }
        }
        if (hasRender && props.containsKey("performance.renderDistance")) {
            Integer v = parseInt(props.get("performance.renderDistance"), 2, 32, warnings, "performance.renderDistance");
            if (v == null) hasRender = false; else render = v;
        }
        if (hasSim && props.containsKey("performance.simulationDistance")) {
            Integer v = parseInt(props.get("performance.simulationDistance"), 2, 32, warnings, "performance.simulationDistance");
            if (v == null) hasSim = false; else sim = v;
        }
        if (hasFps && props.containsKey("performance.framerateLimit")) {
            Integer v = parseInt(props.get("performance.framerateLimit"), 30, 260, warnings, "performance.framerateLimit");
            if (v == null) hasFps = false; else fps = v;
        }
        Boolean vsyncValue = boolOrNull(props, "performance.vsync", warnings);
        if (vsyncValue != null) {
            vsync = vsyncValue;
        } else if (!presetActive) {
            hasVsync = false;
        }

        int diagnosticPeriod = 30;
        String diagRaw = trim(props.get("diagnostics.periodSeconds"));
        if (!diagRaw.isEmpty()) {
            Integer v = parseInt(diagRaw, 5, 3600, warnings, "diagnostics.periodSeconds");
            if (v == null) { /* keep default */ } else diagnosticPeriod = v;
        }
        return new VisionRuntimeSettings(hasSeated, seated, hasSeatedFreeMove, seatedFreeMove,
            hasSeatedUseHMD, seatedUseHMD, hasRotation, rotation,
            hasSeatedHmdPointer, seatedHmdPointer, hasWorldScale, worldScale,
            hasManualHeight, manualHeight, hasRender, render, hasSim, sim,
            hasFps, fps, hasVsync, vsync, diagnosticPeriod, preset, warnings);
    }

    private static Boolean boolOrNull(Map<String, String> p, String key, List<String> warnings) {
        if (!p.containsKey(key)) return null;
        String raw = trim(p.get(key));
        if (raw.equalsIgnoreCase("true") || raw.equals("1")) return Boolean.TRUE;
        if (raw.equalsIgnoreCase("false") || raw.equals("0")) return Boolean.FALSE;
        warnings.add(key + "='" + raw + "' is not a boolean; ignored");
        return null;
    }

    private static Integer parseInt(String raw, int min, int max, List<String> warnings, String key) {
        try {
            int v = Integer.parseInt(trim(raw));
            if (v < min || v > max) {
                warnings.add(key + "=" + v + " out of range " + min + ".." + max + "; ignored");
                return null;
            }
            return v;
        } catch (NumberFormatException e) {
            warnings.add(key + "='" + raw + "' is not an integer; ignored");
            return null;
        }
    }

    private static Float parseFloat(String raw, List<String> warnings, String key) {
        try {
            float v = Float.parseFloat(trim(raw));
            return Float.isFinite(v) ? v : null;
        } catch (NumberFormatException e) {
            warnings.add(key + "='" + raw + "' is not a number; ignored");
            return null;
        }
    }

    private static String trim(String s) {
        return s == null ? "" : s.trim();
    }

    private static String lower(String s) {
        return s.toLowerCase(java.util.Locale.ROOT);
    }

    /** One-line summary for the startup log. */
    public String summary() {
        return "preset=" + preset
            + " seated=" + (hasSeated ? seated : "unchanged")
            + " seatedFreeMove=" + (hasSeatedFreeMove ? seatedFreeMove : "unchanged")
            + " seatedUseHMD=" + (hasSeatedUseHMD ? seatedUseHMD : "unchanged")
            + " seatedHmdPointer=" + (hasSeatedHmdPointer ? seatedHmdPointer : "unchanged")
            + " worldRotationIncrement=" + (hasWorldRotationIncrement ? worldRotationIncrement : "unchanged")
            + " worldScale=" + (hasWorldScale ? worldScale : "unchanged")
            + " manualHeight=" + (hasManualHeight ? manualHeight : "unchanged")
            + " renderDistance=" + (hasRenderDistance ? renderDistance : "unchanged")
            + " simulationDistance=" + (hasSimulationDistance ? simulationDistance : "unchanged")
            + " framerateLimit=" + (hasFramerateLimit ? framerateLimit : "unchanged")
            + " vsync=" + (hasVsync ? vsync : "unchanged")
            + " diagnosticsPeriodSec=" + diagnosticPeriodSeconds;
    }
}
