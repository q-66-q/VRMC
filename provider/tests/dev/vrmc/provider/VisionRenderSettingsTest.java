package dev.vrmc.provider;

import dev.vrmc.provider.bridge.VrmcBridge;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Host test for M8 render feedback parsing + the stereo eye-target size policy.
 *
 * <p>Pure Java: runs without a device, a bridge dylib or Minecraft classes. It validates the
 * documented 68-byte little-endian wire layout (the C side asserts the same size/offsets in
 * bridge/tests/bridge_shared_test.c), malformed-payload fail-safe behaviour, and the deterministic
 * eye-target scale policy consumed by VisionRenderer.
 */
public final class VisionRenderSettingsTest {
    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) {
            failures++;
            System.out.println("  FAIL " + name + " " + detail);
        }
    }

    private static void check(String name, boolean ok) {
        check(name, ok, "");
    }

    /** Build a valid 68-byte payload with little-endian fields (mirrors vrmc_render_settings). */
    private static ByteBuffer payload(int leftW, int leftH, int rightW, int rightH,
                                      float quality, float maxQuality, float displayHz,
                                      float frameTimeMs, int foveation, int rateMaps) {
        ByteBuffer buffer = ByteBuffer.allocateDirect(VisionRenderSettings.BYTES)
            .order(ByteOrder.LITTLE_ENDIAN);
        for (int i = 0; i < VisionRenderSettings.BYTES; i += 4) buffer.putInt(i, 0);
        buffer.putInt(VisionRenderSettings.OFF_VERSION, VisionRenderSettings.VERSION);
        buffer.putInt(VisionRenderSettings.OFF_VALID, 1);
        buffer.putInt(VisionRenderSettings.OFF_FRAME_INDEX, 1234);
        buffer.putInt(VisionRenderSettings.OFF_FOVEATION, foveation);
        buffer.putInt(VisionRenderSettings.OFF_RATE_MAP_COUNT, rateMaps);
        buffer.putInt(VisionRenderSettings.OFF_LEFT_LOGICAL_W, leftW);
        buffer.putInt(VisionRenderSettings.OFF_LEFT_LOGICAL_H, leftH);
        buffer.putInt(VisionRenderSettings.OFF_RIGHT_LOGICAL_W, rightW);
        buffer.putInt(VisionRenderSettings.OFF_RIGHT_LOGICAL_H, rightH);
        buffer.putInt(VisionRenderSettings.OFF_DRAWABLE_W, 2412);
        buffer.putInt(VisionRenderSettings.OFF_DRAWABLE_H, 2108);
        buffer.putFloat(VisionRenderSettings.OFF_RENDER_QUALITY, quality);
        buffer.putFloat(VisionRenderSettings.OFF_MAX_RENDER_QUALITY, maxQuality);
        buffer.putFloat(VisionRenderSettings.OFF_DISPLAY_HZ, displayHz);
        buffer.putFloat(VisionRenderSettings.OFF_FRAME_TIME_MS, frameTimeMs);
        buffer.putInt(VisionRenderSettings.OFF_PROVIDER_EYE_W, 0);
        buffer.putInt(VisionRenderSettings.OFF_PROVIDER_EYE_H, 0);
        return buffer;
    }

    public static void main(String[] args) {
        // ---- wire layout (C contract mirror) ------------------------------------------------------
        check("payload size 68", VisionRenderSettings.BYTES == 68, String.valueOf(VisionRenderSettings.BYTES));
        check("last field ends at 68",
            VisionRenderSettings.OFF_PROVIDER_EYE_H + 4 == VisionRenderSettings.BYTES);
        check("offsets are 4-byte aligned fields", (VisionRenderSettings.OFF_VERSION & 3) == 0
            && (VisionRenderSettings.OFF_DRAWABLE_W & 3) == 0
            && (VisionRenderSettings.OFF_PROVIDER_EYE_H & 3) == 0);
        check("quality offsets", VisionRenderSettings.OFF_RENDER_QUALITY == 44
            && VisionRenderSettings.OFF_MAX_RENDER_QUALITY == 48
            && VisionRenderSettings.OFF_DISPLAY_HZ == 52
            && VisionRenderSettings.OFF_FRAME_TIME_MS == 56);
        check("logical size offsets", VisionRenderSettings.OFF_LEFT_LOGICAL_W == 20
            && VisionRenderSettings.OFF_LEFT_LOGICAL_H == 24
            && VisionRenderSettings.OFF_RIGHT_LOGICAL_W == 28
            && VisionRenderSettings.OFF_RIGHT_LOGICAL_H == 32);

        // ---- valid payload round-trip --------------------------------------------------------------
        VisionRenderSettings valid = VisionRenderSettings.parse(
            payload(3660, 3200, 3660, 3200, 0.75f, 1.0f, 120.0f, 8.33f, 1, 2));
        check("valid payload accepted", valid.valid);
        check("logical sizes parsed", valid.leftLogicalWidth == 3660 && valid.leftLogicalHeight == 3200
            && valid.rightLogicalWidth == 3660 && valid.rightLogicalHeight == 3200);
        check("quality parsed", Math.abs(valid.renderQuality - 0.75f) < 1e-6
            && Math.abs(valid.maxRenderQuality - 1.0f) < 1e-6);
        check("cadence parsed", Math.abs(valid.displayHz - 120.0f) < 1e-6
            && Math.abs(valid.frameTimeMs - 8.33f) < 1e-3);
        check("foveation parsed", valid.foveationEnabled && valid.rateMapCount == 2);
        check("describe is non-null", valid.describe() != null && valid.describe().contains("logical L=3660"));
        check("parse restores buffer order", valid.valid);

        // ---- fail-safe on malformed payloads -------------------------------------------------------
        ByteBuffer badVersion = payload(3660, 3200, 3660, 3200, 0.5f, 1.0f, 90.0f, 11.1f, 0, 0);
        badVersion.putInt(VisionRenderSettings.OFF_VERSION, 99);
        check("wrong version rejected", !VisionRenderSettings.parse(badVersion).valid);

        ByteBuffer notValid = payload(3660, 3200, 3660, 3200, 0.5f, 1.0f, 90.0f, 11.1f, 0, 0);
        notValid.putInt(VisionRenderSettings.OFF_VALID, 0);
        check("valid=0 rejected", !VisionRenderSettings.parse(notValid).valid);

        ByteBuffer nanQuality = payload(3660, 3200, 3660, 3200, Float.NaN, 1.0f, 90.0f, 11.1f, 0, 0);
        check("NaN quality rejected", !VisionRenderSettings.parse(nanQuality).valid);

        ByteBuffer zeroSize = payload(0, 3200, 3660, 3200, 0.5f, 1.0f, 90.0f, 11.1f, 0, 0);
        check("zero logical size rejected", !VisionRenderSettings.parse(zeroSize).valid);

        ByteBuffer qualityAboveMax = payload(3660, 3200, 3660, 3200, 1.0f, 0.5f, 90.0f, 11.1f, 0, 0);
        check("quality > max rejected", !VisionRenderSettings.parse(qualityAboveMax).valid);

        check("null buffer -> none", !VisionRenderSettings.parse(null).valid);
        check("short buffer -> none",
            !VisionRenderSettings.parse(ByteBuffer.allocate(VisionRenderSettings.BYTES - 4)).valid);
        check("zeroed buffer -> none",
            !VisionRenderSettings.parse(ByteBuffer.allocateDirect(VisionRenderSettings.BYTES)).valid);
        check("none() invalid + describe", !VisionRenderSettings.none().valid
            && VisionRenderSettings.none().describe().contains("none"));

        // ---- eye-target policy ---------------------------------------------------------------------
        int[] half = VisionRenderSettings.eyeTarget(valid, 0.5f);
        check("eye target at 0.5 scale", half != null && half[0] == 1832 && half[1] == 1600,
            half == null ? "null" : half[0] + "x" + half[1]);
        int[] full = VisionRenderSettings.eyeTarget(valid, 1.0f);
        check("eye target at 1.0 scale rounds to 8", full != null && full[0] == 3664 && full[1] == 3200,
            full == null ? "null" : full[0] + "x" + full[1]);
        int[] quarter = VisionRenderSettings.eyeTarget(valid, 0.25f);
        check("eye target at 0.25 scale clamped >= 512", quarter != null && quarter[0] >= 512
            && quarter[1] >= 512, quarter == null ? "null" : quarter[0] + "x" + quarter[1]);
        int[] clampedLow = VisionRenderSettings.eyeTarget(valid, -3.0f);
        check("negative scale clamps to MIN_SCALE", clampedLow != null
            && clampedLow[0] == quarter[0] && clampedLow[1] == quarter[1]);
        int[] clampedHigh = VisionRenderSettings.eyeTarget(valid, 9.0f);
        check("scale > 1 clamps to 1.0", clampedHigh != null && clampedHigh[0] == full[0]);
        check("invalid settings have no eye target", VisionRenderSettings.eyeTarget(
            VisionRenderSettings.none(), 1.0f) == null);

        // ---- display cadence + auto-scale policy ---------------------------------------------------
        check("120 Hz target interval", Math.abs(VisionRenderSettings.targetIntervalMs(120.0f) - 8.3333) < 1e-3);
        check("90 Hz target interval", Math.abs(VisionRenderSettings.targetIntervalMs(90.0f) - 11.1111) < 1e-3);
        check("unknown cadence falls back to 90 Hz",
            Math.abs(VisionRenderSettings.targetIntervalMs(0.0f) - VisionFrameStats.NINETY_HZ_MS) < 1e-6);

        float base = 0.5f;
        check("auto scale drops on misses", Math.abs(
            VisionRenderSettings.nextAutoScale(base, 40, 240, 20.0, 11.111) - 0.40f) < 1e-5);
        check("auto scale drops on slow p50", Math.abs(
            VisionRenderSettings.nextAutoScale(base, 0, 240, 20.0, 11.111) - 0.40f) < 1e-5);
        check("auto scale takes a big step with strong headroom", Math.abs(
            VisionRenderSettings.nextAutoScale(base, 0, 240, 8.0, 11.111) - 0.60f) < 1e-5);
        check("auto scale takes a small step near the budget edge", Math.abs(
            VisionRenderSettings.nextAutoScale(base, 0, 240, 9.2, 11.111) - 0.55f) < 1e-5);
        check("auto scale holds in the dead band", Math.abs(
            VisionRenderSettings.nextAutoScale(base, 2, 240, 11.5, 11.111) - base) < 1e-5);
        check("auto scale bounded low", VisionRenderSettings.nextAutoScale(
            VisionRenderSettings.MIN_SCALE, 240, 240, 100.0, 11.111) == VisionRenderSettings.MIN_SCALE);
        check("auto scale bounded high", VisionRenderSettings.nextAutoScale(
            VisionRenderSettings.MAX_SCALE, 0, 240, 1.0, 11.111) == VisionRenderSettings.MAX_SCALE);
        check("auto scale ignores empty window", Math.abs(
            VisionRenderSettings.nextAutoScale(base, 0, 0, 0.0, 11.111) - base) < 1e-5);

        // ---- 1.3.7: display-paced frames + loading-time decisions ---------------------------------
        // Device trace 1.3.6: interval p50 11.10-11.14 ms at 90 Hz all session -> never raised.
        double h = VisionRenderSettings.headroomMs(0, 11.12, 5.8, 11.111);
        check("paced frames with light render work show headroom", !Double.isNaN(h) && h == 5.8);
        check("paced headroom raises the scale", VisionRenderSettings.nextAutoScale(0.35f, 0, 240, h,
            11.111) > 0.35f);
        check("paced frames with heavy render work show no headroom",
            Double.isNaN(VisionRenderSettings.headroomMs(0, 11.12, 9.0, 11.111)));
        check("missed frames never count as headroom",
            Double.isNaN(VisionRenderSettings.headroomMs(5, 11.12, 4.0, 11.111)));
        check("unpaced fast frames keep the interval as headroom",
            VisionRenderSettings.headroomMs(0, 8.0, Double.NaN, 11.111) == 8.0);
        check("slow interval is not headroom even with a light busy time",
            Double.isNaN(VisionRenderSettings.headroomMs(0, 13.0, 4.0, 11.111)));
        check("no busy samples is no headroom on paced frames",
            Double.isNaN(VisionRenderSettings.headroomMs(0, 11.12, Double.NaN, 11.111)));
        check("no adaptation before a world is loaded (title screen / loading)",
            !VisionRenderSettings.adaptAllowed(false, -1L));
        check("no adaptation in the first seconds of a world",
            !VisionRenderSettings.adaptAllowed(true, VisionRenderSettings.MIN_LEVEL_STABLE_FRAMES - 1));
        check("adaptation once the world is stable",
            VisionRenderSettings.adaptAllowed(true, VisionRenderSettings.MIN_LEVEL_STABLE_FRAMES));

        // ---- resize safety policy (world load / menu room / warm-up) -------------------------------
        check("no resize during session warm-up",
            !VisionRenderSettings.canResizeNow(true, 500L, true, VisionRenderSettings.MIN_RESIZE_FRAME - 1));
        check("no resize in a loading screen (no level, not menu room)",
            !VisionRenderSettings.canResizeNow(false, -1L, false, 600L));
        check("no resize in the menu room (title screen / menu world build)",
            !VisionRenderSettings.canResizeNow(false, 0L, true, 10_000L));
        check("45 Hz measured cadence still budgets for 90 Hz (no 45 Hz lock)",
            Math.abs(VisionRenderSettings.targetIntervalMs(45.0f) - 11.1111) < 1e-3);
        check("60 Hz measured cadence budgets for 90 Hz",
            Math.abs(VisionRenderSettings.targetIntervalMs(60.0f) - 11.1111) < 1e-3);
        check("explicit 60 Hz override is still honoured",
            Math.abs(VisionRenderSettings.targetIntervalMsFor(90.0f, 60) - 16.6667) < 1e-3);
        check("auto scale never steps below the auto floor",
            Math.abs(VisionRenderSettings.nextAutoScale(0.40f, 240, 240, 40.0, 11.111)
                - VisionRenderSettings.AUTO_MIN_SCALE) < 1e-5
            && Math.abs(VisionRenderSettings.nextAutoScale(VisionRenderSettings.AUTO_MIN_SCALE, 240, 240,
                40.0, 11.111) - VisionRenderSettings.AUTO_MIN_SCALE) < 1e-5);
        check("explicit low scale is not pushed further down",
            Math.abs(VisionRenderSettings.nextAutoScale(0.25f, 240, 240, 40.0, 11.111) - 0.25f) < 1e-5);
        check("world-load spikes do not resize for ~7 s",
            !VisionRenderSettings.canResizeNow(true, 300L, false, 5000L));
        check("no resize in the first frames of a loaded world",
            !VisionRenderSettings.canResizeNow(true, 30L, false, 600L));
        check("resize allowed once the loaded world is stable",
            VisionRenderSettings.canResizeNow(true, VisionRenderSettings.MIN_LEVEL_STABLE_FRAMES, false, 600L));

        // ---- resize hysteresis ---------------------------------------------------------------------
        check("same size is not significant", !VisionRenderSettings.isChangeSignificant(1832, 1600, 1832, 1600));
        check("small drift is not significant", !VisionRenderSettings.isChangeSignificant(1832, 1600, 1850, 1610));
        check("large change is significant", VisionRenderSettings.isChangeSignificant(1832, 1600, 2000, 1700));
        check("first target always significant", VisionRenderSettings.isChangeSignificant(0, 0, 1832, 1600));

        // ---- 120 Hz end-to-end decision example ----------------------------------------------------
        VisionRenderSettings hz120 = VisionRenderSettings.parse(
            payload(3660, 3200, 3660, 3200, 1.0f, 1.0f, 120.0f, 8.33f, 1, 2));
        double target120 = VisionRenderSettings.targetIntervalMs(hz120.displayHz);
        float scale120 = VisionRenderSettings.nextAutoScale(0.6f, 0, 240, 7.0, target120);
        check("120 Hz headroom raises scale", scale120 > 0.6f, String.valueOf(scale120));
        float stay120 = VisionRenderSettings.nextAutoScale(0.6f, 0, 240, 8.4, target120);
        check("120 Hz on-cadence holds scale", Math.abs(stay120 - 0.6f) < 1e-5, String.valueOf(stay120));

        System.out.println("[m8-render-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m8-render-test] PASS" : "[m8-render-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
