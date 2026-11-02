package dev.vrmc.provider;

import java.util.Locale;

/**
 * M4 startup/log formatting kept in one pure, host-tested place (format-string/argument type mismatches
 * in printf are runtime IllegalFormatConversionExceptions and previously crashed VisionVR.init).
 */
public final class VisionLogFormat {
    private VisionLogFormat() {}

    public static String locomotionLine(VisionInput in, float hotbarRange, float moveOriginZ,
                                        float moveForwardScale, float moveStrafeScale, float moveDeadzone,
                                        long rotatePulseNanos) {
        return String.format(Locale.ROOT,
            "[VRMC-M4] locomotion: middleEnabled=%s ringEnabled=%s hotbarRange=%.2f "
                + "swipeEnabled=%s virtual stick originZ=%.2f forwardScale=%.2f "
                + "strafeScale=%.2f deadzone=%.2f rotatePulseMs=%d middleOn=%.3f middleOff=%.3f "
                + "middleTapMs=%.0f middleDoubleMs=%.0f swipeSpeed=%.2f swipeCoolMs=%.0f",
            in.middleEnabled(), in.ringEnabled(), hotbarRange,
            in.swipeEnabled(), moveOriginZ, moveForwardScale, moveStrafeScale, moveDeadzone,
            rotatePulseNanos / 1_000_000L,
            in.middleOn(), in.middleOff(),
            (double) in.middleTapMillis(), (double) in.middleDoubleMillis(),
            in.swipeSpeed(), (double) in.swipeCooldownMillis());
    }
}
