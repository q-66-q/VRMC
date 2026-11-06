package dev.vrmc.provider;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Random;

/**
 * Fuzz/robustness test for the M8 render-feedback parser (pure Java, no game/device).
 *
 * <p>The compositor payload arrives from shared memory, so {@link VisionRenderSettings#parse} must never
 * throw and must never surface out-of-contract values: arbitrary 68-byte buffers and single/multi-byte
 * mutations of a valid payload are fed through it and every accepted snapshot is checked against the
 * documented bounds (dimensions, quality, cadence, non-negative counts). This is the safety net for
 * device log/shared-memory corruption - the renderer must keep its current target instead of crashing
 * or allocating an absurd eye texture.
 */
public final class VisionRenderSettingsFuzzTest {
    private static final int RANDOM_CASES = 100_000;
    private static final int MUTATION_CASES = 20_000;

    public static void main(String[] args) {
        Random random = new Random(42);
        int violations = 0;
        int samples = 0;
        byte[] buffer = new byte[68];

        for (int i = 0; i < RANDOM_CASES; i++) {
            random.nextBytes(buffer);
            violations += checkBuffer(buffer, i, "random");
            if (violations > 5) break;
        }

        // A valid payload (mirrors the C fixture case 0) mutated at random byte positions.
        for (int i = 0; i < MUTATION_CASES; i++) {
            buildValid(buffer);
            int flips = 1 + random.nextInt(4);
            for (int f = 0; f < flips; f++) {
                buffer[random.nextInt(buffer.length)] = (byte) random.nextInt(256);
            }
            violations += checkBuffer(buffer, i, "mutation");
            if (violations > 5) break;
        }

        System.out.println("[m8-rs-fuzz-test] cases=" + (RANDOM_CASES + MUTATION_CASES)
            + " violations=" + violations);
        if (violations > 0) {
            System.out.println("[m8-rs-fuzz-test] FAIL");
            System.exit(1);
        }
        System.out.println("[m8-rs-fuzz-test] PASS");
        if (samples != 0) {
            throw new IllegalStateException("unreachable: " + samples);
        }
    }

    private static void buildValid(byte[] buffer) {
        ByteBuffer bb = ByteBuffer.wrap(buffer).order(ByteOrder.LITTLE_ENDIAN);
        bb.clear();
        for (int i = 0; i < buffer.length; i++) buffer[i] = 0;
        bb.putInt(0, 1);          // version
        bb.putInt(4, 1);          // valid
        bb.putInt(8, 1234);       // frame index
        bb.putInt(12, 1);         // foveation
        bb.putInt(16, 2);         // rate maps
        bb.putInt(20, 3660);
        bb.putInt(24, 3200);
        bb.putInt(28, 3660);
        bb.putInt(32, 3200);
        bb.putInt(36, 2412);
        bb.putInt(40, 2108);
        bb.putFloat(44, 1.0f);
        bb.putFloat(48, 1.0f);
        bb.putFloat(52, 120.0f);
        bb.putFloat(56, 8.345f);
        bb.putInt(60, 3664);
        bb.putInt(64, 3200);
    }

    private static int checkBuffer(byte[] bytes, int index, String kind) {
        VisionRenderSettings settings;
        try {
            settings = VisionRenderSettings.parse(ByteBuffer.wrap(bytes));
        } catch (Throwable throwable) {
            System.out.println("  VIOLATION " + kind + " case=" + index + " threw " + throwable);
            return 1;
        }
        if (settings == null) {
            System.out.println("  VIOLATION " + kind + " case=" + index + " parse returned null");
            return 1;
        }
        if (!settings.valid) {
            // Rejected payloads must come back as the clean zero snapshot.
            if (settings.frameIndex != 0 || settings.leftLogicalWidth != 0 || settings.leftLogicalHeight != 0
                || settings.rightLogicalWidth != 0 || settings.rightLogicalHeight != 0
                || settings.drawableWidth != 0 || settings.drawableHeight != 0
                || settings.rateMapCount != 0 || settings.providerEyeWidth != 0
                || settings.providerEyeHeight != 0 || settings.displayHz != 0.0f) {
                System.out.println("  VIOLATION " + kind + " case=" + index + " rejected payload not zeroed");
                return 1;
            }
            return 0;
        }
        if (!saneDimension(settings.leftLogicalWidth) || !saneDimension(settings.leftLogicalHeight)
            || !saneDimension(settings.rightLogicalWidth) || !saneDimension(settings.rightLogicalHeight)) {
            System.out.println("  VIOLATION " + kind + " case=" + index + " insane logical dims");
            return 1;
        }
        if (settings.rateMapCount < 0 || settings.drawableWidth < 0 || settings.drawableHeight < 0
            || settings.providerEyeWidth < 0 || settings.providerEyeHeight < 0) {
            System.out.println("  VIOLATION " + kind + " case=" + index + " negative field");
            return 1;
        }
        if (!(settings.renderQuality >= 0.0f && settings.renderQuality <= 1.0f)
            || !(settings.maxRenderQuality >= settings.renderQuality - 1.0e-3f
                 && settings.maxRenderQuality <= 1.0f)) {
            System.out.println("  VIOLATION " + kind + " case=" + index + " bad quality");
            return 1;
        }
        if (!(settings.displayHz >= 0.0f && settings.displayHz <= 240.0f)
            || !(settings.frameTimeMs >= 0.0f && settings.frameTimeMs <= 1000.0f)) {
            System.out.println("  VIOLATION " + kind + " case=" + index + " bad cadence/frame time");
            return 1;
        }
        return 0;
    }

    private static boolean saneDimension(int value) {
        return value >= 64 && value <= 16384;
    }
}
