package dev.vrmc.provider;

/**
 * Host test for {@link QuickMenuPlacement} (R3).
 *
 * <p>The rectangle sets below are the real 26.2 pause-screen layout measured from the game classes
 * with {@code VRSettings.modifyPauseMenu} on (the default): vanilla's 204px "Back to Game", the
 * Advancements/Statistics row, the report/feedback/chat icon row, the options row, Vivecraft's
 * overlay/profiler/screenshot/calibrate rows and the disconnect button, inside a 212x214 centred
 * grid aligned at 25% of the free vertical space (see the host layout probe in the review report).
 */
public final class QuickMenuPlacementTest {
    private static int checks;
    private static int failures;

    private static void check(String name, boolean ok) {
        checks++;
        if (!ok) failures++;
        System.out.println("  " + (ok ? "ok  " : "FAIL") + " " + name);
    }

    private static final int BUTTON_W = 204;
    private static final int BUTTON_H = 20;

    /** Pause-screen widgets at 341x256 (8-scale 2732-class framing), grid y=10 h=214. */
    private static int[] pauseRects() {
        return new int[] {
            // title StringWidget (font-width approximated; it must not be covered either)
            130, 40, 80, 9,
            // vanilla grid rows + Vivecraft rows (measured positions; x/y numbers from the probe)
            68, 60, 204, 20,   // Back to Game
            68, 84, 98, 20, 174, 84, 98, 20,   // Advancements / Statistics
            86, 108, 168, 20,  // report bugs / feedback / chat / social / friends / report
            68, 132, 98, 20, 174, 132, 98, 20, // Options / Multiplayer Options
            68, 156, 52, 20, 122, 156, 48, 20, // overlay / profiler (Vivecraft nested grid)
            174, 156, 98, 20,  // screenshot
            68, 180, 98, 20,   // calibrate height
            68, 204, 204, 20   // disconnect
        };
    }

    private static boolean inside(int[] pos, int screenW, int screenH) {
        return pos != null && pos.length == 2 && pos[0] >= 0 && pos[1] >= 0
            && pos[0] <= Math.max(0, screenW - BUTTON_W) && pos[1] <= Math.max(0, screenH - BUTTON_H);
    }

    private static boolean overlaps(int[] pos, int[] rects) {
        for (int i = 0; i + 3 < rects.length; i += 4) {
            int ox = rects[i], oy = rects[i + 1], ow = rects[i + 2], oh = rects[i + 3];
            if (pos[0] < ox + ow && ox < pos[0] + BUTTON_W
                && pos[1] < oy + oh && oy < pos[1] + BUTTON_H) return true;
        }
        return false;
    }

    public static void main(String[] args) {
        emptyScreenKeepsHistoricalSpot();
        typicalPauseScreenKeepsHistoricalSpot();
        crampedPauseScreenAvoidsBottomOverlap();
        blockedCentreMovesWithoutOverlap();
        blockedEverywhereFallsBackInsideScreen();
        tinyScreenClamps();
        deterministic();

        System.out.println("[m5-quick-menu-placement-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0
            ? "[m5-quick-menu-placement-test] PASS" : "[m5-quick-menu-placement-test] FAIL");
        if (failures != 0) System.exit(1);
    }

    private static void emptyScreenKeepsHistoricalSpot() {
        System.out.println("[m5-quick-menu-placement-test] no widgets -> the historical bottom-centre spot");
        int[] pos = QuickMenuPlacement.find(341, 256, BUTTON_W, BUTTON_H, new int[0]);
        check("bottom-centre at height-28", pos[0] == (341 - BUTTON_W) / 2
            && pos[1] == 256 - BUTTON_H - QuickMenuPlacement.MARGIN);
    }

    private static void typicalPauseScreenKeepsHistoricalSpot() {
        System.out.println("[m5-quick-menu-placement-test] typical pause screen keeps the bottom-centre spot");
        int[] rects = pauseRects();
        int[] pos = QuickMenuPlacement.find(341, 256, BUTTON_W, BUTTON_H, rects);
        check("placed at the historical position (68,228)", pos[0] == 68 && pos[1] == 228);
        check("does not overlap any pause-screen widget", !overlaps(pos, rects));
        check("stays inside the screen", inside(pos, 341, 256));
    }

    private static void crampedPauseScreenAvoidsBottomOverlap() {
        System.out.println("[m5-quick-menu-placement-test] cramped 320x240 GUI: the modified grid reaches y=220");
        // Same rows shifted to the 320x240 layout (grid y=6): bottom row at y=200..220.
        int[] rects = new int[] {
            115, 40, 80, 9,
            58, 56, 204, 20,
            58, 80, 98, 20, 160, 80, 98, 20,
            76, 104, 168, 20,
            58, 128, 98, 20, 160, 128, 98, 20,
            58, 152, 52, 20, 112, 152, 48, 20,
            160, 152, 98, 20,
            58, 176, 98, 20,
            58, 200, 204, 20
        };
        int[] pos = QuickMenuPlacement.find(320, 240, BUTTON_W, BUTTON_H, rects);
        // The old fixed spot (58,212) overlapped the disconnect row at y=200..220; the only free
        // strip is the last 20 px band, so the button must sit at y=220.
        check("moved into the free bottom strip instead of the old overlapping spot", pos[1] == 220);
        check("still horizontally centred and reachable", pos[0] == 58 && inside(pos, 320, 240));
        check("does not overlap any pause-screen widget", !overlaps(pos, rects));
    }

    private static void blockedCentreMovesWithoutOverlap() {
        System.out.println("[m5-quick-menu-placement-test] a blocked bottom band moves the button, never hides a widget");
        int[] rects = new int[] {
            0, 0, 341, 200,      // a tall widget (e.g. a long mod menu row)
            120, 220, 100, 20    // blocked centre in the bottom strip
        };
        int[] pos = QuickMenuPlacement.find(341, 256, BUTTON_W, BUTTON_H, rects);
        check("no overlap with the blocking widgets", !overlaps(pos, rects));
        check("inside the screen", inside(pos, 341, 256));
        check("raised above the blocker (kept away from the top)", pos[1] >= 200 - BUTTON_H && pos[1] <= 228);
    }

    private static void blockedEverywhereFallsBackInsideScreen() {
        System.out.println("[m5-quick-menu-placement-test] fully covered screen: fall back inside the bounds");
        int[] rects = new int[] {0, 0, 341, 256};
        int[] pos = QuickMenuPlacement.find(341, 256, BUTTON_W, BUTTON_H, rects);
        check("inside the screen bounds", inside(pos, 341, 256));
        check("falls back to the historical clamped spot", pos[0] == 68 && pos[1] == 228);
    }

    private static void tinyScreenClamps() {
        System.out.println("[m5-quick-menu-placement-test] a screen smaller than the button is clamped, not negative");
        int[] pos = QuickMenuPlacement.find(200, 100, BUTTON_W, BUTTON_H, new int[0]);
        check("x/y are not negative", pos[0] >= 0 && pos[1] >= 0);
        check("x is clamped to 0 when the button is wider than the screen", pos[0] == 0);
        int[] occupied = new int[] {0, 0, 200, 100};
        int[] fallback = QuickMenuPlacement.find(200, 100, BUTTON_W, BUTTON_H, occupied);
        check("covered tiny screen still returns a non-negative spot",
            fallback[0] >= 0 && fallback[1] >= 0);
    }

    private static void deterministic() {
        System.out.println("[m5-quick-menu-placement-test] repeated calls are deterministic");
        int[] rects = pauseRects();
        int[] a = QuickMenuPlacement.find(341, 256, BUTTON_W, BUTTON_H, rects.clone());
        int[] b = QuickMenuPlacement.find(341, 256, BUTTON_W, BUTTON_H, rects.clone());
        check("same input -> same placement", a[0] == b[0] && a[1] == b[1]);
        int[] nullRects = QuickMenuPlacement.find(341, 256, BUTTON_W, BUTTON_H, null);
        check("null rectangle list is handled", inside(nullRects, 341, 256));
    }
}
