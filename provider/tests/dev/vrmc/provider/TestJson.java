package dev.vrmc.provider;

import java.util.LinkedHashMap;
import java.util.Map;

/** Tiny strict-enough JSON parser used by host tests (objects/strings/numbers/bools/null only). */
final class TestJson {
    private TestJson() {}

    static Map<String, Object> parseObject(String s) {
        return new Parser(s).parseObject();
    }

    private static final class Parser {
        private final String s;
        private int i;
        Parser(String s) { this.s = s; }

        Map<String, Object> parseObject() {
            skip(); expect('{');
            Map<String, Object> map = new LinkedHashMap<>();
            skip();
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
            if (i >= s.length() || !Character.isDigit(s.charAt(i))) {
                throw new IllegalArgumentException("bad number at " + i);
            }
            while (i < s.length() && Character.isDigit(s.charAt(i))) i++;
            if (i < s.length() && s.charAt(i) == '.') {
                i++;
                while (i < s.length() && Character.isDigit(s.charAt(i))) i++;
            }
            if (i < s.length() && (s.charAt(i) == 'e' || s.charAt(i) == 'E')) {
                i++;
                if (i < s.length() && (s.charAt(i) == '+' || s.charAt(i) == '-')) i++;
                while (i < s.length() && Character.isDigit(s.charAt(i))) i++;
            }
            return Double.parseDouble(s.substring(start, i));
        }

        private String parseString() {
            skip(); expect('"');
            StringBuilder out = new StringBuilder();
            while (true) {
                char c = next();
                if (c == '"') return out.toString();
                if (c != '\\') { out.append(c); continue; }
                char e = next();
                switch (e) {
                    case '"' -> out.append('"');
                    case '\\' -> out.append('\\');
                    case '/' -> out.append('/');
                    case 'b' -> out.append('\b');
                    case 'f' -> out.append('\f');
                    case 'n' -> out.append('\n');
                    case 'r' -> out.append('\r');
                    case 't' -> out.append('\t');
                    case 'u' -> {
                        if (i + 4 > s.length()) throw new IllegalArgumentException("short unicode escape");
                        int code = Integer.parseInt(s.substring(i, i + 4), 16);
                        i += 4;
                        out.append((char) code);
                    }
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
