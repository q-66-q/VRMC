package dev.vrmc.provider;

/**
 * M7 simplified whole-hand gesture engine (data-driven thresholds from the Gesture Lab).
 *
 * <p>Pure Java: it consumes the 27 ARKit joints already parsed by {@link VisionInput} plus the HMD
 * pose, and produces action intents. It never touches Minecraft/Vivecraft types, so the state machine
 * is host-testable and fuzzable.
 *
 * <p>Operator mapping (docs/mvp/M7_GESTURES.md):
 * <ul>
 *   <li>short right pinch (&lt;350 ms) = place/select; held right pinch (&ge;350 ms) = break/mine;</li>
 *   <li>left fist tap = Escape; both-fist short tap = inventory; both fists + alternating swing = walk;</li>
 *   <li>right-hand swing = entity attack; right index-finger tap = hotbar next (double = previous);</li>
 *   <li>both fists, hands separated front/back = bow draw; release the back fist to fire;</li>
 *   <li>right hand near the head = eat/drink; left pinch hold = teleport aim, release commits;</li>
 *   <li>head rise = jump (auto-jump remains enabled); head drop = sneak.</li>
 * </ul>
 *
 * <p>Priority: GUI &gt; bow &gt; climb/grab &gt; eat &gt; held break/attack &gt; walk &gt; place/select.
 * Every intent has a release path on tracking loss, stale input, GUI transition, seated mode, or a
 * mode/environment change.
 */
public final class VisionM7Gesture {
    // Joint indices in the ABI (ARKit order, see VrmcBridge.JOINT_*).
    private static final int WRIST = 0;
    private static final int THUMB_TIP = 4;
    private static final int INDEX_KNUCKLE = 6;
    private static final int INDEX_TIP = 9;
    private static final int MIDDLE_KNUCKLE = 11;
    private static final int MIDDLE_TIP = 14;
    private static final int RING_KNUCKLE = 16;
    private static final int RING_TIP = 19;
    private static final int LITTLE_KNUCKLE = 21;
    private static final int LITTLE_TIP = 24;
    private static final int JOINTS = 27;
    private static final int FLOATS = JOINTS * 3;

    // Pinch (from VisionInput, same ABI distances).
    public static final float PINCH_ON = 0.030F;
    public static final float PINCH_OFF = 0.045F;
    // Curl ratio (same definition as Gesture Lab / data summaries).
    public static final float FIST_ON = 0.55F;
    public static final float FIST_OFF = 0.75F;

    public static final long PLACE_MAX_NS = 350_000_000L;
    public static final long INVENTORY_TAP_MAX_NS = 350_000_000L;
    public static final float WALK_START_SWING = 0.04F;
    public static final float BOW_SEPARATION = 0.55F;
    public static final float EAT_DISTANCE = 0.28F;
    public static final float HEAD_JUMP_RISE = 0.08F;
    public static final float HEAD_SNEAK_DROP = 0.10F;
    public static final long HEAD_JUMP_COOLDOWN_NS = 700_000_000L;
    public static final long HEAD_SNEAK_LATCH_NS = 350_000_000L;
    public static final long HOTBAR_DOUBLE_NS = 450_000_000L;
    public static final float ATTACK_SPEED = 1.4F;
    public static final long ATTACK_COOLDOWN_NS = 300_000_000L;

    private final float[] jointsL = new float[FLOATS];
    private final float[] jointsR = new float[FLOATS];
    private final float[] curlBuffer = new float[4];

    private boolean trackedL, trackedR;
    private final float[] wL = new float[3];
    private final float[] wR = new float[3];
    private final float[] tipL = new float[3];
    private final float[] tipR = new float[3];
    private float pinchL, pinchR;
    private float curlL = Float.NaN, curlR = Float.NaN;
    private boolean fistL, fistR;
    private long prevNs;
    private boolean prevPinchL, prevPinchR, prevFistL, prevFistR;
    private final float[] prevWL = new float[3];
    private final float[] prevWR = new float[3];
    private final float[] prevTipL = new float[3];
    private final float[] prevTipR = new float[3];
    private float speedL, speedR, tipSpeedL, tipSpeedR;

    private long leftFistPressNs, rightFistPressNs;
    private long bothFistStartNs;
    private boolean bothFistPrev;
    private long leftPinchPressNs, rightPinchPressNs;

    private float headY, headBaseline;
    private float prevHeadY;
    private long headJumpUntilNs;
    private long headSneakSinceNs;
    private boolean sneaking;
    private long attackUntilNs;
    private long hotbarLastNs;
    private long placePulseUntilNs;
    private long inventoryPulseUntilNs;
    private long menuPulseUntilNs;
    private long hotbarNextPulseUntilNs;
    private long hotbarPrevPulseUntilNs;
    private long attackPulseUntilNs;
    private long jumpPulseUntilNs;
    private long guiClickPulseUntilNs;
    private long bowFireUntilNs;
    private long climbJumpPulseUntilNs;
    private long lastPlaceNs;
    private long rightPinchLastDurationNs;

    private boolean walkActive;
    private float walkForward;
    private int swingSign;
    private int swingCrossings;
    private long swingLastCrossNs;

    private final StringBuilder summaryBuilder = new StringBuilder(160);
    private String summary = "M7 idle";

    public void update(boolean trackedL, float[] jointsL, boolean trackedR, float[] jointsR,
                       float pinchL, float pinchR, float headX, float headY, float headZ,
                       long nowNs, boolean guiOpen, boolean seated) {
        if (jointsL == null || jointsR == null || jointsL.length < FLOATS || jointsR.length < FLOATS) {
            releaseAll();
            return;
        }
        this.trackedL = trackedL;
        this.trackedR = trackedR;
        if (trackedL) System.arraycopy(jointsL, 0, this.jointsL, 0, FLOATS);
        if (trackedR) System.arraycopy(jointsR, 0, this.jointsR, 0, FLOATS);
        this.pinchL = pinchL;
        this.pinchR = pinchR;
        this.headY = headY;

        double dt = this.prevNs == 0L ? 1.0 / 60.0 : Math.max(1.0e-3, (nowNs - this.prevNs) * 1.0e-9);
        if (trackedL) {
            copyPos(this.jointsL, WRIST, this.wL);
            copyPos(this.jointsL, INDEX_TIP, this.tipL);
            this.curlL = curl(this.jointsL);
            this.fistL = this.curlL < FIST_ON;
            this.speedL = this.prevNs == 0L ? 0.0F : (float) (dist(this.wL, this.prevWL) / dt);
            this.tipSpeedL = this.prevNs == 0L ? 0.0F : (float) (dist(this.tipL, this.prevTipL) / dt);
        } else {
            this.fistL = false;
            this.curlL = Float.NaN;
            this.speedL = 0.0F;
            this.tipSpeedL = 0.0F;
        }
        if (trackedR) {
            copyPos(this.jointsR, WRIST, this.wR);
            copyPos(this.jointsR, INDEX_TIP, this.tipR);
            this.curlR = curl(this.jointsR);
            this.fistR = this.curlR < FIST_ON;
            this.speedR = this.prevNs == 0L ? 0.0F : (float) (dist(this.wR, this.prevWR) / dt);
            this.tipSpeedR = this.prevNs == 0L ? 0.0F : (float) (dist(this.tipR, this.prevTipR) / dt);
        } else {
            this.fistR = false;
            this.curlR = Float.NaN;
            this.speedR = 0.0F;
            this.tipSpeedR = 0.0F;
        }

        boolean pinchNowL = trackedL && pinchL >= 0.0F && pinchL < PINCH_ON;
        boolean pinchNowR = trackedR && pinchR >= 0.0F && pinchR < PINCH_ON;
        if (pinchNowL && !this.prevPinchL) this.leftPinchPressNs = nowNs;
        if (pinchNowR && !this.prevPinchR) this.rightPinchPressNs = nowNs;
        if (pinchNowR) this.rightPinchLastDurationNs = nowNs - this.rightPinchPressNs;
        if (this.fistL && !this.prevFistL) this.leftFistPressNs = nowNs;
        if (this.fistR && !this.prevFistR) this.rightFistPressNs = nowNs;

        // ---- head jump / sneak (seated disables both; GUI does not need them) ----
        if (this.prevNs == 0L) this.headBaseline = headY;
        this.headBaseline = this.headBaseline * 0.985F + headY * 0.015F;
        float headVel = this.prevNs == 0L ? 0.0F : (headY - this.prevHeadY) / (float) dt;
        if (!seated && !guiOpen && nowNs >= this.headJumpUntilNs
            && headY - this.headBaseline > HEAD_JUMP_RISE && headVel > 0.25F) {
            this.jumpPulseUntilNs = nowNs + 80_000_000L;
            this.headJumpUntilNs = nowNs + HEAD_JUMP_COOLDOWN_NS;
        }
        if (!seated && !guiOpen && this.headBaseline - headY > HEAD_SNEAK_DROP) {
            if (this.headSneakSinceNs == 0L) this.headSneakSinceNs = nowNs;
            if (nowNs - this.headSneakSinceNs >= HEAD_SNEAK_LATCH_NS) this.sneaking = true;
        } else {
            this.headSneakSinceNs = 0L;
            this.sneaking = false;
        }

        // ---- both-fist family ----
        boolean both = this.fistL && this.fistR;
        float handSep = (trackedL && trackedR) ? dist(this.wL, this.wR) : 0.0F;
        if (both && !this.bothFistPrev) this.bothFistStartNs = nowNs;
        boolean gui = guiOpen;
        boolean bow = !gui && both && handSep > BOW_SEPARATION;
        boolean climbCandidate = !gui && !bow && ((this.fistL && this.wL[1] - headY > -0.05F)
            || (this.fistR && this.wR[1] - headY > -0.05F));

        // Walk: both fists, hands not separated as a bow, alternating wrist swing. The forward axis is
        // approximated by world Z (the operator faces forward); a sign change of left-right Z is the
        // swing cycle. Start after two crossings, stop after 0.6 s without a crossing.
        if (both && !bow && !gui && !seated && trackedL && trackedR) {
            float diff = this.wL[2] - this.wR[2];
            if (Math.abs(diff) > WALK_START_SWING) {
                int sign = diff > 0 ? 1 : -1;
                if (this.swingSign != 0 && sign != this.swingSign) {
                    this.swingCrossings++;
                    this.swingLastCrossNs = nowNs;
                }
                this.swingSign = sign;
            }
        }
        if (both && !bow && !gui && !seated && this.swingCrossings >= 2
            && (nowNs - this.swingLastCrossNs) < 600_000_000L) {
            this.walkActive = true;
            this.walkForward = 1.0F;
        } else if (nowNs - this.swingLastCrossNs > 600_000_000L || !both || bow || gui || seated) {
            this.walkActive = false;
            this.walkForward = 0.0F;
            if (!both) {
                this.swingSign = 0;
                this.swingCrossings = 0;
            }
        }
        // Inventory: both fists together for a short tap, released before walking/sustained hold.
        if (both && !this.bothFistPrev) {
            // started above
        }
        // Use the *previous* mode state for both the bow-fire edge and inventory suppression: by the
        // time the inventory release is evaluated, bow/climb may already have ended this frame.
        boolean wasBow = this.bowActivePrev;
        boolean wasClimb = this.climbActivePrev;
        if (wasBow && !bow && !gui && nowNs - this.bowFireUntilNs > 250_000_000L) {
            this.bowFireUntilNs = nowNs + 80_000_000L;
        }
        // Inventory pulse on the release edge of a short both-fist tap that never became walk/bow/climb.
        if (this.bothFistPrev && !both && !wasBow && !wasClimb
            && !this.walkActive && !gui
            && this.bothFistStartNs > 0L && nowNs - this.bothFistStartNs <= INVENTORY_TAP_MAX_NS) {
            this.inventoryPulseUntilNs = nowNs + 80_000_000L;
        }
        this.bowActivePrev = bow;
        this.climbActivePrev = climbCandidate;

        // Right pinch duration split: short = place pulse, held = break. On release, use the duration
        // recorded while the pinch was still closed (the current pinch metric is already open).
        boolean rightPinch = pinchNowR;
        long rightPinchDuration = rightPinch ? this.rightPinchLastDurationNs : 0L;
        this.breakHeld = !gui && rightPinch && rightPinchDuration >= PLACE_MAX_NS;
        if (!gui && this.prevPinchR && !rightPinch && this.rightPinchLastDurationNs < PLACE_MAX_NS) {
            this.placePulseUntilNs = nowNs + 80_000_000L;
            this.rightPinchLastDurationNs = 0L;
        }
        // Right attack swing: fast wrist movement, one-handed, not a pinch/fist/bow/eat.
        boolean nearHead = trackedR && dist3(this.wR[0], this.wR[1], this.wR[2], headX, headY, headZ) < EAT_DISTANCE;
        this.attackHeld = false;
        if (!gui && !bow && !both && trackedR && !rightPinch && !nearHead && this.speedR > ATTACK_SPEED
            && nowNs >= this.attackUntilNs) {
            this.attackPulseUntilNs = nowNs + 80_000_000L;
            this.attackUntilNs = nowNs + ATTACK_COOLDOWN_NS;
        }
        this.eatHeld = !gui && !bow && trackedR && nearHead && !this.fistR;

        // Teleport: left pinch held, release commits.
        this.teleportHold = !gui && !seated && trackedL && pinchNowL;

        // Left fist tap = Escape (short release; not both-fist inventory, not GUI click path).
        if (this.prevFistL && !this.fistL && !this.fistR && this.leftFistPressNs > 0L
            && nowNs - this.leftFistPressNs <= INVENTORY_TAP_MAX_NS) {
            this.menuPulseUntilNs = nowNs + 80_000_000L;
        }

        // Right index-finger tap = hotbar next; double tap = previous.
        // Hotbar tap is a fingertip tap with a quiet wrist; attack swings are wrist-fast and must not
        // also cycle the hotbar.
        if (!gui && !bow && trackedR && !rightPinch && !this.fistR && this.speedR < 0.8F
            && this.tipSpeedR > 1.2F && nowNs >= this.hotbarLastNs + 150_000_000L) {
            if (nowNs - this.hotbarLastNs <= HOTBAR_DOUBLE_NS) {
                this.hotbarPrevPulseUntilNs = nowNs + 80_000_000L;
            } else {
                this.hotbarNextPulseUntilNs = nowNs + 80_000_000L;
            }
            this.hotbarLastNs = nowNs;
        }

        // GUI: right pinch click; left fist = menu pulse handled above (world gating).
        if (gui && trackedR && rightPinch && !this.prevPinchR) {
            this.guiClickPulseUntilNs = nowNs + 80_000_000L;
        }

        // Climb: a closed hand above the chest is a grab candidate; release when it opens/drops.
        this.climbGrabL = climbCandidate && this.fistL && !bow && !gui;
        this.climbGrabR = climbCandidate && this.fistR && !bow && !gui;
        // Climb jump: both hands are grabbing and both move downward sharply.
        if (this.climbGrabL && this.climbGrabR && this.speedL > 0.8F && this.speedR > 0.8F) {
            this.climbJumpPulseUntilNs = nowNs + 80_000_000L;
        }

        this.jump = nowNs < this.jumpPulseUntilNs;
        this.sneak = this.sneaking;
        this.place = nowNs < this.placePulseUntilNs;
        this.attack = nowNs < this.attackPulseUntilNs || this.breakHeld;
        this.menu = nowNs < this.menuPulseUntilNs;
        this.inventory = nowNs < this.inventoryPulseUntilNs;
        this.hotbarNext = nowNs < this.hotbarNextPulseUntilNs;
        this.hotbarPrev = nowNs < this.hotbarPrevPulseUntilNs;
        this.bowDraw = bow;
        this.bowFire = nowNs < this.bowFireUntilNs;
        this.guiClick = nowNs < this.guiClickPulseUntilNs;
        this.eat = this.eatHeld;
        this.climbJump = nowNs < this.climbJumpPulseUntilNs;
        this.walk = this.walkActive;

        this.prevPinchL = pinchNowL;
        this.prevPinchR = pinchNowR;
        this.prevFistL = this.fistL;
        this.prevFistR = this.fistR;
        this.bothFistPrev = both;
        System.arraycopy(this.wL, 0, this.prevWL, 0, 3);
        System.arraycopy(this.wR, 0, this.prevWR, 0, 3);
        System.arraycopy(this.tipL, 0, this.prevTipL, 0, 3);
        System.arraycopy(this.tipR, 0, this.prevTipR, 0, 3);
        this.prevHeadY = headY;
        this.prevNs = nowNs;
    }

    // fields used by the transition logic
    private boolean bowActivePrev;
    private boolean climbActivePrev;
    private boolean breakHeld;
    private boolean attackHeld;
    private boolean eatHeld;
    private boolean teleportHold;
    private boolean climbGrabL, climbGrabR;
    private boolean jump, sneak, place, attack, menu, inventory, hotbarNext, hotbarPrev, bowDraw, bowFire, guiClick, eat, climbJump, walk;

    public boolean walkActive() { return this.walk; }
    public float walkForward() { return this.walk ? 1.0F : 0.0F; }
    public boolean jump() { return this.jump; }
    public boolean sneak() { return this.sneak; }
    public boolean teleportHeld() { return this.teleportHold; }
    public boolean place() { return this.place; }
    public boolean breakHeld() { return this.breakHeld; }
    public boolean attack() { return this.attack; }
    public boolean menu() { return this.menu; }
    public boolean inventory() { return this.inventory; }
    public boolean hotbarNext() { return this.hotbarNext; }
    public boolean hotbarPrev() { return this.hotbarPrev; }
    public boolean bowDraw() { return this.bowDraw; }
    public boolean bowFire() { return this.bowFire; }
    public boolean guiClick() { return this.guiClick; }
    public boolean eat() { return this.eat; }
    public boolean climbGrabLeft() { return this.climbGrabL; }
    public boolean climbGrabRight() { return this.climbGrabR; }
    public boolean climbJump() { return this.climbJump; }
    public String summary() { return buildSummary(this.walk ? false : false, false); }

    public void releaseAll() {
        this.trackedL = false; this.trackedR = false;
        this.fistL = false; this.fistR = false;
        this.prevPinchL = false; this.prevPinchR = false;
        this.prevFistL = false; this.prevFistR = false;
        this.bothFistPrev = false;
        this.bowActivePrev = false;
        this.climbActivePrev = false;
        this.walk = false; this.walkForward = 0.0F;
        this.jump = false; this.sneak = false; this.teleportHold = false;
        this.place = false; this.breakHeld = false; this.attack = false;
        this.menu = false; this.inventory = false; this.hotbarNext = false; this.hotbarPrev = false;
        this.bowDraw = false; this.bowFire = false; this.guiClick = false; this.eat = false;
        this.climbGrabL = false; this.climbGrabR = false; this.climbJump = false;
        this.prevNs = 0L;
        this.summary = "M7 released";
    }

    private static void copyPos(float[] joints, int index, float[] out) {
        int o = index * 3;
        out[0] = joints[o]; out[1] = joints[o + 1]; out[2] = joints[o + 2];
    }

    private static float dist3(float ax, float ay, float az, float bx, float by, float bz) {
        float dx = ax - bx, dy = ay - by, dz = az - bz;
        return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    private static float dist(float[] a, float[] b) {
        float dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2];
        return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    private static float length(float[] joints, int a, int b) {
        int ao = a * 3, bo = b * 3;
        float dx = joints[ao] - joints[bo], dy = joints[ao + 1] - joints[bo + 1],
            dz = joints[ao + 2] - joints[bo + 2];
        return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    /** Curl ratio from the Gesture Lab: mean(tip→knuckle / wrist→knuckle) over four fingers. */
    private float curl(float[] joints) {
        float sum = 0.0F;
        int[] knuckles = {INDEX_KNUCKLE, MIDDLE_KNUCKLE, RING_KNUCKLE, LITTLE_KNUCKLE};
        int[] tips = {INDEX_TIP, MIDDLE_TIP, RING_TIP, LITTLE_TIP};
        for (int i = 0; i < 4; i++) {
            float wrist = length(joints, WRIST, knuckles[i]);
            float curl = length(joints, tips[i], knuckles[i]) / Math.max(0.02F, wrist);
            sum += Math.max(0.0F, Math.min(2.0F, curl));
        }
        return sum * 0.25F;
    }

    private String buildSummary(boolean gui, boolean seated) {
        StringBuilder b = this.summaryBuilder;
        b.setLength(0);
        b.append("M7 gui=").append(gui).append(" seated=").append(seated)
            .append(" track=").append(this.trackedL ? 'L' : '-').append(this.trackedR ? 'R' : '-')
            .append(" curl=").append(String.format(java.util.Locale.ROOT, "%.2f/%.2f", this.curlL, this.curlR))
            .append(" walk=").append(this.walkActive ? 1 : 0)
            .append(" place=").append(this.place ? 1 : 0)
            .append(" break=").append(this.breakHeld ? 1 : 0)
            .append(" attack=").append(this.attack ? 1 : 0)
            .append(" inv=").append(this.inventory ? 1 : 0)
            .append(" menu=").append(this.menu ? 1 : 0)
            .append(" tele=").append(this.teleportHold ? 1 : 0)
            .append(" bow=").append(this.bowDraw ? 1 : 0)
            .append(" eat=").append(this.eat ? 1 : 0)
            .append(" climb=").append((this.climbGrabL ? 'L' : '-')).append(this.climbGrabR ? 'R' : '-');
        return b.toString();
    }
}
