import dev.vrmc.provider.GpuSyncFlags;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Host test for {@code GpuSyncFlags} (provider/tests/run_tests.sh).
 * Verifies: off by default, flag-file activation, -Dvrmc.gpuSync activation/override, no game dir,
 * and that the decision is stable/repeatable.
 */
public final class GpuSyncFlagsTest {
    private static int failures;

    private static void check(String name, boolean actual, boolean expected) {
        System.out.printf("  %-52s actual=%-5s expected=%-5s %s%n", name, actual, expected,
            actual == expected ? "ok" : "FAIL");
        if (actual != expected) failures++;
    }

    private static File tempDir(String name) throws IOException {
        Path dir = Files.createTempDirectory("vrmc-gpu-sync-" + name + "-");
        dir.toFile().deleteOnExit();
        return dir.toFile();
    }

    private static void setProperty(String value) {
        if (value == null) System.clearProperty("vrmc.gpuSync");
        else System.setProperty("vrmc.gpuSync", value);
    }

    public static void main(String[] args) throws Exception {
        System.out.println("[provider-flags-test] GpuSyncFlags (off by default)");
        File empty = tempDir("empty");
        setProperty(null);
        check("no flag file, no property -> OFF", GpuSyncFlags.isRequested(empty), false);
        check("null game dir, no property -> OFF", GpuSyncFlags.isRequested(null), false);

        File flagged = tempDir("flagged");
        Files.writeString(new File(flagged, GpuSyncFlags.FLAG_FILE).toPath(), "1\n");
        check("flag file -> ON", GpuSyncFlags.isRequested(flagged), true);
        check("flag file in other dir -> OFF for empty dir", GpuSyncFlags.isRequested(empty), false);

        setProperty("1");
        check("-Dvrmc.gpuSync=1, no flag file -> ON", GpuSyncFlags.isRequested(empty), true);
        setProperty("0");
        check("-Dvrmc.gpuSync=0 beats flag file -> OFF", GpuSyncFlags.isRequested(flagged), false);
        setProperty("false");
        check("-Dvrmc.gpuSync=false beats flag file -> OFF", GpuSyncFlags.isRequested(flagged), false);
        setProperty("true");
        check("-Dvrmc.gpuSync=true -> ON", GpuSyncFlags.isRequested(empty), true);
        setProperty("yes");
        check("-Dvrmc.gpuSync=yes -> ON", GpuSyncFlags.isRequested(empty), true);
        setProperty("on");
        check("-Dvrmc.gpuSync=on -> ON", GpuSyncFlags.isRequested(empty), true);
        setProperty("garbage");
        check("-Dvrmc.gpuSync=garbage is explicit OFF", GpuSyncFlags.isRequested(flagged), false);

        setProperty(null);
        System.out.println(failures == 0 ? "[provider-flags-test] PASS" : "[provider-flags-test] FAIL");
        System.exit(failures == 0 ? 0 : 1);
    }
}
