package dev.vrmc.provider;

import dev.vrmc.provider.bridge.VrmcBridge;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import org.joml.Matrix4f;
import org.joml.Matrix4fc;
import org.joml.Quaternionf;
import org.joml.Vector2f;
import org.joml.Vector2fc;
import org.joml.Vector3f;
import org.vivecraft.client.VivecraftVRMod;
import org.vivecraft.client_vr.ClientDataHolderVR;
import org.vivecraft.client_vr.gameplay.screenhandlers.KeyboardHandler;
import org.vivecraft.client_vr.gameplay.screenhandlers.RadialHandler;
import org.vivecraft.client_vr.provider.ControllerType;
import org.vivecraft.client_vr.provider.MCVR;
import org.vivecraft.client_vr.provider.VRRenderer;
import org.vivecraft.client_vr.provider.nullvr.NullVRHapticScheduler;
import org.vivecraft.client_vr.provider.openvr_lwjgl.VRInputAction;

import java.io.File;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
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
    private final ByteBuffer tracking = ByteBuffer.allocateDirect(TRACKING_BYTES).order(ByteOrder.nativeOrder());
    private final ByteBuffer displayViews = ByteBuffer.allocateDirect(VrmcBridge.DISPLAY_VIEWS_BYTES).order(ByteOrder.nativeOrder());
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
    private VRInputAction[] bindingActions;
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
        this.visionInput = new VisionInput(tuning);
        this.smoothingConfig = loadSmoothingConfig(tuning);
        this.poseSmoothers = new VisionPoseSmoother[] {
            new VisionPoseSmoother(this.smoothingConfig),
            new VisionPoseSmoother(this.smoothingConfig)
        };
        logInputTuning(this.visionInput);
        logSmoothingConfig(this.smoothingConfig);

        this.initialized = true;
        this.initSuccess = true;
        System.out.println("[VRMC-M2] VisionVR.init() succeeded");
        return true;
    }

    @Override
    public void destroy() {
        // Shutdown ordering (M4 follow-up, EV-0096 defect): drop the eye-texture handles BEFORE the
        // renderer/VkImages are destroyed so the compositor cannot sample a freed MTLTexture.
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

    private static void logSmoothingConfig(VisionPoseSmoother.Config c) {
        System.out.printf("[VRMC-M4] hand smoothing: enabled=%s posMinCutoff=%.2f posBeta=%.2f dCutoff=%.2f "
                + "rotMinCutoff=%.2f rotBeta=%.2f%n",
            c.enabled, c.posMinCutoff, c.posBeta, c.derivativeCutoff, c.rotMinCutoff, c.rotBeta);
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
            if (renderer != null) {
                renderer.setEyeFov(eye, l, r, u, d);
            }
            Matrix4f eyeToHead = eye == 0 ? this.hmdPoseLeftEye : this.hmdPoseRightEye;
            float[] m = new float[16];
            for (int k = 0; k < 16; k++) {
                m[k] = this.displayViews.getFloat(o + 16 + k * 4);
            }
            eyeToHead.set(m); // JOML column-major, same layout as the C matrix
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
            this.updateAim();
            this.processInputs();
            this.hmdSampling();
        }
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
                    this.poseSmoothers[c].apply(this.controllerPose[c], System.nanoTime());
                }
            } else {
                if (this.poseSmoothers != null) {
                    this.poseSmoothers[c].reset();
                }
                VisionHandPose.gazeFallback(this.hmdPose, hand == VisionInput.HAND_RIGHT,
                    this.controllerPose[c]);
            }
            this.controllerTracking[c] = tracked;
        }
    }

    // ------------------------------------------------------------------------------------------
    // M4-W1 logging (decisive + rate-limited; never logs raw joint arrays)
    // ------------------------------------------------------------------------------------------

    private void logInputDiagnostics() {
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

        this.applyActionData();

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
