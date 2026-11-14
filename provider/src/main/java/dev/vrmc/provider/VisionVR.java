package dev.vrmc.provider;

import dev.vrmc.provider.bridge.VrmcBridge;
import net.minecraft.client.KeyMapping;
import net.minecraft.core.Vec3i;
import net.minecraft.world.entity.Entity;
import net.minecraft.client.Minecraft;
import org.joml.Vector2ic;
import org.joml.Matrix4f;
import org.joml.Matrix4fc;
import org.joml.Quaternionf;
import org.joml.Vector2f;
import org.joml.Vector2fc;
import org.joml.Vector3f;
import org.vivecraft.client.VivecraftVRMod;
import org.vivecraft.client_vr.ClientDataHolderVR;
import org.vivecraft.client_vr.VRState;
import org.vivecraft.client_vr.gameplay.screenhandlers.GuiHandler;
import org.vivecraft.client_vr.settings.AutoCalibration;
import org.vivecraft.client_vr.settings.VRSettings;
import org.vivecraft.client_vr.gameplay.screenhandlers.KeyboardHandler;
import org.vivecraft.client_vr.gameplay.screenhandlers.RadialHandler;
import org.vivecraft.client_vr.provider.ControllerType;
import org.vivecraft.client_vr.provider.MCVR;
import org.vivecraft.client_vr.provider.InputSimulator;
import org.vivecraft.client_vr.extensions.WindowExtension;
import org.vivecraft.client_vr.provider.VRRenderer;
import org.vivecraft.client_vr.provider.nullvr.NullVRHapticScheduler;
import org.vivecraft.client_vr.provider.openvr_lwjgl.VRInputAction;

import java.io.File;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;

/**
 * VRMC's Vivecraft provider for visionOS (M2 + M4-W1 immersive input).
 *
 * The provider is substituted for MCOpenVR by VRStateMixin (S3/EV-0006/0009) and talks to the native
 * VRMC bridge through the versioned ABI v3 (bridge/abi/vrmc_abi.h). It fails closed: if the bridge
 * cannot be loaded/initialised or the ABI version mismatches, init() returns false and Vivecraft shows
 * the failure instead of silently rendering without tracking.
 *
 * <p>M4-W1 adds the input path that makes the game controllable from the immersive scene: the
 * compositor publishes ARKit hand tracking (ABI v3 {@code vrmc_input_state}), {@link VisionInput}
 * turns the 27 joints into pinch/fist gestures, {@link VisionHandPose} derives the two controller
 * poses from the joints, and {@link #processInputs()} writes/dispatches Vivecraft's VRInputActions.
 * Vivecraft itself stays unmodified; the one hard-coded OpenVR check in
 * {@code VRInputAction.isEnabled()} is replaced by VRInputActionMixin only while this provider is the
 * active backend.
 */
public class VisionVR extends MCVR implements VisionQuickMenuScreen.Host {
    private static final int TRACKING_BYTES = VrmcBridge.TRACKING_BYTES;
    /** Host harness only: no real controllers exist, so identity component transforms are correct. */
    private static final Matrix4f IDENTITY = new Matrix4f();
    private static final boolean HOST_HARNESS = Boolean.getBoolean("vrmc.hostHarness");
    /** GLFW_MOUSE_BUTTON_LEFT; kept as a literal because the provider compiler classpath does not
     * expose LWJGL's GLFW class (InputSimulator owns the actual mouse calls). */
    private static final int MOUSE_BUTTON_LEFT = 0;
    private final ByteBuffer tracking = ByteBuffer.allocateDirect(TRACKING_BYTES).order(ByteOrder.nativeOrder());
    private final ByteBuffer displayViews = ByteBuffer.allocateDirect(VrmcBridge.DISPLAY_VIEWS_BYTES).order(ByteOrder.nativeOrder());
    /** M4-W2 gaze mailbox (tile id + phase/kind + grid dims), polled once per frame. */
    private final ByteBuffer gazeEvent = ByteBuffer.allocateDirect(VrmcBridge.GAZE_EVENT_BYTES).order(ByteOrder.nativeOrder());
    /** Latest display-view tangents per eye (0 left, 1 right) for gaze ray reconstruction. */
    private final float[][] displayTangents = new float[2][4];
    private final float[] displayMatrixScratch = new float[16];
    private final Vector2f locomotionAxes = new Vector2f();
    private long gazeClickReleaseAtNs;
    private long gazeSuppressUntilNs;
    private boolean gazeNoPlaneLogged;
    private int gazeActivationLogCount;
    /** ONE preallocated input snapshot buffer, polled every frame (design §5.1: no per-frame allocation). */
    private final ByteBuffer input = ByteBuffer.allocateDirect(VrmcBridge.INPUT_BYTES).order(ByteOrder.nativeOrder());
    private long displayViewsGen = -1;
    private int displayViewsApplied;
    private final Quaternionf rot = new Quaternionf();
    private boolean bridgeReady;
    /** Native input entry point failed to resolve/execute: fail safe (untracked), never crash mid-frame. */
    private boolean inputChannelBroken;
    private boolean inputPollErrorLogged;
    private boolean firstSnapshotLogged;
    private boolean staleWarned;
    private boolean seatedWarned;
    private boolean registeredHandDataInvalid;
    /** Default until the compositor reports the measured eye distance (NullVR's 0.1 m is far too wide). */
    private float ipd = 0.064F;
    private int trackedFrames;

    /** M4-W1 gesture engine (pure Java, host-tested) and its resolved Vivecraft action table. */
    private VisionInput visionInput;
    /** M4-W2 One-Euro hand-pose smoothers, indexed by controller (0 = right, 1 = left). */
    private VisionPoseSmoother[] poseSmoothers;
    private VisionPoseSmoother.Config smoothingConfig;
    // M4-W3 locomotion tuning + snap-turn pulse state.
    private float moveOriginZ = VisionLocomotion.DEFAULT_ORIGIN_Z;
    private float moveForwardScale = VisionLocomotion.DEFAULT_FORWARD_SCALE;
    private float moveStrafeScale = VisionLocomotion.DEFAULT_STRAFE_SCALE;
    private float moveDeadzone = VisionLocomotion.DEFAULT_DEADZONE;
    /** M5 opt-in runtime/comfort/performance settings (vrmc-runtime.properties); nothing applied absent file. */
    private VisionRuntimeSettings runtimeSettings = VisionRuntimeSettings.defaults();
    private long diagWindowStartNs;
    private long diagWindowFrames;
    private long diagLastPollNs;
    private long diagMaxGapNs;
    private long diagNextLogNs;
    private long nextCommandPollNs;
    // M4-W4 direct hotbar wheel (both ring pinches + left-hand horizontal displacement).
    private Map<String, String> inputTuning = Map.of();
    /** Experimental M4 visual polish: attach the tip component to the index fingertip (default identity). */
    private boolean handComponentJoints;
    /** M5 seated parity: allow the HMD-aim fallback to drive the controller/GUI pointer when seated. */
    private boolean seatedHmdPointer;
    private final Matrix4f[] tipComponent = {new Matrix4f(), new Matrix4f()};
    // M4 tracking-dropout hardening: hold the last valid hand pose briefly instead of snapping to the
    // shoulder fallback. Actions are still released (controllerTracking stays false).
    private final Matrix4f[] lastTrackedPose = {new Matrix4f(), new Matrix4f()};
    private final long[] lastTrackedNs = new long[2];
    private final long[] lastHoldLogNs = new long[2];
    private long holdLastPoseNanos = 250_000_000L;
    private final Vector3f tipOffsetTmp = new Vector3f();
    private float hotbarRange = VisionHotbarWheel.DEFAULT_HALF_RANGE_METRES;
    private boolean hotbarWheelActive;
    private float hotbarWheelStartX;
    private int hotbarWheelSelected;
    private String lastThermalState = "";
    private long nextThermalPollNs;
    private float lastFrameP50Ms;
    private float lastFrameP95Ms;
    private int lastMissed90Frames;
    private String thermalResponse = "notify";
    private boolean adaptiveFramerate;
    private int adaptivePressureWindows;
    private boolean adaptiveApplied;
    // Originals captured before thermal/adaptive quality caps so the user can restore them.
    private int preReductionRender = -1;
    private int preReductionSim = -1;
    private int preReductionFps = -1;
    private boolean statusAutoWritePending = true;
    private final VisionHandCalibration handCalibration = new VisionHandCalibration();
    private boolean handCalibrationActive;
    private long handCalibrationStartNs;
    private int handCalibrationLastPhase = -1;
    private boolean thermalReductionApplied;
    private final VisionFrameStats frameStats = new VisionFrameStats(900);
    private long rotatePulseNanos = 120_000_000L;
    private long rotatePulseUntilNs;
    private int rotatePulseDirection;
    private int lastSwipeDirection = VisionInput.SWIPE_NONE;
    private VRInputAction[] bindingActions;
    private boolean m7Mode;
    private VisionM7Gesture m7Gesture = new VisionM7Gesture();
    /** Scratch pose vectors for the gesture engine's head frame (allocated once). */
    private final Vector3f m7HeadForward = new Vector3f();
    private final Vector3f m7HeadRight = new Vector3f();
    private boolean m7ContextAuto = true;
    /** Item-context probe result throttled to a few Hz (held item changes are not fast). */
    private int m7ItemContextFrame;
    private int m7BowHandMask;
    private int m7ItemContextBits;
    private final Vector3f m7GuiOrigin = new Vector3f();
    private final Vector3f m7GuiDir = new Vector3f();
    private int m7GuiWarnCount;
    private long m7PlacePulseUntilNs;
    private long m7LastRightActionNs;
    private boolean m7RightPinchPrev;
    private long m7RightPinchStartNs;
    private boolean m7HeldBreak;
    private long m7ShortAttackUntilNs;
    private long m7ShortUseUntilNs;
    /** Latch for the right-fist tap: decision (use vs dismount) is made once on the tap edge. */
    private boolean m7FistTapPrev;
    private long m7FistTapUseUntilNs;
    private long m7FistTapSneakUntilNs;
    /** Right-fist radial menu (see applyM7Radial). */
    private boolean m7RadialPressed;
    private boolean m7RadialHoldModeForced;
    private boolean m7RadialSavedHoldMode = true;
    private boolean m7RadialRestorePending;
    private int m7RadialLogCount;
    private int m7RadialCursorLogCount;
    private int m7RadialCursorWarn;
    private final Vector3f m7RadialOrigin = new Vector3f();
    private final Vector3f m7RadialDir = new Vector3f();
    private java.lang.reflect.Field radialPointedR;
    private java.lang.reflect.Field radialPointedL;
    private java.lang.reflect.Field radialActiveController;
    private static final float M7_GUI_CURSOR_DOWN = 0.08F;
    /** Menu-hand gray box correction: our pose forward is -Z, while Vivecraft's gray box grows +Z. */
    private static final float M7_MENU_HAND_SHIFT_M = 0.18F;
    /** Bow model roll relative to our finger-aim hand pose (degrees around local forward). */
    private static final float M7_BOW_ROLL_DEG = 90.0F;
    /** Show/aim a main-hand bow from the left hand (tune bow.hand=right keeps the right hand). */
    private boolean m7BowLeftHand = true;
    /** Bow roll for the left hand (tune bow.roll.left, degrees) - the left hand pose is mirrored. */
    private float m7BowRollLeftDeg = M7_BOW_ROLL_DEG;
    private float m7BowRollRightDeg = M7_BOW_ROLL_DEG;
    private final VisionHandMesh[] handMeshes = {new VisionHandMesh(), new VisionHandMesh()};
    private final VisionHandMesh.Feedback[] handFeedback = {new VisionHandMesh.Feedback(),
        new VisionHandMesh.Feedback()};
    private final boolean[] handMeshShow = new boolean[2];
    private final Vector3f m7HeadRightTmp = new Vector3f();
    /** Tune hands.model=vivecraft keeps Vivecraft's own blocky arms. */
    private boolean handModelVrmc = true;
    private boolean handModelLogged;
    private long lastSoundRestartNs;
    private long soundRestartDueNs;
    private long lastPollWallNs;
    /** Selected main-hand bow drawn in the left hand (see VRArmHelperMixin). */
    private boolean m7BowLeft;
    private final Vector3f bowHandFwd = new Vector3f();
    private final org.joml.Quaternionf bowAlignRot = new org.joml.Quaternionf();
    private final Matrix4f bowAlignTmp = new Matrix4f();
    private long m7BowLeftSinceNs;
    private boolean m7BowRenderHookSeen;
    private boolean m7BowHookWarned;
    /** Height of the bow sight above the bow-hand middle knuckle (aim line passes over the fist). */
    private static final float M7_BOW_SIGHT_UP_M = 0.035F;
    private final Vector3f bowSightUp = new Vector3f();
    private boolean bowViewOverride;
    private boolean savedShowPlayerHands = true;
    private boolean savedCrosshairOcclusion = true;
    private int bowViewWarnCount;
    private int m7GuiCursorLogCount;
    /** GUI-cursor session state: center once when a screen opens, then head-ray tracking. */
    private boolean m7GuiScreenOpen;
    private boolean m7GuiHadValidUv;
    private int m7GuiNullLogCount;
    private int m7GuiDebugFrameCount;
    /**
     * Empirically measured onMove coordinate scale. On this Vivecraft/visionOS build the runtime
     * MouseHandler.onMove mixin transforms the argument (observed x0.5: actual window 2560 logical px
     * vs MC screen width 1280), so a raw uv*screenWidth write lands at half position (top-left-ish)
     * and clicks miss. We calibrate with one probe write + MouseHandler read-back and divide it out.
     */
    private double m7CursorScaleX = 1.0D;
    private double m7CursorScaleY = 1.0D;
    private boolean m7CursorCalibrated;
    private int m7CursorCalibWinW = -1;
    private int m7CursorCalibWinH = -1;
    /** VR-state the probe was measured in: the onMove scale only applies while VR_RUNNING. */
    private boolean m7CursorCalibVrRunning;
    private long m7LastScreenCloseNs;
    private int m7CursorRescaleLogs;
    /**
     * A right pinch that was already held when a screen opened or closed belongs to the previous
     * context: clicking "Back to Game" must not place a block / start mining when the menu closes,
     * and a pinch held while the inventory opens must not click whatever is under the cursor. The
     * guard also owns the case where the pinch is released on the exact transition frame (R1).
     */
    private final PinchCarryGuard m7PinchCarry = new PinchCarryGuard();
    /**
     * Seated play (launcher/quick-menu "Play style: Seated"): hands keep working, head rise/drop
     * jump+sneak are off, and the middle-finger pinches take over (right tap = jump, right hold =
     * sneak, left tap / double tap = snap turn left / right). Vivecraft's own seated mode is never
     * enabled here: it is the keyboard/mouse mode and would release every hand action.
     */
    private boolean seatedPlay;
    private int invalidTrackingLogs;
    /**
     * Bow aim: while the two-hand bow gesture is drawn (and briefly after, so the release frame that
     * fires the arrow is covered) the right controller - which Vivecraft uses as the shooting hand
     * for the vanilla bow - points along the line from the back hand to the front hand.
     */
    private long bowAimUntilNs;
    private final Vector3f bowAimDir = new Vector3f(0.0F, 0.0F, -1.0F);
    private final Vector3f bowAimTmp = new Vector3f();
    private boolean bowModeLogged;
    private boolean seatedPlayJumpPrev;
    private long seatedPlayJumpUntilNs;
    /**
     * Seated snap turn: a left middle-finger single tap is deferred by the double-tap window so a
     * double tap nets ONE right turn instead of left-then-right (see {@link SeatedTurnGesture}).
     */
    private final SeatedTurnGesture seatedTurn = new SeatedTurnGesture();
    /**
     * M4 fallback snap turn uses the same deferral as the seated path (R6/R12): the engine emits the
     * single-tap pulse on the first tap of a double tap, so acting on it immediately made a double
     * tap turn left then right (net zero). A separate instance keeps the two modes independent.
     */
    private final SeatedTurnGesture m4Turn = new SeatedTurnGesture();
    private boolean vivecraftSeatedWarned;
    /** Pause-screen entry point of the in-VR quick menu (re-added after every screen re-init). */
    private Object quickMenuButton;
    private java.lang.reflect.Method addRenderableWidgetMethod;
    /** R5: transient injection failures are retried instead of permanently disabling the button. */
    private final QuickMenuInjectionRetry quickMenuInjection = new QuickMenuInjectionRetry();
    private static final int QUICK_MENU_BUTTON_WIDTH = 204;
    private static final int QUICK_MENU_BUTTON_HEIGHT = 20;
    /** M7 GUI click edge state: dispatched directly through vanilla MouseHandler (not the VR binding). */
    private boolean m7GuiClickPressed;
    private int m7GuiClickLogCount;
    // Direct touch-hotbar: touch/tap the rendered HUD hotbar bar with the right index fingertip to
    // select that slot (replaces asking the operator to cycle with index taps when the bar is at hand).
    private static final float M7_TOUCH_HOTBAR_MAX_DIST = 0.06F;
    private static final float M7_TOUCH_HOTBAR_MAX_DRIFT = 0.03F;
    private static final long M7_TOUCH_HOTBAR_DWELL_NS = 60_000_000L;
    private static final long M7_TOUCH_HOTBAR_COOLDOWN_NS = 300_000_000L;
    private final Vector3f m7HotbarStart = new Vector3f();
    private final Vector3f m7HotbarLine = new Vector3f();
    private final Vector3f m7HotbarDelta = new Vector3f();
    private final Vector3f m7HotbarCross = new Vector3f();
    private final Vector3f m7HotbarTip = new Vector3f();
    private final Vector3f m7HotbarDwellStart = new Vector3f();
    private int m7TouchHotbarSlot = -1;
    private long m7TouchHotbarSinceNs;
    private long m7TouchHotbarLastSelectNs;
    private int m7TouchHotbarLogCount;
    private boolean m7TouchHotbarArmedLogged;
    private int m7TouchHotbarWarnCount;
    // M7 movement: left thumb-middle pinch hold + move the left hand = analog virtual stick
    // (operator request 2026-11-05: "for the movement, use left thumb to control"). This replaces the
    // both-fist alternating-swing walk dispatch; the engine's both-fist walk detector stays as an
    // internal context/suppression signal only.
    private final Vector2f m7LocomotionAxes = new Vector2f();
    private final Vector3f m7MoveForward = new Vector3f();
    private final Vector3f m7MoveRight = new Vector3f();
    private boolean m7StickOriginSet;
    private float m7StickOriginAlong;
    private float m7StickOriginRight;
    private boolean m7LocomotionEngaged;
    private long m7LocomotionLastLogNs;
    /** Reflective hotbar selection: LocalPlayer.getInventory() is @Nullable-annotated in MC 26.2 and the
     * jspecify annotation class is not on the provider compile classpath, so resolve it reflectively. */
    private java.lang.reflect.Method m7InventoryMethod;
    private java.lang.reflect.Method m7GetSelectedSlotMethod;
    private java.lang.reflect.Method m7SetSelectedSlotMethod;
    private boolean m7InventoryReflectionTried;
    /** Reflection cache for Player.isPassenger(): right-fist tap becomes dismount while riding. */
    private java.lang.reflect.Method m7IsPassengerMethod;
    private int m7InventoryReflectionWarnCount;
    private Map<VRInputAction, List<Long>> originsByAction;
    /** Pose-diagnostic pacing (first tracked pose of an episode + every ~300 tracked frames). */
    private int poseLogFrames;
    private boolean poseLoggedThisEpisode;
    /** Identity token of the action map the binding table was resolved against (VR re-entry safety). */
    private Object resolvedActionMap;
    private final boolean[] lastHandTracked = new boolean[VisionInput.HAND_COUNT];
    private final boolean[] lastPinchPressed = new boolean[VisionInput.HAND_COUNT];
    private final boolean[] lastFistPressed = new boolean[VisionInput.HAND_COUNT];
    private final boolean[] lastFistTapPressed = new boolean[VisionInput.HAND_COUNT];
    private boolean lastBothFistTapPressed;
    private int gestureLogCount;

    // ---- F12: action-level dispatch evidence (device runbook expects one line per real edge) ----
    /** Burst of action-transition lines logged per kind before switching to every-300th. */
    private static final int ACTION_LOG_BURST = 60;
    /** After the burst, log every Nth action transition of each kind. */
    private static final int ACTION_LOG_EVERY = 300;
    /** Per-binding-row (== per action+hand pair) last-logged dispatched state; preallocated at resolve. */
    private boolean[] actionLogPressed;
    /** Identity map action -> first binding row (F12 lookup; preallocated at resolve, no per-frame alloc). */
    private java.util.IdentityHashMap<VRInputAction, Integer> actionLogRows;
    private int actionPressLogCount;
    private int actionReleaseLogCount;

    public VisionVR(Minecraft mc, ClientDataHolderVR dh) {
        super(mc, dh, VivecraftVRMod.INSTANCE);
        this.initStatus = "VRMC M2: bridge not initialized";
        this.hapticScheduler = new NullVRHapticScheduler();
        System.out.println("[VRMC-M2] VisionVR constructed");
    }

    @Override
    public boolean init() {
        try {
            VrmcBridge.load();
            int abi = VrmcBridge.abiVersion();
            if (abi != VrmcBridge.ABI_VERSION) {
                this.initStatus = "VRMC bridge ABI mismatch: " + abi;
                System.out.println("[VRMC-M2] " + this.initStatus);
                return false;
            }
            int rc = VrmcBridge.init(VrmcBridge.CAPS_JSON);
            if (rc != 0) {
                this.initStatus = "vrmc_init failed rc=" + rc + ": " + VrmcBridge.lastError();
                System.out.println("[VRMC-M2] " + this.initStatus);
                return false;
            }
            // Bind the per-eye FOV submit now (zero handles are rejected without side effects) so a bridge
            // dylib from an older build fails init with UnsatisfiedLinkError instead of mid-frame.
            VrmcBridge.submitEyes(0L, 0L, 0, 0, 0, 0.0F);
            // Bind the ABI v3 input entry point during the handshake too. A bridge without it (stale dev
            // dylib) disables the input channel once and keeps rendering instead of throwing mid-frame.
            try {
                VrmcBridge.pollInput(this.input);
            } catch (Throwable t) {
                this.inputChannelBroken = true;
                System.out.println("[VRMC-M4][WARN] nativePollInput unavailable (" + t
                    + "); immersive input disabled, treated as no hands (rendering continues)");
            }
            this.bridgeReady = true;
            this.initStatus = "VRMC bridge ABI v3";
            System.out.println("[VRMC-M2] bridge handshake ok (ABI " + abi + ")");
            System.out.println("[VRMC-M4] input channel ready (caps " + VrmcBridge.CAPS_JSON + ")");
        } catch (Throwable t) {
            this.initStatus = "VRMC bridge load failed: " + t;
            System.out.println("[VRMC-M2] " + this.initStatus);
            return false;
        }

        // Identity pose until tracking arrives (matches NullVR/RemoteVR shape).
        this.headIsTracking = true;
        this.hmdPose.identity();
        this.hmdPose.m31(1.62F);
        float ipdHalf = this.ipd * 0.5F;
        this.hmdPoseLeftEye.identity().m30(-ipdHalf);
        this.hmdPoseRightEye.identity().m30(ipdHalf);

        this.populateInputActions();
        Map<String, String> tuning = loadInputTuning();
        this.inputTuning = tuning;
        String componentMode = System.getProperty("vrmc.hands.componentMode",
            tuning.getOrDefault("hands.componentMode", "identity"));
        this.handComponentJoints = "joints".equalsIgnoreCase(componentMode);
        this.hotbarRange = floatValue(tuning, "hotbar.range", "vrmc.input.hotbar.range", this.hotbarRange);
        this.holdLastPoseNanos = (long) (Math.max(0.0F, Math.min(2000.0F,
            floatValue(tuning, "tracking.holdLastPoseMs", "vrmc.input.tracking.holdLastPoseMs", 250.0F)))
            * 1_000_000L);
        this.visionInput = new VisionInput(tuning);
        this.smoothingConfig = loadSmoothingConfig(tuning);
        this.moveOriginZ = floatValue(tuning, "move.originZ", "vrmc.input.move.originZ", this.moveOriginZ);
        this.moveForwardScale = floatValue(tuning, "move.forwardScale", "vrmc.input.move.forwardScale", this.moveForwardScale);
        this.moveStrafeScale = floatValue(tuning, "move.strafeScale", "vrmc.input.move.strafeScale", this.moveStrafeScale);
        this.moveDeadzone = floatValue(tuning, "move.deadzone", "vrmc.input.move.deadzone", this.moveDeadzone);
        this.rotatePulseNanos = (long) (floatValue(tuning, "move.rotatePulseMs", "vrmc.input.move.rotatePulseMs",
            (float) (this.rotatePulseNanos / 1_000_000L)) * 1_000_000L);
        this.poseSmoothers = new VisionPoseSmoother[] {
            new VisionPoseSmoother(this.smoothingConfig),
            new VisionPoseSmoother(this.smoothingConfig)
        };
        this.m7Mode = gestureModeM7(tuning, System.out::println);
        this.m7Gesture = buildM7Gesture(tuning);
        logInputTuning(this.visionInput);
        logSmoothingConfig(this.smoothingConfig);
        System.out.println("[VRMC-M4] hand components: mode=" + (this.handComponentJoints ? "joints" : "identity")
            + " (hands.componentMode/-Dvrmc.hands.componentMode) holdLastPoseMs="
            + (this.holdLastPoseNanos / 1_000_000L));
        System.out.println(VisionLogFormat.locomotionLine(this.visionInput, this.hotbarRange,
            this.moveOriginZ, this.moveForwardScale, this.moveStrafeScale, this.moveDeadzone,
            this.rotatePulseNanos));
        System.out.println("[VRMC-M7] gesture mode=" + (this.m7Mode ? "m7" : "m4")
            + " (tune gesture.mode / -Dvrmc.gesture.mode; operator mapping)");
        if (this.m7Mode) {
            System.out.println("[VRMC-M7] mapping: short right pinch=place/use (attack on a mob), held right "
                + "pinch=break, right fist tap=use (mount/interact; dismount while riding), right fist hold=radial menu (point, open to choose), left pinch "
                + "hold+move=walk/strafe, left fist tap=menu/back, both-fist tap=inventory, head "
                + "rise/lower=jump/sneak (standing), right middle pinch tap/hold=jump/sneak and left "
                + "middle tap/double=snap turn (seated play), right swing=attack, hotbar touch/index "
                + "tap=slot, near-head=eat, two fists=bow (draw with the back fist, open it to shoot; the bow shows in the left hand), alternating grips=climb");
        }

        this.runtimeSettings = VisionRuntimeSettings.load(this.mc.gameDirectory, System.out::println);
        applyRuntimeSettings(this.runtimeSettings);
        long diagNow = System.nanoTime();
        this.diagWindowStartNs = diagNow;
        this.diagNextLogNs = diagNow + this.runtimeSettings.diagnosticPeriodSeconds * 1_000_000_000L;

        this.initialized = true;
        this.initSuccess = true;
        appendShutdownLog("init", "bridgeReady=" + this.bridgeReady + " abi=" + VrmcBridge.ABI_VERSION);
        writeVrState("on");
        // Do NOT write the status document here: dh.vrPlayer/trackers are still being constructed during
        // VRState.initializeVR, and tracker queries (e.g. ClimbTracker.isClimbeyClimb) NPE until vrPlayer
        // exists. statusAutoWritePending writes it on the first update after init returns.
        System.out.println("[VRMC-M2] VisionVR.init() succeeded");
        return true;
    }

    @Override
    public void destroy() {
        // VR turned off from the game (Vivecraft's VR toggle) vs the game closing: Vivecraft tears VR
        // down from exitWorldAndClose only after Minecraft.stop() cleared the running flag, while the
        // toggle runs mid-game. The launcher reads this to keep the game "running, VR off" and to
        // re-enter VR by itself when VR is turned back on (1.4.0 device report: re-enabling VR left
        // the immersive space closed, which looked like a crash).
        boolean gameExiting = this.mc == null || !this.mc.isRunning();
        writeVrState(gameExiting ? "exit" : "off");
        appendShutdownLog("destroy-start", "bridgeReady=" + this.bridgeReady
            + " displayViewsGen=" + this.displayViewsGen + " trackedFrames=" + this.trackedFrames
            + " reason=" + (gameExiting ? "game-exit" : "vr-off"));
        // Shutdown ordering (M4 follow-up, EV-0096 defect): drop the eye-texture handles BEFORE the
        // renderer/VkImages are destroyed so the compositor cannot sample a freed MTLTexture.
        try {
            VrmcBridge.signalGameStopping();
        } catch (Throwable t) {
            System.out.println("[VRMC-M4][WARN] signalGameStopping at shutdown failed: " + t);
        }
        try {
            VrmcBridge.clearEyeTextures();
        } catch (Throwable t) {
            System.out.println("[VRMC-M4][WARN] clearEyeTextures at shutdown failed: " + t);
        }
        // Leaving VR while a gesture is held must not leave a pressed key behind.
        this.releaseAllImmediately();
        this.restoreBowDrawView();
        this.closeM7RadialWithoutChoice("shutdown");
        if (this.poseSmoothers != null) {
            for (VisionPoseSmoother smoother : this.poseSmoothers) {
                smoother.reset();
            }
        }
        this.initialized = false;
        super.destroy();
        appendShutdownLog("destroy-complete", "no exception during provider teardown");
    }

    /** M5/M6 support file: current provider status snapshot (local only; user-initiated export). */
    private void writeStatusReport() {
        if (this.mc.gameDirectory == null) return;
        // M8: renderer/display state in the status document so a diagnostics pull alone can answer
        // "what eye target, display logical size, foveation/rate-map state and cadence did the session
        // see?" even if the compositor log is missing (the device checker uses it as a fallback).
        VisionRenderer statusRenderer =
            (this.dh != null && this.dh.vrRenderer instanceof VisionRenderer sr) ? sr : null;
        String renderSummary = "";
        if (statusRenderer != null) {
            VisionRenderSettings rs = statusRenderer.renderSettingsSnapshot();
            renderSummary = String.format(java.util.Locale.ROOT,
                "eyeTarget=%dx%d displayLogical=%dx%d drawable=%dx%d foveation=%d rateMaps=%d "
                    + "displayHz=%.1f target=%d(%s) scale=%.2f(%s) resizes=%d valid=%d",
                statusRenderer.renderEyeTargetWidth(), statusRenderer.renderEyeTargetHeight(),
                rs.leftLogicalWidth, rs.leftLogicalHeight, rs.drawableWidth, rs.drawableHeight,
                rs.foveationEnabled ? 1 : 0, rs.rateMapCount, rs.displayHz,
                statusRenderer.targetHzOverride(), statusRenderer.targetHzSource(),
                statusRenderer.eyeScaleValue(), statusRenderer.eyeScaleIsAuto() ? "auto" : "fixed",
                statusRenderer.eyeResizeCount(), rs.valid ? 1 : 0);
        }
        VisionStatusJson.Data data = new VisionStatusJson.Data(
            java.time.Instant.now().toString(),
            VrmcBridge.ABI_VERSION,
            this.bridgeReady,
            this.initialized,
            this.displayViewsGen,
            this.trackedFrames,
            this.dh.vrSettings.seated || this.seatedPlay,
            this.visionInput != null && this.visionInput.isInputHealthy(),
            this.visionInput != null && this.visionInput.isHandTracked(VisionInput.HAND_LEFT),
            this.visionInput != null && this.visionInput.isHandTracked(VisionInput.HAND_RIGHT),
            this.mc.player != null,
            VisionStatusJson.platformName(System.getProperty("os.name")),
            this.runtimeSettings.summary(),
            this.hotbarRange,
            this.visionInput == null ? "" : this.visionInput.tuningSummary(),
            this.lastThermalState,
            this.thermalResponse,
            this.adaptiveFramerate,
            this.adaptiveApplied,
            this.lastFrameP50Ms,
            this.lastFrameP95Ms,
            this.lastMissed90Frames,
            (this.m7Mode && this.m7Gesture.bowDraw())
                || (this.dh.vrPlayer != null && this.dh.bowTracker != null && this.mc.player != null
                    && this.dh.bowTracker.isActive(this.mc.player)),
            this.dh.vrPlayer != null && this.dh.bowTracker != null && this.dh.bowTracker.isNotched(),
            this.dh.vrPlayer == null || this.dh.bowTracker == null ? 0.0F
                : Math.max(0.0F, Math.min(1.0F, this.dh.bowTracker.getDrawPercent())),
            this.dh.vrPlayer != null && this.dh.climbTracker != null
                && this.dh.climbTracker.isGrabbingLadder(),
            this.dh.vrPlayer != null && this.dh.climbTracker != null && this.mc.player != null
                && this.dh.climbTracker.isClimbeyClimb(),
            this.dh.vrPlayer != null && this.dh.climbTracker != null && this.mc.player != null
                && this.dh.climbTracker.isActive(this.mc.player),
            this.m7Mode ? this.m7Gesture.summary()
                : (this.visionInput == null ? "" : this.visionInput.gestureSummary()),
            renderSummary);
        String json = VisionStatusJson.build(data, java.time.Instant.now());
        java.nio.file.Path path = this.mc.gameDirectory.toPath().resolve("vrmc-status.json");
        try {
            java.nio.file.Files.writeString(path, json,
                java.nio.file.StandardOpenOption.CREATE,
                java.nio.file.StandardOpenOption.TRUNCATE_EXISTING);
        } catch (Throwable t) {
            System.out.println("[VRMC-M5][WARN] could not write vrmc-status.json: " + t);
        }
    }

    /**
     * M6: append-only local shutdown/restart journal in the game directory. Used by the soak harness
     * to distinguish a clean quit from a JVM crash (a crash leaves no destroy-complete line) and to
     * correlate the shell/game logs. Never throws into game code.
     */
    /** Launcher hand-off: "on" after VR init, "off" when VR is turned off mid-game, "exit" on quit. */
    private void writeVrState(String state) {
        try {
            File dir = this.mc == null ? null : this.mc.gameDirectory;
            if (dir == null) return;
            Path path = dir.toPath().resolve("vrmc-vr-state.txt");
            Path tmp = dir.toPath().resolve("vrmc-vr-state.txt.tmp");
            Files.writeString(tmp, state);
            Files.move(tmp, path, java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                java.nio.file.StandardCopyOption.ATOMIC_MOVE);
        } catch (Throwable t) {
            System.out.println("[VRMC-M6][WARN] could not write vrmc-vr-state.txt: " + t);
        }
    }

    private void appendShutdownLog(String event, String detail) {
        try {
            File dir = this.mc.gameDirectory;
            if (dir == null) return;
            Path path = dir.toPath().resolve("vrmc-shutdown.log");
            String line = Instant.now() + " event=" + event + " " + detail + System.lineSeparator();
            Files.writeString(path, line, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (Throwable t) {
            System.out.println("[VRMC-M6][WARN] could not append vrmc-shutdown.log: " + t);
        }
    }

    // ------------------------------------------------------------------------------------------
    // Immersive input tuning (game-dir file + -D system properties; design §5.3)
    // ------------------------------------------------------------------------------------------

    /** Read {@code vrmc-input-tune.properties} from the game directory (missing file = defaults). */
    private Map<String, String> loadInputTuning() {
        Map<String, String> tune = new HashMap<>();
        try {
            File gameDir = this.mc.gameDirectory;
            if (gameDir == null) return tune;
            Path path = gameDir.toPath().resolve(VisionInput.TUNE_FILE);
            if (!Files.isRegularFile(path)) return tune;
            Properties props = new Properties();
            try (InputStream in = Files.newInputStream(path)) {
                props.load(in);
            }
            for (String name : props.stringPropertyNames()) {
                tune.put(name, props.getProperty(name));
            }
            System.out.println("[VRMC-M4] input tuning loaded from " + path + " (" + tune.size() + " keys)");
        } catch (Throwable t) {
            System.out.println("[VRMC-M4][WARN] could not read " + VisionInput.TUNE_FILE + ": " + t);
        }
        return tune;
    }

    /** M4-W2 smoothing tuning: game-dir properties first, then -D system properties, then defaults. */
    private static VisionPoseSmoother.Config loadSmoothingConfig(Map<String, String> tune) {
        VisionPoseSmoother.Config c = new VisionPoseSmoother.Config();
        c.enabled = boolValue(tune, "input.smooth", "vrmc.input.smooth", c.enabled);
        c.posMinCutoff = floatValue(tune, "input.smooth.posMinCutoff", "vrmc.input.smooth.posMinCutoff", c.posMinCutoff);
        c.posBeta = floatValue(tune, "input.smooth.posBeta", "vrmc.input.smooth.posBeta", c.posBeta);
        c.derivativeCutoff = floatValue(tune, "input.smooth.derivativeCutoff", "vrmc.input.smooth.derivativeCutoff", c.derivativeCutoff);
        c.rotMinCutoff = floatValue(tune, "input.smooth.rotMinCutoff", "vrmc.input.smooth.rotMinCutoff", c.rotMinCutoff);
        c.rotBeta = floatValue(tune, "input.smooth.rotBeta", "vrmc.input.smooth.rotBeta", c.rotBeta);
        return c;
    }

    private static boolean boolValue(Map<String, String> tune, String tuneKey, String propKey, boolean def) {
        String v = tune.get(tuneKey);
        if (v == null) v = System.getProperty(propKey);
        if (v == null) return def;
        return "true".equalsIgnoreCase(v.trim()) || "1".equals(v.trim());
    }

    private static float floatValue(Map<String, String> tune, String tuneKey, String propKey, float def) {
        String v = tune.get(tuneKey);
        if (v == null) v = System.getProperty(propKey);
        if (v == null) return def;
        try {
            float f = Float.parseFloat(v.trim());
            return Float.isFinite(f) ? f : def;
        } catch (NumberFormatException e) {
            System.out.println("[VRMC-M4][WARN] invalid smoothing value " + v + " for " + tuneKey + "; using " + def);
            return def;
        }
    }

    /** Apply the opt-in M5 settings; every field is guarded by an explicit presence flag. */
    private void applyRuntimeSettings(VisionRuntimeSettings settings) {
        if (this.m7Mode && this.mc != null) {
            try {
                // The operator wants one-block step-up without a dedicated jump gesture; head-rise
                // jump remains available for deliberate jumps.
                this.mc.options.autoJump().set(true);
            } catch (Throwable t) {
                System.out.println("[VRMC-M7][WARN] could not enable autoJump: " + t);
            }
        }
        applyBowMode();
        if (settings == null) return;
        if (settings.hasSeated) setSeatedPlayInternal(settings.seated, "settings");
        if (settings.hasSeatedFreeMove) this.dh.vrSettings.seatedFreeMove = settings.seatedFreeMove;
        if (settings.hasSeatedUseHMD) this.dh.vrSettings.seatedUseHMD = settings.seatedUseHMD;
        if (settings.hasSeatedHmdPointer) this.seatedHmdPointer = settings.seatedHmdPointer;
        if (settings.hasWorldRotationIncrement) this.dh.vrSettings.worldRotationIncrement = settings.worldRotationIncrement;
        if (settings.hasWorldScale) this.dh.vrSettings.worldScale = settings.worldScale;
        if (settings.hasManualHeight) this.dh.vrSettings.manualCalibration = settings.manualHeight;
        if (settings.hasRenderDistance) this.mc.options.renderDistance().set(settings.renderDistance);
        if (settings.hasSimulationDistance) this.mc.options.simulationDistance().set(settings.simulationDistance);
        if (settings.hasFramerateLimit) this.mc.options.framerateLimit().set(settings.framerateLimit);
        if (settings.hasVsync) this.mc.options.enableVsync().set(settings.vsync);
        this.thermalResponse = settings.thermalResponse;
        this.adaptiveFramerate = settings.adaptiveFramerate;
        if (settings.hasAutoSprint) this.dh.vrSettings.autoSprint = settings.autoSprint;
        if (settings.hasAutoSprintThreshold) this.dh.vrSettings.autoSprintThreshold = settings.autoSprintThreshold;
        System.out.println("[VRMC-M5] runtime settings: " + settings.summary());
        System.out.println("[VRMC-M5] diagnostics: periodSeconds=" + settings.diagnosticPeriodSeconds);
    }

    /** M5 thermal awareness: surface shell thermal pressure in-game once per state change. */
    private void pollThermalState() {
        // Avoid per-frame filesystem I/O: the shell writes this file at thermal-change/30 s cadence.
        long nowNs = System.nanoTime();
        if (nowNs < this.nextThermalPollNs) return;
        this.nextThermalPollNs = nowNs + 5_000_000_000L;
        java.nio.file.Path dir = this.mc.gameDirectory == null ? null : this.mc.gameDirectory.toPath();
        String state = VisionThermalState.readState(dir);
        if (state.equals(this.lastThermalState)) return;
        this.lastThermalState = state;
        String advisory = VisionThermalState.advisory(state);
        if (advisory != null) {
            System.out.println("[VRMC-M5] thermal state=" + state + " -> " + advisory);
            if ("reduce".equals(this.thermalResponse) && !this.thermalReductionApplied) {
                applyThermalReduction(state);
            } else {
                showGameMessage(advisory);
            }
        } else {
            System.out.println("[VRMC-M5] thermal state=" + state);
            this.thermalReductionApplied = false;
        }
    }

    /** Recreate the gesture engine + all input-derived config from the current tune file. */
    private String reloadInputTuning() {
        Map<String, String> tuned = loadInputTuning();
        this.inputTuning = tuned;
        this.bowModeLogged = false;
        applyBowMode();
        this.hotbarRange = floatValue(tuned, "hotbar.range", "vrmc.input.hotbar.range", this.hotbarRange);
        this.holdLastPoseNanos = (long) (Math.max(0.0F, Math.min(2000.0F,
            floatValue(tuned, "tracking.holdLastPoseMs", "vrmc.input.tracking.holdLastPoseMs",
                (float) (this.holdLastPoseNanos / 1_000_000L)))) * 1_000_000L);
        String mode = System.getProperty("vrmc.hands.componentMode",
            tuned.getOrDefault("hands.componentMode", "identity"));
        this.handComponentJoints = "joints".equalsIgnoreCase(mode);
        this.visionInput = new VisionInput(tuned);
        this.smoothingConfig = loadSmoothingConfig(tuned);
        this.poseSmoothers = new VisionPoseSmoother[] {
            new VisionPoseSmoother(this.smoothingConfig),
            new VisionPoseSmoother(this.smoothingConfig)
        };
        this.moveOriginZ = floatValue(tuned, "move.originZ", "vrmc.input.move.originZ", this.moveOriginZ);
        this.moveForwardScale = floatValue(tuned, "move.forwardScale", "vrmc.input.move.forwardScale", this.moveForwardScale);
        this.moveStrafeScale = floatValue(tuned, "move.strafeScale", "vrmc.input.move.strafeScale", this.moveStrafeScale);
        this.moveDeadzone = floatValue(tuned, "move.deadzone", "vrmc.input.move.deadzone", this.moveDeadzone);
        this.rotatePulseNanos = (long) (floatValue(tuned, "move.rotatePulseMs",
            "vrmc.input.move.rotatePulseMs", (float) (this.rotatePulseNanos / 1_000_000L)) * 1_000_000L);
        this.bindingActions = null;
        this.resolvedActionMap = null;
        this.hotbarWheelActive = false;
        this.m4Turn.reset();
        this.m7Mode = gestureModeM7(tuned, System.out::println);
        this.m7Gesture = buildM7Gesture(tuned);
        logInputTuning(this.visionInput);
        logSmoothingConfig(this.smoothingConfig);
        return "input tuning reloaded (middle=" + this.visionInput.middleEnabled()
            + " ring=" + this.visionInput.ringEnabled()
            + " swipe=" + this.visionInput.swipeEnabled()
            + " hold=" + (this.holdLastPoseNanos / 1_000_000L) + "ms"
            + " move=" + this.moveForwardScale + "/" + this.moveStrafeScale
            + " components=" + (this.handComponentJoints ? "joints" : "identity") + ")";
    }

    private void startHandCalibration() {
        long now = System.nanoTime();
        this.handCalibration.begin(now);
        this.handCalibrationStartNs = now;
        this.handCalibrationLastPhase = -1;
        this.handCalibrationActive = true;
        System.out.println("[VRMC-M4] hand calibration started (open/fist/pinch, 9 s)");
    }

    /** Guided W5 calibration: prompt 3 phases, sample tracked hands, then save an advisory report. */
    private void updateHandCalibration() {
        if (!this.handCalibrationActive) return;
        long now = System.nanoTime();
        int phase = this.handCalibration.phaseAt(now);
        if (phase != this.handCalibrationLastPhase) {
            this.handCalibrationLastPhase = phase;
            showGameMessage(VisionHandCalibration.promptFor(phase));
            System.out.println("[VRMC-M4] hand calibration phase=" + phase);
        }
        if (phase == VisionHandCalibration.PHASE_DONE) {
            String report = this.handCalibration.report(now);
            System.out.println(report);
            try {
                if (this.mc.gameDirectory != null) {
                    java.nio.file.Files.writeString(
                        this.mc.gameDirectory.toPath().resolve("vrmc-hand-calibration.txt"), report);
                }
            } catch (Throwable t) {
                System.out.println("[VRMC-M4][WARN] could not write hand calibration report: " + t);
            }
            String suggestion = "n/a";
            for (String line : report.split("\n")) {
                if (line.startsWith("oneLine ")) suggestion = line.substring("oneLine ".length()).trim();
            }
            showGameMessage("[VRMC] hand calibration done: " + suggestion);
            if (this.mc.gameDirectory != null) {
                VisionCommandFile.appendResult(this.mc.gameDirectory.toPath(), "calibrate-hands",
                    "done " + suggestion, System.out::println);
            }
            this.handCalibrationActive = false;
            return;
        }
        for (int hand = 0; hand < VisionInput.HAND_COUNT; hand++) {
            if (this.visionInput != null && this.visionInput.isHandTracked(hand)) {
                this.handCalibration.record(phase, this.visionInput.pinchDistance(hand),
                    this.visionInput.fistRatio(hand));
            }
        }
    }

    /** Restore the settings captured by thermal/adaptive quality caps (explicit user command). */
    private String restorePerformanceReductions() {
        StringBuilder restored = new StringBuilder();
        try {
            if (this.preReductionRender >= 0) {
                this.mc.options.renderDistance().set(this.preReductionRender);
                restored.append("render=").append(this.preReductionRender).append(' ');
                this.preReductionRender = -1;
            }
            if (this.preReductionSim >= 0) {
                this.mc.options.simulationDistance().set(this.preReductionSim);
                restored.append("sim=").append(this.preReductionSim).append(' ');
                this.preReductionSim = -1;
            }
            if (this.preReductionFps >= 0) {
                this.mc.options.framerateLimit().set(this.preReductionFps);
                restored.append("fps=").append(this.preReductionFps).append(' ');
                this.preReductionFps = -1;
            }
        } catch (Throwable t) {
            return "restore-performance failed: " + t;
        }
        this.thermalReductionApplied = false;
        this.adaptiveApplied = false;
        this.adaptivePressureWindows = 0;
        if (restored.length() == 0) return "nothing to restore";
        String detail = "restored " + restored.toString().trim();
        System.out.println("[VRMC-M5] " + detail);
        showGameMessage("[VRMC] " + detail);
        return detail;
    }

    /**
     * Opt-in M5 thermal protection: cap render distance/simulation distance and frame limit once when
     * shell thermal state becomes serious/critical. Never auto-restores (avoids oscillation); the user
     * can raise values in the launcher after cooling.
     */
    private void applyThermalReduction(String state) {
        this.thermalReductionApplied = true;
        try {
            int render = this.mc.options.renderDistance().get();
            int sim = this.mc.options.simulationDistance().get();
            int fps = this.mc.options.framerateLimit().get();
            if (this.preReductionRender < 0) this.preReductionRender = render;
            if (this.preReductionSim < 0) this.preReductionSim = sim;
            if (this.preReductionFps < 0) this.preReductionFps = fps;
            int newRender = Math.min(render, 8);
            int newSim = Math.min(sim, 8);
            int newFps = Math.min(fps, 72);
            if (newRender != render) this.mc.options.renderDistance().set(newRender);
            if (newSim != sim) this.mc.options.simulationDistance().set(newSim);
            if (newFps != fps) this.mc.options.framerateLimit().set(newFps);
            String detail = "render " + render + "->" + newRender + ", sim " + sim + "->" + newSim
                + ", fps " + fps + "->" + newFps;
            System.out.println("[VRMC-M5] thermal protection (" + state + "): " + detail);
            showGameMessage("[VRMC] thermal protection: " + detail + " (raise later in launcher)");
        } catch (Throwable t) {
            System.out.println("[VRMC-M5][WARN] thermal reduction failed: " + t);
        }
    }

    /**
     * Restart Minecraft's sound engine (re-opens the OpenAL device). Device log 1.3.8: after the
     * headset slept, visionOS interrupted audio; the launcher re-activated the audio session
     * ("[Audio] interruption ended") but OpenAL's stopped CoreAudio output never restarted, so the
     * game stayed muted. A reload builds a new output on the re-activated session. Debounced.
     */
    private boolean restartSoundEngine(String reason) {
        long now = System.nanoTime();
        if (this.lastSoundRestartNs != 0L && now - this.lastSoundRestartNs < 5_000_000_000L) return false;
        this.lastSoundRestartNs = now;
        this.soundRestartDueNs = 0L;
        try {
            this.mc.getSoundManager().reload();
            System.out.println("[VRMC-M5] audio: sound engine restarted (" + reason + ")");
            return true;
        } catch (Throwable t) {
            System.out.println("[VRMC-M5][WARN] audio: sound engine restart failed: " + t);
            return false;
        }
    }

    /**
     * Backstop for a missed shell signal: a multi-second stall of the frame loop is the headset
     * sleeping / the app in the background. Restart the sound engine shortly after frames resume.
     */
    private void watchAudioResume() {
        long now = System.nanoTime();
        if (this.lastPollWallNs != 0L && now - this.lastPollWallNs > 3_000_000_000L) {
            this.soundRestartDueNs = now + 1_500_000_000L;
            System.out.println("[VRMC-M5] audio: frame loop resumed after "
                + (now - this.lastPollWallNs) / 1_000_000L + " ms; sound engine restart scheduled");
        }
        this.lastPollWallNs = now;
        if (this.soundRestartDueNs != 0L && now >= this.soundRestartDueNs) {
            restartSoundEngine("frame loop resumed after a stall");
            this.soundRestartDueNs = 0L;
        }
    }

    /** M5 command file: consume at most one command every 500 ms; never throws into the frame loop. */
    private void pollCommandFile() {
        long now = System.nanoTime();
        if (now < this.nextCommandPollNs) return;
        this.nextCommandPollNs = now + 500_000_000L;
        java.nio.file.Path dir = this.mc.gameDirectory == null ? null : this.mc.gameDirectory.toPath();
        String command = VisionCommandFile.take(dir, System.out::println);
        if (command == null) return;
        String detail;
        try {
            switch (command) {
                case "recenter" -> { performRecenter(); detail = "recenter requested"; }
                case "calibrate-height" -> {
                    AutoCalibration.calibrateManual();
                    this.m7Gesture.resetHeadBaseline();
                    detail = "manual height calibration performed";
                }
                case "quick-menu" -> {
                    this.mc.gui.setScreen(new VisionQuickMenuScreen(this, this.mc.gui.screen()));
                    detail = "quick menu opened";
                }
                case "audio-reset" -> {
                    detail = restartSoundEngine("shell: app active again / audio interruption ended")
                        ? "sound engine restarted" : "sound engine restart skipped (debounced)";
                }
                case "reload-settings" -> {
                    this.runtimeSettings = VisionRuntimeSettings.load(this.mc.gameDirectory, System.out::println);
                    applyRuntimeSettings(this.runtimeSettings);
                    detail = "runtime settings reloaded and applied (play style="
                        + (this.seatedPlay ? "seated" : "standing") + ")";
                }
                case "release-input" -> {
                    this.visionInput = new VisionInput(this.inputTuning);
                    this.m7Gesture.releaseAll();
                    this.bindingActions = null;
                    this.resolvedActionMap = null;
                    this.hotbarWheelActive = false;
                    this.rotatePulseDirection = 0;
                    this.rotatePulseUntilNs = 0L;
                    this.m4Turn.reset();
                    detail = "input engine reset; held actions released (sources re-arm on fresh gestures)";
                    System.out.println("[VRMC-M4] " + detail);
                    showGameMessage("[VRMC] " + detail);
                }
                case "reload-input" -> {
                    detail = reloadInputTuning();
                }
                case "apply-hand-calibration" -> {
                    if (this.mc.gameDirectory == null) {
                        detail = "no game directory; cannot apply calibration";
                    } else {
                        String applied = VisionHandCalibration.applyReport(this.mc.gameDirectory.toPath(),
                            this.mc.gameDirectory.toPath().resolve(VisionInput.TUNE_FILE), System.out::println);
                        detail = applied + (applied.startsWith("applied") ? "; " + reloadInputTuning() : "");
                    }
                }
                case "calibrate-hands" -> {
                    startHandCalibration();
                    detail = "hand calibration started (open/fist/pinch, 9 s)";
                }
                case "restore-performance" -> {
                    detail = restorePerformanceReductions();
                }
                case "controls" -> {
                    String[] help = controlsHelpLines();
                    String[] chat = new String[help.length];
                    for (int i = 0; i < help.length; i++) chat[i] = "[VRMC] " + help[i];
                    showGameChat(chat);
                    detail = "controls summary sent to chat";
                }
                case "diag" -> {
                    this.diagNextLogNs = 0L;
                    detail = "diagnostics forced";
                }
                case "status" -> {
                    writeStatusReport();
                    detail = "bridgeReady=" + this.bridgeReady
                        + " displayViewsGen=" + this.displayViewsGen + " trackedFrames=" + this.trackedFrames
                        + " inputHealthy=" + (this.visionInput != null && this.visionInput.isInputHealthy())
                        + " statusFile=vrmc-status.json";
                }
                default -> detail = "unknown";
            }
        } catch (Throwable t) {
            detail = "FAILED: " + t;
        }
        System.out.println("[VRMC-M5] command=" + command + " -> " + detail);
        VisionCommandFile.appendResult(dir, command, detail, System.out::println);
        showGameMessage("[VRMC] " + command + ": " + detail);
    }

    /** M5 periodic diagnostics: cheap counters only; formatting happens once per period. */
    private void updateDiagnostics() {
        long now = System.nanoTime();
        if (this.diagLastPollNs != 0L) {
            long gap = now - this.diagLastPollNs;
            if (gap > this.diagMaxGapNs) this.diagMaxGapNs = gap;
            this.frameStats.record(gap);
        }
        this.diagLastPollNs = now;
        this.diagWindowFrames++;
        if (now < this.diagNextLogNs) return;
        double seconds = Math.max(1.0E-6, (now - this.diagWindowStartNs) * 1.0E-9);
        double hz = this.diagWindowFrames / seconds;
        String screen = this.mc.gui.screen() == null ? "none" : this.mc.gui.screen().getClass().getSimpleName();
        boolean hasPlayer = this.mc.player != null;
        // M8: score frame pacing against the display cadence the compositor actually measured (90 or
        // 120 Hz) instead of assuming 90 Hz, and report the renderer's state in the same line.
        VisionRenderer visionRenderer =
            (this.dh != null && this.dh.vrRenderer instanceof VisionRenderer r) ? r : null;
        VisionRenderSettings renderSettings =
            visionRenderer != null ? visionRenderer.renderSettingsSnapshot() : VisionRenderSettings.none();
        double targetMs = 1000.0 / 90.0;
        String renderDiag = "";
        if (visionRenderer != null) {
            if (renderSettings.valid && renderSettings.displayHz >= 30.0f
                && renderSettings.displayHz <= 240.0f) {
                targetMs = 1000.0 / (double) renderSettings.displayHz;
            }
            renderDiag = String.format(java.util.Locale.ROOT,
                " displayHz=%.1f foveation=%d rateMaps=%d logical=%dx%d eyeTarget=%dx%d scale=%.2f resizes=%d",
                renderSettings.displayHz, renderSettings.foveationEnabled ? 1 : 0,
                renderSettings.rateMapCount, renderSettings.leftLogicalWidth,
                renderSettings.leftLogicalHeight, visionRenderer.renderEyeTargetWidth(),
                visionRenderer.renderEyeTargetHeight(), visionRenderer.eyeScaleValue(),
                visionRenderer.eyeResizeCount());
        }
        VisionFrameStats.Snapshot fs = this.frameStats.snapshotAndReset(targetMs);
        this.lastFrameP50Ms = (float) fs.p50Ms;
        this.lastFrameP95Ms = (float) fs.p95Ms;
        this.lastMissed90Frames = fs.missed90HzFrames;
        System.out.printf("[VRMC-M5] diag: pollHz=%.1f frames=%d maxGapMs=%.1f p50Ms=%.2f p95Ms=%.2f "
                + "p95MaxMs=%.2f missed90=%d missedTarget=%d targetHz=%.0f screen=%s seated=%s "
                + "hands=L%d R%d displayViewsGen=%d trackedFrames=%d playerPresent=%d%s%n",
            hz, this.diagWindowFrames, this.diagMaxGapNs * 1.0E-6, fs.p50Ms, fs.p95Ms, fs.maxMs,
            fs.missed90HzFrames, fs.missedTargetFrames, 1000.0 / targetMs, screen,
            this.dh.vrSettings.seated,
            this.visionInput.isHandTracked(VisionInput.HAND_LEFT) ? 1 : 0,
            this.visionInput.isHandTracked(VisionInput.HAND_RIGHT) ? 1 : 0,
            this.displayViewsGen, this.trackedFrames, hasPlayer ? 1 : 0, renderDiag);
        boolean overBudget = fs.p95Ms > targetMs * 1.5
            || fs.missedTargetFrames > Math.max(2, this.diagWindowFrames / 10);
        if (overBudget) {
            System.out.printf("[VRMC-M5][WARN] frame pacing above %.0f Hz budget: p95=%.2f ms missed=%d/%d%n",
                1000.0 / targetMs, fs.p95Ms, fs.missedTargetFrames, this.diagWindowFrames);
        }
        if (this.adaptiveFramerate && !this.adaptiveApplied) {
            if (overBudget) {
                this.adaptivePressureWindows++;
                if (this.adaptivePressureWindows >= 2) {
                    this.adaptiveApplied = true;
                    try {
                        int fps = this.mc.options.framerateLimit().get();
                        if (this.preReductionFps < 0) this.preReductionFps = fps;
                        int newFps = Math.min(fps, 72);
                        if (newFps != fps) this.mc.options.framerateLimit().set(newFps);
                        System.out.println("[VRMC-M5] adaptive framerate: " + fps + " -> " + newFps
                            + " after " + this.adaptivePressureWindows + " over-budget windows");
                        showGameMessage("[VRMC] adaptive framerate: " + fps + " -> " + newFps);
                    } catch (Throwable t) {
                        System.out.println("[VRMC-M5][WARN] adaptive framerate failed: " + t);
                    }
                }
            } else {
                this.adaptivePressureWindows = 0;
            }
        }
        this.diagWindowStartNs = now;
        this.diagWindowFrames = 0;
        this.diagMaxGapNs = 0L;
        this.diagNextLogNs = now + this.runtimeSettings.diagnosticPeriodSeconds * 1_000_000_000L;
        // Keep the launcher/support status current without requiring a manual status command.
        writeStatusReport();
    }

    private static void logSmoothingConfig(VisionPoseSmoother.Config c) {
        System.out.printf("[VRMC-M4] hand smoothing: enabled=%s posMinCutoff=%.2f posBeta=%.2f dCutoff=%.2f "
                + "rotMinCutoff=%.2f rotBeta=%.2f%n",
            c.enabled, c.posMinCutoff, c.posBeta, c.derivativeCutoff, c.rotMinCutoff, c.rotBeta);
    }

    /** M7 is the product mapping; gesture.mode=m4/legacy keeps the previous M4 bindings for A/B. */
    private static boolean gestureModeM7(Map<String, String> tune, java.util.function.Consumer<String> log) {
        String v = System.getProperty("vrmc.gesture.mode");
        if (v == null || v.isBlank()) v = tune == null ? null : tune.get("gesture.mode");
        if (v == null || v.isBlank()) return true;
        String normalized = v.trim().toLowerCase(java.util.Locale.ROOT);
        boolean m7 = !normalized.equals("m4") && !normalized.equals("legacy");
        if (!m7) log.accept("[VRMC-M7] gesture.mode=m4 requested; using legacy M4 mappings");
        return m7;
    }

    /**
     * Build the M7 gesture engine from the tune file. M7 uses its own fist-ratio thresholds because
     * the M4 fist ratio uses a different (palm-relative) metric; pinch thresholds are shared with the
     * M4/calibration keys because they measure the same thumb-index distance.
     */
    private VisionM7Gesture buildM7Gesture(Map<String, String> tuning) {
        Map<String, String> tune = tuning == null ? Map.of() : tuning;
        float pinchOn = m7Float(tune, "m7.pinch.on", m7Float(tune, "pinch.on", VisionM7Gesture.PINCH_ON));
        float pinchOff = m7Float(tune, "m7.pinch.off", m7Float(tune, "pinch.off", VisionM7Gesture.PINCH_OFF));
        pinchOn = Math.max(0.005F, Math.min(0.080F, pinchOn));
        pinchOff = Math.max(pinchOn + 0.005F, Math.min(0.120F, pinchOff));
        float fistOn = Math.max(0.20F, Math.min(1.00F,
            m7Float(tune, "m7.fist.on", VisionM7Gesture.FIST_ON)));
        float fistOff = Math.max(fistOn + 0.03F, Math.min(1.20F,
            m7Float(tune, "m7.fist.off", VisionM7Gesture.FIST_OFF)));
        String context = System.getProperty("vrmc.m7.context");
        if (context == null || context.isBlank()) context = tune.getOrDefault("m7.context", "auto");
        this.m7ContextAuto = !"off".equalsIgnoreCase(context.trim());
        VisionM7Gesture gesture = new VisionM7Gesture(pinchOn, pinchOff, fistOn, fistOff,
            this.m7ContextAuto);
        System.out.printf(java.util.Locale.ROOT,
            "[VRMC-M7] engine thresholds pinch=%.3f/%.3f fist=%.2f/%.2f context=%s%n",
            pinchOn, pinchOff, fistOn, fistOff, this.m7ContextAuto ? "auto" : "off");
        return gesture;
    }

    private static float m7Float(Map<String, String> tune, String key, float def) {
        String raw = tune.get(key);
        if (raw == null || raw.isBlank()) return def;
        try {
            float v = Float.parseFloat(raw.trim());
            return Float.isFinite(v) && v > 0.0F ? v : def;
        } catch (NumberFormatException e) {
            System.out.println("[VRMC-M7][WARN] invalid tune " + key + "=" + raw + "; using " + def);
            return def;
        }
    }

    /**
     * Game-context bits for the gesture engine: GUI/seated plus the held-item contexts (bow, edible).
     * Item probes are fail-safe (a reflection/API problem degrades to "not held", never throws).
     */
    private int computeM7Context() {
        int ctx = 0;
        if (this.mc == null) return ctx;
        try {
            if (this.mc.gui.screen() != null) ctx |= VisionM7Gesture.CTX_GUI;
        } catch (Throwable ignored) {
            // GUI state unavailable: treat as world context
        }
        try {
            if (this.dh.vrSettings.seated) ctx |= VisionM7Gesture.CTX_SEATED;
        } catch (Throwable ignored) {
            // settings unavailable: keep default
        }
        if (this.seatedPlay) ctx |= VisionM7Gesture.CTX_NO_HEAD_GESTURES;
        if ((this.m7ItemContextFrame++ % 6) == 0) {
            this.m7ItemContextBits = VisionM7ItemContext.flags(this.mc.player);
            this.m7BowHandMask = VisionM7ItemContext.bowHands(this.mc.player);
        }
        if ((this.m7ItemContextBits & 1) != 0) ctx |= VisionM7Gesture.CTX_BOW_HELD;
        if ((this.m7ItemContextBits & 2) != 0) ctx |= VisionM7Gesture.CTX_EDIBLE_HELD;
        try {
            if (this.dh.vrPlayer != null && this.dh.climbTracker != null
                && this.mc.player != null
                && (this.dh.climbTracker.isGrabbingLadder()
                    || this.dh.climbTracker.isClimbeyClimb())) {
                ctx |= VisionM7Gesture.CTX_CLIMBABLE;
            }
        } catch (Throwable ignored) {
            // climb context is advisory; fall back to the geometry heuristic
        }
        return ctx;
    }

    private static void logInputTuning(VisionInput in) {
        System.out.printf("[VRMC-M4] input tuning: pinchOn=%.3f pinchOff=%.3f fistOn=%.2f fistOff=%.2f "
                + "holdMs=%d armMs=%d staleMs=%d tapFrames=%d%n",
            in.pinchOn(), in.pinchOff(), in.fistOn(), in.fistOff(),
            in.fistHoldMillis(), in.armMillis(), in.staleMillis(), in.tapFrames());
    }

    // ------------------------------------------------------------------------------------------
    // Frame loop
    // ------------------------------------------------------------------------------------------

    /** True once the compositor's display views (per-eye frustum + eye transforms) are live. */
    private boolean hasDisplayViews() {
        return this.dh.vrRenderer instanceof VisionRenderer renderer && renderer.hasDisplayViews();
    }

    /** Adopt the headset's display views (eye transforms + per-eye frustum) from the compositor. */
    private void pollDisplayViews() {
        long gen = VrmcBridge.getDisplayViews(this.displayViews);
        if (gen <= 0 || gen == this.displayViewsGen) {
            return;
        }
        this.displayViewsGen = gen;
        VisionRenderer renderer = (this.dh.vrRenderer instanceof VisionRenderer r) ? r : null;
        for (int eye = 0; eye < 2; eye++) {
            int o = eye * (4 + 16) * 4;
            float l = this.displayViews.getFloat(o);
            float r = this.displayViews.getFloat(o + 4);
            float u = this.displayViews.getFloat(o + 8);
            float d = this.displayViews.getFloat(o + 12);
            this.displayTangents[eye][0] = l;
            this.displayTangents[eye][1] = r;
            this.displayTangents[eye][2] = u;
            this.displayTangents[eye][3] = d;
            if (renderer != null) {
                renderer.setEyeFov(eye, l, r, u, d);
            }
            Matrix4f eyeToHead = eye == 0 ? this.hmdPoseLeftEye : this.hmdPoseRightEye;
            for (int k = 0; k < 16; k++) {
                this.displayMatrixScratch[k] = this.displayViews.getFloat(o + 16 + k * 4);
            }
            eyeToHead.set(this.displayMatrixScratch); // JOML column-major, same layout as the C matrix
        }
        float displayIpd = this.displayViews.getFloat(40 * 4);
        if (displayIpd > 0.0F) {
            this.ipd = displayIpd;
        }
        this.displayViewsApplied++;
        // The compositor re-publishes views nearly every frame; keep the first few + a slow cadence so
        // the log stays readable while an applied-transform change is still provable.
        if (this.displayViewsApplied <= 3 || (this.displayViewsApplied % 120) == 0) {
            System.out.printf("[VRMC-M2] display views gen=%d applied=%d ipd=%.4f Lpos=(%.4f,%.4f,%.4f) Rpos=(%.4f,%.4f,%.4f)%n",
                gen, this.displayViewsApplied, this.ipd,
                this.hmdPoseLeftEye.m30(), this.hmdPoseLeftEye.m31(), this.hmdPoseLeftEye.m32(),
                this.hmdPoseRightEye.m30(), this.hmdPoseRightEye.m31(), this.hmdPoseRightEye.m32());
        }
    }

    /**
     * Frame order (design §5.6): getTracking -> parse input + update controller poses (tracked hand
     * pose / gaze fallback) -> pollDisplayViews -> updateAim -> processInputs -> hmdSampling, exactly
     * like MCOpenVR: processInputs needs current aim poses and must run before the game's tick-time
     * processBindings.
     */
    @Override
    public void poll(long frameIndex) {
        if (!this.initialized) {
            return;
        }
        if (this.bridgeReady) {
            this.pollTracking();
            this.pollInput();
            this.pollDisplayViews();
            this.pollGazeEvents();
            this.updateAim();
            if (this.m7Mode) {
                this.updateM7GuiCursor();
                try {
                    this.updateM7TouchHotbar();
                } catch (Throwable t) {
                    // A HUD-touch failure (e.g. a runtime/GUI race) must never crash the render thread.
                    if (this.m7TouchHotbarWarnCount++ < 3) {
                        System.out.println("[VRMC-M7][WARN] touch hotbar update failed: " + t);
                    }
                }
            }
            this.processInputs();
            this.hmdSampling();
        }
        guardVivecraftSeated();
        updateQuickMenuEntry();
        watchAudioResume();
        pollCommandFile();
        pollThermalState();
        updateHandCalibration();
        if (this.statusAutoWritePending && this.mc.gameDirectory != null) {
            writeStatusReport();
            this.statusAutoWritePending = false;
        }
        updateDiagnostics();
        if (this.dh.vrRenderer instanceof VisionRenderer r) {
            r.markPolled();
        }
    }

    /** Head pose + IPD from the bridge; validates tracking data instead of silently inventing poses. */
    private void pollTracking() {
        int rc = VrmcBridge.getTracking(this.tracking);
        if (rc != 0) {
            return;
        }
        // vrmc_tracking_state: u64 presentation_time_ns, then head pose (quat xyzw + pos xyz)
        int o = 8;
        float qx = this.tracking.getFloat(o), qy = this.tracking.getFloat(o + 4);
        float qz = this.tracking.getFloat(o + 8), qw = this.tracking.getFloat(o + 12);
        float px = this.tracking.getFloat(o + 16), py = this.tracking.getFloat(o + 20), pz = this.tracking.getFloat(o + 24);
        // An invalid sample (zero/NaN quaternion, non-finite position) used to throw on the render
        // thread and crash the game. Keep the last good pose instead (never invent one), report the
        // head as not tracking for this frame, and log the first few occurrences.
        float qLen = qx * qx + qy * qy + qz * qz + qw * qw;
        boolean valid = Float.isFinite(qLen) && qLen > 1.0e-6F
            && Float.isFinite(px) && Float.isFinite(py) && Float.isFinite(pz);
        if (!valid) {
            this.headIsTracking = false;
            if (this.invalidTrackingLogs++ < 5) {
                System.out.println("[VRMC-M2][WARN] invalid head tracking sample from bridge (q=" + qx + ","
                    + qy + "," + qz + "," + qw + " p=" + px + "," + py + "," + pz + "); keeping the last pose");
            }
            return;
        }
        this.hmdPose.rotation(this.rot.set(qx, qy, qz, qw).normalize());
        this.hmdPose.setTranslation(px, py, pz);
        this.hmdRotation.rotation(this.rot);
        this.headIsTracking = true;
        float bridgeIpd = this.tracking.getFloat(8 + 84);
        if (bridgeIpd > 0.0F) {
            this.ipd = bridgeIpd;
            // The display-view channel owns the head-relative eye transforms while it is live
            // (asymmetric per-eye offsets, not just +/- IPD/2). Only fall back to the IPD-only
            // approximation before the first display views arrive; otherwise this would overwrite
            // the compositor-provided eye poses every frame (macstream applies ViewsConfig the
            // same way: pollViews() owns hmdPoseLeftEye/RightEye once a generation is live).
            if (!this.hasDisplayViews()) {
                this.hmdPoseLeftEye.identity().m30(-this.ipd * 0.5F);
                this.hmdPoseRightEye.identity().m30(this.ipd * 0.5F);
            }
        }
        if ((this.trackedFrames++ % 300) == 0) {
            System.out.printf("[VRMC-M2] tracking frame %d head=(%.2f, %.2f, %.2f)%n",
                this.trackedFrames, px, py, pz);
        }
    }

    /**
     * Poll the ABI v3 input snapshot into the preallocated buffer, run the gesture engine and derive
     * the two controller poses. Fail-safe throughout: a broken/malformed/stale channel produces
     * untracked hands (gaze fallback poses), never a crash and never a stuck press.
     */
    private void pollInput() {
        if (this.visionInput == null) {
            return;
        }
        long nowNs = System.nanoTime();
        int rc = -1;
        if (!this.inputChannelBroken) {
            try {
                rc = VrmcBridge.pollInput(this.input);
            } catch (Throwable t) {
                this.inputChannelBroken = true;
                System.out.println("[VRMC-M4][WARN] nativePollInput failed mid-frame (" + t
                    + "); immersive input disabled, treated as no hands");
            }
            if (rc != 0 && !this.inputChannelBroken && !this.inputPollErrorLogged) {
                this.inputPollErrorLogged = true;
                System.out.println("[VRMC-M4][WARN] pollInput rejected rc=" + rc + " (" + VrmcBridge.lastError()
                    + "); treating snapshot as untracked");
            }
        }
        this.visionInput.poll(this.inputChannelBroken ? null : this.input, rc, nowNs);

        if (this.m7Mode) {
            boolean trackedL = this.visionInput.isHandTracked(VisionInput.HAND_LEFT);
            boolean trackedR = this.visionInput.isHandTracked(VisionInput.HAND_RIGHT);
            boolean healthy = this.visionInput.isInputHealthy() && !this.visionInput.isStale();
            if (healthy) {
                this.m7HeadForward.set(0.0F, 0.0F, -1.0F);
                this.hmdPose.transformDirection(this.m7HeadForward);
                this.m7HeadRight.set(1.0F, 0.0F, 0.0F);
                this.hmdPose.transformDirection(this.m7HeadRight);
                this.m7Gesture.update(trackedL, this.visionInput.joints(VisionInput.HAND_LEFT),
                    trackedR, this.visionInput.joints(VisionInput.HAND_RIGHT),
                    m7IndexPinchDistance(VisionInput.HAND_LEFT),
                    m7IndexPinchDistance(VisionInput.HAND_RIGHT),
                    this.hmdPose.m30(), this.hmdPose.m31(), this.hmdPose.m32(),
                    this.m7HeadRight.x, this.m7HeadRight.y, this.m7HeadRight.z,
                    this.m7HeadForward.x, this.m7HeadForward.y, this.m7HeadForward.z,
                    nowNs, computeM7Context());
            } else {
                this.m7Gesture.releaseAll();
            }
        }

        // Tracking acquisition/loss episodes (one line each) + single-hand loss releases that hand's
        // held actions on the SAME frame (G4: never a stuck attack/teleport).
        for (int hand = 0; hand < VisionInput.HAND_COUNT; hand++) {
            boolean tracked = this.visionInput.isHandTracked(hand);
            if (tracked != this.lastHandTracked[hand]) {
                if (this.lastHandTracked[hand]) {
                    this.releaseActionsForHand(hand);
                }
                System.out.printf("[VRMC-M4] %s hand %s (frame=%d valid_mask=%d)%n",
                    hand == VisionInput.HAND_LEFT ? "left" : "right",
                    tracked ? "acquired" : "lost", this.visionInput.frameIndex(), this.visionInput.validMask());
                this.lastHandTracked[hand] = tracked;
            }
        }

        this.updateControllerPoses();
        this.updateHandMeshes();
        this.logPoseDiagnostics();
        this.logInputDiagnostics();
    }

    /**
     * Controller pose per MCVR index (RIGHT_CONTROLLER=0, LEFT_CONTROLLER=1): tracked hand pose from
     * joints, or the shoulder/gaze fallback while that hand is not tracked. controllerTracking stays
     * false for the fallback (honest signal - see design §5.2).
     */
    private void updateControllerPoses() {
        long nowNs = System.nanoTime();
        // A selected main-hand bow is drawn in the left hand with the arrow in the right hand
        // (VRArmHelperMixin, Vivecraft's own roomscale-bow presentation). Controller poses are NOT
        // swapped: the wrist hotbar stays on the left wrist and the right hand keeps aiming.
        boolean bowLeft = bowInLeftHandWanted();
        if (bowLeft && !this.m7BowRenderHookSeen && this.m7BowLeftSinceNs != 0L
            && nowNs - this.m7BowLeftSinceNs > 3_000_000_000L && !this.m7BowHookWarned) {
            this.m7BowHookWarned = true;
            System.out.println("[VRMC-M7][WARN] bow render hook (VRArmHelperMixin) did not run; the bow "
                + "stays in the right hand (Vivecraft version mismatch?)");
        }
        if (bowLeft != this.m7BowLeft) {
            this.m7BowLeft = bowLeft;
            this.m7BowLeftSinceNs = bowLeft ? nowNs : 0L;
            System.out.println("[VRMC-M7] bow hand: " + (bowLeft ? "left (bow in the left hand, arrow in "
                + "the right hand)" : "normal (item in the hand that holds it)"));
        }
        for (int hand = 0; hand < VisionInput.HAND_COUNT; hand++) {
            int c = hand == VisionInput.HAND_LEFT ? LEFT_CONTROLLER : RIGHT_CONTROLLER;
            boolean tracked = this.visionInput.isHandTracked(hand);
            if (tracked) {
                VisionHandPose.handPose(this.visionInput.joints(hand),
                    this.visionInput.wristQx(hand), this.visionInput.wristQy(hand),
                    this.visionInput.wristQz(hand), this.visionInput.wristQw(hand),
                    this.visionInput.wristX(hand), this.visionInput.wristY(hand),
                    this.visionInput.wristZ(hand), this.controllerPose[c]);
                // M4-W2: smooth the raw joint-derived pose (One-Euro translation + angle-adaptive
                // slerp orientation). Reset history whenever the hand was untracked, so reacquisition
                // never lags behind a teleporting wrist.
                if (this.poseSmoothers != null) {
                    this.poseSmoothers[c].apply(this.controllerPose[c], nowNs);
                }
                this.lastTrackedPose[c].set(this.controllerPose[c]);
                this.lastTrackedNs[hand] = nowNs;
            } else {
                if (this.poseSmoothers != null) {
                    this.poseSmoothers[c].reset();
                }
                long trackedAt = this.lastTrackedNs[hand];
                boolean held = this.holdLastPoseNanos > 0L && trackedAt != 0L
                    && nowNs - trackedAt <= this.holdLastPoseNanos;
                if (held) {
                    this.controllerPose[c].set(this.lastTrackedPose[c]);
                    if (nowNs - this.lastHoldLogNs[hand] > 2_000_000_000L) {
                        this.lastHoldLogNs[hand] = nowNs;
                        System.out.printf("[VRMC-M4] hand %s untracked: holding last pose for %d ms (actions released)%n",
                            hand == VisionInput.HAND_LEFT ? "left" : "right",
                            this.holdLastPoseNanos / 1_000_000L);
                    }
                } else {
                    VisionHandPose.gazeFallback(this.hmdPose, hand == VisionInput.HAND_RIGHT,
                        this.controllerPose[c]);
                }
            }
            // Bow grip roll is applied to the bow model only (VivecraftItemRenderingMixin): rolling
            // the controller pose also rotated the wrist hotbar hanging off the left controller.
            // Menu hands: Vivecraft's gray box grows along local +Z, but this hand pose uses
            // -Z as forward (R*(0,0,-1)=aim). Shift the menu-hand origin to the fingertip along
            // local -Z so the gray box covers the hand instead of floating behind the wrist.
            if (this.mc.gui.screen() != null) {
                this.controllerPose[c].translate(0.0F, 0.0F, -M7_MENU_HAND_SHIFT_M);
            }
            // M5 seated parity (opt-in): when seated with no tracked hand, the HMD-aim fallback pose
            // may drive the controller/GUI pointer. Input actions still require real gestures.
            this.controllerTracking[c] = tracked
                || (this.seatedHmdPointer && this.dh.vrSettings.seated);
        }
        applyBowAim(nowNs);
        alignBowToCrosshair(nowNs);
        updateBowDrawView();
    }

    /**
     * VRMC hand model (VisionHandMesh): rebuilt every frame from the tracked joints plus gesture
     * feedback; drawn by VRArmHelperMixin instead of Vivecraft's blocky first-person arms.
     */
    private void updateHandMeshes() {
        if (this.visionInput == null) return;
        this.m7HeadRightTmp.set(1.0F, 0.0F, 0.0F);
        this.hmdPose.transformDirection(this.m7HeadRightTmp);
        this.m7HeadRightTmp.y = 0.0F;
        if (this.m7HeadRightTmp.lengthSquared() < 1.0E-8F) this.m7HeadRightTmp.set(1.0F, 0.0F, 0.0F);
        this.m7HeadRightTmp.normalize();
        boolean drawing = this.m7Mode && this.m7Gesture.bowDraw();
        for (int hand = 0; hand < VisionInput.HAND_COUNT; hand++) {
            boolean right = hand == VisionInput.HAND_RIGHT;
            VisionHandMesh mesh = this.handMeshes[hand];
            this.handMeshShow[hand] = false;
            if (!this.visionInput.isHandTracked(hand)) continue;
            // While drawing the bow, the draw (back) hand sits at the cheek: do not draw it in front
            // of the eye (1.3.6 report "the hand blocks my view").
            if (drawing && right == this.m7Gesture.bowFrontIsLeft()) continue;
            VisionHandMesh.Feedback fb = this.handFeedback[hand];
            fb.clear();
            if (this.m7Mode) {
                fb.pinchProximity = VisionHandMesh.pinchProximity(this.visionInput.pinchDistance(hand),
                    VisionM7Gesture.PINCH_ON, 0.060F);
                fb.pinchHeld = right ? this.m7Gesture.rightPinchHeld() : this.m7Gesture.leftPinchHeld();
                fb.breaking = right && this.m7HeldBreak;
                fb.fist = this.m7Gesture.fist(!right);
                fb.radialProgress = right ? this.m7Gesture.radialHoldProgress() : 0.0F;
                fb.middleHeld = this.visionInput.middlePressed(hand);
            }
            this.handMeshShow[hand] = mesh.build(this.visionInput.joints(hand), right,
                this.hmdPose.m30(), this.hmdPose.m31(), this.hmdPose.m32(),
                this.m7HeadRightTmp.x, this.m7HeadRightTmp.z, fb);
        }
    }

    /** VRArmHelperMixin: the hand-model hook ran (logged once, for device evidence). */
    public void noteHandModelRendered() {
        if (!this.handModelLogged) {
            this.handModelLogged = true;
            System.out.println("[VRMC-M7] hand model: VRMC arms/hands/fingers active (tune hands.model="
                + "vivecraft restores Vivecraft's arms)");
        }
    }

    /** VRArmHelperMixin: the VRMC hand model replaces Vivecraft's first-person arms. */
    public boolean handModelEnabled() { return this.handModelVrmc && this.visionInput != null; }

    /** VRArmHelperMixin: the hand mesh to draw (room space), or null when that hand is not shown. */
    public VisionHandMesh handMesh(boolean right) {
        int hand = right ? VisionInput.HAND_RIGHT : VisionInput.HAND_LEFT;
        return this.handModelVrmc && this.handMeshShow[hand] ? this.handMeshes[hand] : null;
    }

    /** True when the selected main-hand bow should be drawn in the left hand this frame. */
    private boolean bowInLeftHandWanted() {
        if (!this.m7Mode || this.visionInput == null || !this.m7BowLeftHand) return false;
        // Main-hand bow only; a bow in the off hand already sits in the left hand.
        if ((this.m7BowHandMask & 1) == 0 || (this.m7BowHandMask & 2) != 0) return false;
        if (this.mc.gui.screen() != null) return false;
        // During a draw the front hand is the bow hand (M7_GESTURES.md #9); a right-hand-front
        // (mirrored) draw shows the bow in the right hand.
        return !(this.m7Gesture.bowDraw() && !this.m7Gesture.bowFrontIsLeft());
    }

    /**
     * While the bow is drawn, point the bow hand exactly along the shot (the crosshair ray). Device
     * feedback 1.3.8: "the bow should align with the crosshair". The bow hand (left controller) is
     * turned by the smallest rotation that maps its forward axis onto the aim direction, so the
     * operator's own wrist roll is kept; only the draw window is affected (the hotbar is not used
     * while drawing).
     */
    private void alignBowToCrosshair(long nowNs) {
        if (!this.m7BowLeft || nowNs >= this.bowAimUntilNs) return;
        Matrix4f pose = this.controllerPose[LEFT_CONTROLLER];
        pose.transformDirection(0.0F, 0.0F, -1.0F, this.bowHandFwd);
        if (this.bowHandFwd.lengthSquared() < 1.0E-8F || this.bowAimDir.lengthSquared() < 1.0E-8F) return;
        this.bowHandFwd.normalize();
        this.bowAlignRot.rotationTo(this.bowHandFwd, this.bowAimDir);
        float px = pose.m30(), py = pose.m31(), pz = pose.m32();
        pose.setTranslation(0.0F, 0.0F, 0.0F);
        this.bowAlignTmp.rotation(this.bowAlignRot).mul(pose, pose);
        pose.setTranslation(px, py, pz);
    }

    /**
     * VivecraftItemRenderingMixin: grip roll (degrees) for a bow rendered in the given hand slot, NaN
     * for anything else. Our hand pose's local +Z is the back of the hand while the vanilla bow model
     * is authored for a controller roll that lands it parallel to the fingers, so the bow is rolled
     * 90 deg around local forward to cross the hand (tunes bow.roll.left / bow.roll.right).
     */
    public float m7BowRenderRollDeg(Object stack, boolean offHandSlot) {
        if (!this.m7Mode || !VisionM7ItemContext.isBowStack(this.mc.player, stack)) return Float.NaN;
        return offHandSlot ? this.m7BowRollLeftDeg : this.m7BowRollRightDeg;
    }

    /** VRArmHelperMixin: draw the selected main-hand bow in the left hand, the arrow in the right. */
    public boolean m7BowInLeftHand() { return this.m7BowLeft; }

    /**
     * VRArmHelperMixin: the stack to draw in a hand while the bow is shown in the left hand - the bow
     * for the off (left) hand; for the main (right) hand the arrow it would shoot, or nothing while
     * drawing (the drawn bow model carries the arrow). Null = no override / nothing to show.
     */
    public Object m7BowRenderStack(boolean offHand) {
        this.m7BowRenderHookSeen = true;
        Object bow = VisionM7ItemContext.mainHandStack(this.mc.player);
        if (offHand || bow == null) return bow;
        if (this.m7Mode && this.m7Gesture.bowDraw()) return null;
        return VisionM7ItemContext.projectileFor(this.mc.player, bow);
    }


    /**
     * While the bow is drawn: hide the floating first-person hands (the draw hand sits at the cheek,
     * right in front of the eye - device report "the hand blocks my view") and draw the crosshair
     * over the bow instead of behind it (aim runs from the eye past the bow hand, so the occluded
     * crosshair was always hidden by the bow model - "there is no crosshair"). Both settings are
     * restored the moment the draw ends and are never left modified.
     */
    private void updateBowDrawView() {
        boolean drawing = this.m7Mode && this.m7Gesture.bowDraw() && this.mc.gui.screen() == null;
        if (drawing == this.bowViewOverride) return;
        try {
            if (drawing) {
                this.savedShowPlayerHands = this.dh.vrSettings.showPlayerHands;
                this.savedCrosshairOcclusion = this.dh.vrSettings.useCrosshairOcclusion;
                this.dh.vrSettings.showPlayerHands = false;
                this.dh.vrSettings.useCrosshairOcclusion = false;
            } else {
                this.dh.vrSettings.showPlayerHands = this.savedShowPlayerHands;
                this.dh.vrSettings.useCrosshairOcclusion = this.savedCrosshairOcclusion;
            }
            this.bowViewOverride = drawing;
        } catch (Throwable t) {
            if (this.bowViewWarnCount++ < 3) {
                System.out.println("[VRMC-M7][WARN] bow draw view settings unavailable: " + t);
            }
        }
    }

    /** Restore any view setting the bow draw changed (called on teardown). */
    private void restoreBowDrawView() {
        if (!this.bowViewOverride) return;
        try {
            this.dh.vrSettings.showPlayerHands = this.savedShowPlayerHands;
            this.dh.vrSettings.useCrosshairOcclusion = this.savedCrosshairOcclusion;
        } catch (Throwable ignored) {
            // settings gone during shutdown
        }
        this.bowViewOverride = false;
    }

    /**
     * M7 GUI guidance: the operator expects look-to-target + right-pinch click. Raw eye gaze is not
     * available for a rendered Minecraft GUI, so the closest controllable approximation is a head-ray
     * cursor: project the HMD forward axis onto Vivecraft's GUI plane every frame while a screen is open.
     * This does not replace the game's own GUI rendering; it only positions the existing cursor so the
     * right-pinch click lands where the operator is looking. The system-provided eye-hover remains native
     * SwiftUI only.
     */
    /** True when M7 is responsible for positioning the GUI cursor this frame. */
    public boolean m7OwnsGuiCursor() {
        return this.m7Mode && this.mc != null && this.mc.gui.screen() != null;
    }

    private void updateM7GuiCursor() {
        if (this.mc.gui.screen() == null || GuiHandler.GUI_POS_ROOM == null
            || GuiHandler.GUI_ROTATION_ROOM == null) {
            this.m7GuiScreenOpen = false;
            this.m7GuiHadValidUv = false;
            return;
        }
        if (!this.m7GuiScreenOpen) {
            // Start the cursor in the middle of the view instead of the top-left default (0,0) while
            // the head ray is still being resolved. The first valid ray projection refines it.
            this.m7GuiScreenOpen = true;
            this.m7GuiHadValidUv = false;
            this.m7GuiDebugFrameCount = 0;
            calibrateM7GuiCursorScale();
            centerM7GuiCursor();
            System.out.printf(
                "[VRMC-M7] head cursor centered on GUI open screen=%s scale=(%.3f,%.3f)%n",
                this.mc.gui.screen().getClass().getSimpleName(), this.m7CursorScaleX,
                this.m7CursorScaleY);
        }
        try {
            updateM7GuiCursorImpl();
        } catch (Throwable t) {
            // A GUI-aim failure must never crash the render thread; the next frame may succeed.
            if (this.m7GuiWarnCount++ < 3) {
                System.out.println("[VRMC-M7][WARN] GUI cursor update failed: " + t);
            }
        }
    }

    /** Put the GUI cursor in the centre of the window (used on screen-open and until the ray hits). */
    private void centerM7GuiCursor() {
        int winW = Math.max(1, this.mc.getWindow().getScreenWidth());
        int winH = Math.max(1, this.mc.getWindow().getScreenHeight());
        double tx = winW * 0.5D;
        double ty = winH * (0.5D + M7_GUI_CURSOR_DOWN);
        setM7CursorClosedLoop(tx, ty, tx / this.m7CursorScaleX, ty / this.m7CursorScaleY);
    }

    /**
     * Place the cursor so MouseHandler stores (targetX, targetY), correcting the runtime onMove scale
     * every time. The scale depends on the native game-surface size, which changes during a session
     * (window resize/parking): the old one-shot probe measured 0.60 at menu open and the real factor
     * later became 1.8, so the head-ray cursor and its clicks landed off-screen (device log
     * 2026-11-12: clicks at x=2680 on a 1280-wide screen). Set -> read back -> if off, re-measure
     * from this very pair and set again (the mapping is proportional, so one correction converges).
     */
    private void setM7CursorClosedLoop(double targetX, double targetY, double guessX, double guessY) {
        InputSimulator.setMousePos(guessX, guessY);
        double rx = this.mc.mouseHandler.xpos();
        double ry = this.mc.mouseHandler.ypos();
        boolean offX = Math.abs(rx - targetX) > 0.75D;
        boolean offY = Math.abs(ry - targetY) > 0.75D;
        if (!offX && !offY) return;
        double sx = this.m7CursorScaleX;
        double sy = this.m7CursorScaleY;
        if (offX && Math.abs(guessX) > 1.0D) {
            double m = rx / guessX;
            if (Double.isFinite(m) && m > 0.05D && m < 20.0D) sx = m;
        }
        if (offY && Math.abs(guessY) > 1.0D) {
            double m = ry / guessY;
            if (Double.isFinite(m) && m > 0.05D && m < 20.0D) sy = m;
        }
        if (Math.abs(sx - this.m7CursorScaleX) > 0.01D || Math.abs(sy - this.m7CursorScaleY) > 0.01D) {
            if (this.m7CursorRescaleLogs++ < 10) {
                System.out.printf("[VRMC-M7] cursor scale re-measured (%.3f,%.3f) -> (%.3f,%.3f) "
                        + "target=(%.1f,%.1f) readback=(%.1f,%.1f) win=(%d,%d)%n",
                    this.m7CursorScaleX, this.m7CursorScaleY, sx, sy, targetX, targetY, rx, ry,
                    this.mc.getWindow().getScreenWidth(), this.mc.getWindow().getScreenHeight());
            }
            this.m7CursorScaleX = sx;
            this.m7CursorScaleY = sy;
        }
        InputSimulator.setMousePos(targetX / this.m7CursorScaleX, targetY / this.m7CursorScaleY);
    }

    /**
     * Measure how MouseHandler transforms onMove arguments on this runtime build by writing a known
     * probe position and reading the stored value back. The provider cannot call the runtime-missing
     * WindowExtension helper (EV-0235), so calibration keeps the mapping correct across Vivecraft
     * builds/window scales. Falls back to 1.0 when the probe is not measurable.
     */
    private void calibrateM7GuiCursorScale() {
        int winW = Math.max(1, this.mc.getWindow().getScreenWidth());
        int winH = Math.max(1, this.mc.getWindow().getScreenHeight());
        boolean vrRunning = VRState.VR_RUNNING;
        if (this.m7CursorCalibrated && winW == this.m7CursorCalibWinW
            && winH == this.m7CursorCalibWinH && vrRunning == this.m7CursorCalibVrRunning) {
            return;
        }
        this.m7CursorCalibrated = false;
        double probeX = winW * 0.5D;
        double probeY = winH * 0.5D;
        try {
            InputSimulator.setMousePos(probeX, probeY);
            double readX = this.mc.mouseHandler.xpos();
            double readY = this.mc.mouseHandler.ypos();
            double sx = readX / probeX;
            double sy = readY / probeY;
            if (Double.isFinite(sx) && Double.isFinite(sy) && sx > 0.05D && sx < 20.0D
                && sy > 0.05D && sy < 20.0D) {
                this.m7CursorScaleX = sx;
                this.m7CursorScaleY = sy;
                this.m7CursorCalibrated = true;
                System.out.printf(
                    "[VRMC-M7] cursor scale probe=(%.1f,%.1f) readback=(%.1f,%.1f) scale=(%.3f,%.3f)%n",
                    probeX, probeY, readX, readY, sx, sy);
            } else {
                System.out.printf(
                    "[VRMC-M7][WARN] cursor scale probe unusable readback=(%.1f,%.1f); using 1.0%n",
                    readX, readY);
            }
        } catch (Throwable t) {
            System.out.println("[VRMC-M7][WARN] cursor scale probe failed: " + t);
        }
        this.m7CursorCalibWinW = winW;
        this.m7CursorCalibWinH = winH;
        this.m7CursorCalibVrRunning = VRState.VR_RUNNING;
    }

    private void updateM7GuiCursorImpl() {
        this.m7GuiOrigin.set(this.hmdPose.m30(), this.hmdPose.m31(), this.hmdPose.m32());
        this.m7GuiDir.set(0.0F, 0.0F, -1.0F);
        this.hmdPose.transformDirection(this.m7GuiDir);
        float aspect = (float) this.mc.getWindow().getGuiScaledHeight()
            / (float) this.mc.getWindow().getGuiScaledWidth();
        Vector2f uv = VisionGazeMath.intersectGuiPlane(this.m7GuiOrigin, this.m7GuiDir,
            GuiHandler.GUI_POS_ROOM, GuiHandler.GUI_ROTATION_ROOM, GuiHandler.GUI_SCALE, aspect);
        int winW = this.mc.getWindow().getScreenWidth();
        int winH = this.mc.getWindow().getScreenHeight();
        boolean vrRunning = VRState.VR_RUNNING;
        if (!this.m7CursorCalibrated || winW != this.m7CursorCalibWinW
            || winH != this.m7CursorCalibWinH || vrRunning != this.m7CursorCalibVrRunning) {
            // The onMove scale only applies while VR is running; re-probe on the flat<->VR
            // transition and re-centre on the next miss with the new scale.
            this.m7GuiHadValidUv = false;
            calibrateM7GuiCursorScale();
        }
        if (uv == null) {
            // Ray misses the GUI plane: keep the cursor centred until the first real hit rather than
            // leaving it in the top-left default.
            if (!this.m7GuiHadValidUv) {
                centerM7GuiCursor();
            }
            if (this.m7GuiNullLogCount < 3) {
                this.m7GuiNullLogCount++;
                System.out.printf("[VRMC-M7] head cursor ray miss (kept=%s) screenPx=(%d,%d) screen=%s%n",
                    this.m7GuiHadValidUv ? "last" : "centre", winW, winH,
                    this.mc.gui.screen().getClass().getSimpleName());
            }
            return;
        }
        this.m7GuiHadValidUv = true;
        // Divide the runtime onMove scale out so the stored MouseHandler position is uv*win; the
        // renderer/click mapping (xpos * guiScaledWidth / screenWidth) then lands on uv.
        double mx = uv.x * (double) winW / this.m7CursorScaleX;
        double uvY = Math.max(0.0D, Math.min(1.0D, uv.y + M7_GUI_CURSOR_DOWN));
        double my = uvY * (double) winH / this.m7CursorScaleY;
        if (this.m7GuiCursorLogCount < 3) {
            this.m7GuiCursorLogCount++;
            System.out.printf("[VRMC-M7] head cursor uv=(%.4f,%.4f) screenPx=(%d,%d) mouse=(%.1f,%.1f) screen=%s%n",
                uv.x, uv.y, winW, winH, mx, my, this.mc.gui.screen().getClass().getSimpleName());
        }
        setM7CursorClosedLoop(uv.x * (double) winW, uvY * (double) winH, mx, my);
        // Slow diagnostic cadence: enough to prove the mapping on device without flooding the log.
        if ((this.m7GuiDebugFrameCount++ % 300) == 0) {
            System.out.printf(
                "[VRMC-M7] cursor diag uv=(%.4f,%.4f) mouse=(%.1f,%.1f) readback=(%.1f,%.1f) "
                    + "cursorScale=(%.3f,%.3f) vr=%b win=(%d,%d) fb=(%d,%d) gui=(%d,%d) "
                    + "guiScale=%.2f plane=(%.2f,%.2f,%.2f) head=(%.2f,%.2f,%.2f) dir=(%.2f,%.2f,%.2f)%n",
                uv.x, uv.y, mx, my, this.mc.mouseHandler.xpos(), this.mc.mouseHandler.ypos(),
                this.m7CursorScaleX, this.m7CursorScaleY, VRState.VR_RUNNING,
                winW, winH, this.mc.getWindow().getWidth(), this.mc.getWindow().getHeight(),
                this.mc.getWindow().getGuiScaledWidth(), this.mc.getWindow().getGuiScaledHeight(),
                GuiHandler.GUI_SCALE, GuiHandler.GUI_POS_ROOM.x(), GuiHandler.GUI_POS_ROOM.y(),
                GuiHandler.GUI_POS_ROOM.z(), this.m7GuiOrigin.x(), this.m7GuiOrigin.y(),
                this.m7GuiOrigin.z(), this.m7GuiDir.x(), this.m7GuiDir.y(), this.m7GuiDir.z());
        }
    }

    private boolean resolveM7InventoryReflection() {
        if (this.m7InventoryReflectionTried) {
            return this.m7InventoryMethod != null && this.m7GetSelectedSlotMethod != null
                && this.m7SetSelectedSlotMethod != null;
        }
        this.m7InventoryReflectionTried = true;
        try {
            Class<?> playerClass = net.minecraft.world.entity.player.Player.class;
            Class<?> inventoryClass = Class.forName("net.minecraft.world.entity.player.Inventory");
            this.m7InventoryMethod = playerClass.getMethod("getInventory");
            this.m7GetSelectedSlotMethod = inventoryClass.getMethod("getSelectedSlot");
            this.m7SetSelectedSlotMethod = inventoryClass.getMethod("setSelectedSlot", int.class);
            System.out.println("[VRMC-M7] touch hotbar inventory access resolved reflectively");
        } catch (Throwable t) {
            System.out.println("[VRMC-M7][WARN] touch hotbar inventory reflection failed: " + t);
            this.m7InventoryMethod = null;
            this.m7GetSelectedSlotMethod = null;
            this.m7SetSelectedSlotMethod = null;
        }
        return this.m7InventoryMethod != null && this.m7GetSelectedSlotMethod != null
            && this.m7SetSelectedSlotMethod != null;
    }

    /**
     * Direct touch-hotbar (operator request: "tap on the inventory bar to select"). Vivecraft renders
     * the HUD on the offhand/wrist by default; its own interactive-hotbar module maps the main-hand
     * controller position onto the hotbar bar and selects on a physical trigger press. M7 has no
     * trigger, so this mirrors the module's bar geometry and selects when the right index fingertip
     * touches the bar and dwells briefly (a deliberate tap), never while a GUI is open or seated.
     */
    private void updateM7TouchHotbar() {
        final int touchHand = VisionInput.HAND_RIGHT;
        if (!this.m7Mode || this.mc.player == null || this.mc.gui.screen() != null
            || this.visionInput == null || this.dh.vrSettings == null
            || this.dh.vrSettings.seated
            || this.dh.vrSettings.vrHudLockMode == VRSettings.HUDLock.HEAD
            || !this.dh.vrSettings.vrTouchHotbar
            || !GuiHandler.HUD_POPUP
            || GuiHandler.GUI_RENDER_POS_ROOM == null
            || GuiHandler.GUI_RENDER_ROTATION_ROOM == null
            || GuiHandler.GUI_OFFSET_LOCAL == null
            || GuiHandler.GUI_SCALE_FACTOR_MAX <= 0
            || !this.visionInput.isInputHealthy() || this.visionInput.isStale()
            || !this.visionInput.isHandTracked(touchHand)) {
            this.m7TouchHotbarSlot = -1;
            return;
        }
        long nowNs = System.nanoTime();
        if (this.m7Gesture.rightPinchHeld() || this.m7Gesture.attack()
            || this.m7Gesture.breakHeld() || nowNs < this.m7PlacePulseUntilNs
            || nowNs - this.m7LastRightActionNs < 500_000_000L) {
            this.m7TouchHotbarSlot = -1;
            return;
        }
        float scale = GuiHandler.GUI_SCALE_APPLIED
            * (float) this.mc.getWindow().getGuiScale() / (float) GuiHandler.GUI_SCALE_FACTOR_MAX;
        if (!(scale > 0.0F) || !Float.isFinite(scale)) {
            this.m7TouchHotbarSlot = -1;
            return;
        }
        // Bar geometry, exactly the installed InteractiveHotbarModule's getHotbarStart/getHotbarEnd.
        this.m7HotbarStart.set(GuiHandler.GUI_OFFSET_LOCAL)
            .add(-0.32F * scale, -0.38F * scale, 0.0F);
        GuiHandler.GUI_RENDER_ROTATION_ROOM.transformDirection(this.m7HotbarStart);
        this.m7HotbarStart.add(GuiHandler.GUI_RENDER_POS_ROOM);
        // MathUtils.LEFT in this Vivecraft is +X; the bar spans 0.64*scale along it.
        this.m7HotbarLine.set(1.0F, 0.0F, 0.0F);
        GuiHandler.GUI_RENDER_ROTATION_ROOM.transformDirection(this.m7HotbarLine)
            .mul(0.64F * scale);
        float lineLen2 = this.m7HotbarLine.lengthSquared();
        if (!(lineLen2 > 1.0E-8F)) {
            this.m7TouchHotbarSlot = -1;
            return;
        }
        float[] joints = this.visionInput.joints(touchHand);
        int tip = 9 * 3; // VisionHandPose.JOINT_INDEX_TIP
        this.m7HotbarTip.set(joints[tip], joints[tip + 1], joints[tip + 2]);
        if (!this.m7HotbarTip.isFinite()) {
            this.m7TouchHotbarSlot = -1;
            return;
        }
        if (!this.m7TouchHotbarArmedLogged) {
            this.m7TouchHotbarArmedLogged = true;
            System.out.printf(
                "[VRMC-M7] touch hotbar armed barStart=(%.2f,%.2f,%.2f) barLine=(%.2f,%.2f,%.2f) "
                    + "scale=%.2f hud=%s%n",
                this.m7HotbarStart.x, this.m7HotbarStart.y, this.m7HotbarStart.z,
                this.m7HotbarLine.x, this.m7HotbarLine.y, this.m7HotbarLine.z, scale,
                this.dh.vrSettings.vrHudLockMode);
        }
        // Closest point on the segment and slot index; distance to the infinite bar line.
        this.m7HotbarDelta.set(this.m7HotbarStart).sub(this.m7HotbarTip);
        this.m7HotbarCross.set(this.m7HotbarDelta).cross(this.m7HotbarLine);
        float dist = this.m7HotbarCross.length() / (float) Math.sqrt(lineLen2);
        float along = -this.m7HotbarDelta.dot(this.m7HotbarLine) / lineLen2; // 0=start, 1=end
        int slot = -1;
        if (Float.isFinite(dist) && Float.isFinite(along)
            && dist <= M7_TOUCH_HOTBAR_MAX_DIST && along >= -0.06F && along < 1.06F) {
            slot = (int) Math.floor(along * 9.0F);
            if (slot < 0 || slot > 8) {
                slot = -1;
            }
        }
        if (slot < 0) {
            this.m7TouchHotbarSlot = -1;
            return;
        }
        if (this.m7TouchHotbarSlot != slot) {
            this.m7TouchHotbarSlot = slot;
            this.m7TouchHotbarSinceNs = nowNs;
            this.m7HotbarDwellStart.set(this.m7HotbarTip);
            this.m7TouchHotbarLogCount++;
            if (this.m7TouchHotbarLogCount <= 5) {
                System.out.printf(
                    "[VRMC-M7] touch hotbar hover slot=%d dist=%.3f along=%.3f%n",
                    slot, dist, along);
            }
            return;
        }
        if (nowNs - this.m7TouchHotbarSinceNs < M7_TOUCH_HOTBAR_DWELL_NS) {
            return;
        }
        if (nowNs - this.m7TouchHotbarLastSelectNs < M7_TOUCH_HOTBAR_COOLDOWN_NS) {
            return;
        }
        if (this.m7HotbarTip.distance(this.m7HotbarDwellStart) > M7_TOUCH_HOTBAR_MAX_DRIFT) {
            // Hand is sliding along the bar; do not machine-gun through slots.
            this.m7TouchHotbarSinceNs = nowNs;
            this.m7HotbarDwellStart.set(this.m7HotbarTip);
            return;
        }
        if (!this.resolveM7InventoryReflection()) {
            return;
        }
        int current;
        try {
            Object inventory = this.m7InventoryMethod.invoke(this.mc.player);
            if (inventory == null) {
                return;
            }
            current = (Integer) this.m7GetSelectedSlotMethod.invoke(inventory);
            if (current == slot) {
                return;
            }
            this.m7SetSelectedSlotMethod.invoke(inventory, slot);
        } catch (Throwable t) {
            if (this.m7InventoryReflectionWarnCount++ < 3) {
                System.out.println("[VRMC-M7][WARN] touch hotbar inventory access failed: " + t);
            }
            return;
        }
        this.m7TouchHotbarLastSelectNs = nowNs;
        this.m7TouchHotbarLogCount++;
        if (this.m7TouchHotbarLogCount <= 20) {
            System.out.printf(
                "[VRMC-M7] touch hotbar select slot=%d (was %d) dist=%.3f along=%.3f%n",
                slot, current, dist, along);
        }
    }

    // ------------------------------------------------------------------------------------------
    // M4-W2 gaze: tile id -> GUI pixel, pinch-confirm click. The compositor publishes a tile event
    // only when Documents/vrmc-gaze.flag enabled its tracking-area grid; no event = no behaviour.
    // ------------------------------------------------------------------------------------------
    private void pollGazeEvents() {
        if (this.gazeEvent == null) return;
        long now = System.nanoTime();
        if (this.gazeClickReleaseAtNs != 0L && now >= this.gazeClickReleaseAtNs) {
            this.gazeClickReleaseAtNs = 0L;
            InputSimulator.releaseMouse(MOUSE_BUTTON_LEFT);
        }
        int rc = VrmcBridge.pollGazeEvent(this.gazeEvent);
        if (rc != 1) return;
        long tileId = this.gazeEvent.getLong(VrmcBridge.GAZE_OFF_TILE);
        int phase = this.gazeEvent.getInt(VrmcBridge.GAZE_OFF_PHASE);
        int kind = this.gazeEvent.getInt(VrmcBridge.GAZE_OFF_KIND);
        int gridW = this.gazeEvent.getInt(VrmcBridge.GAZE_OFF_GRID_W);
        int gridH = this.gazeEvent.getInt(VrmcBridge.GAZE_OFF_GRID_H);
        if (phase != VrmcBridge.GAZE_PHASE_ACTIVE) return;
        handleGazeActivation(tileId, kind, gridW, gridH);
    }

    private void handleGazeActivation(long tileId, int kind, int gridW, int gridH) {
        if (this.mc.gui.screen() == null) {
            if (this.gazeActivationLogCount < 3) {
                this.gazeActivationLogCount++;
                System.out.println("[VRMC-M4] gaze tile=" + tileId + " ignored: no GUI screen open");
            }
            return;
        }
        if (GuiHandler.GUI_POS_ROOM == null || GuiHandler.GUI_ROTATION_ROOM == null) {
            if (!this.gazeNoPlaneLogged) {
                this.gazeNoPlaneLogged = true;
                System.out.println("[VRMC-M4][WARN] gaze activation ignored: GUI plane pose not initialized yet");
            }
            return;
        }
        Vector2f ndc = VisionGazeMath.tileToNdc(tileId, gridW, gridH);
        if (ndc == null) {
            System.out.println("[VRMC-M4][WARN] gaze activation with bad tile=" + tileId
                + " grid=" + gridW + "x" + gridH);
            return;
        }
        // The fused gaze point is between the eyes; use the right display view (the GUI cursor's
        // controller-0 convention) when its display view is live.
        int eye = 1;
        float[] tangents = this.displayTangents[eye];
        if (tangents[0] == 0.0F && tangents[1] == 0.0F && tangents[2] == 0.0F && tangents[3] == 0.0F) {
            eye = 0;
            tangents = this.displayTangents[eye];
        }
        if (tangents[0] == 0.0F && tangents[1] == 0.0F && tangents[2] == 0.0F && tangents[3] == 0.0F) {
            System.out.println("[VRMC-M4][WARN] gaze activation ignored: no display views yet");
            return;
        }
        Matrix4f eyeToHead = eye == 0 ? this.hmdPoseLeftEye : this.hmdPoseRightEye;
        Vector3f eyeDir = VisionGazeMath.eyeRay(tangents, ndc);
        Vector3f roomDir = VisionGazeMath.eyeToRoomDirection(eyeToHead, this.hmdPose, eyeDir);
        Vector3f roomOrigin = VisionGazeMath.eyeOriginToRoom(eyeToHead, this.hmdPose);
        float aspect = (float) this.mc.getWindow().getGuiScaledHeight()
            / (float) this.mc.getWindow().getGuiScaledWidth();
        Vector2f uv = VisionGazeMath.intersectGuiPlane(roomOrigin, roomDir, GuiHandler.GUI_POS_ROOM,
            GuiHandler.GUI_ROTATION_ROOM, GuiHandler.GUI_SCALE, aspect);
        if (uv == null) {
            if (this.gazeActivationLogCount < 3) {
                this.gazeActivationLogCount++;
                System.out.printf("[VRMC-M4] gaze tile=%d (%dx%d) -> GUI miss (screen=%s)%n",
                    tileId, gridW, gridH, this.mc.gui.screen().getClass().getSimpleName());
            }
            return;
        }
        int winW = this.mc.getWindow().getWidth();
        int winH = this.mc.getWindow().getHeight();
        double mx = uv.x * (double) winW;
        double my = uv.y * (double) winH;
        if (this.gazeActivationLogCount < 20) {
            this.gazeActivationLogCount++;
            System.out.printf("[VRMC-M4] gaze tile=%d (%dx%d) kind=%d uv=(%.4f,%.4f) mouse=(%.1f,%.1f) screen=%s%n",
                tileId, gridW, gridH, kind, uv.x, uv.y, mx, my,
                this.mc.gui.screen().getClass().getSimpleName());
        }
        InputSimulator.setMousePos(mx, my);
        InputSimulator.pressMouse(MOUSE_BUTTON_LEFT);
        long now = System.nanoTime();
        this.gazeClickReleaseAtNs = now + 50_000_000L;
        // The system indirect pinch also reaches the W1 hand-pinch path; suppress that duplicate GUI
        // click for a short window so one pinch = one selection.
        this.gazeSuppressUntilNs = now + 500_000_000L;
    }

    private boolean gazeGuiClickSuppressed() {
        return this.gazeSuppressUntilNs != 0L && System.nanoTime() < this.gazeSuppressUntilNs;
    }

    // ------------------------------------------------------------------------------------------
    // M4-W1 logging (decisive + rate-limited; never logs raw joint arrays)
    // ------------------------------------------------------------------------------------------

    private void logInputDiagnostics() {
        if (this.m7Mode) {
            return; // M4 gesture edge log is misleading in M7 mode; M7 summary is in status/report
        }
        VisionInput in = this.visionInput;
        if (!this.firstSnapshotLogged && in.hasSeenSnapshot() && in.hasPublishEvidence()) {
            this.firstSnapshotLogged = true;
            System.out.printf("[VRMC-M4] first input snapshot frame=%d valid_mask=%d ts=%d Ltracked=%d Rtracked=%d%n",
                in.frameIndex(), in.validMask(), in.snapshotTimestampNs(),
                in.isHandTracked(VisionInput.HAND_LEFT) ? 1 : 0,
                in.isHandTracked(VisionInput.HAND_RIGHT) ? 1 : 0);
        }
        if (in.invalidHandMask() != 0 && !this.registeredHandDataInvalid) {
            this.registeredHandDataInvalid = true;
            System.out.println("[VRMC-M4][WARN] invalid hand data from bridge (mask=" + in.invalidHandMask()
                + "); treating those hands as untracked");
        } else if (in.invalidHandMask() == 0) {
            this.registeredHandDataInvalid = false;
        }
        if (in.isStale()) {
            // Only warn once we have actually seen the compositor publish (a startup zero snapshot is
            // "safe, no hands", not a fault).
            if (in.hasPublishEvidence() && !this.staleWarned) {
                this.staleWarned = true;
                System.out.printf("[VRMC-M4][WARN] input stale: no publish for >%d ms (frame=%d); all actions released%n",
                    in.staleMillis(), in.frameIndex());
            }
        } else if (this.staleWarned) {
            this.staleWarned = false;
            System.out.printf("[VRMC-M4] input resumed (frame=%d)%n", in.frameIndex());
        }
        this.logGestureEdges(in);
    }

    /**
     * Pose diagnostic for the real-hands device run (runbook triage: "cursor missing while hands are
     * tracked" needs the actual wrist/aim values). Emitted on the first tracked pose of each tracking
     * episode and then every ~300 tracked frames; untracked hands are skipped (no gaze-fallback numbers
     * in the line). Aim is R*(0,0,-1) of the posed controller, i.e. exactly what MCVR.getAimVector(0)
     * uses for the GUI cursor. Allocations happen only on the ~300-frame log path, never per frame.
     *
     * <pre>[VRMC-M4] pose: right wrist=(x.xxx,y.xxx,z.xxx) aim=(x.xxx,y.xxx,z.xxx) left wrist=(...) aim=(...)</pre>
     */
    private void logPoseDiagnostics() {
        boolean rightTracked = this.visionInput.isHandTracked(VisionInput.HAND_RIGHT);
        boolean leftTracked = this.visionInput.isHandTracked(VisionInput.HAND_LEFT);
        if (!rightTracked && !leftTracked) {
            this.poseLogFrames = 0;
            this.poseLoggedThisEpisode = false;
            return;
        }
        this.poseLogFrames++;
        if (this.poseLoggedThisEpisode && this.poseLogFrames % 300 != 0) {
            return;
        }
        this.poseLoggedThisEpisode = true;
        StringBuilder line = new StringBuilder("[VRMC-M4] pose:");
        if (rightTracked) {
            appendPoseSegment(line, "right", RIGHT_CONTROLLER);
        }
        if (leftTracked) {
            appendPoseSegment(line, "left", LEFT_CONTROLLER);
        }
        System.out.println(line);
    }

    /** Append " <side> wrist=(...) aim=(...)" for one controller pose (translation + R*(0,0,-1)). */
    private void appendPoseSegment(StringBuilder line, String side, int controller) {
        Matrix4f pose = this.controllerPose[controller];
        Vector3f aim = pose.transformDirection(new Vector3f(0.0F, 0.0F, -1.0F));
        line.append(String.format(" %s wrist=(%.3f,%.3f,%.3f) aim=(%.3f,%.3f,%.3f)",
            side, pose.m30(), pose.m31(), pose.m32(), aim.x, aim.y, aim.z));
    }

    private void logGestureEdges(VisionInput in) {
        for (int hand = 0; hand < VisionInput.HAND_COUNT; hand++) {
            boolean pinch = in.pinchPressed(hand);
            if (pinch != this.lastPinchPressed[hand]) {
                this.lastPinchPressed[hand] = pinch;
                logGesture("pinch %s %s (d=%.3f)", side(hand), pinch ? "press" : "release", in.pinchDistance(hand));
            }
            boolean fist = in.fistPressed(hand);
            if (fist != this.lastFistPressed[hand]) {
                this.lastFistPressed[hand] = fist;
                logGesture("fist %s %s (r=%.2f)", side(hand), fist ? "engaged" : "released", in.fistRatio(hand));
            }
            boolean tap = in.fistTapPressed(hand);
            if (tap != this.lastFistTapPressed[hand]) {
                this.lastFistTapPressed[hand] = tap;
                if (tap) {
                    logGesture("fist-tap %s pulse", side(hand));
                }
            }
        }
        boolean both = in.bothFistTapPressed();
        if (both && !this.lastBothFistTapPressed) {
            logGesture("both-fist tap pulse (inventory)");
        }
        this.lastBothFistTapPressed = both;
    }

    private static String side(int hand) {
        return hand == VisionInput.HAND_LEFT ? "left" : "right";
    }

    /** First 40 gesture events, then every 300th: readable logs during a whole session. */
    private void logGesture(String format, Object... args) {
        if (this.gestureLogCount < 40 || this.gestureLogCount % 300 == 0) {
            System.out.println("[VRMC-M4] " + String.format(format, args));
        }
        this.gestureLogCount++;
    }

    // ------------------------------------------------------------------------------------------
    // Input dispatch (adapted from macstream RemoteVR; LGPL-3.0, upstream ec5a851c..., ADR-0009)
    // ------------------------------------------------------------------------------------------

    /**
     * Resolve the binding table against Vivecraft's live VRInputAction map. Re-resolved when the map
     * instance changes (VR off/on cycles call populateInputActions() again, creating fresh actions -
     * the "controllers dead after re-entering VR" failure macstream hit; ADR-0009).
     */
    private void resolveInputActions() {
        if (this.bindingActions != null && this.resolvedActionMap == this.inputActions) {
            return;
        }
        this.resolvedActionMap = this.inputActions;
        int count = this.visionInput.bindingCount();
        this.bindingActions = new VRInputAction[count];
        int missing = 0;
        for (int i = 0; i < count; i++) {
            VRInputAction action = this.getInputAction(this.visionInput.bindingAction(i));
            this.bindingActions[i] = action;
            if (action == null) {
                missing++;
                System.out.println("[VRMC-M4][WARN] bound KeyMapping missing from Vivecraft: "
                    + this.visionInput.bindingAction(i));
            }
        }
        Map<VRInputAction, List<Long>> origins = new IdentityHashMap<>();
        for (String name : VisionInput.ACTION_NAMES) {
            VRInputAction action = this.getInputAction(name);
            if (action != null) {
                origins.put(action, VisionInput.origins(name));
            }
        }
        this.originsByAction = origins;

        // F12 action-log state: one dedupe slot per binding row (W1 rows are unique action+hand pairs)
        // plus an identity map action -> first row so the dispatch loop skips unbound actions cheaply.
        this.actionLogPressed = new boolean[count];
        java.util.IdentityHashMap<VRInputAction, Integer> rows = new java.util.IdentityHashMap<>();
        for (int i = 0; i < count; i++) {
            VRInputAction action = this.bindingActions[i];
            if (action != null && !rows.containsKey(action)) {
                rows.put(action, i);
            }
        }
        this.actionLogRows = rows;
        System.out.printf("[VRMC-M4] resolved %d/%d binding rows over %d actions (missing=%d)%n",
            count - missing, count, origins.size(), missing);
    }

    // ---- F12: action-dispatch evidence lines (W1-bound actions only; exact runbook format) ----------
    //
    //   [VRMC-M4] action <keyMappingName> press origin=<left|right|none>
    //   [VRMC-M4] action <keyMappingName> release origin=<left|right|none>
    //
    // One line per real dispatched edge proves the binding/dispatch actually called VRInputAction
    // .pressBinding()/unpressBinding*() (the device runbook Step 1 claim). Dedupe: per (action, hand)
    // pair (one binding row each in W1). Rate limit: first ACTION_LOG_BURST transitions of each kind,
    // then every ACTION_LOG_EVERY-th; a rate-limited transition still updates the dedupe state, so the
    // next logged transition is always a genuine edge. All state is preallocated at resolve(); the
    // per-frame dispatch path allocates nothing unless a line is actually printed.

    /** Binding row for this action + dispatched hand, or -1 when the action is not W1-bound. */
    private int actionLogRow(VRInputAction action, ControllerType hand) {
        if (this.actionLogRows == null || this.bindingActions == null) {
            return -1;
        }
        Integer first = this.actionLogRows.get(action);
        if (first == null) {
            return -1;
        }
        if (!action.isHanded() || hand == null) {
            return first;
        }
        for (int i = 0; i < this.bindingActions.length; i++) {
            if (this.bindingActions[i] != action) {
                continue;
            }
            int boundHand = this.visionInput.bindingHand(i);
            if (boundHand == VisionInput.HAND_NONE) {
                return i;
            }
            if (boundHand == VisionInput.HAND_LEFT ? hand == ControllerType.LEFT : hand == ControllerType.RIGHT) {
                return i;
            }
        }
        return -1;
    }

    /** Log a press edge if this (action, hand) was not already logged pressed. */
    private void logActionPress(VRInputAction action, ControllerType hand) {
        if (this.actionLogPressed == null) {
            return;
        }
        int row = actionLogRow(action, hand);
        if (row < 0 || this.actionLogPressed[row]) {
            return;
        }
        this.actionLogPressed[row] = true;
        // design §5.5: origin handles are 1 = LEFT, 2 = RIGHT; unknown -> none
        logActionTransition(action, action.getLastOrigin(), true);
    }

    /** Log the release edge for a binding row if that (action, hand) was last logged pressed. */
    private void logActionReleaseRow(int row) {
        if (this.actionLogPressed == null || row < 0 || row >= this.actionLogPressed.length) {
            return;
        }
        if (!this.actionLogPressed[row]) {
            return;
        }
        this.actionLogPressed[row] = false;
        VRInputAction action = this.bindingActions[row];
        if (action == null) {
            return;
        }
        logActionTransition(action, this.visionInput.bindingOrigin(row), false);
    }

    /** Release edge for the hand currently being dispatched (dispatchAction's release/unpress paths). */
    private void logActionReleaseCurrentHand(VRInputAction action) {
        logActionReleaseRow(actionLogRow(action, action.getCurrentHand()));
    }

    private void logActionTransition(VRInputAction action, long origin, boolean pressed) {
        int index;
        if (pressed) {
            index = this.actionPressLogCount++;
        } else {
            index = this.actionReleaseLogCount++;
        }
        if (index >= ACTION_LOG_BURST && index % ACTION_LOG_EVERY != 0) {
            return; // rate-limited: dedupe state was already updated by the caller
        }
        System.out.printf("[VRMC-M4] action %s %s origin=%s%n",
            action.keyBinding.getName(), pressed ? "press" : "release", actionOriginName(origin));
    }

    private static String actionOriginName(long origin) {
        ControllerType type = originControllerType(origin);
        if (type == null) {
            return "none";
        }
        return type == ControllerType.LEFT ? "left" : "right";
    }

    /** per-hand same-frame release of every action bound to that hand (tracking-loss safety, G4). */
    private void releaseActionsForHand(int hand) {
        if (this.bindingActions == null) {
            return;
        }
        ControllerType controller = hand == VisionInput.HAND_LEFT ? ControllerType.LEFT : ControllerType.RIGHT;
        for (int i = 0; i < this.bindingActions.length; i++) {
            if (this.visionInput.bindingHand(i) != hand) {
                continue;
            }
            VRInputAction action = this.bindingActions[i];
            if (action == null) {
                continue;
            }
            this.logActionReleaseRow(i); // F12: only logs if this (action, hand) was last logged pressed
            if (action.isHanded()) {
                action.unpressBindingImmediately(controller);
            } else {
                action.unpressBindingImmediately();
            }
        }
    }

    /**
     * Immediate release of every W1-bound action (loss of tracking / stale channel / seated): never a
     * stuck key. Only actions THIS provider can press are touched, so keyboard-driven movement keys
     * (which VisionVR never presses) are not disturbed.
     */
    private void releaseAllImmediately() {
        if (this.bindingActions == null || this.visionInput == null) {
            return;
        }
        this.zeroM7Locomotion();
        for (int i = 0; i < this.bindingActions.length; i++) {
            VRInputAction action = this.bindingActions[i];
            if (action == null) {
                continue;
            }
            this.logActionReleaseRow(i); // F12: covers stale/loss/seated/destroy releases
            if (action.isHanded()) {
                action.unpressBindingImmediately(this.visionInput.bindingHand(i) == VisionInput.HAND_LEFT
                    ? ControllerType.LEFT : ControllerType.RIGHT);
            } else {
                action.unpressBindingImmediately();
            }
        }
    }

    /**
     * M7 dispatch: write the simplified-gesture actions directly. Only this provider's action data is
     * touched; the generic dispatch loop below still applies Vivecraft's action-set gating and presses
     * the KeyMapping, so stuck-input safety is unchanged.
     */
    /** M7 left-fist in a GUI closes the current screen; it must not open a pause menu on top. */
    private void closeM7Screen() {
        Object screen = this.mc.gui.screen();
        if (screen == null) return;
        try {
            this.mc.gui.setScreen(null);
        } catch (Throwable t) {
            try {
                screen.getClass().getMethod("onClose").invoke(screen);
            } catch (Throwable t2) {
                System.out.println("[VRMC-M7][WARN] could not close GUI screen: " + t);
            }
        }
    }

    /** True when the current crosshair hit is an entity (short pinch attacks; hold breaks blocks). */
    private boolean m7TargetIsEntity() {
        try {
            return this.mc.crosshairPickEntity != null;
        } catch (Throwable t) {
            return false;
        }
    }

    /** True when the current crosshair hit is a block (context for one-pinch place/use). */
    private boolean m7TargetIsBlock() {
        try {
            return this.mc.hitResult != null
                && this.mc.hitResult.getType() == net.minecraft.world.phys.HitResult.Type.BLOCK;
        } catch (Throwable t) {
            return false;
        }
    }

    /** True while the player is riding an entity (boat/minecart/horse): right-fist tap dismounts. */
    private boolean m7IsRiding() {
        try {
            Object player = this.mc.player;
            if (player == null) return false;
            if (this.m7IsPassengerMethod == null) {
                this.m7IsPassengerMethod = player.getClass().getMethod("isPassenger");
            }
            return Boolean.TRUE.equals(this.m7IsPassengerMethod.invoke(player));
        } catch (Throwable t) {
            return false;
        }
    }

    private void applyM7Actions() {
        boolean gui = this.mc.gui.screen() != null;
        boolean seated = this.dh.vrSettings.seated;
        applyM7Locomotion();
        boolean moving = this.m7LocomotionEngaged;
        boolean rightPinchRaw = this.m7Gesture.rightPinchHeld();
        boolean rightPinchHeld = this.m7PinchCarry.update(gui, rightPinchRaw);
        if (this.m7PinchCarry.carriedNow()) {
            // Forget the old context's press so its duration/release cannot become a place/break
            // here. R1: this also covers a pinch released on the exact GUI-transition frame.
            this.m7RightPinchPrev = false;
            this.m7HeldBreak = false;
            System.out.println("[VRMC-M7] right pinch carried across a screen "
                + (gui ? "open" : "close")
                + (rightPinchRaw ? "; ignored until released" : "; released on the transition frame"));
        }
        long actionNow = System.nanoTime();
        boolean riding = m7IsRiding();
        boolean rightFistTap = this.m7Gesture.rightFistTap();
        // Latch on the rising edge: mounting on this tap must not flip the same pulse into sneak
        // on the next frame once the player is suddenly riding (that made the boat bounce out).
        if (rightFistTap && !this.m7FistTapPrev) {
            if (riding) {
                this.m7FistTapSneakUntilNs = actionNow + 150_000_000L;
            } else {
                this.m7FistTapUseUntilNs = actionNow + 150_000_000L;
            }
        }
        this.m7FistTapPrev = rightFistTap;
        boolean targetEntity = !gui && !seated && this.m7TargetIsEntity();
        boolean targetBlock = !gui && !seated && this.m7TargetIsBlock();
        if (rightPinchHeld && !this.m7RightPinchPrev) {
            this.m7RightPinchStartNs = actionNow;
        }
        long rightPinchDuration = rightPinchHeld ? actionNow - this.m7RightPinchStartNs : 0L;
        this.m7HeldBreak = !gui && !seated && rightPinchHeld
            && rightPinchDuration >= VisionM7Gesture.PLACE_MAX_NS;
        if (!rightPinchHeld && this.m7RightPinchPrev) {
            long releasedDuration = actionNow - this.m7RightPinchStartNs;
            if (!gui && !seated && releasedDuration > 0L
                && releasedDuration < VisionM7Gesture.PLACE_MAX_NS) {
                // Short pinch never breaks a block: on an entity it attacks, on a block/air it
                // places/uses; hold >=350 ms is break/mine.
                if (targetEntity) {
                    this.m7ShortAttackUntilNs = actionNow + 80_000_000L;
                } else {
                    this.m7ShortUseUntilNs = actionNow + 80_000_000L;
                }
            }
        }
        this.m7RightPinchPrev = rightPinchHeld;
        boolean use = (actionNow < this.m7ShortUseUntilNs)
            || this.m7Gesture.eat() || this.m7Gesture.bowDraw()
            || (actionNow < this.m7FistTapUseUntilNs);
        boolean radialOpen = applyM7Radial(gui);
        boolean attack = !radialOpen && ((actionNow < this.m7ShortAttackUntilNs)
            || this.m7HeldBreak
            || (this.m7Gesture.attack() && !this.m7Gesture.breakHeld()));
        if (!gui && !seated && (rightPinchHeld || attack || use)) {
            this.m7LastRightActionNs = actionNow;
        }
        setM7Action(VisionInput.KEY_ATTACK, VisionInput.HAND_RIGHT, attack);
        setM7Action(VisionInput.KEY_USE, VisionInput.HAND_RIGHT, use);
        setM7Action(VisionInput.KEY_INVENTORY, VisionInput.HAND_NONE, this.m7Gesture.inventory());
        long nowNs = System.nanoTime();
        boolean menuPulse = this.m7Gesture.menu();
        boolean menuAction = menuPulse && !gui && nowNs - this.m7LastScreenCloseNs > 400_000_000L;
        boolean closeTap = this.m7Gesture.leftFistTap();
        if (gui && closeTap && nowNs - this.m7LastScreenCloseNs > 400_000_000L) {
            this.closeM7Screen();
            this.m7LastScreenCloseNs = nowNs;
        }
        setM7Action(VisionInput.KEY_INGAME_MENU, VisionInput.HAND_LEFT, menuAction);
        // Seated play: the right middle-finger pinch replaces the head gestures (tap = jump, hold =
        // sneak) and the left one snap-turns, because a seated operator cannot rise/crouch/turn.
        boolean seatedJump = false;
        boolean seatedSneak = false;
        if (this.seatedPlay && !gui && !seated) {
            boolean tap = this.visionInput.middleTapPressed(VisionInput.HAND_RIGHT);
            if (tap && !this.seatedPlayJumpPrev) this.seatedPlayJumpUntilNs = actionNow + 120_000_000L;
            this.seatedPlayJumpPrev = tap;
            seatedJump = actionNow < this.seatedPlayJumpUntilNs;
            seatedSneak = this.visionInput.middlePressed(VisionInput.HAND_RIGHT)
                && this.visionInput.isHandTracked(VisionInput.HAND_RIGHT);
        } else {
            this.seatedPlayJumpPrev = false;
            this.seatedPlayJumpUntilNs = 0L;
        }
        applySeatedPlayTurn(this.seatedPlay && !gui && !seated, actionNow);
        setM7Action(VisionInput.KEY_JUMP, VisionInput.HAND_RIGHT, this.m7Gesture.jump() || seatedJump);
        // Right-fist tap is context sensitive: on foot = use (mount/interact), riding = sneak (dismount).
        setM7Action(VisionInput.KEY_SNEAK, VisionInput.HAND_RIGHT,
            this.m7Gesture.sneak() || seatedSneak || (actionNow < this.m7FistTapSneakUntilNs));
        // M7 left pinch is the movement stick; teleport must not also fire on the same pinch.
        // A dedicated teleport gesture is still TODO, so keep the action released here.
        setM7Action(VisionInput.KEY_TELEPORT, VisionInput.HAND_LEFT, false);
        setM7Action(VisionInput.KEY_HOTBAR_NEXT, VisionInput.HAND_RIGHT, this.m7Gesture.hotbarNext());
        setM7Action(VisionInput.KEY_HOTBAR_PREV, VisionInput.HAND_RIGHT, this.m7Gesture.hotbarPrev());
        applyM7GuiClick(gui);
        setM7Action(VisionInput.KEY_CLIMBEY_GRAB, VisionInput.HAND_LEFT, this.m7Gesture.climbGrabLeft());
        setM7Action(VisionInput.KEY_CLIMBEY_GRAB, VisionInput.HAND_RIGHT, this.m7Gesture.climbGrabRight());
        setM7Action(VisionInput.KEY_CLIMBEY_JUMP, VisionInput.HAND_NONE, this.m7Gesture.climbJump());
    }

    /**
     * Right fist hold = Vivecraft's radial (shortcut) menu - chat, commands, screenshots and the other
     * entries Vivecraft ships by default. The fist drives Vivecraft's own radial-menu key in hold
     * mode: holding opens the menu at the right hand, pointing the fist highlights an entry, opening
     * the fist chooses it (Vivecraft clicks on key release). A cancelled hold (second fist, lost
     * tracking, a screen) closes the menu first so the release never chooses anything.
     *
     * @return true while VRMC holds the radial menu open
     */
    private boolean applyM7Radial(boolean gui) {
        boolean held = this.m7Gesture.radialHeld() && !gui;
        if (this.m7Gesture.radialCancelled() || (this.m7RadialPressed && gui)) {
            closeM7RadialWithoutChoice("cancelled");
            held = false;
        }
        if (held && !this.m7RadialPressed) {
            try {
                // VRMC's gesture needs hold mode (release = choose); restore the operator's mode after.
                this.m7RadialSavedHoldMode = this.dh.vrSettings.radialModeHold;
                this.dh.vrSettings.radialModeHold = true;
                this.m7RadialHoldModeForced = true;
            } catch (Throwable t) {
                this.m7RadialHoldModeForced = false;
            }
            if (this.m7RadialLogCount++ < 10) {
                System.out.println("[VRMC-M7] radial menu: right fist hold -> open (point, open the fist to "
                    + "choose)");
            }
        }
        if (!held && this.m7RadialPressed) {
            this.m7RadialRestorePending = true;
        }
        this.m7RadialPressed = held;
        setM7Action(VisionInput.KEY_RADIAL_MENU, VisionInput.HAND_RIGHT, held);
        if (this.m7RadialRestorePending && !held && !RadialHandler.isShowing()) {
            restoreM7RadialMode();
        }
        return held || RadialHandler.isShowing();
    }

    /**
     * RadialHandlerMixin: drive the radial menu with ONE head-ray cursor and hide the other one.
     *
     * <p>The head ray must go into the cursor slot of the hand that opened the menu, because that is
     * the slot Vivecraft clicks with. In Vivecraft 26.2-1.3.15 {@code TwoHandedScreen.processCursor(..,
     * left)} stores the LEFT controller in cursorX1/Y1 and the RIGHT controller in cursorX2/Y2, and the
     * hold-mode release in {@code RadialHandler.processBindings} clicks at cursor 1 only when
     * {@code ACTIVE_CONTROLLER == LEFT}, otherwise at cursor 2. VRMC opens the menu with the right
     * fist, so the click reads cursor 2. Writing the head ray into cursor 1 (1.3.8-1.4.1) drew a
     * working highlight, but every release clicked the hidden cursor 2 = (-1,-1), clamped to the
     * top-left corner, so no option could ever be chosen.
     *
     * @return true when handled (Vivecraft's two-controller cursor update must be skipped)
     */
    public boolean m7RadialHeadCursor() {
        if (!this.m7Mode || this.dh.vrSettings == null || this.dh.vrSettings.seated) return false;
        if (!RadialHandler.isShowing() || RadialHandler.UI == null || RadialHandler.POS_ROOM == null
            || RadialHandler.ROTATION_ROOM == null) {
            return false;
        }
        try {
            this.m7RadialOrigin.set(this.hmdPose.m30(), this.hmdPose.m31(), this.hmdPose.m32());
            this.m7RadialDir.set(0.0F, 0.0F, -1.0F);
            this.hmdPose.transformDirection(this.m7RadialDir);
            float aspect = (float) this.mc.getWindow().getGuiScaledHeight()
                / (float) this.mc.getWindow().getGuiScaledWidth();
            Vector2f uv = VisionGazeMath.intersectGuiPlane(this.m7RadialOrigin, this.m7RadialDir,
                RadialHandler.POS_ROOM, RadialHandler.ROTATION_ROOM, GuiHandler.GUI_SCALE, aspect);
            var ui = RadialHandler.UI;
            boolean leftHand = radialActiveIsLeft();
            float prevX = leftHand ? ui.cursorX1 : ui.cursorX2;
            float prevY = leftHand ? ui.cursorY1 : ui.cursorY2;
            float x = -1.0F;
            float y = -1.0F;
            boolean pointed = uv != null;
            if (pointed) {
                x = (int) (uv.x * GuiHandler.GUI_WIDTH);
                y = (int) (uv.y * GuiHandler.GUI_HEIGHT);
                if (prevX >= 0.0F && prevY >= 0.0F) {
                    // Same light smoothing Vivecraft applies to controller cursors.
                    x = prevX * 0.7F + x * 0.3F;
                    y = prevY * 0.7F + y * 0.3F;
                }
            }
            // The clicking hand's slot gets the head ray; the other slot stays hidden (-1).
            ui.cursorX1 = leftHand ? x : -1.0F;
            ui.cursorY1 = leftHand ? y : -1.0F;
            ui.cursorX2 = leftHand ? -1.0F : x;
            ui.cursorY2 = leftHand ? -1.0F : y;
            setRadialPointed(pointed, leftHand);
            if (this.m7RadialCursorLogCount++ < 3) {
                System.out.println("[VRMC-M7] radial menu: head-ray cursor " + (pointed
                    ? String.format(java.util.Locale.ROOT, "uv=(%.2f,%.2f) gui=(%.0f,%.0f)", uv.x, uv.y, x, y)
                    : "off the menu")
                    + " slot=" + (leftHand ? "cursor1/left" : "cursor2/right") + " (hand cursors hidden)");
            }
            return true;
        } catch (Throwable t) {
            if (this.m7RadialCursorWarn++ < 3) {
                System.out.println("[VRMC-M7][WARN] radial head-ray cursor failed; using Vivecraft's: " + t);
            }
            return false;
        }
    }

    /** RadialHandler.POINTED_R/L are private: set them reflectively (fail-soft). */
    private void setRadialPointed(boolean pointed, boolean leftHand) {
        try {
            if (this.radialPointedR == null) {
                this.radialPointedR = RadialHandler.class.getDeclaredField("POINTED_R");
                this.radialPointedL = RadialHandler.class.getDeclaredField("POINTED_L");
                this.radialPointedR.setAccessible(true);
                this.radialPointedL.setAccessible(true);
            }
            this.radialPointedR.setBoolean(null, pointed && !leftHand);
            this.radialPointedL.setBoolean(null, pointed && leftHand);
        } catch (Throwable t) {
            // Only the non-hold click path reads these; hold mode (forced by VRMC) clicks on release.
        }
    }

    /**
     * RadialHandler.ACTIVE_CONTROLLER is private: read it reflectively. Anything but LEFT (including a
     * failed lookup) means the right hand: VRMC opens the menu with the right fist, and Vivecraft's
     * own release path also clicks with the right-hand cursor unless the active hand is LEFT.
     */
    private boolean radialActiveIsLeft() {
        try {
            if (this.radialActiveController == null) {
                this.radialActiveController = RadialHandler.class.getDeclaredField("ACTIVE_CONTROLLER");
                this.radialActiveController.setAccessible(true);
            }
            return this.radialActiveController.get(null) == ControllerType.LEFT;
        } catch (Throwable t) {
            return false;
        }
    }

    /** Close the radial overlay without choosing (before the key release can click). */
    private void closeM7RadialWithoutChoice(String why) {
        if (!this.m7RadialPressed) return;
        try {
            if (RadialHandler.isShowing()) {
                RadialHandler.setOverlayShowing(false, null);
            }
        } catch (Throwable t) {
            System.out.println("[VRMC-M7][WARN] could not close the radial menu: " + t);
        }
        if (this.m7RadialLogCount++ < 10) {
            System.out.println("[VRMC-M7] radial menu: closed without a choice (" + why + ")");
        }
        this.m7RadialPressed = false;
        restoreM7RadialMode();
    }

    private void restoreM7RadialMode() {
        this.m7RadialRestorePending = false;
        if (!this.m7RadialHoldModeForced) return;
        try {
            this.dh.vrSettings.radialModeHold = this.m7RadialSavedHoldMode;
        } catch (Throwable ignored) {
            // settings gone during shutdown
        }
        this.m7RadialHoldModeForced = false;
    }

    /**
     * M7 left-pinch virtual stick. While the LEFT thumb-index pinch is held, the left wrist position
     * relative to the head is a joystick: hand forward/back = walk forward/back, left/right = strafe
     * (same mapping/tunables as M4's middle-pinch locomotion: move.originZ/forwardScale/strafeScale/
     * deadzone). Values feed Vivecraft's keyFreeMoveStrafe analog action so free-move rotation/comfort
     * settings still apply. Zeroed in GUI, seated, keyboard, stale/unhealthy input, or when the pinch
     * is not held; this replaces the both-fist swing walk dispatch.
     */
    private void applyM7Locomotion() {
        long nowNs = System.nanoTime();
        boolean usable = this.visionInput != null && this.visionInput.isInputHealthy()
            && !this.visionInput.isStale() && !this.dh.vrSettings.seated
            && this.mc.gui.screen() == null && !KeyboardHandler.SHOWING;
        float x = 0.0F;
        float y = 0.0F;
        float debugAlong = 0.0F;
        float debugRight = 0.0F;
        if (usable && this.m7Gesture.leftPinchHeld()) {
            // Player-relative stick: project wrist-minus-head onto the HMD's horizontal forward/right
            // basis. The neutral origin is captured when the pinch engages, so a hand that naturally
            // rests left of the head does not report constant strafe; only motion from the engaged
            // position moves the player.
            this.m7MoveForward.set(0.0F, 0.0F, -1.0F);
            this.hmdPose.transformDirection(this.m7MoveForward);
            this.m7MoveForward.y = 0.0F;
            if (this.m7MoveForward.lengthSquared() < 1.0E-8F) {
                this.m7MoveForward.set(0.0F, 0.0F, -1.0F);
            } else {
                this.m7MoveForward.normalize();
            }
            this.m7MoveRight.set(-this.m7MoveForward.z, 0.0F, this.m7MoveForward.x);
            float relX = this.visionInput.wristX(VisionInput.HAND_LEFT) - this.hmdPose.m30();
            float relZ = this.visionInput.wristZ(VisionInput.HAND_LEFT) - this.hmdPose.m32();
            float along = relX * this.m7MoveForward.x + relZ * this.m7MoveForward.z;
            float right = relX * this.m7MoveRight.x + relZ * this.m7MoveRight.z;
            debugAlong = along - this.m7StickOriginAlong;
            debugRight = right - this.m7StickOriginRight;
            if (!this.m7StickOriginSet) {
                this.m7StickOriginSet = true;
                this.m7StickOriginAlong = along;
                this.m7StickOriginRight = right;
            }
            VisionLocomotion.axesRelative(along - this.m7StickOriginAlong,
                right - this.m7StickOriginRight, 0.0F,
                this.moveForwardScale, this.moveStrafeScale, this.moveDeadzone,
                this.m7LocomotionAxes);
            x = this.m7LocomotionAxes.x;
            y = this.m7LocomotionAxes.y;
        } else if (!this.m7Gesture.leftPinchHeld()) {
            this.m7StickOriginSet = false;
        }
        VRInputAction strafe = this.getInputAction(VivecraftVRMod.INSTANCE.keyFreeMoveStrafe);
        if (strafe != null) {
            writeAnalog2D(strafe, ControllerType.RIGHT.ordinal(), x, y, VisionInput.ORIGIN_LEFT);
        }
        boolean engaged = x != 0.0F || y != 0.0F;
        if (engaged != this.m7LocomotionEngaged
            || (engaged && nowNs - this.m7LocomotionLastLogNs > 3_000_000_000L)) {
            this.m7LocomotionEngaged = engaged;
            this.m7LocomotionLastLogNs = nowNs;
            float dataX = strafe == null ? 0.0F : strafe.analogData[ControllerType.RIGHT.ordinal()].x;
            float dataY = strafe == null ? 0.0F : strafe.analogData[ControllerType.RIGHT.ordinal()].y;
            System.out.printf(
                "[VRMC-M7] pinch stick(player-relative) %s strafe=%.2f forward=%.2f "
                    + "delta=(%.2f,%.2f) fwd=(%.2f,%.2f) data=(%.2f,%.2f) active=%b enabled=%b "
                    + "wrist=(%.2f,%.2f,%.2f)%n",
                engaged ? "engaged" : "released", x, y, debugAlong, debugRight,
                this.m7MoveForward.x, this.m7MoveForward.z, dataX, dataY,
                strafe != null && strafe.isActive(), strafe != null && strafe.isEnabledRaw(),
                this.visionInput.wristX(VisionInput.HAND_LEFT),
                this.visionInput.wristY(VisionInput.HAND_LEFT),
                this.visionInput.wristZ(VisionInput.HAND_LEFT));
        }
    }

    /** Zero the M7 virtual-stick output (tracking loss, seated, mode change, release paths). */
    private void zeroM7Locomotion() {
        VRInputAction strafe = this.getInputAction(VivecraftVRMod.INSTANCE.keyFreeMoveStrafe);
        if (strafe != null) {
            writeAnalog2D(strafe, ControllerType.RIGHT.ordinal(), 0.0F, 0.0F, VisionInput.ORIGIN_LEFT);
        }
        this.m7LocomotionEngaged = false;
        this.m7StickOriginSet = false;
    }

    /**
     * Thumb-index distance for the M7 engine. In seated play the middle-finger pinch is a gesture of
     * its own, and a thumb touching the middle fingertip also sits close to the index fingertip:
     * the closer fingertip wins, so a jump/sneak/turn pinch is never also read as place/break/walk.
     */
    private float m7IndexPinchDistance(int hand) {
        float index = this.visionInput.pinchDistance(hand);
        // Only when the middle-finger family is actually live: with it disabled a low middle-tip
        // distance cannot become a jump/sneak/turn, so it must not suppress the index pinch either.
        if (!this.seatedPlay || !this.visionInput.middleEnabled()) return index;
        float middle = this.visionInput.middleDistance(hand);
        if (Float.isFinite(middle) && Float.isFinite(index) && middle < index
            && middle < this.visionInput.middleOff()) {
            return 1.0F; // an open hand as far as the index pinch is concerned
        }
        return index;
    }

    /**
     * Seated play snap turn: left middle-finger pinch tap = turn left, double tap = turn right.
     *
     * <p>The single tap is deferred by the engine's middle double-tap window ({@link SeatedTurnGesture}):
     * the engine emits a single-tap pulse on the first tap of a double tap, so turning immediately
     * would make a double tap turn left *and* right (net zero). The deferred decision costs ~0.38 s
     * of latency on a single tap; a double tap turns right immediately.
     */
    private void applySeatedPlayTurn(boolean enabled, long now) {
        if (enabled) {
            int turn = this.seatedTurn.update(true,
                this.visionInput.middleTapPressed(VisionInput.HAND_LEFT),
                this.visionInput.middleDoubleTapPressed(VisionInput.HAND_LEFT),
                now, this.visionInput.middleDoubleMillis() * 1_000_000L);
            if (turn != SeatedTurnGesture.NONE) {
                this.rotatePulseDirection = turn;
                this.rotatePulseUntilNs = now + this.rotatePulseNanos;
            }
        } else if (this.rotatePulseDirection == 0 && this.rotatePulseUntilNs == 0L) {
            return; // nothing to release (keeps the M4 path's own rotate writes untouched)
        } else {
            this.rotatePulseDirection = 0;
            this.rotatePulseUntilNs = 0L;
        }
        writeSnapTurnPulse(now);
    }

    /**
     * Shared snap-turn pulse writer used by the seated play path and the M4 fallback. Vivecraft reads
     * the rotate bindings as an analog pulse (getAxis1DUseTracked), so the decided direction is held
     * for {@link #rotatePulseNanos} and then released.
     */
    private void writeSnapTurnPulse(long now) {
        boolean pulse = this.rotatePulseDirection != 0 && now < this.rotatePulseUntilNs;
        VRInputAction rotateLeft = this.getInputAction(VivecraftVRMod.INSTANCE.keyRotateLeft);
        VRInputAction rotateRight = this.getInputAction(VivecraftVRMod.INSTANCE.keyRotateRight);
        if (rotateLeft != null) {
            writeAnalog1D(rotateLeft, ControllerType.RIGHT.ordinal(),
                pulse && this.rotatePulseDirection < 0 ? 1.0F : 0.0F, VisionInput.ORIGIN_LEFT);
        }
        if (rotateRight != null) {
            writeAnalog1D(rotateRight, ControllerType.RIGHT.ordinal(),
                pulse && this.rotatePulseDirection > 0 ? 1.0F : 0.0F, VisionInput.ORIGIN_LEFT);
        }
        if (!pulse) {
            this.rotatePulseDirection = 0;
            this.rotatePulseUntilNs = 0L;
        }
    }

    /**
     * Vivecraft's roomscale bow (bowMode ON/VANILLA) only draws when its bow interact module sees one
     * controller "notched" against the other at a fixed angle. Controller poses derived from ARKit
     * hands do not satisfy that geometry reliably, and in that mode the use key VRMC presses for the
     * two-hand bow gesture is ignored, so the bow never fired on device. VRMC drives bows itself
     * (hold use = draw, release = fire, aimed along the hands), so Vivecraft's mode is set to OFF.
     * Tune key bow.mode=vivecraft keeps Vivecraft's setting for A/B.
     */
    private float bowRollTune(String key) {
        String roll = this.inputTuning == null ? null : this.inputTuning.get(key);
        float rollDeg = M7_BOW_ROLL_DEG;
        if (roll != null) {
            try {
                rollDeg = Float.parseFloat(roll.trim());
            } catch (NumberFormatException e) {
                System.out.println("[VRMC-M7][WARN] " + key + "=" + roll + " is not a number; using "
                    + M7_BOW_ROLL_DEG);
            }
        }
        return Float.isFinite(rollDeg) ? Math.max(-180.0F, Math.min(180.0F, rollDeg)) : M7_BOW_ROLL_DEG;
    }

    private void applyBowMode() {
        String handsModel = this.inputTuning == null ? null : this.inputTuning.get("hands.model");
        this.handModelVrmc = handsModel == null || !handsModel.trim().equalsIgnoreCase("vivecraft");
        String hand = this.inputTuning == null ? null : this.inputTuning.get("bow.hand");
        this.m7BowLeftHand = hand == null || !hand.trim().equalsIgnoreCase("right");
        this.m7BowRollLeftDeg = bowRollTune("bow.roll.left");
        this.m7BowRollRightDeg = bowRollTune("bow.roll.right");
        try {
            String mode = this.inputTuning == null ? null : this.inputTuning.get("bow.mode");
            if (mode != null && mode.trim().equalsIgnoreCase("vivecraft")) {
                if (!this.bowModeLogged) {
                    this.bowModeLogged = true;
                    System.out.println("[VRMC-M7] bow: keeping Vivecraft bowMode="
                        + this.dh.vrSettings.bowMode + " (bow.mode=vivecraft)");
                }
                return;
            }
            if (this.dh.vrSettings.bowMode != VRSettings.BowMode.OFF) {
                System.out.println("[VRMC-M7] bow: Vivecraft bowMode " + this.dh.vrSettings.bowMode
                    + " -> OFF (VRMC two-hand bow gesture: hold = draw, release = fire)");
                this.dh.vrSettings.bowMode = VRSettings.BowMode.OFF;
            }
        } catch (Throwable t) {
            System.out.println("[VRMC-M7][WARN] could not set Vivecraft bow mode: " + t);
        }
    }

    /**
     * Aim the shot where the player points the bow: from the head (eye) through the front (bow) hand.
     * 1.3.5 aimed along the back-hand -> front-hand line; with the bow held out in one hand and the
     * draw anchored at the opposite cheek that line points sideways (device report: "the bow turns
     * right when I launch it"). The front hand is the one that was in front when the draw started.
     */
    private void applyBowAim(long nowNs) {
        if (!this.m7Mode || this.visionInput == null) return;
        boolean drawing = this.m7Gesture.bowDraw();
        int front = this.m7Gesture.bowFrontIsLeft() ? VisionInput.HAND_LEFT : VisionInput.HAND_RIGHT;
        if (drawing && this.visionInput.isHandTracked(front)) {
            // Sight over the top of the bow fist (middle knuckle + a few cm up), like sighting along
            // the arrow: the line through the wrist hid the crosshair behind the bow and the hand.
            float[] j = this.visionInput.joints(front);
            int k = 11 * 3; // ARKit middleFingerKnuckle
            float fx = j[k], fy = j[k + 1], fz = j[k + 2];
            if (!Float.isFinite(fx) || !Float.isFinite(fy) || !Float.isFinite(fz)) {
                fx = this.visionInput.wristX(front);
                fy = this.visionInput.wristY(front);
                fz = this.visionInput.wristZ(front);
            }
            this.hmdPose.transformDirection(0.0F, 1.0F, 0.0F, this.bowSightUp);
            fx += this.bowSightUp.x * M7_BOW_SIGHT_UP_M;
            fy += this.bowSightUp.y * M7_BOW_SIGHT_UP_M;
            fz += this.bowSightUp.z * M7_BOW_SIGHT_UP_M;
            float dx = fx - this.hmdPose.m30();
            float dy = fy - this.hmdPose.m31();
            float dz = fz - this.hmdPose.m32();
            float len = (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
            if (len > 0.15F && Float.isFinite(len)) {
                this.bowAimDir.set(dx / len, dy / len, dz / len);
                this.bowAimUntilNs = nowNs + 250_000_000L;
            }
        }
        if (nowNs >= this.bowAimUntilNs) return;
        Matrix4f pose = this.controllerPose[RIGHT_CONTROLLER];
        float px = pose.m30(), py = pose.m31(), pz = pose.m32();
        // Local -Z is the aim axis of these poses (R*(0,0,-1) = aim): align local +Z with -dir.
        pose.translation(px, py, pz).rotateTowards(-this.bowAimDir.x, -this.bowAimDir.y,
            -this.bowAimDir.z, 0.0F, 1.0F, 0.0F);
    }

    /** Switch seated play; Vivecraft's keyboard/mouse seated mode always stays off (see field doc). */
    private void setSeatedPlayInternal(boolean seated, String source) {
        boolean changed = seated != this.seatedPlay;
        this.seatedPlay = seated;
        this.dh.vrSettings.seated = false;
        if (changed) {
            this.m7Gesture.resetHeadBaseline();
            System.out.println("[VRMC-M7] play style=" + (seated ? "seated" : "standing")
                + " (" + source + "): head jump/sneak " + (seated ? "off; middle-pinch jump/sneak/turn on"
                    : "on") + "; Vivecraft keyboard-seated mode stays off");
            if (seated && this.visionInput != null && !this.visionInput.middleEnabled()) {
                // Seated play moves jump/sneak/turn onto the middle-finger family; with that family
                // disabled the operator would have no jump/sneak/turn at all. Say so instead of
                // leaving a silently half-broken control scheme.
                System.out.println("[VRMC-M7][WARN] seated play enabled while middle gestures are "
                    + "disabled: jump/sneak/turn are unavailable (enable middle gestures in the launcher)");
                showGameMessage("[VRMC] Seated play needs middle gestures; enable them in the launcher tuning");
            }
        }
    }

    /**
     * Vivecraft's own "Seated" toggle (its VR settings screen) switches to keyboard/mouse play and
     * this provider then releases every hand action - with no keyboard on the headset that leaves no
     * way to turn it back off. Convert it into seated play instead of leaving the game unusable.
     */
    private void guardVivecraftSeated() {
        try {
            if (!this.dh.vrSettings.seated) return;
            setSeatedPlayInternal(true, "vivecraft seated toggle");
            persistRuntimeSetting("comfort.seated", "true");
            if (!this.vivecraftSeatedWarned) {
                this.vivecraftSeatedWarned = true;
                showGameMessage("[VRMC] Seated play on: hands stay active (see Quick Menu > Gesture guide)");
            }
        } catch (Throwable t) {
            // settings object unavailable during VR (re)initialisation; try again next frame
        }
    }

    private void persistRuntimeSetting(String key, String value) {
        if (this.mc.gameDirectory == null) return;
        Path file = this.mc.gameDirectory.toPath().resolve(VisionSettingsFile.RUNTIME_FILE);
        if (!VisionSettingsFile.update(file, key, value)) {
            System.out.println("[VRMC-M5][WARN] could not persist " + key + "=" + value + " to " + file);
        }
    }

    /**
     * Add the "VRMC Quick Menu" button to the game menu. Screen.addRenderableWidget is protected, so
     * it is invoked reflectively (Minecraft 26.x ships unobfuscated names). A transient failure is
     * logged (first few attempts) and retried rather than disabling the in-VR entry point; the
     * launcher's quick-menu command remains the fallback. The button position is chosen against the
     * widgets already on the screen so it cannot hide the vanilla/Vivecraft rows.
     *
     * <p>Any {@code PauseScreen} gets the button, not only the singleplayer one: in multiplayer the
     * same screen is shown with {@code showsPauseMenu()==false}, and a headset user still needs the
     * comfort/recovery controls there.
     */
    private void updateQuickMenuEntry() {
        long now = System.nanoTime();
        try {
            net.minecraft.client.gui.screens.Screen screen = this.mc.gui.screen();
            if (!(screen instanceof net.minecraft.client.gui.screens.PauseScreen)) {
                this.quickMenuButton = null;
                this.quickMenuInjection.reset();
                return;
            }
            if (this.quickMenuButton != null && screen.children().contains(this.quickMenuButton)) return;
            // R5: retry a transient injection failure after a cooldown, and immediately on a new
            // pause screen, instead of disabling the button for the rest of the session.
            if (!this.quickMenuInjection.shouldAttempt(now, screen)) return;
            if (this.addRenderableWidgetMethod == null) {
                this.addRenderableWidgetMethod = net.minecraft.client.gui.screens.Screen.class
                    .getDeclaredMethod("addRenderableWidget",
                        net.minecraft.client.gui.components.events.GuiEventListener.class);
                this.addRenderableWidgetMethod.setAccessible(true);
            }
            int[] pos = this.quickMenuButtonPosition(screen);
            final net.minecraft.client.gui.screens.Screen parent = screen;
            net.minecraft.client.gui.components.Button button = net.minecraft.client.gui.components.Button
                .builder(net.minecraft.network.chat.Component.literal("VRMC Quick Menu"),
                    b -> this.mc.gui.setScreen(new VisionQuickMenuScreen(this, parent)))
                .bounds(pos[0], pos[1], QUICK_MENU_BUTTON_WIDTH, QUICK_MENU_BUTTON_HEIGHT)
                .build();
            this.addRenderableWidgetMethod.invoke(screen, button);
            this.quickMenuButton = button;
            this.quickMenuInjection.recordSuccess();
        } catch (Throwable t) {
            this.quickMenuButton = null;
            this.quickMenuInjection.recordFailure(now);
            // R5: the launcher quick-menu command remains the fallback; retry quietly after the
            // first few attempts (a permanent failure would otherwise spam every cooldown).
            if (this.quickMenuInjection.shouldLogFailure()) {
                System.out.println("[VRMC-M7][WARN] quick menu button unavailable on the pause screen"
                    + " (attempt " + this.quickMenuInjection.attempts() + ", retrying): " + t);
            }
        }
    }

    /**
     * R3: place the quick-menu button where it does not overlap the widgets the vanilla/Vivecraft
     * pause screen already laid out (the Vivecraft-modified grid reaches the bottom edge on small GUI
     * scales). Falls back to the historical bottom-centre spot when no free position exists.
     */
    private int[] quickMenuButtonPosition(net.minecraft.client.gui.screens.Screen screen) {
        java.util.List<? extends net.minecraft.client.gui.components.events.GuiEventListener> children =
            screen.children();
        int[] rects = new int[children.size() * 4];
        int n = 0;
        for (int i = 0; i < children.size(); i++) {
            net.minecraft.client.gui.components.events.GuiEventListener child = children.get(i);
            if (child == this.quickMenuButton) continue;
            if (!(child instanceof net.minecraft.client.gui.components.AbstractWidget widget)) continue;
            if (!widget.visible) continue;
            rects[n++] = widget.getX();
            rects[n++] = widget.getY();
            rects[n++] = widget.getWidth();
            rects[n++] = widget.getHeight();
        }
        if (n != rects.length) rects = java.util.Arrays.copyOf(rects, n);
        return QuickMenuPlacement.find(screen.width, screen.height,
            QUICK_MENU_BUTTON_WIDTH, QUICK_MENU_BUTTON_HEIGHT, rects);
    }

    // ---- VisionQuickMenuScreen.Host ----

    @Override public void quickRecenter() { performRecenter(); }

    @Override public void quickCalibrateHeight() {
        try {
            AutoCalibration.calibrateManual();
            this.m7Gesture.resetHeadBaseline();
            System.out.println("[VRMC-M5] quick menu: manual height calibration performed");
        } catch (Throwable t) {
            System.out.println("[VRMC-M5][WARN] quick menu height calibration failed: " + t);
        }
    }

    @Override public boolean quickSeatedPlay() { return this.seatedPlay; }

    @Override public void quickSetSeatedPlay(boolean seated) {
        setSeatedPlayInternal(seated, "quick menu");
        persistRuntimeSetting("comfort.seated", seated ? "true" : "false");
    }

    @Override public float quickTurnIncrement() { return this.dh.vrSettings.worldRotationIncrement; }

    @Override public void quickSetTurnIncrement(float degrees) {
        float clamped = Math.max(0.0F, Math.min(90.0F, degrees));
        this.dh.vrSettings.worldRotationIncrement = clamped;
        persistRuntimeSetting("comfort.worldRotationIncrement", String.valueOf(Math.round(clamped)));
        System.out.println("[VRMC-M5] quick menu: worldRotationIncrement=" + clamped);
    }

    @Override public float quickWorldScale() { return this.dh.vrSettings.worldScale; }

    @Override public void quickSetWorldScale(float scale) {
        float clamped = Math.max(0.8F, Math.min(1.5F, scale));
        this.dh.vrSettings.worldScale = clamped;
        persistRuntimeSetting("comfort.worldScale",
            String.format(java.util.Locale.ROOT, "%.2f", clamped));
        System.out.println("[VRMC-M5] quick menu: worldScale=" + clamped);
    }

    @Override public int quickRenderDistance() {
        try {
            return this.mc.options.renderDistance().get();
        } catch (Throwable t) {
            return 12;
        }
    }

    @Override public void quickSetRenderDistance(int chunks) {
        int clamped = Math.max(6, Math.min(24, chunks));
        try {
            this.mc.options.renderDistance().set(clamped);
        } catch (Throwable t) {
            System.out.println("[VRMC-M5][WARN] quick menu render distance apply failed: " + t);
            return;
        }
        persistRuntimeSetting("performance.renderDistance", String.valueOf(clamped));
        System.out.println("[VRMC-M5] quick menu: renderDistance=" + clamped);
    }

    @Override public int quickVignetteLevel() {
        Path flag = this.mc.gameDirectory == null ? null
            : VisionSettingsFile.vignetteFlag(this.mc.gameDirectory.toPath());
        if (flag == null) return -1;
        try {
            if (!Files.isRegularFile(flag)) return 0;
            return VisionSettingsFile.vignetteLevel(Files.readString(flag));
        } catch (Throwable t) {
            return 0;
        }
    }

    @Override public void quickSetVignetteLevel(int level) {
        Path flag = this.mc.gameDirectory == null ? null
            : VisionSettingsFile.vignetteFlag(this.mc.gameDirectory.toPath());
        if (flag == null) return;
        int index = Math.max(0, Math.min(VisionSettingsFile.VIGNETTE_LEVELS.length - 1, level));
        try {
            if (index == 0) {
                Files.deleteIfExists(flag);
            } else {
                Files.writeString(flag, String.format(java.util.Locale.ROOT, "%.2f",
                    VisionSettingsFile.VIGNETTE_LEVELS[index]));
            }
            System.out.println("[VRMC-M5] quick menu: vignette level=" + index + " (" + flag + ")");
        } catch (Throwable t) {
            System.out.println("[VRMC-M5][WARN] quick menu vignette write failed: " + t);
        }
    }

    @Override public void quickReleaseInput() {
        this.visionInput = new VisionInput(this.inputTuning);
        this.m7Gesture.releaseAll();
        this.bindingActions = null;
        this.resolvedActionMap = null;
        this.hotbarWheelActive = false;
        this.rotatePulseDirection = 0;
        this.rotatePulseUntilNs = 0L;
        this.m4Turn.reset();
        this.m7PinchCarry.reset();
        System.out.println("[VRMC-M4] quick menu: input engine reset; held actions released");
    }

    @Override public String[] quickControlsHelp() { return controlsHelpLines(); }

    private void setM7Action(String name, int hand, boolean state) {
        VRInputAction action = this.getInputAction(name);
        if (action == null) return;
        int slot;
        long origin;
        if (action.isHanded()) {
            boolean left = hand == VisionInput.HAND_LEFT;
            slot = left ? ControllerType.LEFT.ordinal() : ControllerType.RIGHT.ordinal();
            origin = left ? VisionInput.ORIGIN_LEFT : VisionInput.ORIGIN_RIGHT;
        } else {
            slot = 0;
            origin = hand == VisionInput.HAND_LEFT ? VisionInput.ORIGIN_LEFT : VisionInput.ORIGIN_RIGHT;
        }
        writeDigital(action, slot, true, state, origin);
    }

    /**
     * M7 GUI left click. Vivecraft's own guiLeftClick binding is consumed in
     * GuiHandler.processBindingsGui(), but that path only clicks when CONTROLLER_MOUSE_* is valid, and
     * the M7 head-ray cursor owns the cursor (GuiHandler.processGui is cancelled by the mixin), so the
     * binding never fires. Dispatch the click directly through the vanilla mouse handler instead: the
     * cursor has already been positioned by updateM7GuiCursor() this frame, so Screen.mouseClicked()
     * receives the head-ray coordinate.
     */
    private void applyM7GuiClick(boolean gui) {
        boolean want = gui && this.m7Gesture.guiClick() && !this.m7PinchCarry.carrying();
        if (want && !this.m7GuiClickPressed) {
            this.m7GuiClickPressed = true;
            InputSimulator.pressMouse(MOUSE_BUTTON_LEFT);
            if (this.m7GuiClickLogCount < 5) {
                this.m7GuiClickLogCount++;
                System.out.printf(
                    "[VRMC-M7] gui click press mouse=(%.1f,%.1f) grabbed=%b screen=%s%n",
                    this.mc.mouseHandler.xpos(), this.mc.mouseHandler.ypos(),
                    this.mc.mouseHandler.isMouseGrabbed(),
                    this.mc.gui.screen() == null ? "none"
                        : this.mc.gui.screen().getClass().getSimpleName());
            }
        } else if (!want && this.m7GuiClickPressed) {
            this.m7GuiClickPressed = false;
            InputSimulator.releaseMouse(MOUSE_BUTTON_LEFT);
        }
    }

    private void releaseM7Actions() {
        // Lost/stale hands must close the radial menu without choosing (hold mode clicks on release).
        closeM7RadialWithoutChoice("input lost");
        this.zeroM7Locomotion();
        this.m7PinchCarry.reset();
        this.seatedPlayJumpPrev = false;
        this.seatedPlayJumpUntilNs = 0L;
        applySeatedPlayTurn(false, System.nanoTime());
        this.m7RightPinchPrev = false;
        this.m7HeldBreak = false;
        this.m7ShortAttackUntilNs = 0L;
        this.m7ShortUseUntilNs = 0L;
        this.m7FistTapPrev = false;
        this.m7FistTapUseUntilNs = 0L;
        this.m7FistTapSneakUntilNs = 0L;
        this.m7RightPinchStartNs = 0L;
        if (this.m7GuiClickPressed) {
            this.m7GuiClickPressed = false;
            InputSimulator.releaseMouse(MOUSE_BUTTON_LEFT);
        }
        for (String name : new String[]{VisionInput.KEY_ATTACK, VisionInput.KEY_USE,
            VisionInput.KEY_INVENTORY, VisionInput.KEY_INGAME_MENU, VisionInput.KEY_JUMP,
            VisionInput.KEY_SNEAK, VisionInput.KEY_TELEPORT, VisionInput.KEY_HOTBAR_NEXT,
            VisionInput.KEY_HOTBAR_PREV, VisionInput.KEY_GUI_LEFT_CLICK,
            VisionInput.KEY_CLIMBEY_GRAB, VisionInput.KEY_CLIMBEY_JUMP, VisionInput.KEY_RADIAL_MENU}) {
            VRInputAction action = this.getInputAction(name);
            if (action == null) continue;
            if (action.isHanded()) {
                writeDigital(action, ControllerType.LEFT.ordinal(), false, false, VisionInput.ORIGIN_LEFT);
                writeDigital(action, ControllerType.RIGHT.ordinal(), false, false, VisionInput.ORIGIN_RIGHT);
            } else {
                writeDigital(action, 0, false, false, VisionInput.ORIGIN_RIGHT);
            }
        }
        VRInputAction strafe = this.getInputAction(VivecraftVRMod.INSTANCE.keyFreeMoveStrafe);
        if (strafe != null) {
            writeAnalog2D(strafe, ControllerType.RIGHT.ordinal(), 0.0F, 0.0F, VisionInput.ORIGIN_LEFT);
        }
    }

    /**
     * Write each bound action's DigitalData/AnalogData exactly where MCOpenVR.readDigitalData/
     * readAnalogData would, with the action-set gating computed by VisionInput (design §5.4/§5.5).
     */
    private void applyActionData() {
        for (int i = 0; i < this.bindingActions.length; i++) {
            VRInputAction action = this.bindingActions[i];
            if (action == null) {
                continue;
            }
            boolean active = this.visionInput.bindingActive(i);
            boolean state = this.visionInput.bindingPressed(i);
            long origin = this.visionInput.bindingOrigin(i);
            int slot;
            if (action.isHanded()) {
                slot = this.visionInput.bindingHand(i) == VisionInput.HAND_LEFT
                    ? ControllerType.LEFT.ordinal() : ControllerType.RIGHT.ordinal();
            } else {
                // non-handed actions only ever read slot 0; stamp the bound hand's origin so
                // getLastOrigin()/findActiveBindingControllerType resolve the hand (design §5.5)
                slot = 0;
            }
            writeDigital(action, slot, active, state, origin);
        }
    }

    /**
     * M4-W4 direct hotbar wheel: both hands thumb-ring pinch to enter; moving the left hand left/right
     * from the start point selects slot 1..9; releasing commits it. This is a deliberate two-hand
     * chord (ring fingers), independent of the index/middle families, and shows the current slot in
     * the action bar. Cancels without committing on stale/lost input.
     */
    private void applyHotbarWheel() {
        if (this.visionInput == null) return;
        boolean usable = this.visionInput.isInputHealthy() && !this.visionInput.isStale()
            && !this.dh.vrSettings.seated && this.mc.gui.screen() == null && !KeyboardHandler.SHOWING;
        boolean both = usable && this.visionInput.bothRingPinchPressed();
        if (!usable) {
            if (this.hotbarWheelActive) {
                this.hotbarWheelActive = false;
                showGameMessage("[VRMC] hotbar wheel cancelled (input lost)");
            }
            return;
        }
        if (both) {
            if (!this.hotbarWheelActive) {
                this.hotbarWheelActive = true;
                this.hotbarWheelStartX = this.visionInput.wristX(VisionInput.HAND_LEFT);
                this.hotbarWheelSelected = VisionHotbarWheel.slotForDelta(0.0F, this.hotbarRange);
                showGameMessage("[VRMC] hotbar wheel: move left hand, release to select");
            }
            float delta = this.visionInput.wristX(VisionInput.HAND_LEFT) - this.hotbarWheelStartX;
            int slot = VisionHotbarWheel.slotForDelta(delta, this.hotbarRange);
            if (slot != this.hotbarWheelSelected) {
                this.hotbarWheelSelected = slot;
                showGameMessage("[VRMC] hotbar slot " + slot);
            }
        } else if (this.hotbarWheelActive) {
            this.hotbarWheelActive = false;
            commitHotbarSlot(this.hotbarWheelSelected);
            showGameMessage("[VRMC] hotbar slot " + this.hotbarWheelSelected + " selected");
        }
    }

    private void commitHotbarSlot(int slot) {
        Object player = this.mc.player;
        if (player == null) return;
        try {
            Object inventory = player.getClass().getMethod("getInventory").invoke(player);
            java.lang.reflect.Method set = inventory.getClass().getMethod("setSelectedSlot", int.class);
            set.invoke(inventory, Math.max(0, Math.min(8, slot - 1)));
        } catch (Throwable t) {
            System.out.println("[VRMC-M4][WARN] hotbar slot commit failed: " + t);
        }
    }

    /**
     * M4-W3 locomotion: while the left middle pinch is held, the left wrist relative to the head is a
     * virtual stick (forward/strafe) written to Vivecraft's {@code keyFreeMoveStrafe}. A left
     * middle-pinch tap / double-tap pulses the snap-turn analog actions. Everything is zeroed in GUI,
     * seated mode, or when the input channel is unhealthy; no analog value can stick on tracking loss.
     */
    private void applyLocomotion() {
        long now = System.nanoTime();
        boolean usable = this.visionInput != null && this.visionInput.isInputHealthy()
            && !this.visionInput.isStale() && !this.dh.vrSettings.seated
            && this.mc.gui.screen() == null && !KeyboardHandler.SHOWING;
        float x = 0.0F;
        float y = 0.0F;
        float debugAlong = 0.0F;
        float debugRight = 0.0F;
        if (usable && this.m7Gesture.leftPinchHeld()) {
            VisionLocomotion.axes(
                this.visionInput.wristX(VisionInput.HAND_LEFT),
                this.visionInput.wristY(VisionInput.HAND_LEFT),
                this.visionInput.wristZ(VisionInput.HAND_LEFT),
                this.hmdPose.m30(), this.hmdPose.m31(), this.hmdPose.m32(),
                this.moveOriginZ, this.moveForwardScale, this.moveStrafeScale, this.moveDeadzone,
                this.locomotionAxes);
            x = this.locomotionAxes.x;
            y = this.locomotionAxes.y;
        }
        VRInputAction strafe = this.getInputAction(VivecraftVRMod.INSTANCE.keyFreeMoveStrafe);
        if (strafe != null) {
            writeAnalog2D(strafe, ControllerType.RIGHT.ordinal(), x, y, VisionInput.ORIGIN_LEFT);
        }
        // Snap turn: a tap = left, a double-tap = right (R6/R12). The decision is deferred by the
        // engine's middle double-tap window through {@link SeatedTurnGesture}, exactly like the M7
        // seated path: the engine emits the single-tap pulse on the first tap of a double tap, so the
        // old immediate handling turned left and then right and a double tap netted zero rotation.
        if (usable) {
            int turn = this.m4Turn.update(true,
                this.visionInput.middleTapPressed(VisionInput.HAND_LEFT),
                this.visionInput.middleDoubleTapPressed(VisionInput.HAND_LEFT),
                now, this.visionInput.middleDoubleMillis() * 1_000_000L);
            if (turn != SeatedTurnGesture.NONE) {
                this.rotatePulseDirection = turn;
                this.rotatePulseUntilNs = now + this.rotatePulseNanos;
            }
        } else {
            this.m4Turn.update(false, false, false, now, 0L); // cancel a deferred turn (GUI/seated/input loss)
            this.rotatePulseDirection = 0;
            this.rotatePulseUntilNs = 0L;
        }
        writeSnapTurnPulse(now);
    }

    /** Compact in-headset control reference for the active gesture mode (chat + quick-menu guide). */
    private String[] controlsHelpLines() {
        if (!this.m7Mode) {
            return new String[] {
                "Pinch thumb+index: attack / GUI click; left hold = teleport.",
                "Right fist hold = use / bow draw; left fist tap = menu; both fists tap = inventory.",
                "Middle pinch: left hold+move = walk; right hold = sneak; right tap = jump; left tap/double = snap turn.",
                "Both thumb-ring pinches: hotbar wheel (move left hand, release).",
            };
        }
        java.util.List<String> lines = new java.util.ArrayList<>();
        lines.add("Look at something to aim. Menus: look + right pinch to click.");
        lines.add("Right pinch, short: place / use.  Right pinch, hold: break / mine.");
        lines.add("Right pinch on a mob, or a right-hand punch: attack.");
        lines.add("Left pinch, hold and move the hand: walk / strafe.");
        lines.add("Left fist tap: game menu (in a menu: go back).");
        lines.add("Both fists tap: inventory.  Right fist tap: use / mount / dismount.");
        lines.add("Touch the hotbar with your right index finger, or tap it in the air: change slot.");
        lines.add("Bow: hands apart to draw, open the back hand to fire.  Food: right hand to mouth.");
        if (this.seatedPlay) {
            lines.add("Seated: right middle-finger pinch tap = jump, hold = sneak.");
            lines.add("Seated: left middle-finger pinch tap = turn left, double tap = turn right.");
        } else {
            lines.add("Standing: rise on your toes = jump, crouch = sneak.");
        }
        lines.add("Both middle-finger pinches, double tap: recenter.");
        lines.add("Game menu > VRMC Quick Menu: comfort, turning, world scale, draw distance, release input.");
        return lines.toArray(new String[0]);
    }

    private void showGameChat(String[] lines) {
        Object player = this.mc.player;
        if (player == null) return;
        try {
            Class<?> componentClass = Class.forName("net.minecraft.network.chat.Component");
            java.lang.reflect.Method literal = componentClass.getMethod("literal", String.class);
            java.lang.reflect.Method display = player.getClass().getMethod(
                "displayClientMessage", componentClass, boolean.class);
            for (String text : lines) {
                display.invoke(player, literal.invoke(null, text), false); // chat, not action bar
            }
        } catch (Throwable t) {
            // Chat unavailable early; command remains non-fatal.
        }
    }

    /**
     * Best-effort on-device feedback for safety/command actions. Uses reflection so the provider build
     * does not depend on the MC chat Component annotation classes; failures are silent (logs only).
     */
    private void showGameMessage(String text) {
        Object player = this.mc.player;
        if (player == null) return;
        try {
            Class<?> componentClass = Class.forName("net.minecraft.network.chat.Component");
            java.lang.reflect.Method literal = componentClass.getMethod("literal", String.class);
            Object component = literal.invoke(null, text);
            java.lang.reflect.Method display = player.getClass().getMethod(
                "displayClientMessage", componentClass, boolean.class);
            display.invoke(player, component, true); // action bar
        } catch (Throwable t) {
            // Chat/UI may be unavailable (e.g. very early init); never fail the command.
        }
    }

    /** M5 safety action: put the VR room origin back at the player (no movement/teleport side effects). */
    private void performRecenter() {
        if (this.mc.player == null || this.dh.vrPlayer == null) return;
        try {
            // Reflective call keeps the provider build independent of the @Nullable annotation class
            // that javac needs for a direct call on this MC/Vivecraft signature.
            java.lang.reflect.Method m = this.dh.vrPlayer.getClass().getMethod(
                "snapRoomOriginToPlayerEntity", Entity.class, boolean.class, boolean.class);
            m.invoke(this.dh.vrPlayer, this.mc.player, false, true);
            this.m7Gesture.resetHeadBaseline();
            System.out.println("[VRMC-M5] recenter: room origin snapped to player (both-middle double-tap)");
            showGameMessage("[VRMC] recenter: room origin snapped to player");
        } catch (Throwable t) {
            System.out.println("[VRMC-M5][WARN] recenter failed: " + t);
        }
    }

    /**
     * M4-W4 opt-in open-hand swipes (default OFF via swipe.enabled): right-hand horizontal swipe =
     * hotbar previous/next; right-hand vertical swipe = mouse wheel (hotbar in game / list scroll in GUI).
     * Only the rising edge of the 2-frame swipe pulse acts, so one swipe = one action.
     */
    private void applySwipeActions() {
        if (this.visionInput == null || !this.visionInput.swipeEnabled()) {
            this.lastSwipeDirection = VisionInput.SWIPE_NONE;
            return;
        }
        int direction = this.visionInput.swipeDirection(VisionInput.HAND_RIGHT);
        if (direction == this.lastSwipeDirection) return;
        this.lastSwipeDirection = direction;
        if (direction == VisionInput.SWIPE_NONE || this.dh.vrSettings.seated || KeyboardHandler.SHOWING) {
            return;
        }
        switch (direction) {
            case VisionInput.SWIPE_UP -> {
                InputSimulator.scrollMouse(0.0D, 1.0D);
                System.out.println("[VRMC-M4] swipe right-hand UP -> scroll up");
            }
            case VisionInput.SWIPE_DOWN -> {
                InputSimulator.scrollMouse(0.0D, -1.0D);
                System.out.println("[VRMC-M4] swipe right-hand DOWN -> scroll down");
            }
            default -> { }
        }
    }

    private static void writeAnalog2D(VRInputAction action, int slot, float x, float y, long origin) {
        VRInputAction.AnalogData a = action.analogData[slot];
        a.deltaX = -a.x;
        a.deltaY = -a.y;
        a.deltaZ = -a.z;
        a.x = x;
        a.y = y;
        a.z = 0.0F;
        a.isChanged = a.deltaX != 0.0F || a.deltaY != 0.0F || a.deltaZ != 0.0F;
        a.isActive = true;
        a.activeOrigin = origin;
    }

    private static void writeAnalog1D(VRInputAction action, int slot, float x, long origin) {
        VRInputAction.AnalogData a = action.analogData[slot];
        a.deltaX = -a.x;
        a.x = x;
        a.y = 0.0F;
        a.z = 0.0F;
        a.isChanged = a.deltaX != 0.0F;
        a.isActive = true;
        a.activeOrigin = origin;
    }

    private static void writeDigital(VRInputAction action, int slot, boolean active, boolean state, long origin) {
        VRInputAction.DigitalData d = action.digitalData[slot];
        d.isChanged = d.state != state;
        d.state = state;
        d.isActive = active;
        d.activeOrigin = origin;

        VRInputAction.AnalogData a = action.analogData[slot];
        a.deltaX = -a.x;
        a.deltaY = -a.y;
        a.deltaZ = -a.z;
        a.x = 0.0F;
        a.y = 0.0F;
        a.z = 0.0F;
        a.isChanged = a.deltaX != 0.0F || a.deltaY != 0.0F || a.deltaZ != 0.0F;
        a.isActive = active;
        a.activeOrigin = origin;
    }

    /**
     * M4-W1 action dispatch. Adapted from macstream's RemoteVR.processInputs()/dispatchAction()
     * (LGPL-3.0, upstream ec5a851c..., ADR-0009): same shape as MCOpenVR.processInputs' per-action
     * loop, but reading the data VisionInput wrote instead of OpenVR state. Releases are made
     * immediate whenever the input channel is lost/stale (G4: never a stuck attack/teleport).
     */
    @Override
    public void processInputs() {
        if (!this.initialized || !this.bridgeReady || this.visionInput == null || this.inputActions == null) {
            this.ignorePressesNextFrame = false;
            return;
        }
        if (this.dh.viewOnly) {
            this.ignorePressesNextFrame = false;
            return;
        }
        this.resolveInputActions();

        if (this.dh.vrSettings.seated) {
            if (!this.seatedWarned) {
                this.seatedWarned = true;
                System.out.println("[VRMC-M4][WARN] seated mode: gesture input needs standing mode; "
                    + "hands are disabled for actions in M4-W1 (seated parity is M4-W2)");
            }
            this.releaseAllImmediately();
            this.ignorePressesNextFrame = false;
            return;
        }

        boolean anyTracked = this.visionInput.isHandTracked(VisionInput.HAND_LEFT)
            || this.visionInput.isHandTracked(VisionInput.HAND_RIGHT);
        if (!anyTracked || !this.visionInput.isInputHealthy() || this.visionInput.isStale()) {
            // No usable hand data this frame: release every binding NOW rather than waiting for
            // Vivecraft's 1-tick unpress scheduling, then continue (the per-action loop keeps state
            // consistent; the fallback poses still keep body yaw sane).
            this.releaseAllImmediately();
        }

        // MCOpenVR.updateActiveActionSets equivalent (same shape as macstream TouchPlusInput).
        boolean screenOpen = this.mc.gui.screen() != null;
        boolean keyboardShowing = KeyboardHandler.SHOWING || RadialHandler.isShowing();
        this.visionInput.setEnvironment(screenOpen, this.dh.vrSettings.ingameBindingsInGui, keyboardShowing);

        if (this.m7Mode) {
            boolean usable = this.visionInput.isInputHealthy() && !this.visionInput.isStale()
                && (this.visionInput.isHandTracked(VisionInput.HAND_LEFT)
                    || this.visionInput.isHandTracked(VisionInput.HAND_RIGHT));
            if (usable) {
                this.applyM7Actions();
            } else {
                this.releaseM7Actions();
            }
            if (this.visionInput.bothMiddleDoubleTapPressed()) {
                performRecenter();
            }
            for (VRInputAction action : this.inputActions.values()) {
                if (action.isHanded()) {
                    for (ControllerType hand : ControllerType.values()) {
                        action.setCurrentHand(hand);
                        this.dispatchAction(action);
                    }
                } else {
                    this.dispatchAction(action);
                }
            }
            this.ignorePressesNextFrame = false;
            return;
        }

        this.applyActionData();
        this.applyLocomotion();
        this.applySwipeActions();
        this.applyHotbarWheel();

        if (this.visionInput.bothMiddleDoubleTapPressed()) {
            performRecenter();
        }

        for (VRInputAction action : this.inputActions.values()) {
            if (action.isHanded()) {
                for (ControllerType hand : ControllerType.values()) {
                    action.setCurrentHand(hand);
                    this.dispatchAction(action);
                }
            } else {
                this.dispatchAction(action);
            }
        }
        this.ignorePressesNextFrame = false;
    }

    /** processInputAction equivalent (MCOpenVR.processInputAction) without OpenVR handles. */
    private void dispatchAction(VRInputAction action) {
        if (gazeGuiClickSuppressed() && action.keyBinding == GuiHandler.KEY_LEFT_CLICK) {
            // The gaze path already delivered this selection; swallow the duplicate hand-pinch click.
            if (action.isButtonPressed()) {
                action.unpressBinding();
            }
            return;
        }
        if (action.isActive() && action.isEnabledRaw()) {
            if (action.isButtonChanged()) {
                if (action.isButtonPressed() && action.isEnabled()) {
                    this.logActionPress(action, action.getCurrentHand());
                    action.pressBinding();
                } else {
                    this.logActionReleaseCurrentHand(action);
                    action.unpressBinding();
                }
            } else if (action.isButtonPressed() && action.isEnabled() && !action.keyBinding.isDown()) {
                // allow re-pressing buttons that were held before an action-set change
                this.logActionPress(action, action.getCurrentHand());
                action.pressBinding();
            }
        } else if (action.keyBinding != this.mc.options.keyLeft
            && action.keyBinding != this.mc.options.keyRight
            && action.keyBinding != this.mc.options.keyUp
            && action.keyBinding != this.mc.options.keyDown) {
            this.logActionReleaseCurrentHand(action);
            action.unpressBinding();
        }
    }

    @Override
    public String getName() { return "VRMC"; }

    @Override public String getRuntimeName() { return "VRMC visionOS bridge"; }

    @Override
    protected ControllerType findActiveBindingControllerType(KeyMapping keyMapping) {
        if (this.visionInput == null || keyMapping == null) {
            return null;
        }
        VRInputAction action = this.getInputAction(keyMapping);
        return action == null ? null : originControllerType(action.getLastOrigin());
    }

    /**
     * Provider origin convention (design §5.4, same as macstream TouchPlusInput): 1 = LEFT hand,
     * 2 = RIGHT hand. Static so VRInputActionMixin can resolve the generic backend path in place of
     * the MCOpenVR handle lookup; unknown origins resolve to null.
     */
    public static ControllerType originControllerType(long origin) {
        return switch ((int) origin) {
            case 1 -> ControllerType.LEFT;
            case 2 -> ControllerType.RIGHT;
            default -> null;
        };
    }

    /** Instance view of {@link #originControllerType(long)} (MCVR-facing shape). */
    public ControllerType getOriginControllerType(long origin) {
        return originControllerType(origin);
    }

    @Override
    public List<Long> getOrigins(VRInputAction action) {
        if (this.originsByAction == null || action == null) {
            return List.of();
        }
        List<Long> origins = this.originsByAction.get(action);
        return origins != null ? origins : List.of();
    }

    @Override
    public String getOriginName(long origin) {
        return switch ((int) origin) {
            case 1 -> "left hand";
            case 2 -> "right hand";
            default -> "VRMC";
        };
    }

    @Override
    public Vector2fc getPlayAreaSize() { return new Vector2f(1.0F, 1.0F); }

    @Override public void refreshControllerTransforms() { /* M3/M4 */ }

    @Override
    public Matrix4fc getControllerComponentTransform(int controllerIndex, String componentName) {
        if (this.handComponentJoints && "tip".equals(componentName) && this.visionInput != null) {
            int hand = controllerIndex == RIGHT_CONTROLLER ? VisionInput.HAND_RIGHT : VisionInput.HAND_LEFT;
            if (this.visionInput.isHandTracked(hand)) {
                VisionHandPose.tipOffset(this.visionInput.joints(hand), this.controllerPose[controllerIndex],
                    this.tipOffsetTmp);
                this.tipComponent[controllerIndex].identity().setTranslation(this.tipOffsetTmp);
                return this.tipComponent[controllerIndex];
            }
        }
        // These are *static* handgrip/tip model offsets, not tracking data. The M4-W1 hand pose is
        // already the wrist pose with a joint-derived rotation that makes R*(0,0,-1) the finger aim,
        // so the model-offset step must be identity (adding a tip offset here would double-shift the
        // aim source). Tracking poses are the data that must never be silently invented - poll()
        // validates them.
        return IDENTITY;
    }

    /**
     * M8 world-supersample knob: startup-only SSAA lever for jagged edges (Minecraft 26.2 has no MSAA).
     * Vivecraft's renderScaleFactor sizes the world render target at eye x sqrt(factor) per axis and
     * resolves it down to the eye target. Read before the first render-target creation; 1.0 (off) is
     * the default. Changing it requires a game restart (documented in the runbook).
     */
    private void applyWorldSupersampleKnob() {
        String value = "off";
        java.io.File gameDir = Minecraft.getInstance().gameDirectory;
        if (gameDir != null) {
            java.io.File knob = new java.io.File(gameDir, "vrmc-world-supersample.txt");
            if (knob.isFile()) {
                try {
                    String text = java.nio.file.Files.readString(knob.toPath()).trim();
                    if (!text.isEmpty()) value = text;
                } catch (java.io.IOException | RuntimeException readError) {
                    System.out.println("[VRMC-M8][WARN] could not read vrmc-world-supersample.txt: " + readError);
                }
            }
        }
        float factor = VisionWorldSupersample.parse(value);
        if (factor < 0.0f) {
            System.out.println("[VRMC-M8] world supersample: ignoring invalid value '" + value
                + "' (expected off or " + VisionWorldSupersample.MIN_FACTOR + ".."
                + VisionWorldSupersample.MAX_FACTOR + ")");
            return;
        }
        if (factor <= VisionWorldSupersample.MIN_FACTOR + 1.0e-4f) {
            if (!value.equalsIgnoreCase("off")) {
                System.out.println("[VRMC-M8] world supersample: 1.00x (file) - off (world render target "
                    + "equals the eye target)");
            }
            return;
        }
        this.dh.vrSettings.renderScaleFactor = factor;
        System.out.println(String.format(java.util.Locale.ROOT,
            "[VRMC-M8] world supersample: %.2fx (file) - world render target = eye target * %.2f per axis "
                + "(Vivecraft renderScaleFactor; startup-only SSAA to reduce jagged edges; pixel cost %.2fx)",
            factor, VisionWorldSupersample.axisScale(factor), factor));
    }

    @Override public VRRenderer createVRRenderer() {
        applyWorldSupersampleKnob();
        return new VisionRenderer(this);
    }
    @Override public boolean isActive() { return this.initialized; }
    @Override public float getIPD() { return this.ipd; }
}
