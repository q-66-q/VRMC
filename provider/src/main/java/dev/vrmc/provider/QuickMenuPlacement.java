package dev.vrmc.provider;

/**
 * Safe placement for the "VRMC Quick Menu" button on the vanilla pause screen.
 *
 * <p>Minecraft 26.2 lays out the pause menu with a {@code GridLayout} whose rows are the vanilla
 * buttons plus, when {@code VRSettings.modifyPauseMenu} is on (the default), Vivecraft's own rows
 * (overlay/profiler/screenshot/calibrate...). The grid is aligned at 25% of the free vertical space
 * and is ~214 px tall; on a 320x240-scaled GUI it reaches down to y=220, so a fixed bottom-centre
 * button at {@code height-28} overlaps the last vanilla/Vivecraft row (R3). A fixed offset cannot be
 * safe on every GUI scale, so this helper keeps the historical bottom-centre spot when it is free
 * and otherwise moves the button to the nearest free spot (still bottom-anchored if possible).
 *
 * <p>Pure Java: the caller passes the widget rectangles the screen already has; the host tests pin
 * the overlap avoidance and the clamping.
 */
final class QuickMenuPlacement {
    /** Distance kept between the button and the screen edge in the preferred spot (historical). */
    static final int MARGIN = 8;

    /**
     * @param screenW/screenH GUI-scaled screen size
     * @param buttonW/buttonH button size
     * @param occupied flat x,y,w,h rectangles of the widgets already on the screen (possibly empty)
     * @return {x, y} for the button, always inside the screen (never null)
     */
    static int[] find(int screenW, int screenH, int buttonW, int buttonH, int[] occupied) {
        int maxX = Math.max(0, screenW - buttonW);
        int maxY = Math.max(0, screenH - buttonH);
        int centreX = maxX / 2;
        int[] xs = {centreX, Math.min(MARGIN, maxX), Math.max(0, maxX - MARGIN)};

        // Preferred: the historical bottom-centre spot.
        int preferredY = Math.max(0, maxY - MARGIN);
        for (int x : xs) {
            if (fits(x, preferredY, buttonW, buttonH, occupied)) return new int[] {x, preferredY};
        }
        // Still bottom-anchored: the strip between the preferred spot and the screen edge. This is
        // the only free band at 320x240 with Vivecraft's modified pause menu (the grid ends at 220).
        for (int y = maxY; y > preferredY; y--) {
            for (int x : xs) {
                if (fits(x, y, buttonW, buttonH, occupied)) return new int[] {x, y};
            }
        }
        // The bottom is full: move up row by row instead of covering a vanilla/Vivecraft widget.
        for (int y = preferredY - 1; y >= 0; y--) {
            for (int x : xs) {
                if (fits(x, y, buttonW, buttonH, occupied)) return new int[] {x, y};
            }
        }
        // Nothing is free (overlapping vanilla widgets everywhere): keep the historical position
        // clamped into the screen, so the button is still reachable instead of vanishing.
        return new int[] {centreX, Math.max(0, maxY - MARGIN)};
    }

    /** True when the rect does not intersect any occupied rectangle (edge contact is allowed). */
    private static boolean fits(int x, int y, int w, int h, int[] rects) {
        if (rects == null) return true;
        for (int i = 0; i + 3 < rects.length; i += 4) {
            int ox = rects[i], oy = rects[i + 1], ow = rects[i + 2], oh = rects[i + 3];
            if (ow <= 0 || oh <= 0) continue;
            boolean overlap = x < ox + ow && ox < x + w && y < oy + oh && oy < y + h;
            if (overlap) return false;
        }
        return true;
    }

    private QuickMenuPlacement() {}
}
