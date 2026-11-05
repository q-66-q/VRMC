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
public class VisionVR extends MCVR {
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
    private int m7ItemContextBits;
    private final Vector3f m7GuiOrigin = new Vector3f();
    private final Vector3f m7GuiDir = new Vector3f();
    private int m7GuiWarnCount;
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
            System.out.println("[VRMC-M7] mapping: short right pinch=place, held right pinch=break, "
                + "left fist=escape, both-fist tap=inventory, both-fist swing=walk, head rise/lower=jump/sneak, "
                + "left pinch hold=teleport, right swing=attack, right index tap=hotbar, near-head=eat, "
                + "wide both fists=bow, alternating grips=climb");
        }

        this.runtimeSettings = VisionRuntimeSettings.load(this.mc.gameDirectory, System.out::println);
        applyRuntimeSettings(this.runtimeSettings);
        long diagNow = System.nanoTime();
        this.diagWindowStartNs = diagNow;
        this.diagNextLogNs = diagNow + this.runtimeSettings.diagnosticPeriodSeconds * 1_000_000_000L;

        this.initialized = true;
        this.initSuccess = true;
        appendShutdownLog("init", "bridgeReady=" + this.bridgeReady + " abi=" + VrmcBridge.ABI_VERSION);
        // Do NOT write the status document here: dh.vrPlayer/trackers are still being constructed during
        // VRState.initializeVR, and tracker queries (e.g. ClimbTracker.isClimbeyClimb) NPE until vrPlayer
        // exists. statusAutoWritePending writes it on the first update after init returns.
        System.out.println("[VRMC-M2] VisionVR.init() succeeded");
        return true;
    }

    @Override
    public void destroy() {
        appendShutdownLog("destroy-start", "bridgeReady=" + this.bridgeReady
            + " displayViewsGen=" + this.displayViewsGen + " trackedFrames=" + this.trackedFrames);
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
        VisionStatusJson.Data data = new VisionStatusJson.Data(
            java.time.Instant.now().toString(),
            VrmcBridge.ABI_VERSION,
            this.bridgeReady,
            this.initialized,
            this.displayViewsGen,
            this.trackedFrames,
            this.dh.vrSettings.seated,
            this.visionInput != null && this.visionInput.isInputHealthy(),
            this.visionInput != null && this.visionInput.isHandTracked(VisionInput.HAND_LEFT),
            this.visionInput != null && this.visionInput.isHandTracked(VisionInput.HAND_RIGHT),
            this.mc.player != null,
            System.getProperty("os.name", ""),
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
            this.dh.vrPlayer != null && this.dh.bowTracker != null && this.mc.player != null
                && this.dh.bowTracker.isActive(this.mc.player),
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
                : (this.visionInput == null ? "" : this.visionInput.gestureSummary()));
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
        if (settings == null) return;
        if (settings.hasSeated) this.dh.vrSettings.seated = settings.seated;
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
                    detail = "manual height calibration performed";
                }
                case "reload-settings" -> {
                    this.runtimeSettings = VisionRuntimeSettings.load(this.mc.gameDirectory, System.out::println);
                    applyRuntimeSettings(this.runtimeSettings);
                    detail = "runtime settings reloaded and applied";
                }
                case "release-input" -> {
                    this.visionInput = new VisionInput(this.inputTuning);
                    this.m7Gesture.releaseAll();
                    this.bindingActions = null;
                    this.resolvedActionMap = null;
                    this.hotbarWheelActive = false;
                    this.rotatePulseDirection = 0;
                    this.rotatePulseUntilNs = 0L;
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
                    showGameChat(controlsHelpLines());
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
        VisionFrameStats.Snapshot fs = this.frameStats.snapshotAndReset();
        this.lastFrameP50Ms = (float) fs.p50Ms;
        this.lastFrameP95Ms = (float) fs.p95Ms;
        this.lastMissed90Frames = fs.missed90HzFrames;
        System.out.printf("[VRMC-M5] diag: pollHz=%.1f frames=%d maxGapMs=%.1f p50Ms=%.2f p95Ms=%.2f "
                + "p95MaxMs=%.2f missed90=%d screen=%s seated=%s hands=L%d R%d displayViewsGen=%d "
                + "trackedFrames=%d playerPresent=%d%n",
            hz, this.diagWindowFrames, this.diagMaxGapNs * 1.0E-6, fs.p50Ms, fs.p95Ms, fs.maxMs,
            fs.missed90HzFrames, screen, this.dh.vrSettings.seated,
            this.visionInput.isHandTracked(VisionInput.HAND_LEFT) ? 1 : 0,
            this.visionInput.isHandTracked(VisionInput.HAND_RIGHT) ? 1 : 0,
            this.displayViewsGen, this.trackedFrames, hasPlayer ? 1 : 0);
        boolean overBudget = fs.p95Ms > 16.7
            || fs.missed90HzFrames > Math.max(2, this.diagWindowFrames / 10);
        if (overBudget) {
            System.out.printf("[VRMC-M5][WARN] frame pacing above 90 Hz budget: p95=%.2f ms missed90=%d/%d%n",
                fs.p95Ms, fs.missed90HzFrames, this.diagWindowFrames);
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
        if ((this.m7ItemContextFrame++ % 6) == 0) {
            this.m7ItemContextBits = VisionM7ItemContext.flags(this.mc.player);
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
            }
            this.processInputs();
            this.hmdSampling();
        }
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
        this.hmdPose.rotation(this.rot.set(qx, qy, qz, qw));
        this.hmdPose.setTranslation(px, py, pz);
        this.hmdRotation.rotation(this.rot);
        this.headIsTracking = (qw != 0.0F);
        // Fail loudly if the bridge returned no usable tracking data (never silently invent poses).
        if (qw == 0.0F || !Float.isFinite(qw) || !Float.isFinite(px) || !Float.isFinite(py) || !Float.isFinite(pz)) {
            String msg = "VRMC: invalid/missing head tracking data from bridge (q=" + qx + "," + qy
                + "," + qz + "," + qw + " p=" + px + "," + py + "," + pz + ")";
            System.out.println("[VRMC-M2][FATAL] " + msg);
            throw new IllegalStateException(msg);
        }
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
                    this.visionInput.pinchDistance(VisionInput.HAND_LEFT),
                    this.visionInput.pinchDistance(VisionInput.HAND_RIGHT),
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
            // M5 seated parity (opt-in): when seated with no tracked hand, the HMD-aim fallback pose
            // may drive the controller/GUI pointer. Input actions still require real gestures.
            this.controllerTracking[c] = tracked
                || (this.seatedHmdPointer && this.dh.vrSettings.seated);
        }
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
        InputSimulator.setMousePos(
            winW * 0.5D / this.m7CursorScaleX, winH * 0.5D / this.m7CursorScaleY);
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
        double my = uv.y * (double) winH / this.m7CursorScaleY;
        if (this.m7GuiCursorLogCount < 3) {
            this.m7GuiCursorLogCount++;
            System.out.printf("[VRMC-M7] head cursor uv=(%.4f,%.4f) screenPx=(%d,%d) mouse=(%.1f,%.1f) screen=%s%n",
                uv.x, uv.y, winW, winH, mx, my, this.mc.gui.screen().getClass().getSimpleName());
        }
        InputSimulator.setMousePos(mx, my);
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

    private void applyM7Actions() {
        boolean gui = this.mc.gui.screen() != null;
        boolean seated = this.dh.vrSettings.seated;
        boolean walk = this.m7Gesture.walkActive() && !gui && !seated;
        boolean use = this.m7Gesture.place() || this.m7Gesture.eat() || this.m7Gesture.bowDraw();
        boolean attack = this.m7Gesture.attack();
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
        setM7Action(VisionInput.KEY_JUMP, VisionInput.HAND_RIGHT, this.m7Gesture.jump());
        setM7Action(VisionInput.KEY_SNEAK, VisionInput.HAND_RIGHT, this.m7Gesture.sneak());
        setM7Action(VisionInput.KEY_TELEPORT, VisionInput.HAND_LEFT, this.m7Gesture.teleportHeld());
        setM7Action(VisionInput.KEY_HOTBAR_NEXT, VisionInput.HAND_RIGHT, this.m7Gesture.hotbarNext());
        setM7Action(VisionInput.KEY_HOTBAR_PREV, VisionInput.HAND_RIGHT, this.m7Gesture.hotbarPrev());
        setM7Action(VisionInput.KEY_GUI_LEFT_CLICK, VisionInput.HAND_RIGHT, this.m7Gesture.guiClick());
        setM7Action(VisionInput.KEY_CLIMBEY_GRAB, VisionInput.HAND_LEFT, this.m7Gesture.climbGrabLeft());
        setM7Action(VisionInput.KEY_CLIMBEY_GRAB, VisionInput.HAND_RIGHT, this.m7Gesture.climbGrabRight());
        setM7Action(VisionInput.KEY_CLIMBEY_JUMP, VisionInput.HAND_NONE, this.m7Gesture.climbJump());

        VRInputAction strafe = this.getInputAction(VivecraftVRMod.INSTANCE.keyFreeMoveStrafe);
        if (strafe != null) {
            writeAnalog2D(strafe, ControllerType.RIGHT.ordinal(), 0.0F,
                walk ? this.m7Gesture.walkForward() : 0.0F, VisionInput.ORIGIN_LEFT);
        }
    }

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

    private void releaseM7Actions() {
        for (String name : new String[]{VisionInput.KEY_ATTACK, VisionInput.KEY_USE,
            VisionInput.KEY_INVENTORY, VisionInput.KEY_INGAME_MENU, VisionInput.KEY_JUMP,
            VisionInput.KEY_SNEAK, VisionInput.KEY_TELEPORT, VisionInput.KEY_HOTBAR_NEXT,
            VisionInput.KEY_HOTBAR_PREV, VisionInput.KEY_GUI_LEFT_CLICK,
            VisionInput.KEY_CLIMBEY_GRAB, VisionInput.KEY_CLIMBEY_JUMP}) {
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
        if (usable && this.visionInput.middlePressed(VisionInput.HAND_LEFT)) {
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
        // Snap turn: a tap = left, a double-tap = right. The action data is a short pulse because
        // MCVR reads getAxis1DUseTracked() (vector1) rather than a digital edge.
        if (usable) {
            if (this.visionInput.middleDoubleTapPressed(VisionInput.HAND_LEFT)) {
                this.rotatePulseDirection = 1;
                this.rotatePulseUntilNs = now + this.rotatePulseNanos;
            } else if (this.visionInput.middleTapPressed(VisionInput.HAND_LEFT)) {
                this.rotatePulseDirection = -1;
                this.rotatePulseUntilNs = now + this.rotatePulseNanos;
            }
        } else {
            this.rotatePulseDirection = 0;
            this.rotatePulseUntilNs = 0L;
        }
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
        }
    }

    /** Compact in-headset control reference (chat lines; actionbar would truncate). */
    private static String[] controlsHelpLines() {
        return new String[] {
            "[VRMC] Pinch thumb+index: attack / GUI click; left hold = teleport.",
            "[VRMC] Right fist hold = use / bow draw; left fist tap = menu; both fists tap = inventory.",
            "[VRMC] Middle pinch: left hold+move hand = walk/strafe; right hold = sneak; right tap = jump; left tap/double = snap turn; right double = radial; both tap = climb jump; both double = recenter.",
            "[VRMC] Both thumb-ring pinches: hotbar wheel (move left hand, release).",
            "[VRMC] Optional swipes: right horiz = hotbar +/-; right vert = scroll; left up/down = keyboard/chat; left horiz = swap/drop.",
            "[VRMC] Launcher: settings, tuning, recenter/calibrate, diagnostics. Reload input applies tuning live.",
        };
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

    @Override public VRRenderer createVRRenderer() { return new VisionRenderer(this); }
    @Override public boolean isActive() { return this.initialized; }
    @Override public float getIPD() { return this.ipd; }
}
