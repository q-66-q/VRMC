package dev.vrmc.provider;

/** Host test for the M8 frame-trace CSV schema/formatting (no game/device). */
public final class VisionTraceTest {
    private static int checks = 0;
    private static int failures = 0;

    private static void check(String name, boolean ok, String detail) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name + " " + detail); }
    }
    private static void check(String name, boolean ok) { check(name, ok, ""); }

    public static void main(String[] args) {
        String header = VisionTrace.HEADER;
        String[] names = header.split(",", -1);
        check("header columns", names.length == 18, "got " + names.length);
        check("columnCount matches header", VisionTrace.columnCount() == names.length);
        check("header starts with frame", names[0].equals("frame"));
        check("header has display_hz", header.contains("display_hz"));
        check("header has target_hz", header.contains("target_hz"));
        check("header has eye_w,eye_h", header.contains("eye_w,eye_h"));
        check("header has content_first,reductions", header.contains("content_first,reductions"));
        check("no spaces in header", !header.contains(" "));

        String row = VisionTrace.row(1234L, 5678L, 120.04, 120, 1832, 1600, 0.504f, 2,
            4, 240, 8.31, 9.75, 1, 2, 1.0f, 1.0f, 0, 0);
        String[] fields = row.split(",", -1);
        check("row columns", fields.length == 18, "gets " + fields.length + ": " + row);
        check("row frame", fields[0].equals("1234"));
        check("row timestamp", fields[1].equals("5678"));
        check("row display_hz 2dp", fields[2].equals("120.04"));
        check("row target_hz", fields[3].equals("120"));
        check("row eye dims", fields[4].equals("1832") && fields[5].equals("1600"));
        check("row scale 2dp", fields[6].equals("0.50"));
        check("row resizes", fields[7].equals("2"));
        check("row missed/samples", fields[8].equals("4") && fields[9].equals("240"));
        check("row p50/p95", fields[10].equals("8.31") && fields[11].equals("9.75"));
        check("row foveation/rate maps", fields[12].equals("1") && fields[13].equals("2"));
        check("row quality", fields[14].equals("1.00") && fields[15].equals("1.00"));
        check("row content-first", fields[16].equals("0") && fields[17].equals("0"));

        // Non-finite inputs must not break the CSV (device logs are parsed by the checker).
        String nanRow = VisionTrace.row(1L, 1L, Double.NaN, 0, 1024, 1024, Float.NaN, 0,
            0, 240, Double.NaN, Double.NaN, 0, 0, Float.NaN, Float.NaN, 1, 0);
        String[] nanFields = nanRow.split(",", -1);
        check("NaN row columns", nanFields.length == 18);
        check("NaN display -> 0", nanFields[2].equals("0.00"));
        check("NaN scale -> 0", nanFields[6].equals("0.00"));
        check("NaN p50/p95 -> 0", nanFields[10].equals("0.00") && nanFields[11].equals("0.00"));
        check("max rows constant", VisionTrace.MAX_ROWS == 20000);
        check("file name", VisionTrace.FILE_NAME.equals("vrmc-m8-trace.csv"));

        System.out.println("[m8-trace-test] " + checks + " checks, " + failures + " failed");
        if (failures > 0) { System.out.println("[m8-trace-test] FAIL"); System.exit(1); }
        System.out.println("[m8-trace-test] PASS");
    }
}
