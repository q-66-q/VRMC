package dev.vrmc.provider;

/**
 * M7 simplified whole-hand gesture engine (data-driven thresholds from the Gesture Lab).
 *
 * <p>Pure Java: it consumes the 27 ARKit joints already parsed by {@link VisionInput}, the HMD pose
 * and a small game-context bitmask, and produces action intents. It never touches Minecraft or
 * Vivecraft types, so the state machine is host-testable, replayable against the recorded operator
 * datasets, and fuzzable.
 *
 * <p>Operator mapping (docs/mvp/M7_GESTURES.md):
 * <ul>
 *   <li>short right pinch (&lt;350 ms) = place/select; held right pinch (&ge;350 ms) = break/mine;</li>
 *   <li>left pinch hold = teleport aim, release commits; left fist tap = Escape/menu (also in GUI);</li>
 *   <li>both-fist short tap (&lt;450 ms) = inventory; both fists + alternating swing = walk forward;</li>
 *   <li>right-hand swing = entity attack; right index-finger tap = hotbar next (double = previous);</li>
 *   <li>wide both fists front/back = bow draw, release the back fist fires (only while a bow is held);</li>
 *   <li>right hand near the head = eat/drink (only while food/drink is held);</li>
 *   <li>head rise = jump (auto-jump remains enabled); head drop = sneak;</li>
 *   <li>alternating closed-hand reach/pull above chest height = climb grab/jump.</li>
 * </ul>
 *
 * <p>Priority: GUI &gt; bow &gt; climb/grab &gt; eat &gt; walk &gt; attack/break/place/teleport.
 * Every intent has a release path on tracking loss, stale input, GUI transition, seated mode, or a
 * mode/environment change.
 *
 * <h2>Accuracy model (why this version differs from the first M7 engine)</h2>
 * Replaying the recorded Gesture Lab datasets through the first engine exposed:
 * <ul>
 *   <li>a fixed per-frame head EMA is frame-rate dependent and lets a sustained crouch adapt away
 *       after a few seconds (sneak released mid-crouch); the baseline is now dt-corrected and frozen
 *       outside a deadband;</li>
 *   <li>a single fist threshold cannot serve every recording: relaxed hands sit around 0.6-0.7 and a
 *       real fist at 0.3-0.45, so 0.65 misclassified relaxed hands as fists (blocking hotbar/eat and
 *       faking both-fist chords). A Schmitt trigger at 0.50/0.60 separates the recorded clusters;</li>
 *   <li>raw hand separation cannot separate a bow draw from walking-in-place arm swings (both reach
 *       &gt;0.5 m). Projecting the separation onto the head-forward axis, requiring chest height and
 *       requiring persistence removes the recorded walk false bows;</li>
 *   <li>wrist-speed-only attack detection fires on every vigorous arm motion (jump-in-place, placing
 *       blocks). Requiring a closed "punch" right hand plus a windowed displacement speed keeps the
 *       recorded attack swings and removes the jump/place false attacks;</li>
 *   <li>single-frame speeds are noisy at 90 Hz and ill-defined on 18 Hz recordings; windowed
 *       displacement speeds (120 ms / 60 ms) are used for attack/swing and finger taps;</li>
 *   <li>game context is now available: a bow draw only makes sense while a bow is held, eating only
 *       while food/drink is held. Context can be disabled with {@code m7.context=off} for the
 *       geometry-only fallback.</li>
 * </ul>
 * Thresholds are fitted on the recorded datasets (docs/mvp/M7_DATA_ANALYSIS_*.md) and must be
 * validated on device; replay scoring lives in scripts/m7_eval_replay.py.
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

    // ---- context bitmask (computed by VisionVR from game state) ----
    public static final int CTX_GUI = 1;
    public static final int CTX_SEATED = 2;
    /** A bow (or crossbow) is held in either hand. */
    public static final int CTX_BOW_HELD = 4;
    /** Food/drink is held (the item stack has a food/consumable component). */
    public static final int CTX_EDIBLE_HELD = 8;
    /** Vivecraft reports a climbable / ladder interaction context this frame (informational). */
    public static final int CTX_CLIMBABLE = 16;

    // ---- data-fitted defaults (override via vrmc-input-tune.properties, see M7_ENGINE.md) ----
    /** Thumb-index pinch entry distance (m). Recorded intentional pinches: p05 0.006-0.007 m. */
    public static final float PINCH_ON = 0.025F;
    /** Pinch release distance (m); Schmitt hysteresis to stop threshold chatter. */
    public static final float PINCH_OFF = 0.045F;
    public static final long PINCH_DEBOUNCE_NS = 30_000_000L;
    public static final long PINCH_ARM_NS = 80_000_000L;
    /**
     * A pinching hand must be raised in front of the body. Recorded intentional pinches sit
     * forward p05/p50 0.24/0.39 (right) and 0.30/0.36-0.43 (left) with the hand at chest height;
     * resting/accidental pinches were recorded at up -0.6 m and forward <=0.13 m.
     */
    public static final float PINCH_HAND_MIN_FORWARD = 0.15F;
    public static final float PINCH_HAND_MIN_UP = -0.55F;
    /**
     * Fist curl ratio = mean(tip->knuckle / wrist->knuckle). Recorded real fists: p50 0.31-0.45;
     * relaxed/open hands: p50 0.65-0.95. Schmitt pair fitted to leave both clusters on their side.
     */
    public static final float FIST_ON = 0.55F;
    /**
     * Fist off threshold. Relaxed/pinch hands sit around 0.62-0.70, so a too-high off threshold
     * (e.g. 0.85) latches a fist for the rest of the recording and blocks every later pinch press.
     * 0.65 opens on the recorded relaxed hands while still holding the sustained walk/bow fists.
     */
    public static final float FIST_OFF = 0.65F;
    /** Short right pinch below this duration places/selects; at or above it breaks/mines. */
    public static final long PLACE_MAX_NS = 320_000_000L;
    public static final long INVENTORY_TAP_MAX_NS = 450_000_000L;
    public static final long LEFT_FIST_TAP_MIN_NS = 60_000_000L;
    /** Recorded left-fist taps (Escape) ran 0.11-0.56 s; other left holds are longer and cannot fire. */
    public static final long LEFT_FIST_TAP_MAX_NS = 550_000_000L;
    public static final float INVENTORY_MAX_HAND_SEP = 0.50F;
    /** A teleport pinch must be a deliberate hold, not a resting thumb-index touch. */
    public static final long TELEPORT_MIN_HOLD_NS = 120_000_000L;

    // Windowed displacement speeds: robust at both 18 Hz replay and 90 Hz runtime.
    public static final long SPEED_WINDOW_NS = 120_000_000L;
    public static final long TIP_SPEED_WINDOW_NS = 60_000_000L;
    public static final long HEAD_VEL_WINDOW_NS = 120_000_000L;
    /**
     * Recorded swings: windowed 120 ms speed p50 1.32 / p95 2.97 / max 4.75; the 28-swing segmentation
     * used a 1.4 m/s peak and re-arm <0.8. Speed alone is shared with walk/place, so attack needs a
     * sustained swing (windowed speed >= 2.0) with real acceleration and a rising-edge re-arm.
     */
    public static final float ATTACK_SPEED = 1.40F;
    public static final float ATTACK_ACCEL = 0.0F;
    public static final float ATTACK_REARM_SPEED = 0.80F;
    public static final long ATTACK_COOLDOWN_NS = 400_000_000L;
    /** If the hand never slows enough to re-arm, allow a new swing after this long anyway. */
    public static final long ATTACK_REARM_TIMEOUT_NS = 550_000_000L;
    /** A closed hand within this window before a fast swing counts as a punch. */
    public static final long ATTACK_FIST_MEMORY_NS = 400_000_000L;

    // Walk: recorded opposite-phase head-forward wrist swing ~0.8 Hz, sign crossings p50 0.50 s /
    // p95 0.72 s; the first engine's 600 ms stop window dropped out between swing crossings.
    public static final float WALK_AMPLITUDE = 0.05F;
    public static final long WALK_STOP_NS = 600_000_000L;
    public static final long WALK_RESET_NS = 1_300_000_000L;
    /** A strong first crossing (large swing amplitude) may start walk without waiting for the 2nd. */
    public static final float WALK_START_PEAK = 0.18F;
    public static final long WALK_FIST_GRACE_NS = 220_000_000L;
    /** Brief one/both-hand tracking dropouts must not end a walk or restart bow arming. */
    public static final long BOTH_TRACK_GRACE_NS = 160_000_000L;
    public static final long BOW_ARM_GAP_NS = 200_000_000L;
    public static final int WALK_CROSSINGS = 2;

    // Bow: recorded draws hold |forward separation| p50 0.36 / p95 0.55 m with hands at chest height
    // (max height p50 -0.11 rel head); walking stays p95 0.35 m but the hands are low (p50 -0.39).
    public static final float BOW_SEPARATION = 0.30F;
    /** Draw hysteresis: release the draw when the projected separation falls below this. */
    public static final float BOW_SEPARATION_OFF = 0.22F;
    public static final float BOW_MIN_MAX_UP = -0.30F;
    /** Recorded draws run 0.11-4.06 s; arming must not reject the short draws. */
    public static final long BOW_ARM_NS = 100_000_000L;
    /** Minecraft needs ~1 s to nock another arrow; prevents a double fire on tracking flicker. */
    public static final long BOW_FIRE_COOLDOWN_NS = 800_000_000L;

    // Eat: recorded wrist->head p05/p50 0.22/0.28 m, in front of the face (fwd p50 +0.15 m).
    // Measured inside the 0.28 m ball: forward 0.098-0.220 m, |lateral| p95 0.128 m, up -0.211..-0.104.
    public static final float EAT_ON = 0.30F;
    public static final float EAT_OFF = 0.32F;
    public static final float EAT_MIN_FORWARD = -0.02F;
    public static final float EAT_MAX_LATERAL = 0.28F;
    public static final float EAT_MIN_UP = -0.45F;
    public static final float EAT_MAX_UP = 0.10F;
    public static final long EAT_LATCH_NS = 60_000_000L;
    /** Bridge short tracking dropouts while latching/保持 (the recorder lost the eating hand 15x). */
    public static final long EAT_GAP_NS = 150_000_000L;

    // Head jump/sneak: dt-corrected baseline with a freeze deadband so a sustained crouch or jump
    // apex cannot adapt the baseline away. Recorded: 29 rises 0.11-0.30 m, 5 drops 0.10-0.25 m.
    // Analyst-head simulation on JUMP_HEAD/SNEAK_HEAD: dt-corrected tau=2 s, 0.10 m adapt-band freeze,
    // 0.10 m rise / 0.35 m/s windowed velocity (120 ms), 0.12 m drop / 0.50 s latch; the current
    // frame-rate EMA had a 0.735 s tau at 90 Hz and 87% crouch dropout.
    public static final float HEAD_JUMP_RISE = 0.10F;
    public static final float HEAD_SNEAK_DROP = 0.12F;
    public static final float HEAD_BASELINE_DEADBAND = 0.10F;
    public static final float HEAD_BASELINE_TAU_S = 2.0F;
    public static final float HEAD_JUMP_VELOCITY = 0.35F;
    public static final long HEAD_JUMP_COOLDOWN_NS = 700_000_000L;
    public static final long HEAD_SNEAK_LATCH_NS = 500_000_000L;
    public static final float HEAD_SNEAK_RELEASE_DROP = 0.05F;
    public static final long HEAD_SNEAK_RELEASE_NS = 250_000_000L;
    /** Looking steeply down (pitch < ~-46 deg) shifts the head ~0.10-0.13 m; gate head gestures. */
    public static final float HEAD_MIN_FORWARD_Y = -0.72F;
    /** Jump landing/crouch suppression after a fired jump. */
    public static final long HEAD_JUMP_SNEAK_SUPPRESS_NS = 600_000_000L;

    // Hotbar: index-fingertip tap with a quiet wrist. Recorded taps: tip window speed p50 1.55 m/s,
    // wrist max 0.65 m/s; attack/jump arm motion moves the wrist far more.
    public static final float HOTBAR_TIP_SPEED = 0.82F;
    public static final float HOTBAR_WRIST_MAX = 0.55F;
    /** A tap is a short tip-speed burst: retry the gates for this long instead of only on the edge. */
    public static final long HOTBAR_BURST_NS = 150_000_000L;
    /** The tap is the index finger alone: recorded index taps move >=2.4x more than the middle tip. */
    public static final float HOTBAR_INDEX_SPECIFIC = 1.35F;
    /** Recorded pinch releases move the index fingertip too; never cycle the hotbar right after one. */
    public static final long HOTBAR_PINCH_RELEASE_QUIET_NS = 1_500_000_000L;
    /** Deliberate pinch presses are made with a hand that is not closed in a fist. */
    public static final float PINCH_PRESS_MAX_SPEED = 1.60F;
    /**
     * A real fist reads curl 0.30-0.45; a pinching hand curls to 0.55-0.70. Only a confirmed grip
     * blocks a pinch, so fist-like pinch postures cannot latch the gate shut.
     */
    public static final float PINCH_BLOCK_GRIP_CURL = 0.45F;
    /** Return motion of one tap peaks ~230 ms after the tap start; a new tap needs a 300 ms gap. */
    public static final long HOTBAR_TAP_COOLDOWN_NS = 200_000_000L;
    /** Minimum spacing between two deliberate taps: the return motion of one tap peaks ~230-300 ms in. */
    public static final long HOTBAR_DOUBLE_MIN_GAP_NS = 500_000_000L;
    /** A deliberate double tap must land inside this window (recorded single-tap cadence is >=0.5 s). */
    public static final long HOTBAR_DOUBLE_NS = 650_000_000L;
    /** Single-tap decision latency: next fires after this delay unless a second tap arrives (previous). */
    public static final long HOTBAR_SINGLE_DELAY_NS = 320_000_000L;

    // Climb: recorded grab hands sit around chest/head height (up p05 -0.50, p50 -0.39); the jump
    // chord needs a deliberate downward pull, not any fast hand motion.
    // Recorded closed-hand height (wrist_y - head_y): p50 -0.29/-0.34, p95 +0.16. Grabs start above
    // +0.05 m and release on an open hand or when the pull passes -0.35 m (26/27 old releases were a
    // premature -0.05 m height cut).
    public static final float CLIMB_GRAB_UP = -0.30F;
    public static final float CLIMB_RELEASE_UP = -0.50F;
    public static final float CLIMB_MIN_FORWARD = -0.10F;
    public static final float CLIMB_JUMP_DOWN_SPEED = 0.30F;
    public static final long CLIMB_JUMP_WINDOW_NS = 250_000_000L;
    public static final long CLIMB_JUMP_COOLDOWN_NS = 600_000_000L;

    private static final int HIST = 24;

    private final float[] jointsL = new float[FLOATS];
    private final float[] jointsR = new float[FLOATS];

    // ---- tuning (configurable from the tune file / hand calibration) ----
    private final float pinchOn;
    private final float pinchOff;
    private final float fistOn;
    private final float fistOff;
    private final boolean contextGating;

    // ---- per-frame inputs ----
    private boolean trackedL, trackedR;
    private final float[] wL = new float[3];
    private final float[] wR = new float[3];
    private final float[] tipR = new float[3];
    private final float[] middleR = new float[3];
    private float pinchL, pinchR;
    private float curlL = Float.NaN, curlR = Float.NaN;
    private boolean fistL, fistR;
    private boolean prevFistL, prevFistR;
    private long prevNs;
    private long nowNs;

    // head pose / basis
    private float headX, headY, headZ;
    private float fwdX, fwdY, fwdZ;
    private float rightX, rightY, rightZ;
    private int context;

    // hand positions in the head frame (right, up, forward); up is world-up relative to the head
    private final float[] relL = new float[3];
    private final float[] relR = new float[3];

    // ---- history for windowed displacement velocities ----
    private final long[] histT = new long[HIST];
    private final float[] histWL = new float[HIST * 3];
    private final float[] histWR = new float[HIST * 3];
    private final float[] histTipR = new float[HIST * 3];
    private final float[] histMiddleR = new float[HIST * 3];

    private final float[] histHeadY = new float[HIST];
    private int histNext;
    private int histCount;

    // ---- pinch (debounced + armed, Schmitt trigger) ----
    private boolean rawPinchL, rawPinchR;
    private boolean pinchPressedL, pinchPressedR;
    private boolean pinchArmedL = true, pinchArmedR = true;
    private long pinchRawSinceL, pinchRawSinceR;
    private long pinchReleasedSinceL, pinchReleasedSinceR;
    private long leftPinchPressNs, rightPinchPressNs;
    private long pinchLastDurationR;
    private long lastPinchReleaseR, lastPinchReleaseL;
    private boolean pinchPressedThisFrameL, pinchPressedThisFrameR;
    private boolean pinchReleasedThisFrameL, pinchReleasedThisFrameR;
    private boolean pinchPrevPressedL, pinchPrevPressedR;
    private boolean pinchEngagedL, pinchEngagedR;
    private boolean pinchPrevEngagedL, pinchPrevEngagedR;
    /** Hand was physically raised when the pinch was confirmed (world actions require this). */
    private boolean pinchRaisedL, pinchRaisedR;
    /** The pinch ended because the hand lost tracking: never place on a tracking-loss release. */
    private boolean pinchLostL, pinchLostR;

    // ---- fist taps ----
    private long leftFistPressNs, rightFistPressNs;
    private long lastBothFistCloseNs, lastBothFistReleaseNs;
    private long lastInventoryNs, lastMenuNs;
    private long leftFistTapPulseUntilNs;
    private boolean bothFistPrev;
    private long bothFistStartNs;
    private float bothMaxSep;
    private boolean bothHadTrackingLoss;

    // ---- walk ----
    private boolean walkActive;
    private int swingSign;
    private int swingCrossings;
    private float swingPeak;
    private long swingLastCrossNs;
    private long swingMotionNs;
    private long lastBothTrueNs;
    private long lastBothTrackedNs;

    // ---- bow ----
    private boolean bowActive;
    private long bowSepSinceNs;
    private long bowStartNs;
    private long bowFireUntilNs;
    private long lastBowFireNs;
    private long lastBowExitNs;

    // ---- eat ----
    private boolean eatLatched;
    private long eatNearSinceNs;
    private long eatLastHoldNs;

    // ---- attack ----
    private long attackUntilNs;
    private long attackPulseUntilNs;
    private long lastFistRTrueNs;
    private long lastWalkNs;
    private long lastPinchActivityRNs;
    private long lastAttackFireNs;
    private boolean attackArmed = true;
    private final float[] histWinSpeedR = new float[HIST];
    private float winSpeedRNow;
    private float pitchY;

    // ---- hotbar ----
    private long hotbarLastNs;
    private long hotbarNextPulseUntilNs;
    private long hotbarPrevPulseUntilNs;
    private long hotbarPendingNextNs;
    private long hotbarActivityNs;
    private long hotbarDoubleLockUntilNs;
    private long hotbarTipBurstNs;
    private boolean hotbarTipAbove;

    // ---- place ----
    private long placePulseUntilNs;

    // ---- action state ----
    private long inventoryPulseUntilNs;
    private long menuPulseUntilNs;
    private long jumpPulseUntilNs;
    private long guiClickPulseUntilNs;
    private long climbJumpPulseUntilNs;
    private boolean teleportHold;
    private boolean breakHeld;
    private boolean eatHeld;
    private boolean climbGrabL, climbGrabR;
    private boolean climbLatchedL, climbLatchedR;
    private long climbDownLNs, climbDownRNs;
    private boolean jump, sneak, place, attack, menu, inventory, hotbarNext, hotbarPrev, bowDraw,
        bowFire, guiClick, eat, climbJump, walk;
    private boolean sneaking;
    private long climbJumpUntilNs;
    private long headJumpUntilNs;
    private long sneakBlockUntilNs;
    private long headSneakSinceNs;
    private long headSneakReleaseSinceNs;
    private float headBaseline;

    private final StringBuilder summaryBuilder = new StringBuilder(200);
    private String summary = "M7 idle";

    public VisionM7Gesture() {
        this(PINCH_ON, PINCH_OFF, FIST_ON, FIST_OFF, true);
    }

    public VisionM7Gesture(float pinchOn, float pinchOff, float fistOn, float fistOff,
                           boolean contextGating) {
        this.pinchOn = pinchOn > 0.0F ? pinchOn : PINCH_ON;
        this.pinchOff = pinchOff > this.pinchOn ? pinchOff : PINCH_OFF;
        this.fistOn = fistOn > 0.05F ? fistOn : FIST_ON;
        this.fistOff = fistOff > this.fistOn ? fistOff : FIST_OFF;
        this.contextGating = contextGating;
    }

    /** Convenience overload for tests/legacy call sites: identity head basis, no game context. */
    public void update(boolean trackedL, float[] jointsL, boolean trackedR, float[] jointsR,
                       float pinchL, float pinchR, float headX, float headY, float headZ,
                       long nowNs, boolean guiOpen, boolean seated) {
        int ctx = (guiOpen ? CTX_GUI : 0) | (seated ? CTX_SEATED : 0);
        update(trackedL, jointsL, trackedR, jointsR, pinchL, pinchR, headX, headY, headZ,
            1.0F, 0.0F, 0.0F, 0.0F, 0.0F, -1.0F, nowNs, ctx);
    }

    /** Convenience overload with the identity head basis and an explicit context bitmask. */
    public void update(boolean trackedL, float[] jointsL, boolean trackedR, float[] jointsR,
                       float pinchL, float pinchR, float headX, float headY, float headZ,
                       long nowNs, int context) {
        update(trackedL, jointsL, trackedR, jointsR, pinchL, pinchR, headX, headY, headZ,
            1.0F, 0.0F, 0.0F, 0.0F, 0.0F, -1.0F, nowNs, context);
    }

    /**
     * One frame. Joint arrays are 27 ARKit positions in device space (the same space as the head
     * position); pass the hand arrays even when untracked (the flag gates them). Head right/forward
     * are unit vectors derived from the HMD pose. {@code context} is a bitmask of {@code CTX_*}.
     */
    public void update(boolean trackedL, float[] jointsL, boolean trackedR, float[] jointsR,
                       float pinchL, float pinchR, float headX, float headY, float headZ,
                       float headRightX, float headRightY, float headRightZ,
                       float headFwdX, float headFwdY, float headFwdZ,
                       long nowNs, int context) {
        if (jointsL == null || jointsR == null || jointsL.length < FLOATS || jointsR.length < FLOATS) {
            releaseAll();
            return;
        }
        // Malformed head input must release, never latch. A NaN pinch is legal: it means that hand is
        // not tracked this frame (per-hand release is handled by tracked/hand state), not a global
        // tracking loss.
        if (!Float.isFinite(headY) || !Float.isFinite(headX) || !Float.isFinite(headZ)) {
            releaseAll();
            return;
        }
        if (this.prevNs != 0L && nowNs < this.prevNs) {
            // Non-monotonic timestamps can only come from a replay/diagnostic feeding mistake; keep
            // the previous state instead of corrupting durations. Equal timestamps are accepted
            // (same-frame re-evaluation) with a 1 ms dt floor.
            return;
        }
        this.nowNs = nowNs;
        this.trackedL = trackedL;
        this.trackedR = trackedR;
        this.pinchL = pinchL;
        this.pinchR = pinchR;
        this.headX = headX;
        this.headY = headY;
        this.headZ = headZ;
        this.context = context;
        boolean gui = (context & CTX_GUI) != 0;
        boolean seated = (context & CTX_SEATED) != 0;

        float dt = this.prevNs == 0L ? 1.0F / 90.0F : Math.max(1.0e-3F, (nowNs - this.prevNs) * 1.0e-9F);
        normalizeHeadBasis(headRightX, headRightY, headRightZ, headFwdX, headFwdY, headFwdZ);

        // ---- hand positions + fists (Schmitt trigger) ----
        boolean currFistL = this.fistL;
        boolean currFistR = this.fistR;
        if (trackedL) {
            System.arraycopy(jointsL, 0, this.jointsL, 0, FLOATS);
            copyPos(this.jointsL, WRIST, this.wL);
            this.curlL = curl(this.jointsL);
            currFistL = this.fistL ? this.curlL < this.fistOff : this.curlL < this.fistOn;
        } else {
            this.curlL = Float.NaN;
            currFistL = false;
        }
        if (trackedR) {
            System.arraycopy(jointsR, 0, this.jointsR, 0, FLOATS);
            copyPos(this.jointsR, WRIST, this.wR);
            copyPos(this.jointsR, INDEX_TIP, this.tipR);
            copyPos(this.jointsR, MIDDLE_TIP, this.middleR);
            this.curlR = curl(this.jointsR);
            currFistR = this.fistR ? this.curlR < this.fistOff : this.curlR < this.fistOn;
        } else {
            this.curlR = Float.NaN;
            currFistR = false;
        }
        this.fistL = currFistL;
        this.fistR = currFistR;
        if (!trackedR) {
            // The delayed single-tap decision is scheduled ~0.3 s ahead; tracking loss must cancel it
            // so no pulse outlives the hand data that produced it (no stuck input without a hand).
            this.hotbarPendingNextNs = 0L;
        }
        if (this.fistL && !this.prevFistL) this.leftFistPressNs = nowNs;
        if (this.fistR && !this.prevFistR) this.rightFistPressNs = nowNs;
        if (this.fistR) this.lastFistRTrueNs = nowNs;

        // Head-relative wrist coordinates: right / up / forward in metres.
        toHeadFrame(this.wL, this.relL);
        toHeadFrame(this.wR, this.relR);

        // ---- windowed speeds + head motion ----
        float winSpeedR = windowedSpeed(histWR, this.wR, SPEED_WINDOW_NS);
        float winSpeedL = windowedSpeed(histWL, this.wL, SPEED_WINDOW_NS);
        float winTipSpeedR = windowedSpeed(histTipR, this.tipR, TIP_SPEED_WINDOW_NS);
        float winMiddleSpeedR = windowedSpeed(histMiddleR, this.middleR, TIP_SPEED_WINDOW_NS);
        this.winSpeedRNow = winSpeedR;
        float headVel = windowedHeadVelocity(HEAD_VEL_WINDOW_NS);
        float vertVelL = windowedVerticalSpeed(histWL, this.wL, SPEED_WINDOW_NS);
        float vertVelR = windowedVerticalSpeed(histWR, this.wR, SPEED_WINDOW_NS);

        // ---- pinch (Schmitt + debounce + arming; world engagement also needs a raised hand) ----
        this.pinchPressedThisFrameL = false;
        this.pinchPressedThisFrameR = false;
        this.pinchReleasedThisFrameL = false;
        this.pinchReleasedThisFrameR = false;
        boolean handReadyL = this.relL[2] > PINCH_HAND_MIN_FORWARD && this.relL[1] > PINCH_HAND_MIN_UP;
        boolean handReadyR = this.relR[2] > PINCH_HAND_MIN_FORWARD && this.relR[1] > PINCH_HAND_MIN_UP;
        boolean pinchNowL = updatePinch(true, trackedL, this.pinchL, nowNs, handReadyL, gui,
            this.curlL, winSpeedL);
        boolean pinchNowR = updatePinch(false, trackedR, this.pinchR, nowNs, handReadyR, gui,
            this.curlR, winSpeedR);
        this.pinchEngagedL = pinchNowL;
        this.pinchEngagedR = pinchNowR;

        // ---- head jump / sneak: dt-corrected baseline, frozen outside the deadband ----
        // The head forward vector gives pitch: looking steeply down lowers the world head position by
        // ~0.10-0.13 m (analyst-head pitch lever), so gate head gestures when pitch < ~-46 deg.
        this.pitchY = fwdY;
        boolean headPitchOk = this.pitchY > HEAD_MIN_FORWARD_Y;
        if (this.prevNs == 0L) this.headBaseline = headY;
        float deviation = headY - this.headBaseline;
        if (Math.abs(deviation) <= HEAD_BASELINE_DEADBAND) {
            float alpha = 1.0F - (float) Math.exp(-dt / HEAD_BASELINE_TAU_S);
            this.headBaseline += deviation * alpha;
        }
        if (!gui && !seated && headPitchOk && nowNs >= this.headJumpUntilNs
            && deviation > HEAD_JUMP_RISE && headVel > HEAD_JUMP_VELOCITY) {
            this.jumpPulseUntilNs = nowNs + 80_000_000L;
            this.headJumpUntilNs = nowNs + HEAD_JUMP_COOLDOWN_NS;
            // Landing after a physical jump dips the head below the baseline; never turn that into
            // a sneak. The recorded JUMP_HEAD session produced exactly that false sneak in replay.
            this.sneakBlockUntilNs = nowNs + HEAD_JUMP_SNEAK_SUPPRESS_NS;
        }
        float drop = this.headBaseline - headY;
        // Start the latch timer as soon as the head is clearly low and not rising sharply. The
        // downward transition itself is fast (physical crouch), so it must NOT reset the timer; a
        // rapid rise (standing up / landing bounce) does. Landing-from-jump is excluded separately by
        // the jump sneak-block above.
        if (!gui && !seated && headPitchOk && nowNs >= this.sneakBlockUntilNs
            && drop > HEAD_SNEAK_DROP && headVel < 0.35F) {
            if (this.headSneakSinceNs == 0L) this.headSneakSinceNs = nowNs;
            if (nowNs - this.headSneakSinceNs >= HEAD_SNEAK_LATCH_NS) this.sneaking = true;
        } else {
            this.headSneakSinceNs = 0L;
        }
        if (this.sneaking) {
            if (drop >= HEAD_SNEAK_RELEASE_DROP) {
                this.headSneakReleaseSinceNs = 0L;
            } else {
                if (this.headSneakReleaseSinceNs == 0L) this.headSneakReleaseSinceNs = nowNs;
                if (nowNs - this.headSneakReleaseSinceNs >= HEAD_SNEAK_RELEASE_NS) {
                    this.sneaking = false;
                    this.headSneakReleaseSinceNs = 0L;
                }
            }
        } else {
            this.headSneakReleaseSinceNs = 0L;
        }
        if (gui || seated) {
            this.sneaking = false;
            this.headSneakSinceNs = 0L;
            this.headSneakReleaseSinceNs = 0L;
        }

        // ---- both-fist family ----
        boolean bothTracked = trackedL && trackedR;
        if (bothTracked) this.lastBothTrackedNs = nowNs;
        boolean bothTrackedGrace = bothTracked
            || (this.lastBothTrackedNs != 0L
                && nowNs - this.lastBothTrackedNs <= BOTH_TRACK_GRACE_NS);
        boolean both = this.fistL && this.fistR && bothTrackedGrace;
        if (both) this.lastBothTrueNs = nowNs;
        float handSep = bothTracked ? dist(this.wL, this.wR) : 0.0F;
        if (both) {
            if (!this.bothFistPrev) {
                this.bothFistStartNs = nowNs;
                this.bothMaxSep = handSep;
                this.bothHadTrackingLoss = false;
            } else {
                this.bothMaxSep = Math.max(this.bothMaxSep, handSep);
            }
        }
        if (this.bothFistPrev && !both) this.lastBothFistReleaseNs = nowNs;
        if (this.bothFistPrev && !bothTracked) this.bothHadTrackingLoss = true;

        // ---- bow: both fists + sustained forward separation at chest height (bow held) ----
        boolean bowHeld = (context & CTX_BOW_HELD) != 0;
        boolean bowAllowed = !this.contextGating || bowHeld;
        float sepFwd = bothTracked ? this.relL[2] - this.relR[2] : 0.0F;
        float absSepFwd = Math.abs(sepFwd);
        float maxUp = Math.max(this.relL[1], this.relR[1]);
        if (this.bowActive) {
            // Draw hysteresis: keep while projected separation stays above the off threshold and the
            // hands stay in front at chest height. Releasing the held use (any exit) fires the arrow,
            // matching Minecraft's hold-to-draw semantics and all 16 recorded draw cycles.
            boolean drawStillHeld = bowAllowed && !gui && !seated && both
                && bothTrackedGrace && absSepFwd > BOW_SEPARATION_OFF
                && maxUp > BOW_MIN_MAX_UP - 0.10F;
            if (!drawStillHeld) {
                // A draw must have been armed for at least half the arm time before an exit fires;
                // one-frame tracking flicker at the start must not release the bow.
                boolean drawRan = nowNs - this.bowStartNs >= 200_000_000L;
                if (drawRan && !gui && !seated && bowAllowed
                    && nowNs - this.lastBowFireNs > BOW_FIRE_COOLDOWN_NS) {
                    this.bowFireUntilNs = nowNs + 80_000_000L;
                    this.lastBowFireNs = nowNs;
                }
                this.bowActive = false;
                this.lastBowExitNs = nowNs;
            }
        } else if (bowAllowed && !gui && !seated && both
            && absSepFwd > BOW_SEPARATION && maxUp > BOW_MIN_MAX_UP) {
            if (this.bowSepSinceNs == 0L) this.bowSepSinceNs = nowNs;
            if (nowNs - this.bowSepSinceNs >= BOW_ARM_NS) {
                this.bowActive = true;
                this.bowStartNs = nowNs;
            }
        } else if (!this.bowActive
            && (this.bowSepSinceNs == 0L || nowNs - this.bowSepSinceNs > BOW_ARM_GAP_NS)) {
            // Tolerate short tracking/fist dropouts while arming (the recorded draws lose a hand for
            // up to ~150 ms); a real cancellation resets the timer.
            this.bowSepSinceNs = 0L;
        }

        // ---- walk: both fists, alternating swing along the head-forward axis ----
        boolean climbContextNow = !this.contextGating || (context & CTX_CLIMBABLE) != 0;
        if (both && !this.bowActive && !gui && !seated && !climbContextNow) {
            float diff = this.relL[2] - this.relR[2];
            if (Math.abs(diff) > WALK_AMPLITUDE) {
                int sign = diff > 0 ? 1 : -1;
                this.swingPeak = Math.max(this.swingPeak, Math.abs(diff));
                this.swingMotionNs = nowNs;
                if (this.swingSign != 0 && sign != this.swingSign) {
                    this.swingCrossings++;
                    this.swingLastCrossNs = nowNs;
                }
                this.swingSign = sign;
            }
            // Starting on the first crossing of a large-amplitude swing matches the recorded swing
            // windows better than waiting for the second crossing (which lands ~0.5 s late).
            boolean strongStart = this.swingCrossings == 1 && this.swingPeak >= WALK_START_PEAK;
            if ((this.swingCrossings >= WALK_CROSSINGS || strongStart)
                && nowNs - this.swingLastCrossNs < WALK_STOP_NS) {
                this.walkActive = true;
            }
        }
        boolean walkingNow = this.walkActive && !gui && !seated && !this.bowActive
            && bothTrackedGrace
            && (both || nowNs - this.lastBothTrueNs < WALK_FIST_GRACE_NS)
            && nowNs - this.swingMotionNs < WALK_RESET_NS;
        this.walkActive = walkingNow;
        if (walkingNow) this.lastWalkNs = nowNs;
        if (!walkingNow) {
            // Reset only on a real state change: GUI/seated/bow, a longer both-fist absence (the
            // recorded WALK loses a hand for up to ~150 ms and a transient dropout must not restart
            // the swing series), or a stale swing. Staleness is measured from the later of the last
            // crossing / both-fists onset so a series can start.
            long swingRef = Math.max(this.swingLastCrossNs, this.lastBothTrueNs);
            boolean stale = this.swingSign != 0 && nowNs - swingRef > WALK_RESET_NS;
            boolean bothLostLong = !both
                && (this.lastBothTrueNs == 0L
                    || nowNs - this.lastBothTrueNs > WALK_FIST_GRACE_NS * 2L);
            if (bothLostLong || this.bowActive || gui || seated || stale) {
                this.swingSign = 0;
                this.swingCrossings = 0;
                this.swingPeak = 0.0F;
            }
        }

        // ---- eat (near the head): only with food/drink held unless context gating is disabled ----
        boolean edibleHeld = (context & CTX_EDIBLE_HELD) != 0;
        boolean eatAllowed = !this.contextGating || edibleHeld;
        float distR = dist3(this.wR[0], this.wR[1], this.wR[2], headX, headY, headZ);
        float lateralR = Math.abs(this.relR[0]);
        boolean nearHeadIn = trackedR && distR < EAT_ON
            && this.relR[2] > EAT_MIN_FORWARD && lateralR < EAT_MAX_LATERAL
            && this.relR[1] > EAT_MIN_UP && this.relR[1] < EAT_MAX_UP;
        boolean nearHeadHold = trackedR && distR < EAT_OFF
            && this.relR[2] > EAT_MIN_FORWARD - 0.03F && lateralR < EAT_MAX_LATERAL
            && this.relR[1] > EAT_MIN_UP + 0.02F && this.relR[1] < EAT_MAX_UP - 0.01F;
        if (nearHeadIn) this.eatLastHoldNs = nowNs;
        if (!this.eatLatched) {
            if (nearHeadIn) {
                if (this.eatNearSinceNs == 0L) this.eatNearSinceNs = nowNs;
                if (nowNs - this.eatNearSinceNs >= EAT_LATCH_NS) this.eatLatched = true;
            } else if (this.eatNearSinceNs != 0L
                && nowNs - this.eatLastHoldNs > EAT_GAP_NS) {
                this.eatNearSinceNs = 0L;
            }
        } else if (!nearHeadHold && nowNs - this.eatLastHoldNs > EAT_GAP_NS) {
            this.eatLatched = false;
            this.eatNearSinceNs = 0L;
        }
        this.eatHeld = this.eatLatched && !gui && !this.bowActive && eatAllowed && !walkingNow;

        // ---- place / break: right pinch duration split (hand raised, not near the head) ----
        boolean nearHeadR = distR < EAT_OFF && this.relR[2] > EAT_MIN_FORWARD
            && this.relR[1] > EAT_MIN_UP && this.relR[1] < EAT_MAX_UP + 0.10F;
        long rightPinchDur = this.rightPinchPressNs == 0L ? 0L : nowNs - this.rightPinchPressNs;
        // World pinch actions only make sense with a free hand in the world: not during a chord,
        // locomotion, bow draw/eat, climb context, or right after an attack/walk (the recorded
        // accidental pinches live exactly in those windows).
        boolean pinchWorldOk = !gui && !seated && !walkingNow && !this.bowActive && !this.eatHeld
            && !both && !bowHeld && !edibleHeld && !climbContextNow
            && this.curlR > PINCH_BLOCK_GRIP_CURL
            && !sneaking;
        boolean breakOk = pinchWorldOk && nowNs - this.lastWalkNs > 300_000_000L;
        this.breakHeld = breakOk && this.pinchPressedR && this.pinchRaisedR && trackedR
            && rightPinchDur >= PLACE_MAX_NS;
        if (pinchWorldOk && this.pinchReleasedThisFrameR && this.pinchRaisedR && !this.pinchLostR
            && nowNs - this.lastBothFistReleaseNs > 500_000_000L
            && nowNs - this.lastBothFistCloseNs > 500_000_000L
            && nowNs - this.hotbarActivityNs > 1_500_000_000L
            && nowNs - this.lastAttackFireNs > 1_100_000_000L
            && this.pinchLastDurationR > 0L && this.pinchLastDurationR < PLACE_MAX_NS) {
            this.placePulseUntilNs = nowNs + 80_000_000L;
        }
        this.pinchLostL = false;
        this.pinchLostR = false;

        // ---- teleport: left pinch hold, release commits (Vivecraft commits on release) ----
        this.teleportHold = !gui && !seated && this.pinchPressedL && this.pinchRaisedL && trackedL
            && !both && this.leftPinchPressNs != 0L
            && nowNs - this.leftPinchPressNs >= TELEPORT_MIN_HOLD_NS
            && !this.bowActive && !walkingNow && !this.eatHeld
            && !bowHeld && !climbContextNow && nowNs - this.lastWalkNs > 300_000_000L;

        // ---- attack: closed "punch" right hand + windowed swing speed (one-handed) ----
        // Rising-edge swing, re-armed only after the wrist slows down again: the old "re-fire every
        // 300 ms" rule emitted 52 pulses for the 28 recorded swings (analyst-hands section 4).
        if (winSpeedR < ATTACK_REARM_SPEED
            || nowNs - this.lastAttackFireNs >= ATTACK_REARM_TIMEOUT_NS) {
            this.attackArmed = true;
        }
        float winAccelR = windowedAcceleration();
        boolean attackCondition = this.attackArmed
            && !gui && !seated && !this.bowActive && !walkingNow
            && trackedR && !both && !this.pinchPressedR && !nearHeadR && !this.eatHeld
            && !sneaking && !edibleHeld
            && nowNs - this.lastWalkNs > 400_000_000L
            && !this.climbGrabL && !this.climbGrabR
            && nowNs - this.lastPinchActivityRNs > 80_000_000L
            && (this.fistR || nowNs - this.lastFistRTrueNs <= ATTACK_FIST_MEMORY_NS)
            && winSpeedR >= ATTACK_SPEED
            && nowNs >= this.attackUntilNs;
        if (attackCondition) {
            this.attackPulseUntilNs = nowNs + 80_000_000L;
            this.attackUntilNs = nowNs + ATTACK_COOLDOWN_NS;
            this.attackArmed = false;
            this.lastAttackFireNs = nowNs;
        }

        // ---- left fist tap = Escape/menu (also closes a GUI); plus generic GUI-close pulse ----
        long leftFistTapDuration = this.leftFistPressNs == 0L ? -1L : nowNs - this.leftFistPressNs;
        boolean leftFistTap = this.prevFistL && !this.fistL && !this.fistR
            && leftFistTapDuration >= LEFT_FIST_TAP_MIN_NS
            && leftFistTapDuration <= LEFT_FIST_TAP_MAX_NS;
        if (gui && leftFistTap && nowNs - this.lastBothFistReleaseNs > 200_000_000L) {
            this.leftFistTapPulseUntilNs = nowNs + 80_000_000L;
        }
        boolean menuQuiet = !gui && !walkingNow && !this.bowActive && !this.teleportHold
            && !this.climbGrabL && !this.climbGrabR && !this.pinchPressedR && !this.breakHeld
            && !this.attack && !bowHeld && !climbContextNow
            && nowNs - this.lastPinchActivityRNs > 500_000_000L
            && nowNs - this.hotbarActivityNs > 400_000_000L
            && nowNs >= this.attackUntilNs + 200_000_000L
            && this.relL[1] < 0.10F
            && winSpeedL < 0.90F
            && nowNs - this.lastBothFistReleaseNs > 200_000_000L
            && nowNs - this.lastBothFistCloseNs > 200_000_000L
            && nowNs - this.lastInventoryNs > 300_000_000L
            && nowNs - this.lastMenuNs > 300_000_000L;
        if (leftFistTap && menuQuiet) {
            this.menuPulseUntilNs = nowNs + 80_000_000L;
            this.lastMenuNs = nowNs;
        }

        // ---- both-fist inventory: short tap, hands together, never walk/bow/climb ----
        if (this.bothFistPrev && !both && !gui && !walkingNow && !this.bowActive
            && !this.climbGrabL && !this.climbGrabR && !this.bothHadTrackingLoss
            && !bowHeld
            && nowNs - this.lastBowExitNs > 400_000_000L
            && this.bothFistStartNs > 0L
            && nowNs - this.bothFistStartNs <= INVENTORY_TAP_MAX_NS
            && this.bothMaxSep < INVENTORY_MAX_HAND_SEP) {
            this.inventoryPulseUntilNs = nowNs + 80_000_000L;
            this.lastInventoryNs = nowNs;
        }
        if (both) this.lastBothFistCloseNs = nowNs;

        // ---- climb: latched closed-hand grab above the chest, release on open hand or finished pull ----
        // Runtime context (Vivecraft climb tracker) gates this in auto mode; the fallback requires
        // both hands to avoid eating ordinary one-handed attack/menu gestures.
        boolean climbContext = !this.contextGating || (context & CTX_CLIMBABLE) != 0;
        boolean fallbackBothHands = this.contextGating || both;
        boolean climbAllowed = climbContext && fallbackBothHands
            && !gui && !seated && !walkingNow && !this.bowActive;
        boolean climbStartL = climbAllowed && trackedL && this.fistL
            && this.relL[1] > (this.contextGating ? CLIMB_GRAB_UP : -0.10F)
            && this.relL[2] > CLIMB_MIN_FORWARD;
        boolean climbStartR = climbAllowed && trackedR && this.fistR
            && this.relR[1] > (this.contextGating ? CLIMB_GRAB_UP : -0.10F)
            && this.relR[2] > CLIMB_MIN_FORWARD;
        boolean climbKeepL = this.climbLatchedL && climbAllowed && trackedL && this.fistL
            && this.relL[1] > CLIMB_RELEASE_UP && this.relL[2] > CLIMB_MIN_FORWARD;
        boolean climbKeepR = this.climbLatchedR && climbAllowed && trackedR && this.fistR
            && this.relR[1] > CLIMB_RELEASE_UP && this.relR[2] > CLIMB_MIN_FORWARD;
        this.climbGrabL = climbStartL || climbKeepL;
        this.climbGrabR = climbStartR || climbKeepR;
        this.climbLatchedL = this.climbGrabL;
        this.climbLatchedR = this.climbGrabR;
        if (climbGrabL && vertVelL < -CLIMB_JUMP_DOWN_SPEED) this.climbDownLNs = nowNs;
        if (climbGrabR && vertVelR < -CLIMB_JUMP_DOWN_SPEED) this.climbDownRNs = nowNs;
        if (this.climbGrabL && this.climbGrabR
            && this.climbDownLNs != 0L && this.climbDownRNs != 0L
            && nowNs - this.climbDownLNs <= CLIMB_JUMP_WINDOW_NS
            && nowNs - this.climbDownRNs <= CLIMB_JUMP_WINDOW_NS
            && nowNs >= this.attackUntilNs
            && nowNs >= this.climbJumpUntilNs) {
            this.climbJumpPulseUntilNs = nowNs + 80_000_000L;
            this.climbJumpUntilNs = nowNs + CLIMB_JUMP_COOLDOWN_NS;
            this.climbDownLNs = 0L;
            this.climbDownRNs = 0L;
        }

        // ---- hotbar: quiet-wrist index-fingertip tap; double tap = previous (net one step back) ----
        if (winTipSpeedR > HOTBAR_TIP_SPEED && !this.hotbarTipAbove) {
            this.hotbarTipAbove = true;
            this.hotbarTipBurstNs = nowNs;
        } else if (winTipSpeedR < HOTBAR_TIP_SPEED * 0.70F) {
            this.hotbarTipAbove = false;
        }
        boolean hotbarBurst = this.hotbarTipAbove
            && nowNs - this.hotbarTipBurstNs <= HOTBAR_BURST_NS;
        boolean hotbarCandidate = hotbarBurst && !gui && !seated && trackedR && !both
            && !this.bowActive && !walkingNow && !this.eatHeld && !this.pinchPressedR
            && !bowHeld && !edibleHeld && !climbContextNow
            && !this.fistR && this.relR[2] > 0.05F && this.relR[1] > -0.55F
            && !this.climbGrabL && !this.climbGrabR
            && winTipSpeedR > HOTBAR_INDEX_SPECIFIC * Math.max(0.05F, winMiddleSpeedR)
            && winSpeedR < HOTBAR_WRIST_MAX
            && nowNs - Math.max(this.lastPinchReleaseR, this.lastPinchActivityRNs) > HOTBAR_PINCH_RELEASE_QUIET_NS
            && nowNs - this.lastBothFistReleaseNs > 250_000_000L
            && nowNs - this.lastInventoryNs > 300_000_000L
            && nowNs - this.lastMenuNs > 250_000_000L
            && nowNs >= this.attackUntilNs + 250_000_000L
            && nowNs >= this.hotbarLastNs + HOTBAR_TAP_COOLDOWN_NS
            && nowNs >= this.hotbarDoubleLockUntilNs;
        if (hotbarCandidate) {
            long gap = this.hotbarLastNs == 0L ? Long.MAX_VALUE : nowNs - this.hotbarLastNs;
            boolean isDouble = gap >= HOTBAR_DOUBLE_MIN_GAP_NS && gap <= HOTBAR_DOUBLE_NS;
            if (isDouble) {
                // Second tap inside the window: cancel the delayed "next" and step back now, so one
                // double tap nets exactly one previous slot (and the return motion of a single tap,
                // which arrives before the minimum gap, is ignored instead of looking like a second tap).
                this.hotbarPendingNextNs = 0L;
                this.hotbarPrevPulseUntilNs = nowNs + 80_000_000L;
                this.hotbarDoubleLockUntilNs = nowNs + 700_000_000L;
            } else if (!isDouble && gap < HOTBAR_DOUBLE_MIN_GAP_NS) {
                // Return motion of the same tap: ignore.
            } else {
                this.hotbarPendingNextNs = nowNs + HOTBAR_SINGLE_DELAY_NS;
            }
            this.hotbarLastNs = nowNs;
            this.hotbarActivityNs = nowNs;
        }
        if (this.hotbarPendingNextNs != 0L && nowNs >= this.hotbarPendingNextNs) {
            this.hotbarNextPulseUntilNs = nowNs + 80_000_000L;
            this.hotbarPendingNextNs = 0L;
        }
        if (!trackedR || gui) {
            this.hotbarPendingNextNs = 0L;
        }

        // ---- GUI: right pinch press = click ----
        if (gui && this.pinchPressedThisFrameR && trackedR) {
            this.guiClickPulseUntilNs = nowNs + 80_000_000L;
        }

        // ---- publish outputs ----
        this.jump = nowNs < this.jumpPulseUntilNs;
        this.sneak = this.sneaking;
        this.place = nowNs < this.placePulseUntilNs;
        this.attack = nowNs < this.attackPulseUntilNs || this.breakHeld;
        this.menu = nowNs < this.menuPulseUntilNs;
        this.inventory = nowNs < this.inventoryPulseUntilNs;
        this.hotbarNext = nowNs < this.hotbarNextPulseUntilNs;
        this.hotbarPrev = nowNs < this.hotbarPrevPulseUntilNs;
        this.bowDraw = this.bowActive;
        this.bowFire = nowNs < this.bowFireUntilNs;
        this.guiClick = nowNs < this.guiClickPulseUntilNs;
        this.eat = this.eatHeld;
        this.climbJump = nowNs < this.climbJumpPulseUntilNs;
        this.walk = this.walkActive;

        // ---- commit per-frame state ----
        this.prevFistL = this.fistL;
        this.prevFistR = this.fistR;
        this.bothFistPrev = both;
        this.pinchPrevEngagedL = this.pinchEngagedL;
        this.pinchPrevEngagedR = this.pinchEngagedR;
        pushHistory(nowNs);
        this.prevNs = nowNs;
        this.summary = buildSummary(gui, seated);
    }

    // ----------------------------------------------------------------------------------------
    // Internals
    // ----------------------------------------------------------------------------------------

    /**
     * Debounced/armed pinch with hysteresis; returns whether the pinch is engaged for gestures.
     * A pinch only engages when the debounce has elapsed and (the hand is raised, or the GUI is open
     * where the cursor click must work regardless of hand height).
     */
    private boolean updatePinch(boolean left, boolean tracked, float distance, long now,
                                boolean handReady, boolean guiOpen, float curlHand, float handSpeed) {
        boolean raw;
        if (!tracked || !Float.isFinite(distance)) {
            raw = false;
        } else {
            boolean wasRaw = left ? this.rawPinchL : this.rawPinchR;
            raw = wasRaw ? distance < this.pinchOff : distance < this.pinchOn;
        }
        boolean pressed = left ? this.pinchPressedL : this.pinchPressedR;
        boolean armed = left ? this.pinchArmedL : this.pinchArmedR;
        long rawSince = left ? this.pinchRawSinceL : this.pinchRawSinceR;
        long releasedSince = left ? this.pinchReleasedSinceL : this.pinchReleasedSinceR;
        long pressNs = left ? this.leftPinchPressNs : this.rightPinchPressNs;
        boolean wasRaw = left ? this.rawPinchL : this.rawPinchR;
        boolean lost = false;

        if (raw) {
            if (!wasRaw) {
                rawSince = now;
            }
            // A deliberate pinch is made with a raised hand that is NOT closed in a fist and is not
            // mid-swing; recorded accidental pinches during punches were closed-fist/fast (p50 1.9 m/s).
            boolean gripClosed = Float.isFinite(curlHand) && curlHand < PINCH_BLOCK_GRIP_CURL;
            boolean pressAllowed = handReady && !gripClosed && handSpeed < PINCH_PRESS_MAX_SPEED;
            if (pressed && !guiOpen && now - pressNs <= 250_000_000L
                && handSpeed > 2.00F) {
                // The hand immediately accelerated like a swing: the contact was incidental (the
                // recorded ATTACK session has 11 such accidental pinches). Abort without an action.
                pressed = false;
                armed = false;
                releasedSince = now;
                lost = false;
            }
            if (!pressed && armed && (pressAllowed || guiOpen) && now - rawSince >= PINCH_DEBOUNCE_NS) {
                pressed = true;
                pressNs = rawSince;
                if (left) {
                    this.leftPinchPressNs = pressNs;
                    this.pinchRaisedL = handReady;
                    this.pinchPressedThisFrameL = true;
                } else {
                    this.rightPinchPressNs = pressNs;
                    this.pinchRaisedR = handReady;
                    this.pinchPressedThisFrameR = true;
                    this.lastPinchActivityRNs = now;
                }
            }
        } else {
            if (pressed) {
                long duration = Math.max(0L, now - pressNs);
                if (left) {
                    this.pinchReleasedThisFrameL = true;
                    this.lastPinchReleaseL = now;
                } else {
                    this.pinchLastDurationR = duration;
                    this.pinchReleasedThisFrameR = true;
                    this.lastPinchReleaseR = now;
                    this.lastPinchActivityRNs = now;
                }
                pressed = false;
                armed = false;
                releasedSince = now;
                lost = !tracked;
            }
            if (!armed && releasedSince != 0L && now - releasedSince >= PINCH_ARM_NS) {
                armed = true;
            }
        }
        if (left) {
            this.rawPinchL = raw;
            this.pinchPressedL = pressed;
            this.pinchArmedL = armed;
            this.pinchRawSinceL = raw ? rawSince : 0L;
            this.pinchReleasedSinceL = releasedSince;
            if (lost) this.pinchLostL = true;
        } else {
            this.rawPinchR = raw;
            this.pinchPressedR = pressed;
            this.pinchArmedR = armed;
            this.pinchRawSinceR = raw ? rawSince : 0L;
            this.pinchReleasedSinceR = releasedSince;
            if (lost) this.pinchLostR = true;
        }
        return pressed && (handReady || guiOpen);
    }

    private void normalizeHeadBasis(float rx, float ry, float rz, float fx, float fy, float fz) {
        float rn = (float) Math.sqrt(rx * rx + ry * ry + rz * rz);
        float fn = (float) Math.sqrt(fx * fx + fy * fy + fz * fz);
        if (!Float.isFinite(rn) || !Float.isFinite(fn) || rn < 1.0e-4F || fn < 1.0e-4F) {
            this.rightX = 1.0F; this.rightY = 0.0F; this.rightZ = 0.0F;
            this.fwdX = 0.0F; this.fwdY = 0.0F; this.fwdZ = -1.0F;
            return;
        }
        this.rightX = rx / rn; this.rightY = ry / rn; this.rightZ = rz / rn;
        this.fwdX = fx / fn; this.fwdY = fy / fn; this.fwdZ = fz / fn;
    }

    private void toHeadFrame(float[] wrist, float[] out) {
        float dx = wrist[0] - this.headX;
        float dy = wrist[1] - this.headY;
        float dz = wrist[2] - this.headZ;
        out[0] = dx * this.rightX + dy * this.rightY + dz * this.rightZ;
        // Head-up axis = right x forward (analyst-verified headMatrix convention). Using the true
        // head-up component keeps the "hands at chest height"/near-face geometry stable when the
        // operator pitches the head, and matches the Gesture Lab analysis feature frame.
        float upX = this.rightY * this.fwdZ - this.rightZ * this.fwdY;
        float upY = this.rightZ * this.fwdX - this.rightX * this.fwdZ;
        float upZ = this.rightX * this.fwdY - this.rightY * this.fwdX;
        float un = (float) Math.sqrt(upX * upX + upY * upY + upZ * upZ);
        if (un < 1.0e-4F) {
            out[1] = dy;
        } else {
            out[1] = (dx * upX + dy * upY + dz * upZ) / un;
        }
        out[2] = dx * this.fwdX + dy * this.fwdY + dz * this.fwdZ;
    }

    private void pushHistory(long now) {
        int o = this.histNext * 3;
        this.histT[this.histNext] = now;
        System.arraycopy(this.wL, 0, this.histWL, o, 3);
        System.arraycopy(this.wR, 0, this.histWR, o, 3);
        System.arraycopy(this.tipR, 0, this.histTipR, o, 3);
        System.arraycopy(this.middleR, 0, this.histMiddleR, o, 3);
        this.histHeadY[this.histNext] = this.headY;
        this.histWinSpeedR[this.histNext] = this.winSpeedRNow;
        this.histNext = (this.histNext + 1) % HIST;
        if (this.histCount < HIST) this.histCount++;
    }

    /** Index of the newest history sample at or before {@code now - windowNs}, or -1. */
    private int historySample(long windowNs) {
        long limit = this.nowNs - windowNs;
        for (int k = 0; k < this.histCount; k++) {
            int idx = (this.histNext - 1 - k + HIST) % HIST;
            if (this.histT[idx] <= limit) {
                return idx;
            }
        }
        return -1;
    }

    private float windowedSpeed(float[] hist, float[] current, long windowNs) {
        int idx = historySample(windowNs);
        if (idx < 0) return 0.0F;
        long dtNs = this.nowNs - this.histT[idx];
        if (dtNs < 1_000_000L) return 0.0F;
        int o = idx * 3;
        float dx = current[0] - hist[o];
        float dy = current[1] - hist[o + 1];
        float dz = current[2] - hist[o + 2];
        return (float) Math.sqrt(dx * dx + dy * dy + dz * dz) / (dtNs * 1.0e-9F);
    }

    private float windowedVerticalSpeed(float[] hist, float[] current, long windowNs) {
        int idx = historySample(windowNs);
        if (idx < 0) return 0.0F;
        long dtNs = this.nowNs - this.histT[idx];
        if (dtNs < 1_000_000L) return 0.0F;
        return (current[1] - hist[idx * 3 + 1]) / (dtNs * 1.0e-9F);
    }

    /** Acceleration of the windowed wrist speed over the last ~110 ms (m/s^2). */
    private float windowedAcceleration() {
        int idx = historySample(110_000_000L);
        if (idx < 0) return 0.0F;
        long dtNs = this.nowNs - this.histT[idx];
        if (dtNs < 1_000_000L) return 0.0F;
        return (this.winSpeedRNow - this.histWinSpeedR[idx]) / (dtNs * 1.0e-9F);
    }

    private float windowedHeadVelocity(long windowNs) {
        int idx = historySample(windowNs);
        if (idx < 0) return 0.0F;
        long dtNs = this.nowNs - this.histT[idx];
        if (dtNs < 1_000_000L) return 0.0F;
        return (this.headY - this.histHeadY[idx]) / (dtNs * 1.0e-9F);
    }

    private static float dist3(float ax, float ay, float az, float bx, float by, float bz) {
        float dx = ax - bx, dy = ay - by, dz = az - bz;
        return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    private static float dist(float[] a, float[] b) {
        float dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2];
        return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    private static void copyPos(float[] joints, int index, float[] out) {
        int o = index * 3;
        out[0] = joints[o]; out[1] = joints[o + 1]; out[2] = joints[o + 2];
    }

    private static float length(float[] joints, int a, int b) {
        int ao = a * 3, bo = b * 3;
        float dx = joints[ao] - joints[bo], dy = joints[ao + 1] - joints[bo + 1],
            dz = joints[ao + 2] - joints[bo + 2];
        return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    /** Curl ratio from the Gesture Lab: mean(tip->knuckle / wrist->knuckle) over four fingers. */
    private static float curl(float[] joints) {
        float sum = 0.0F;
        int[] knuckles = {INDEX_KNUCKLE, MIDDLE_KNUCKLE, RING_KNUCKLE, LITTLE_KNUCKLE};
        int[] tips = {INDEX_TIP, MIDDLE_TIP, RING_TIP, LITTLE_TIP};
        for (int i = 0; i < 4; i++) {
            float wrist = length(joints, WRIST, knuckles[i]);
            float c = length(joints, tips[i], knuckles[i]) / Math.max(0.02F, wrist);
            sum += Math.max(0.0F, Math.min(2.0F, c));
        }
        return sum * 0.25F;
    }

    // ----------------------------------------------------------------------------------------
    // Outputs
    // ----------------------------------------------------------------------------------------

    public boolean walkActive() { return this.walk; }
    public float walkForward() { return this.walk ? 1.0F : 0.0F; }
    public boolean jump() { return this.jump; }
    public boolean sneak() { return this.sneak; }
    public boolean teleportHeld() { return this.teleportHold; }
    public boolean place() { return this.place; }
    public boolean breakHeld() { return this.breakHeld; }
    public boolean attack() { return this.attack; }
    public boolean menu() { return this.menu; }
    /** Left-fist tap pulse for GUI close (world menu pulses use {@link #menu()}). */
    public boolean leftFistTap() { return this.nowNs < this.leftFistTapPulseUntilNs; }
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
    public String summary() { return this.summary; }

    /** Last update timestamp (replay-safe; no wall-clock reads in the pure engine). */
    public long lastUpdateNs() { return this.nowNs; }

    /** Host-diagnostic internals (replay harness/diagnostics only; not used by dispatch). */
    public String debugState() {
        return String.format(java.util.Locale.ROOT,
            "both=%b fist=%b/%b curl=%.2f/%.2f | walk sign=%d cross=%d dCrossMs=%d walkA=%b"
                + " | bowA=%b armed=%b sepFwd=%.3f maxUp=%.3f ageMs=%d"
                + " | pinR=%b raised=%b durMs=%d | tip=%.2f mid=%.2f wS=%.2f dRel=%d dPinch=%d"
                + " relR=%.2f/%.2f/%.2f nearH=%b burst=%b"
                + " | drop=%.3f headVel=%.2f sneak=%b blockMs=%d"
                + " | atkArmed=%b wS=%.2f wAcc=%.2f nearH=%b sneak=%b",
            this.fistL && this.fistR && this.trackedL && this.trackedR, this.fistL, this.fistR,
            this.curlL, this.curlR,
            this.swingSign, this.swingCrossings,
            this.swingLastCrossNs == 0L ? -1L : (this.nowNs - this.swingLastCrossNs) / 1_000_000L,
            this.walkActive,
            this.bowActive, this.bowSepSinceNs != 0L,
            this.relL[2] - this.relR[2], Math.max(this.relL[1], this.relR[1]),
            this.bowSepSinceNs == 0L ? -1L : (this.nowNs - this.bowSepSinceNs) / 1_000_000L,
            this.pinchPressedR, this.pinchRaisedR,
            this.rightPinchPressNs == 0L ? -1L : (this.nowNs - this.rightPinchPressNs) / 1_000_000L,
            windowedSpeed(histTipR, this.tipR, TIP_SPEED_WINDOW_NS),
            windowedSpeed(histMiddleR, this.middleR, TIP_SPEED_WINDOW_NS),
            windowedSpeed(histWR, this.wR, SPEED_WINDOW_NS),
            this.lastPinchReleaseR == 0L ? -1L : (this.nowNs - this.lastPinchReleaseR) / 1_000_000L,
            this.pinchLastDurationR / 1_000_000L,
            this.relR[0], this.relR[1], this.relR[2],
            dist3(this.wR[0], this.wR[1], this.wR[2], this.headX, this.headY, this.headZ) < EAT_OFF
                && this.relR[2] > EAT_MIN_FORWARD && this.relR[1] > EAT_MIN_UP
                && this.relR[1] < EAT_MAX_UP + 0.10F,
            this.hotbarTipAbove,
            this.headBaseline - this.headY, windowedHeadVelocity(HEAD_VEL_WINDOW_NS),
            this.sneaking,
            this.sneakBlockUntilNs == 0L ? -1L : (this.sneakBlockUntilNs - this.nowNs) / 1_000_000L,
            this.attackArmed, this.winSpeedRNow, windowedAcceleration(),
            dist3(this.wR[0], this.wR[1], this.wR[2], this.headX, this.headY, this.headZ) < EAT_OFF
                && this.relR[2] > EAT_MIN_FORWARD && this.relR[1] > EAT_MIN_UP
                && this.relR[1] < EAT_MAX_UP + 0.10F,
            this.sneaking);
    }

    /** Release every action immediately (tracking loss, stale input, mode change, destroy). */
    public void releaseAll() {
        this.trackedL = false; this.trackedR = false;
        this.fistL = false; this.fistR = false;
        this.prevFistL = false; this.prevFistR = false;
        this.rawPinchL = false; this.rawPinchR = false;
        this.pinchPressedL = false; this.pinchPressedR = false;
        this.pinchArmedL = true; this.pinchArmedR = true;
        this.pinchRawSinceL = 0L; this.pinchRawSinceR = 0L;
        this.pinchReleasedSinceL = 0L; this.pinchReleasedSinceR = 0L;
        this.pinchEngagedL = false; this.pinchEngagedR = false;
        this.pinchPrevEngagedL = false; this.pinchPrevEngagedR = false;
        this.pinchRaisedL = false; this.pinchRaisedR = false;
        this.pinchLostL = false; this.pinchLostR = false;
        this.pinchPressedThisFrameL = false; this.pinchPressedThisFrameR = false;
        this.pinchReleasedThisFrameL = false; this.pinchReleasedThisFrameR = false;
        this.lastPinchReleaseL = 0L; this.lastPinchReleaseR = 0L;
        this.leftPinchPressNs = 0L; this.rightPinchPressNs = 0L;
        this.leftFistPressNs = 0L; this.rightFistPressNs = 0L;
        this.bothFistPrev = false;
        this.bothFistStartNs = 0L;
        this.bothMaxSep = 0.0F;
        this.bothHadTrackingLoss = false;
        this.walkActive = false;
        this.swingSign = 0;
        this.swingCrossings = 0;
        this.swingPeak = 0.0F;
        this.swingLastCrossNs = 0L;
        this.swingMotionNs = 0L;
        this.lastBothTrueNs = 0L;
        this.lastBothTrackedNs = 0L;
        this.lastWalkNs = 0L;
        this.lastPinchActivityRNs = 0L;
        this.lastAttackFireNs = 0L;
        this.bowActive = false;
        this.bowSepSinceNs = 0L;
        this.bowStartNs = 0L;
        this.lastBowExitNs = 0L;
        this.eatLatched = false;
        this.eatNearSinceNs = 0L;
        this.eatLastHoldNs = 0L;
        this.attackUntilNs = 0L;
        this.attackPulseUntilNs = 0L;
        this.lastFistRTrueNs = 0L;
        this.attackArmed = true;
        this.winSpeedRNow = 0.0F;
        this.hotbarLastNs = 0L;
        this.hotbarNextPulseUntilNs = 0L;
        this.hotbarPrevPulseUntilNs = 0L;
        this.hotbarPendingNextNs = 0L;
        this.hotbarActivityNs = 0L;
        this.hotbarDoubleLockUntilNs = 0L;
        this.hotbarTipAbove = false;
        this.hotbarTipBurstNs = 0L;
        this.placePulseUntilNs = 0L;
        this.breakHeld = false;
        this.inventoryPulseUntilNs = 0L;
        this.menuPulseUntilNs = 0L;
        this.leftFistTapPulseUntilNs = 0L;
        this.jumpPulseUntilNs = 0L;
        this.guiClickPulseUntilNs = 0L;
        this.climbJumpPulseUntilNs = 0L;
        this.teleportHold = false;
        this.eatHeld = false;
        this.climbGrabL = false; this.climbGrabR = false;
        this.climbLatchedL = false; this.climbLatchedR = false;
        this.climbDownLNs = 0L; this.climbDownRNs = 0L;
        this.jump = false; this.sneak = false; this.place = false; this.attack = false;
        this.menu = false; this.inventory = false; this.hotbarNext = false; this.hotbarPrev = false;
        this.bowDraw = false; this.bowFire = false; this.guiClick = false; this.eat = false;
        this.climbJump = false; this.walk = false;
        this.sneaking = false;
        this.headSneakSinceNs = 0L;
        this.headSneakReleaseSinceNs = 0L;
        this.headJumpUntilNs = 0L;
        this.sneakBlockUntilNs = 0L;
        this.histCount = 0;
        this.histNext = 0;
        this.prevNs = 0L;
        this.nowNs = 0L;
        this.headBaseline = 0.0F;
        this.summary = "M7 released";
    }

    private String buildSummary(boolean gui, boolean seated) {
        StringBuilder b = this.summaryBuilder;
        b.setLength(0);
        b.append("M7 gui=").append(gui).append(" seated=").append(seated)
            .append(" track=").append(this.trackedL ? 'L' : '-').append(this.trackedR ? 'R' : '-')
            .append(" ctx=").append(Integer.toHexString(this.context))
            .append(" curl=").append(String.format(java.util.Locale.ROOT, "%.2f/%.2f", this.curlL, this.curlR))
            .append(" walk=").append(this.walk ? 1 : 0)
            .append(" place=").append(this.place ? 1 : 0)
            .append(" break=").append(this.breakHeld ? 1 : 0)
            .append(" attack=").append(this.attack ? 1 : 0)
            .append(" inv=").append(this.inventory ? 1 : 0)
            .append(" menu=").append(this.menu ? 1 : 0)
            .append(" tele=").append(this.teleportHold ? 1 : 0)
            .append(" bow=").append(this.bowDraw ? 1 : 0)
            .append(" eat=").append(this.eat ? 1 : 0)
            .append(" climb=").append(this.climbGrabL ? 'L' : '-').append(this.climbGrabR ? 'R' : '-');
        return b.toString();
    }
}
