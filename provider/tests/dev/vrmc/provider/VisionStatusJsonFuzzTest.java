package dev.vrmc.provider;

import java.time.Instant;
import java.util.Map;
import java.util.Random;

/** Host fuzz: status JSON must survive arbitrary user strings and non-finite numbers, and round-trip. */
public final class VisionStatusJsonFuzzTest {
    private static final int CASES = 100_000;

    public static void main(String[] args) {
        Random rnd = new Random(0x5A7A5EEDL);
        int violations = 0;
        for (int i = 0; i < CASES; i++) {
            String runtime = randomString(rnd);
            String tuning = randomString(rnd);
            String thermal = randomString(rnd);
            float hotbar = switch (i % 5) {
                case 0 -> Float.NaN;
                case 1 -> Float.POSITIVE_INFINITY;
                case 2 -> Float.NEGATIVE_INFINITY;
                default -> (rnd.nextFloat() - 0.5F) * 10.0F;
            };
            VisionStatusJson.Data d = new VisionStatusJson.Data(
                "t" + i, i, (i & 1) == 0, true, i * 31L, i, false, true,
                (i & 2) == 0, (i & 4) == 0, true, runtime, runtime, hotbar, tuning, thermal,
                thermal, true, false, rnd.nextFloat() * 20.0F, 1.0F, i,
                (i & 1) == 0, (i & 2) == 0, rnd.nextFloat(),
                (i & 4) == 0, (i & 8) == 0, (i & 16) == 0);
            String json;
            Map<String, Object> parsed;
            try {
                json = VisionStatusJson.build(d, Instant.EPOCH);
                parsed = TestJson.parseObject(json);
            } catch (Throwable t) {
                if (++violations <= 5) System.out.println("  VIOLATION parse/build case=" + i + ": " + t);
                continue;
            }
            if (!runtime.equals(parsed.get("runningOnVisionOS"))
                || !tuning.equals(parsed.get("inputTuning"))
                || !thermal.equals(parsed.get("thermalState"))) {
                if (++violations <= 5) System.out.println("  VIOLATION string round-trip case=" + i);
            }
            Object pb = parsed.get("hotbarRange");
            float expectedHotbar = Float.isFinite(hotbar) ? hotbar : 0.0F;
            if (!(pb instanceof Number) || Math.abs(((Number) pb).floatValue() - expectedHotbar) > 1e-5F) {
                if (++violations <= 5) System.out.println("  VIOLATION hotbarRange case=" + i);
            }
            if (violations > 10) break;
        }
        System.out.println("[m5-status-json-fuzz-test] cases=" + CASES + " violations=" + violations);
        System.out.println(violations == 0 ? "[m5-status-json-fuzz-test] PASS" : "[m5-status-json-fuzz-test] FAIL");
        if (violations != 0) System.exit(1);
    }

    private static String randomString(Random rnd) {
        int len = rnd.nextInt(40);
        StringBuilder b = new StringBuilder(len);
        for (int i = 0; i < len; i++) {
            int kind = rnd.nextInt(10);
            char c;
            if (kind < 3) c = (char) rnd.nextInt(0x20);          // control chars
            else if (kind < 5) {
                final char[] special = {'"', '\\', '/', '\b', '\f', '\n', '\r', '\t'};
                c = special[rnd.nextInt(special.length)];
            }
            else if (kind < 8) c = (char) (0x20 + rnd.nextInt(0x7f));
            else c = (char) (0x80 + rnd.nextInt(0x2f00));        // BMP non-surrogate range
            b.append(c);
        }
        return b.toString();
    }
}
