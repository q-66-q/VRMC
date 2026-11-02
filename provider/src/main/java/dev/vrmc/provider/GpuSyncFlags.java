package dev.vrmc.provider;

import java.io.File;

/**
 * Activation switch for the provider-side GPU eye-frame synchronization (timeline VkSemaphore ->
 * MTLSharedEvent -> compositor wait). <b>Off by default</b>; enabled only by:
 *
 * <ul>
 *   <li>a {@code vrmc-gpu-sync.flag} file in the Minecraft game directory (same place as
 *       {@code vrmc-capture.flag}), or</li>
 *   <li>{@code -Dvrmc.gpuSync=1} (also accepts true/yes/on for convenience).</li>
 * </ul>
 *
 * <p>Kept free of Minecraft/Vivecraft imports so {@code provider/tests/GpuSyncFlagsTest} can run it on
 * the build host. See docs/analysis/provider-gpu-sync.md for the device procedure.
 */
public final class GpuSyncFlags {
    /** Game-directory file that enables the GPU sync path. */
    public static final String FLAG_FILE = "vrmc-gpu-sync.flag";
    /** System property that enables the GPU sync path (takes precedence; "0"/"false" is off). */
    public static final String PROPERTY = "vrmc.gpuSync";

    private GpuSyncFlags() {}

    /** True when the sync path was explicitly requested for this launch. */
    public static boolean isRequested(File gameDirectory) {
        String property = System.getProperty(PROPERTY);
        if (property != null) {
            String value = property.trim().toLowerCase(java.util.Locale.ROOT);
            if (value.equals("1") || value.equals("true") || value.equals("yes") || value.equals("on")) {
                return true;
            }
            if (!value.isEmpty()) {
                return false; // explicit off: "-Dvrmc.gpuSync=0" beats the flag file
            }
        }
        return gameDirectory != null && new File(gameDirectory, FLAG_FILE).isFile();
    }
}
