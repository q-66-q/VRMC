package dev.vrmc.provider;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Host test: vrmc-status.json must be strictly valid JSON and round-trip fields (EV-0144 regression). */
public final class VisionStatusJsonTest {
    private static int checks;
    private static int failures;
    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) {
        VisionStatusJson.Data data = new VisionStatusJson.Data(
            "2026-01-01T00:00:00Z", 3, true, true, 2L, 4466, false, true, true, true, true,
            "visionOS \"27\\2\"", "seated=false \"quoted\" \\ back", 0.18F,
            "pinch=0.030/0.045 swipe=true", "nominal", "notify", false, false, 11.5F, 18.25F, 4);
        String json = VisionStatusJson.build(data, Instant.EPOCH);
        Map<String, Object> parsed = null;
        try {
            parsed = new Json(json).parseObject();
        } catch (Throwable t) {
            System.out.println("  JSON parse failed: " + t);
        }
        check("valid JSON", parsed != null);
        if (parsed != null) {
            check("abi", parsed.get("abi") instanceof Number
                && ((Number) parsed.get("abi")).intValue() == 3);
            check("trackedFrames", parsed.get("trackedFrames") instanceof Number
                && ((Number) parsed.get("trackedFrames")).intValue() == 4466);
            check("seated false", Boolean.FALSE.equals(parsed.get("seated")));
            check("handLeft true", Boolean.TRUE.equals(parsed.get("handLeftTracked")));
            check("escaped runningOnVisionOS", ("visionOS \"27\\2\"").equals(parsed.get("runningOnVisionOS")),
                String.valueOf(parsed.get("runningOnVisionOS")));
            check("escaped runtimeSettings", ("seated=false \"quoted\" \\ back").equals(parsed.get("runtimeSettings")));
            check("hotbarRange number", parsed.get("hotbarRange") instanceof Double);
            check("thermalState", "nominal".equals(parsed.get("thermalState")));
            check("adaptiveApplied key", Boolean.FALSE.equals(parsed.get("adaptiveFramerateApplied")));
            check("frameP50Ms", parsed.get("frameP50Ms") instanceof Number
                && Math.abs(((Number) parsed.get("frameP50Ms")).doubleValue() - 11.5) < 1e-6);
            check("frameP95Ms", parsed.get("frameP95Ms") instanceof Number
                && Math.abs(((Number) parsed.get("frameP95Ms")).doubleValue() - 18.25) < 1e-6);
            check("missed90Frames", parsed.get("missed90Frames") instanceof Number
                && ((Number) parsed.get("missed90Frames")).intValue() == 4);
        }
        // Regression shape: the last field must not carry a trailing comma/quote (EV-0144 bug).
        String trimmed = json.trim();
        check("ends with closing brace", trimmed.endsWith("}"));
        check("no comma before closing brace", !trimmed.matches("(?s).*,\\s*}$"));
        System.out.println("[m5-status-json-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[m5-status-json-test] PASS" : "[m5-status-json-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    /** Tiny strict-enough JSON parser for this test (objects/strings/numbers/bools/null). */
    private static final class Json {
        private final String s; private int i;
        Json(String s) { this.s = s; }
        Map<String,Object> parseObject() {
            skip(); expect('{'); Map<String,Object> map = new LinkedHashMap<>(); skip();
            if (peek() == '}') { i++; finish(); return map; }
            while (true) {
                skip();
                String key = parseString();
                skip(); expect(':'); skip();
                Object v = parseValue();
                map.put(key, v);
                skip();
                char c = next();
                if (c == '}') break;
                if (c != ',') throw new IllegalArgumentException("expected , or } at " + i);
            }
            finish();
            return map;
        }
        private Object parseValue() {
            skip();
            char c = peek();
            if (c == '"') return parseString();
            if (c == 't') { literal("true"); return Boolean.TRUE; }
            if (c == 'f') { literal("false"); return Boolean.FALSE; }
            if (c == 'n') { literal("null"); return null; }
            int start = i;
            if (c == '-') i++;
            while (i < s.length() && Character.isDigit(s.charAt(i))) i++;
            if (i < s.length() && s.charAt(i) == '.') {
                i++;
                while (i < s.length() && Character.isDigit(s.charAt(i))) i++;
            }
            if (i == start) throw new IllegalArgumentException("bad value at " + i);
            return Double.parseDouble(s.substring(start, i));
        }
        private String parseString() {
            skip(); expect('"'); StringBuilder out = new StringBuilder();
            while (true) {
                char c = next();
                if (c == '"') return out.toString();
                if (c != '\\') { out.append(c); continue; }
                char e = next();
                switch (e) {
                    case '"' -> out.append('"'); case '\\' -> out.append('\\');
                    case '/' -> out.append('/'); case 'b' -> out.append('\b');
                    case 'f' -> out.append('\f'); case 'n' -> out.append('\n');
                    case 'r' -> out.append('\r'); case 't' -> out.append('\t');
                    case 'u' -> { out.append((char) Integer.parseInt(s.substring(i, i + 4), 16)); i += 4; }
                    default -> throw new IllegalArgumentException("bad escape at " + i);
                }
            }
        }
        private void literal(String word) {
            if (!s.startsWith(word, i)) throw new IllegalArgumentException("bad literal at " + i);
            i += word.length();
        }
        private void skip() { while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++; }
        private char peek() { if (i >= s.length()) throw new IllegalArgumentException("eof"); return s.charAt(i); }
        private char next() { if (i >= s.length()) throw new IllegalArgumentException("eof"); return s.charAt(i++); }
        private void expect(char c) { if (next() != c) throw new IllegalArgumentException("expected " + c + " at " + i); }
        private void finish() { skip(); if (i != s.length()) throw new IllegalArgumentException("trailing data at " + i); }
    }
}
