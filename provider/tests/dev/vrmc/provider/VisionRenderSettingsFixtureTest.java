package dev.vrmc.provider;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Cross-language ABI contract test for the M8 render feedback channel.
 *
 * <p>{@code bridge/tests/make_render_settings_fixture.c} writes three raw 68-byte
 * {@code vrmc_render_settings} records with the C header's layout; this test parses exactly those
 * bytes with {@link VisionRenderSettings#parse(ByteBuffer)} and checks every field. A mismatch between
 * the C struct/offsets and the provider's constants shows up here instead of only on device (where a
 * silent parse failure would mean no display feedback and no 4K-class eye targets).
 *
 * <p>Run by provider/tests/run_tests.sh with the fixture path as the single argument.
 */
public final class VisionRenderSettingsFixtureTest {
    private static int checks = 0;
    private static int failures = 0;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            System.out.println("[m8-rs-fixture-test] FAIL: usage: <fixture.bin>");
            System.exit(1);
        }
        byte[] bytes = Files.readAllBytes(Path.of(args[0]));
        final int recordBytes = 68;
        check("fixture contains three 68-byte records",
            bytes.length == 3 * recordBytes, "bytes=" + bytes.length);
        if (bytes.length != 3 * recordBytes) {
            finish();
            return;
        }
        for (int index = 0; index < 3; index++) {
            ByteBuffer buffer = ByteBuffer.wrap(bytes, index * recordBytes, recordBytes)
                .slice().order(ByteOrder.LITTLE_ENDIAN);
            VisionRenderSettings settings = VisionRenderSettings.parse(buffer);
            if (index == 0) {
                check("case 0 valid", settings.valid);
                check("case 0 frame index", settings.frameIndex == 1234, "got " + settings.frameIndex);
                check("case 0 foveation", settings.foveationEnabled);
                check("case 0 rate maps", settings.rateMapCount == 2, "got " + settings.rateMapCount);
                check("case 0 left logical", settings.leftLogicalWidth == 3660 && settings.leftLogicalHeight == 3200);
                check("case 0 right logical", settings.rightLogicalWidth == 3660 && settings.rightLogicalHeight == 3200);
                check("case 0 drawable", settings.drawableWidth == 2412 && settings.drawableHeight == 2108);
                check("case 0 quality", Math.abs(settings.renderQuality - 1.0f) < 1e-6f);
                check("case 0 max quality", Math.abs(settings.maxRenderQuality - 1.0f) < 1e-6f);
                check("case 0 display hz", Math.abs(settings.displayHz - 120.0f) < 1e-4f,
                    "got " + settings.displayHz);
                check("case 0 frame time", Math.abs(settings.frameTimeMs - 8.345f) < 1e-4f,
                    "got " + settings.frameTimeMs);
                check("case 0 provider recommendation",
                    settings.providerEyeWidth == 3664 && settings.providerEyeHeight == 3200,
                    "got " + settings.providerEyeWidth + "x" + settings.providerEyeHeight);
                check("case 0 target size from logical",
                    VisionRenderSettings.eyeTarget(settings, 0.5f)[0] == 1832,
                    "expected 1832 wide at scale 0.5");
            } else if (index == 1) {
                check("case 1 valid", settings.valid);
                check("case 1 not foveated", !settings.foveationEnabled);
                check("case 1 no rate maps", settings.rateMapCount == 0);
                check("case 1 logical", settings.leftLogicalWidth == 1888 && settings.leftLogicalHeight == 1792);
                check("case 1 drawable", settings.drawableWidth == 1888 && settings.drawableHeight == 1792);
                check("case 1 quality", Math.abs(settings.renderQuality - 0.75f) < 1e-6f);
                check("case 1 display hz", Math.abs(settings.displayHz - 90.0f) < 1e-4f);
                check("case 1 no recommendation",
                    settings.providerEyeWidth == 0 && settings.providerEyeHeight == 0);
            } else {
                check("case 2 invalid record rejected", !settings.valid);
            }
        }
        finish();
    }

    private static void finish() {
        System.out.println("[m8-rs-fixture-test] " + checks + " checks, " + failures + " failed");
        if (failures > 0) {
            System.out.println("[m8-rs-fixture-test] FAIL");
            System.exit(1);
        }
        System.out.println("[m8-rs-fixture-test] PASS");
    }
}
