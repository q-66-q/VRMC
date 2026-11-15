package dev.vrmc.provider;

/**
 * Right-pinch carry guard for the M7 world <-> GUI transition.
 *
 * <p>A right index pinch that is already held when a screen opens or closes belongs to the context
 * that is being left: the click that pressed "Back to Game" must not place a block, and a pinch held
 * while the inventory opens must not click whatever is under the cursor. The pinch is ignored until
 * it is released ({@link #update} returns false while {@link #carrying()}).
 *
 * <p>The release edge can arrive on the <em>exact</em> transition frame: the pinch was down on the
 * last frame inside the GUI and is up on the first frame in world. The old inline guard only armed
 * when the pinch was still held on the transition frame, so that one-frame release pulse was treated
 * as a fresh world action (place/attack). This helper also remembers the previous frame's raw pinch
 * state: a transition frame with a pinch released this frame is reported through
 * {@link #carriedNow()} so the caller can forget the old press and swallow the release pulse.
 *
 * <p>Pure Java (no game classes) so the host tests can pin the state machine.
 */
final class PinchCarryGuard {
    private boolean prevGui;
    private boolean rawPrev;
    private boolean carry;
    private boolean carriedNow;

    /**
     * One frame. {@code guiNow} is true while a screen is open; {@code pinchRawNow} is the engine's
     * raw right index-pinch state. Returns the pinch state the world actions may use (false while a
     * carried pinch is still held).
     */
    boolean update(boolean guiNow, boolean pinchRawNow) {
        this.carriedNow = false;
        if (guiNow != this.prevGui) {
            this.prevGui = guiNow;
            // A pinch was active on one side of the transition if it is down now or was down on the
            // previous frame (the release pulse of that frame is still the old context's).
            if (pinchRawNow || this.rawPrev) {
                this.carry = true;
                this.carriedNow = true;
            }
        }
        if (!pinchRawNow) this.carry = false;
        this.rawPrev = pinchRawNow;
        return pinchRawNow && !this.carry;
    }

    /**
     * True on the frame a GUI transition carried a pinch. The caller must forget the previous press
     * state (press duration / held-break latch) so the carried release cannot become a world action.
     */
    boolean carriedNow() { return this.carriedNow; }

    /** True while a carried pinch is still held and must stay ignored by world actions. */
    boolean carrying() { return this.carry; }

    /** Clear all state (tracking loss, mode change, quick-menu "release stuck input"). */
    void reset() {
        this.prevGui = false;
        this.rawPrev = false;
        this.carry = false;
        this.carriedNow = false;
    }
}
