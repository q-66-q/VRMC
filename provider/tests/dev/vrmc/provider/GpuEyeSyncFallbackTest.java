package dev.vrmc.provider;

import java.io.File;
import java.nio.file.Files;

/**
 * Host test for the flag-gated enable/fallback contract of {@link GpuEyeSync} (no device).
 *
 * <p>On the build host there is no live Minecraft/Vulkan device, so when the flag is requested
 * {@code tryEnable} must return {@code null} after ONE clear warning line and must never throw; when
 * the flag is absent it must return {@code null} silently. The shell runner additionally asserts the
 * warning text and checks the system-property activation path.
 */
public final class GpuEyeSyncFallbackTest {
    public static void main(String[] args) throws Exception {
        File gameDir = (args.length > 0) ? new File(args[0]) : Files.createTempDirectory("vrmc-gpu-sync-")
            .toFile();
        boolean requested = GpuSyncFlags.isRequested(gameDir);
        System.out.println("[provider-fallback-test] gameDir=" + gameDir + " requested=" + requested);

        GpuEyeSync sync;
        try {
            sync = GpuEyeSync.tryEnable(gameDir);
        } catch (Throwable t) {
            System.out.println("FAIL: tryEnable threw " + t);
            System.exit(2);
            return;
        }
        if (sync != null) {
            System.out.println("FAIL: host enabled GPU sync unexpectedly");
            System.exit(3);
            return;
        }
        if (requested) {
            System.out.println("[provider-fallback-test] requested-but-unavailable: returned null safely (see warning line above)");
            System.out.println("[provider-fallback-test] PASS (graceful fallback)");
        } else {
            System.out.println("[provider-fallback-test] not requested: returned null silently");
            System.out.println("[provider-fallback-test] PASS (off by default)");
        }
    }
}
