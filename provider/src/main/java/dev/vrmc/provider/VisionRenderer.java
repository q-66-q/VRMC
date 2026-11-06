package dev.vrmc.provider;

import com.mojang.blaze3d.GpuFormat;
import com.mojang.blaze3d.systems.RenderSystem;
import net.minecraft.client.Minecraft;
import net.minecraft.client.Screenshot;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import org.joml.Matrix4f;
import org.joml.Vector2i;
import org.joml.Vector2ic;
import org.joml.Vector4f;
import org.vivecraft.api.client.data.RenderPass;
import org.vivecraft.client.extensions.LevelRenderStateExtension;
import org.vivecraft.client_vr.ClientDataHolderVR;
import org.vivecraft.client_vr.MethodHolder;
import org.vivecraft.client_vr.VRData;
import org.vivecraft.client_vr.VRTextureTarget;
import org.vivecraft.client_vr.gameplay.screenhandlers.GuiHandler;
import org.vivecraft.client_vr.provider.MCVR;
import org.vivecraft.client_vr.provider.VRRenderer;
import org.vivecraft.client_vr.render.helpers.graphics.GraphicsHelper;
import org.vivecraft.client_vr.render.renderstates.VRRenderState;
import org.vivecraft.client_vr.settings.VRSettings;
import dev.vrmc.provider.bridge.VrmcBridge;

/**
 * M2 stereo renderer: creates the two eye targets and hands their texture handles to the bridge.
 * The OpenGL build (desktop harness) can export GL texture ids today; the Vulkan/MoltenVK path on
 * visionOS uses the S4a interop decision (docs/mvp/S4A_FINDINGS.md) instead.
 *
 * <p>Eye-target content (see docs/analysis/vivecraft-eye-render.md): each frame Vivecraft renders the
 * LEFT/RIGHT passes into {@code framebufferVrRender} (world or menu room + the in-world GUI quad +
 * hands) and then {@code ShaderHelper.doVrPostProcess} copies that image into {@code framebufferEye[0/1]}.
 * {@link #endFrame()} runs after all passes, so the handles submitted here always refer to a rendered
 * image of the current frame (GPU completion is the bridge's job, not the Java side's).
 */
public class VisionRenderer extends VRRenderer {
    /**
     * M8 default per-eye render target before the compositor's display feedback arrives. The old M2
     * renderer used this as a fixed size forever; it is now only the bring-up/fallback size, and the
     * compositor's logical display geometry (plus the eye-scale policy below) drives the real size.
     */
    private static final int DEFAULT_EYE_WIDTH = Integer.getInteger("vrmc.eyeWidth", 1024);
    private static final int DEFAULT_EYE_HEIGHT = Integer.getInteger("vrmc.eyeHeight", 1024);
    /** Half of the (square) per-eye render FOV, in radians. Vision Pro's per-eye FOV fits inside 110°. */
    private static final float EYE_HALF_FOV_RAD =
        0.5F * Mth.DEG_TO_RAD * Float.parseFloat(System.getProperty("vrmc.eyeFovDeg", "110"));
    /**
     * Eye-target PNG capture for off-device verification (layout mirrors macstream's proven
     * RemoteVRStereoRenderer FBO capture): enabled by -Dvrmc.captureDir=&lt;dir&gt; or by a
     * "vrmc-capture.flag" file in the game directory (then &lt;gameDir&gt;/vrmc-capture/ is used).
     * Off by default; capped so a diagnostic run cannot fill the device container.
     */
    private static final int CAPTURE_EVERY = Integer.getInteger("vrmc.captureEvery", 300);
    private static final int CAPTURE_MAX = Integer.getInteger("vrmc.captureMax", 3);
    /** Per-frame render-state diagnostics interval (0 disables). Mirrors the tracking-frame cadence. */
    private static final int DIAG_EVERY = Integer.getInteger("vrmc.diagEvery", 300);
    /**
     * M8 render feedback: the compositor publishes the display's LOGICAL per-eye size (the size that
     * maps 1:1 to displayed pixels in the fovea), the physical foveated drawable extent and the
     * measured display cadence. The provider renders its stereo eye targets at
     * logical size x eyeScale and adapts eyeScale to hold the display cadence. This is what replaces
     * the fixed 1024x1024 upscaled to the headset viewport (the visible softness/jaggedness).
     *
     * <p>Eye-scale knob: {@code -Dvrmc.eyeScale=auto|0.25..1.0} or the game-directory file
     * {@code vrmc-eye-scale.txt} (same content; re-read every ~600 frames so on-device tuning needs no
     * rebuild/relaunch). "auto" (default) starts at AUTO_INITIAL_SCALE and steps 0.05 up / 0.10 down
     * every ~240 frames from the renderer's own frame pacing against the measured display interval.
     */
    private final java.nio.ByteBuffer renderSettingsBuffer =
        java.nio.ByteBuffer.allocateDirect(VrmcBridge.RENDER_SETTINGS_BYTES).order(java.nio.ByteOrder.LITTLE_ENDIAN);
    private final VisionFrameStats renderFrameStats = new VisionFrameStats(240);
    private long lastFrameNanos;
    private VisionRenderSettings renderSettings = VisionRenderSettings.none();
    private boolean loggedRenderSettings;
    private boolean loggedNoRenderSettings;
    private int renderSettingsErrors;
    private boolean eyeScaleAuto = true;
    private float eyeScale = VisionRenderSettings.AUTO_INITIAL_SCALE;
    private String eyeScaleSource = "auto(default)";
    private int headroomWindows;
    private int raiseHoldWindows;
    private int currentEyeWidth = DEFAULT_EYE_WIDTH;
    private int currentEyeHeight = DEFAULT_EYE_HEIGHT;
    private int eyeResizeCount;
    private long lastEyeResizeFrame = -1000L;
    private long lastEyeScaleReadFrame = -1000L;
    /** M8 target cadence override (game dir vrmc-target-hz.txt): 0 = follow measured, else 60..120 Hz. */
    private int targetHzOverride = 0;
    private String targetHzSource = "auto(display)";
    private long lastTargetHzReadFrame = -1000L;
    /** Last knob value parsed from the file (to detect operator changes after an auto-revert). */
    private int lastTargetHzFileValue = Integer.MIN_VALUE;
    /** Consecutive windows where the measured display stayed below the configured target. */
    private int targetLowWindows;
    /** True after the guardrail reverted an unreachable target; stays auto until the knob changes. */
    private boolean targetReverted;
    private int revertedTargetHz;
    /** Opt-in M8 content-first governor (game dir vrmc-content-first.txt): cut scene cost before resolution. */
    private final VisionContentGovernor contentGovernor = new VisionContentGovernor();
    private long lastContentFirstReadFrame = -1000L;
    /** Frame index when the world level became non-null (-1 = no level yet); drives resize gating. */
    private long levelLoadedFrame = -1L;
    /** True once an eye-target rebuild threw; the auto policy is disabled to avoid a retry loop. */
    private boolean loggedResizeFailure;
    /** M8 frame trace CSV (game dir): one row per auto-policy window; disabled on the first write error. */
    private java.nio.file.Path tracePath;
    private boolean traceUnavailable;
    private long traceRows;
    private boolean loggedM8State;
    private long frameIndex;
    private boolean polled;
    private boolean loggedNoHandle;
    /** Latest headset per-eye frustum tangents {left,right,up,down} (signed; left/down negative). */
    private final float[][] eyeFovTan = new float[2][4];
    private volatile boolean hasDisplayViews;
    private long lastLeftHandle = -1L;
    private long lastRightHandle = -1L;
    private Boolean captureEnabled;
    private java.nio.file.Path captureDir;
    private int captured;
    /**
     * Provider-side GPU eye-frame sync, off unless the game-directory flag {@code vrmc-gpu-sync.flag}
     * (or {@code -Dvrmc.gpuSync=1}) is present. Resolved once; {@code null} means "use the existing
     * unsynchronized submitEyes path". See docs/analysis/provider-gpu-sync.md.
     */
    private GpuEyeSync gpuSync;
    private boolean loggedSyncedSubmit;

    public VisionRenderer(MCVR vr) {
        super(vr);
        System.out.println("[VRMC-M2] VisionRenderer created");
        this.gpuSync = resolveGpuSync();
    }

    /** Best-effort, never throws: {@link GpuEyeSync#tryEnable} logs one warning on a requested-but-unavailable path. */
    private static GpuEyeSync resolveGpuSync() {
        try {
            Minecraft mc = Minecraft.getInstance();
            return GpuEyeSync.tryEnable(mc != null ? mc.gameDirectory : null);
        } catch (Throwable t) {
            System.out.println("[VRMC-M2][gpu-sync] WARNING: enable probe failed (" + t
                + "); falling back to unsynchronized eye submission");
            return null;
        }
    }

    @Override
    public Vector2ic getRenderTextureSizes() {
        if (this.resolution == null) {
            this.resolution = new Vector2i(this.currentEyeWidth, this.currentEyeHeight);
            this.ss = -1.0F;
            System.out.println("[VRMC-M8] render texture size " + this.currentEyeWidth + "x"
                + this.currentEyeHeight + " (default until the compositor reports display geometry)");
        }
        return this.resolution;
    }

    /**
     * Adopt the headset's per-eye frustum (signed tangents) and rebuild the cached projections.
     */
    public void setEyeFov(int eye, float left, float right, float up, float down) {
        float[] t = this.eyeFovTan[eye];
        t[0] = left;
        t[1] = right;
        t[2] = up;
        t[3] = down;
        // NaN != anything: forces getCachedProjectionMatrix/getCachedReverseProjectionMatrix to rebuild.
        this.lastFarClip = Float.NaN;
        this.lastReverseFarClip = Float.NaN;
        this.hasDisplayViews = true;
    }

    public boolean hasDisplayViews() { return this.hasDisplayViews; }

    /** M8: true when a world level is loaded. Render-thread read; never throws into the frame. */
    private boolean currentLevelLoaded() {
        try {
            Minecraft mc = Minecraft.getInstance();
            return mc != null && mc.level != null;
        } catch (RuntimeException | LinkageError ignored) {
            return false;
        }
    }

    // ---- M8 render-state accessors (read by VisionVR's diagnostic line / device verification) ----
    public int renderEyeTargetWidth() { return this.currentEyeWidth; }
    public int renderEyeTargetHeight() { return this.currentEyeHeight; }
    public VisionRenderSettings renderSettingsSnapshot() { return this.renderSettings; }
    public float eyeScaleValue() { return this.eyeScale; }
    public boolean eyeScaleIsAuto() { return this.eyeScaleAuto; }
    public int eyeResizeCount() { return this.eyeResizeCount; }

    /** Applied per-eye frustum tangents (only meaningful once {@link #hasDisplayViews()}). */
    public float[] getAppliedTangents(int eye) { return this.eyeFovTan[eye]; }

    @Override
    protected Matrix4f getProjectionMatrix(int eyeType, float nearClip, float farClip) {
        boolean zZeroToOne = RenderSystem.getDevice().getDeviceInfo().isZZeroToOne();
        if (this.hasDisplayViews) {
            // Render exactly the headset's asymmetric per-eye frustum; the compositor can then map the
            // eye texture 1:1 to the drawable (macstream Phase 8 root cause 4: client FOV, not NullVR).
            float[] t = this.eyeFovTan[eyeType];
            return new Matrix4f().frustum(t[0] * nearClip, t[1] * nearClip, t[3] * nearClip,
                t[2] * nearClip, nearClip, farClip, zZeroToOne);
        }
        return new Matrix4f().setPerspective(2.0F * EYE_HALF_FOV_RAD, 1.0F, nearClip, farClip, zZeroToOne);
    }

    @Override
    public void createRenderTexture(int width, int height) {
        this.currentEyeWidth = width;
        this.currentEyeHeight = height;
        this.resolution = new Vector2i(width, height);
        System.out.println("[VRMC-M8] creating eye targets " + width + "x" + height + " (scale="
            + String.format(java.util.Locale.ROOT, "%.2f", this.eyeScale) + " source="
            + this.eyeScaleSource + " displayLogical=" + this.renderSettings.leftLogicalWidth + "x"
            + this.renderSettings.leftLogicalHeight + " resizes=" + this.eyeResizeCount + ")");
        for (int i = 0; i < 2; i++) {
            this.framebufferEye[i] = VRTextureTarget.builder((i == 0 ? "L" : "R") + " Eye")
                .withSize(width, height)
                .withFormat(GpuFormat.RGBA8_UNORM)
                .build();
            System.out.println("[VRMC-M2] eye target " + (i == 0 ? "L" : "R") + " " + width + "x" + height);
            GraphicsHelper.INSTANCE.checkError((i == 0 ? "Left" : "Right") + " eye target");
        }
    }

    @Override
    public void endFrame() {
        final long frameNanos = System.nanoTime();
        if (this.lastFrameNanos != 0L) this.renderFrameStats.record(frameNanos - this.lastFrameNanos);
        this.lastFrameNanos = frameNanos;
        // Track when a world level first becomes available; eye-target resizes are held back until the
        // world has been stable for a moment (see VisionRenderSettings.canResizeNow).
        if (currentLevelLoaded()) {
            if (this.levelLoadedFrame < 0L) this.levelLoadedFrame = this.frameIndex;
        } else {
            this.levelLoadedFrame = -1L;
        }
        if (this.framebufferEye[0] == null || this.framebufferEye[1] == null) {
            return;
        }
        long lt = textureHandle(this.framebufferEye[0]);
        long rt = textureHandle(this.framebufferEye[1]);
        if (lt != 0 && rt != 0) {
            // A framebuffer reinit replaces both VkImages; the bridge keeps the previous (now destroyed)
            // handles until this submit, so the compositor may sample a stale/freed texture for a frame.
            // Log the transition so a device log proves/disproves that window.
            if (this.lastLeftHandle != -1L &&
                (lt != this.lastLeftHandle || rt != this.lastRightHandle)) {
                System.out.printf(
                    "[VRMC-DIAG] eye target handles changed L=0x%x->0x%x R=0x%x->0x%x (framebuffer reinit)%n",
                    this.lastLeftHandle, lt, this.lastRightHandle, rt);
            }
            this.lastLeftHandle = lt;
            this.lastRightHandle = rt;
            // Report the ACTUAL current eye-target size (not the pending resize target): a resize only
            // takes effect on the next render-target reinit, so one frame may still submit the old size.
            final int eyeWidth = this.framebufferEye[0].width;
            final int eyeHeight = this.framebufferEye[0].height;
            int rc = submitEyes(lt, rt, eyeWidth, eyeHeight);
            if (rc != 0) {
                VRSettings.LOGGER.warn("VRMC: submitEyes failed rc={}", rc);
            }
        } else if (!this.loggedNoHandle) {
            this.loggedNoHandle = true;
            System.out.println("[VRMC-M2] eye texture handle unavailable (Vulkan export failed or GL handle missing)");
        }
        if (!this.polled) {
            VRSettings.LOGGER.warn("VRMC: frame ended without poll");
        }
        this.polled = false;
        maybeLogDiag();
        maybeCaptureEyeTargets();
        pollRenderSettings();
        this.frameIndex++;
    }

    /**
     * Once every {@link #DIAG_EVERY} frames, log the render-state facts that decide whether the eye
     * textures can contain the menu GUI at all: current pass, menu-room/menu-world state, the screen,
     * the GUI world position and its NDC in each eye, plus the applied eye frustum.
     */
    private void maybeLogDiag() {
        if (DIAG_EVERY <= 0 || (this.frameIndex % DIAG_EVERY) != 0) {
            return;
        }
        try {
            logDiag();
        } catch (RuntimeException e) {
            System.out.println("[VRMC-DIAG] failed: " + e);
        }
    }

    private void logDiag() {
        Minecraft mc = Minecraft.getInstance();
        ClientDataHolderVR dh = ClientDataHolderVR.getInstance();
        boolean menuRoom = MethodHolder.isInMenuRoom();
        boolean menuWorldReady = dh.menuWorldRenderer != null && dh.menuWorldRenderer.isReady();
        String screen = mc.gui.screen() == null ? "none" : mc.gui.screen().getClass().getSimpleName();
        StringBuilder sb = new StringBuilder("[VRMC-DIAG] frame=").append(this.frameIndex)
            .append(" pass=").append(dh.currentPass)
            .append(" menuRoom=").append(menuRoom ? 1 : 0)
            .append(" level=").append(mc.level == null ? "null" : "loaded")
            .append(" menuWorld=").append(menuWorldReady ? "ready"
                : (dh.menuWorldRenderer != null ? "pending" : "off"))
            .append(" screen=").append(screen)
            .append(" seated=").append(dh.vrSettings.seated ? 1 : 0)
            .append(" fbGUI=").append(GuiHandler.GUI_FRAMEBUFFER != null ? 1 : 0)
            .append(" displayViews=").append(this.hasDisplayViews ? 1 : 0);
        if (this.hasDisplayViews) {
            sb.append(String.format(" tanL=(%.3f,%.3f,%.3f,%.3f) tanR=(%.3f,%.3f,%.3f,%.3f)",
                this.eyeFovTan[0][0], this.eyeFovTan[0][1], this.eyeFovTan[0][2], this.eyeFovTan[0][3],
                this.eyeFovTan[1][0], this.eyeFovTan[1][1], this.eyeFovTan[1][2], this.eyeFovTan[1][3]));
        }
        VRData world = dh.vrPlayer != null ? dh.vrPlayer.getVRDataWorld() : null;
        VRRenderState vrState = null;
        try {
            vrState = ((LevelRenderStateExtension) mc.gameRenderer.gameRenderState().levelRenderState)
                .vivecraft$getVRRenderState();
        } catch (RuntimeException ignore) {
            // render state not available yet (very first frames)
        }
        if (vrState != null) {
            sb.append(" renderGui=").append(vrState.renderGui ? 1 : 0);
            Vec3 guiPos = vrState.guiState.worldPos;
            if (guiPos != null) {
                sb.append(String.format(" guiPos=(%.2f,%.2f,%.2f)", guiPos.x, guiPos.y, guiPos.z));
                if (world != null) {
                    for (int eye = 0; eye < 2; eye++) {
                        Matrix4f proj = this.eyeProj[eye];
                        if (proj == null) {
                            continue;
                        }
                        RenderPass pass = eye == 0 ? RenderPass.LEFT : RenderPass.RIGHT;
                        Matrix4f view = world.getEye(pass).getMatrix().transpose();
                        Vector4f clip = new Vector4f((float) guiPos.x, (float) guiPos.y, (float) guiPos.z, 1.0F);
                        view.transform(clip);
                        proj.transform(clip);
                        if (Math.abs(clip.w) > 1.0e-6F) {
                            sb.append(String.format(" guiNDC%s=(%.2f,%.2f)", eye == 0 ? "L" : "R",
                                clip.x / clip.w, clip.y / clip.w));
                        }
                    }
                }
            }
        }
        if (world != null) {
            Vec3 lp = world.getEye(RenderPass.LEFT).getPosition();
            Vec3 rp = world.getEye(RenderPass.RIGHT).getPosition();
            sb.append(String.format(" eyeL=(%.3f,%.3f,%.3f) eyeR=(%.3f,%.3f,%.3f)",
                lp.x, lp.y, lp.z, rp.x, rp.y, rp.z));
        }
        System.out.println(sb);
        // M8 render state: one line per diagnostics interval so a device log alone answers "what was
        // the display asking for, what did the provider render, and is foveation/cadence live?".
        VisionRenderSettings rs = this.renderSettings;
        if (rs.valid) {
            System.out.println(String.format(java.util.Locale.ROOT,
                "[VRMC-M8] render state frame=%d eyeTarget=%dx%d logical=%dx%d drawable=%dx%d "
                    + "foveation=%d rateMaps=%d displayHz=%.1f target=%d(%s) quality=%.2f/%.2f "
                    + "scale=%.2f(%s) resizes=%d contentFirst=%d(%d)",
                this.frameIndex, this.currentEyeWidth, this.currentEyeHeight,
                rs.leftLogicalWidth, rs.leftLogicalHeight, rs.drawableWidth, rs.drawableHeight,
                rs.foveationEnabled ? 1 : 0, rs.rateMapCount, rs.displayHz, this.targetHzOverride,
                this.targetHzSource, rs.renderQuality, rs.maxRenderQuality, this.eyeScale,
                this.eyeScaleSource, this.eyeResizeCount,
                this.contentGovernor.enabled() ? 1 : 0, this.contentGovernor.reductions()));
        } else if (!this.loggedM8State) {
            this.loggedM8State = true;
            System.out.println("[VRMC-M8] render state: no display feedback yet (compositor immersive "
                + "layer not up or old bridge); eyeTarget=" + this.currentEyeWidth + "x"
                + this.currentEyeHeight);
        }
    }

    /**
     * Diagnostic only: write the post-processed eye targets (and the pre-postprocess world target) to
     * PNG so the exact exported content can be inspected off-device with devicectl/Documents access.
     * Adapted from macstream RemoteVRStereoRenderer's capture harness (LGPL-3.0 reference, ADR-0009).
     */
    private void maybeCaptureEyeTargets() {
        if (this.captureEnabled == null) {
            this.captureEnabled = resolveCapture();
        }
        if (!Boolean.TRUE.equals(this.captureEnabled) || this.captured >= CAPTURE_MAX
            || (this.frameIndex % CAPTURE_EVERY) != 0)
        {
            return;
        }
        this.captured++;
        capture("vrmc_world_f" + this.frameIndex, Minecraft.getInstance().gameRenderer.mainRenderTarget());
        for (int i = 0; i < 2; i++) {
            capture("vrmc_eye_" + (i == 0 ? "L" : "R") + "_f" + this.frameIndex, this.framebufferEye[i]);
        }
    }

    private void capture(String name, com.mojang.blaze3d.pipeline.RenderTarget target) {
        if (target == null || this.captureDir == null) {
            return;
        }
        try {
            Screenshot.grab(this.captureDir.toFile(), name, target, 1,
                component -> System.out.println("[VRMC-CAP] " + component));
            System.out.println("[VRMC-CAP] frame " + this.frameIndex + " " + name + " -> "
                + this.captureDir.resolve(name + ".png"));
        } catch (RuntimeException e) {
            System.out.println("[VRMC-CAP] capture failed for " + name + ": " + e);
            this.captured = CAPTURE_MAX;
        }
    }

    private boolean resolveCapture() {
        String explicit = System.getProperty("vrmc.captureDir");
        java.nio.file.Path dir;
        if (explicit != null && !explicit.isEmpty()) {
            dir = java.nio.file.Path.of(explicit);
        } else {
            java.io.File gameDir = Minecraft.getInstance().gameDirectory;
            java.io.File flag = gameDir == null ? null : new java.io.File(gameDir, "vrmc-capture.flag");
            if (flag == null || !flag.isFile()) {
                return false;
            }
            // The flag file can be overwritten (devicectl cannot delete files) to disable capture:
            // content "off" / "0" / "false" turns it off without changing the provider jar again.
            try {
                String text = java.nio.file.Files.readString(flag.toPath()).trim()
                    .toLowerCase(java.util.Locale.ROOT);
                if (text.equals("0") || text.equals("off") || text.equals("false")) {
                    System.out.println("[VRMC-CAP] eye-target PNG capture disabled by flag content (" + text + ")");
                    return false;
                }
            } catch (RuntimeException | java.io.IOException ignored) {
                // empty/unreadable flag => enabled (existence semantics, as before)
            }
            dir = gameDir.toPath().resolve("vrmc-capture");
        }
        try {
            java.nio.file.Files.createDirectories(dir);
        } catch (java.io.IOException e) {
            System.out.println("[VRMC-CAP] cannot create capture dir " + dir + ": " + e);
            return false;
        }
        this.captureDir = dir;
        System.out.println("[VRMC-CAP] eye-target PNG capture enabled dir=" + dir + " every=" + CAPTURE_EVERY
            + " max=" + CAPTURE_MAX);
        return true;
    }

    private boolean loggedVulkanExport;

    /**
     * GL backends expose a GL texture id directly. Vulkan (MoltenVK) exposes a VkImage handle, which
     * is exported to an MTLTexture through the bridge (ABI v2) so the compositor/native side can
     * consume it zero-copy (S4a host+device PASS: EV-0063/EV-0065).
     */
    private long textureHandle(VRTextureTarget target) {
        try {
            long handle = GraphicsHelper.INSTANCE.getTextureHandle(target.getColorTexture());
            if (handle == 0) {
                return 0;
            }
            String backend = RenderSystem.getDevice().getDeviceInfo().backendName();
            if (backend != null && backend.toLowerCase().contains("opengl")) {
                return handle;
            }
            long mtl = VrmcBridge.exportMTLTexture(handle);
            if (!this.loggedVulkanExport) {
                this.loggedVulkanExport = true;
                System.out.printf("[VRMC-M2] vulkan eye export: VkImage=0x%x -> MTLTexture=0x%x%n", handle, mtl);
            }
            return mtl;
        } catch (RuntimeException e) {
            if (!this.loggedVulkanExport) {
                this.loggedVulkanExport = true;
                System.out.println("[VRMC-M2] vulkan eye export unavailable: " + e);
            }
            return 0;
        }
    }

    /**
     * Publish the eye textures to the bridge. When the flag-gated GPU sync is enabled and healthy this
     * first appends a timeline signal to MC's own frame submission and then uses the synced ABI path
     * ({@code submitEyesSynced}) so the compositor can wait on the exact GPU frame before sampling; any
     * problem falls back to the unsynchronized {@code submitEyes} call for that frame and logs once.
     */
    private int submitEyes(long lt, long rt, int eyeWidth, int eyeHeight) {
        long syncEvent = 0L;
        long syncValue = 0L;
        GpuEyeSync sync = this.gpuSync;
        if (sync != null && sync.enabled()) {
            long value = sync.nextSignalValue();
            if (sync.signalOnGameFrameSubmit(value)) {
                syncEvent = sync.sharedEvent();
                syncValue = value;
            }
        }
        if (syncEvent != 0L) {
            try {
                int rc = VrmcBridge.submitEyesSynced(lt, rt, (int) this.frameIndex, eyeWidth,
                    eyeHeight, EYE_HALF_FOV_RAD, syncEvent, syncValue);
                if (!this.loggedSyncedSubmit) {
                    this.loggedSyncedSubmit = true;
                    System.out.printf(
                        "[VRMC-M2][gpu-sync] frame %d using synced submit: event=0x%x waitValue=%d%n",
                        this.frameIndex, syncEvent, syncValue);
                }
                return rc;
            } catch (UnsatisfiedLinkError e) {
                // Bridge dylib predates nativeSubmitEyesSynced: revert permanently, keep rendering.
                System.out.println("[VRMC-M2][gpu-sync] WARNING: bridge dylib has no "
                    + "nativeSubmitEyesSynced (" + e + "); falling back to unsynchronized eye submission");
                sync.close();
                this.gpuSync = null;
            }
        }
        return VrmcBridge.submitEyes(lt, rt, (int) this.frameIndex, eyeWidth, eyeHeight,
            EYE_HALF_FOV_RAD);
    }

    /**
     * M8: poll the compositor's render feedback once per rendered frame (cheap direct-buffer copy, no
     * allocation on the happy path), adapt the eye scale and resize the stereo eye targets when the
     * display geometry changed. Fail-safe: an old bridge without the symbol, a short buffer or an
     * unpublished payload keeps the current target and never throws into the render loop.
     */
    private void pollRenderSettings() {
        int rc;
        try {
            rc = VrmcBridge.pollRenderSettings(this.renderSettingsBuffer);
        } catch (UnsatisfiedLinkError oldBridge) {
            if (!this.loggedNoRenderSettings) {
                this.loggedNoRenderSettings = true;
                System.out.println("[VRMC-M8] bridge dylib has no render feedback (nativePollRenderSettings): "
                    + "keeping the default " + this.currentEyeWidth + "x" + this.currentEyeHeight
                    + " eye target; presentation/eye submission unaffected");
            }
            return;
        } catch (RuntimeException bridgeError) {
            if (this.renderSettingsErrors++ == 0) {
                System.out.println("[VRMC-M8] render feedback poll failed (" + bridgeError
                    + "); keeping the current eye target");
            }
            return;
        }
        if (rc != 0) {
            if (this.renderSettingsErrors++ == 0) {
                System.out.println("[VRMC-M8] render feedback poll rc=" + rc
                    + "; keeping the current eye target");
            }
            return;
        }
        VisionRenderSettings settings = VisionRenderSettings.parse(this.renderSettingsBuffer);
        if (!settings.valid) {
            if (!this.loggedNoRenderSettings) {
                this.loggedNoRenderSettings = true;
                System.out.println("[VRMC-M8] render settings: none published yet (compositor immersive "
                    + "layer not up or old bridge); keeping " + this.currentEyeWidth + "x"
                    + this.currentEyeHeight + " eye target");
            }
            return;
        }
        this.renderSettings = settings;
        if (!this.loggedRenderSettings) {
            this.loggedRenderSettings = true;
            System.out.println("[VRMC-M8] " + settings.describe());
        }
        maybeReadEyeScale();
        maybeReadTargetHz();
        maybeReadContentFirst();
        maybeAdaptEyeScale(settings);
        maybeResizeEyeTargets(settings);
    }

    /** Re-read the eye-scale knob (system property or game-dir file) every ~600 frames. */
    private void maybeReadEyeScale() {
        if (this.frameIndex - this.lastEyeScaleReadFrame < 600L) return;
        this.lastEyeScaleReadFrame = this.frameIndex;
        String value = System.getProperty("vrmc.eyeScale", "");
        try {
            java.io.File gameDir = Minecraft.getInstance().gameDirectory;
            if (gameDir != null) {
                java.io.File knob = new java.io.File(gameDir, "vrmc-eye-scale.txt");
                if (knob.isFile()) {
                    String text = java.nio.file.Files.readString(knob.toPath()).trim();
                    if (!text.isEmpty()) value = text;
                }
            }
        } catch (RuntimeException | java.io.IOException ignored) {
            // keep the property/default when the knob file is unreadable
        }
        if (value == null || value.isEmpty()) value = "auto";
        if (value.equalsIgnoreCase("auto")) {
            if (!this.eyeScaleAuto) {
                this.eyeScaleAuto = true;
                this.eyeScale = VisionRenderSettings.AUTO_INITIAL_SCALE;
                this.eyeScaleSource = "auto(file)";
                System.out.println("[VRMC-M8] eye scale: auto (start "
                    + String.format(java.util.Locale.ROOT, "%.2f", this.eyeScale) + ")");
            }
            return;
        }
        try {
            float parsed = Float.parseFloat(value);
            if (parsed >= VisionRenderSettings.MIN_SCALE && parsed <= VisionRenderSettings.MAX_SCALE) {
                if (this.eyeScaleAuto || Math.abs(parsed - this.eyeScale) > 1.0e-3f) {
                    System.out.println("[VRMC-M8] eye scale: fixed " + String.format(java.util.Locale.ROOT,
                        "%.2f", parsed) + " (was " + this.eyeScaleSource + ")");
                }
                this.eyeScaleAuto = false;
                this.eyeScale = parsed;
                this.eyeScaleSource = "fixed(file)";
            } else {
                System.out.println("[VRMC-M8] eye scale: ignoring out-of-range value '" + value
                    + "' (expected auto or " + VisionRenderSettings.MIN_SCALE + ".."
                    + VisionRenderSettings.MAX_SCALE + ")");
            }
        } catch (NumberFormatException malformed) {
            System.out.println("[VRMC-M8] eye scale: ignoring unparsable value '" + value + "'");
        }
    }

    /**
     * Append one M8 frame-trace row (game dir vrmc-m8-trace.csv) for the window just measured.
     * Best-effort by design: the first write failure disables tracing with one warning and never
     * affects rendering. The row is a snapshot before this window's policy adjustments.
     */
    private void appendTraceRow(VisionRenderSettings settings, VisionFrameStats.Snapshot stats) {
        if (this.traceUnavailable) return;
        try {
            if (this.tracePath == null) {
                java.io.File gameDir = Minecraft.getInstance().gameDirectory;
                if (gameDir == null) return;
                this.tracePath = gameDir.toPath().resolve(VisionTrace.FILE_NAME);
                if (!java.nio.file.Files.isRegularFile(this.tracePath)) {
                    java.nio.file.Files.writeString(this.tracePath, VisionTrace.HEADER + "\n",
                        java.nio.file.StandardOpenOption.CREATE,
                        java.nio.file.StandardOpenOption.TRUNCATE_EXISTING);
                }
                // Log once per session whether the file is new or appended to from an earlier run.
                System.out.println("[VRMC-M8] trace: " + this.tracePath
                    + " (CSV, one row per auto-policy window, appended)");
            }
            if (this.traceRows >= VisionTrace.MAX_ROWS) {
                this.traceUnavailable = true;
                System.out.println("[VRMC-M8] trace: capped at " + VisionTrace.MAX_ROWS
                    + " rows; further rows are not written");
                return;
            }
            int targetHz = this.targetHzOverride > 0 ? this.targetHzOverride
                : (int) Math.round(settings.displayHz);
            String row = VisionTrace.row(this.frameIndex, System.currentTimeMillis(),
                settings.displayHz, targetHz, this.currentEyeWidth, this.currentEyeHeight,
                this.eyeScale, this.eyeResizeCount, stats.missedTargetFrames, stats.samples,
                stats.p50Ms, stats.p95Ms, settings.foveationEnabled ? 1 : 0, settings.rateMapCount,
                settings.renderQuality, settings.maxRenderQuality,
                this.contentGovernor.enabled() ? 1 : 0, this.contentGovernor.reductions());
            java.nio.file.Files.writeString(this.tracePath, row + "\n",
                java.nio.file.StandardOpenOption.CREATE,
                java.nio.file.StandardOpenOption.APPEND);
            this.traceRows++;
        } catch (Throwable traceError) {
            this.traceUnavailable = true;
            System.out.println("[VRMC-M8][WARN] frame trace disabled: " + traceError);
        }
    }

    /**
     * Re-read the target-cadence knob every ~300 frames (the operator may push it while playing).
     * "auto" (default) follows the display cadence the compositor measured; 90/96/100/120 lets the
     * operator aim at a higher rate so the provider keeps frames inside the shorter deadline and the
     * system can promote the display (if the device cannot hold it, the eye scale settles lower).
     */
    private void maybeReadTargetHz() {
        if (this.frameIndex - this.lastTargetHzReadFrame < 300L) return;
        this.lastTargetHzReadFrame = this.frameIndex;
        String value = "auto";
        try {
            java.io.File gameDir = Minecraft.getInstance().gameDirectory;
            if (gameDir != null) {
                java.io.File knob = new java.io.File(gameDir, "vrmc-target-hz.txt");
                if (knob.isFile()) {
                    String text = java.nio.file.Files.readString(knob.toPath()).trim();
                    if (!text.isEmpty()) value = text;
                }
            }
        } catch (RuntimeException | java.io.IOException ignored) {
            // keep the current target when the knob file is unreadable
        }
        int parsed = VisionRenderSettings.parseTargetHz(value);
        if (parsed < 0) {
            System.out.println("[VRMC-M8] target cadence: ignoring invalid value '" + value
                + "' (expected auto or " + VisionRenderSettings.MIN_TARGET_HZ + ".."
                + VisionRenderSettings.MAX_TARGET_HZ + " Hz)");
            return;
        }
        // A guardrail auto-revert stays in force until the operator changes the file content: the
        // same unreachable value is not re-applied every re-read (that would loop revert -> re-arm).
        if (parsed != this.lastTargetHzFileValue) {
            this.lastTargetHzFileValue = parsed;
            if (this.targetReverted && parsed != this.revertedTargetHz) {
                this.targetReverted = false;
            }
        }
        int requested = parsed;
        if (this.targetReverted && parsed == this.revertedTargetHz) {
            requested = 0;   // file still asks for the unreachable rate: keep auto
        }
        if (requested != this.targetHzOverride) {
            this.targetHzOverride = requested;
            this.targetHzSource = requested > 0 ? (requested + "Hz(file)") : "auto(display)";
            if (requested > 0) {
                System.out.println(String.format(java.util.Locale.ROOT,
                    "[VRMC-M8] target cadence: %d Hz (file) - auto eye scale now aims at %.2f ms frames "
                        + "instead of the measured display cadence", requested, 1000.0 / requested));
            } else {
                System.out.println("[VRMC-M8] target cadence: auto (file) - following the measured "
                    + "display cadence");
            }
        }
    }

    /**
     * Re-read the content-first knob every ~300 frames (game dir vrmc-content-first.txt = on|off).
     * Enabled: struggling windows reduce render/simulation distance before the eye-target resolution.
     * Disabled (default): the previous behaviour (reduce the eye-target resolution).
     */
    private void maybeReadContentFirst() {
        if (this.frameIndex - this.lastContentFirstReadFrame < 300L) return;
        this.lastContentFirstReadFrame = this.frameIndex;
        String value = "off";
        try {
            java.io.File gameDir = Minecraft.getInstance().gameDirectory;
            if (gameDir != null) {
                java.io.File knob = new java.io.File(gameDir, "vrmc-content-first.txt");
                if (knob.isFile()) {
                    String text = java.nio.file.Files.readString(knob.toPath()).trim();
                    if (!text.isEmpty()) value = text;
                }
            }
        } catch (RuntimeException | java.io.IOException ignored) {
            // keep the current mode when the knob file is unreadable
        }
        int parsed = VisionContentGovernor.parse(value);
        if (parsed < 0) {
            System.out.println("[VRMC-M8] content governor: ignoring invalid value '" + value
                + "' (expected on or off)");
            return;
        }
        boolean next = parsed == 1;
        if (next != this.contentGovernor.enabled()) {
            this.contentGovernor.setEnabled(next);
            System.out.println(next
                ? "[VRMC-M8] content governor: on (file) - struggling windows reduce render/simulation "
                    + "distance before the eye-target resolution"
                : "[VRMC-M8] content governor: off (file) - struggling windows reduce the eye-target "
                    + "resolution");
        }
    }

    /** M8 target cadence override (0 = auto/follow measured display); exposed for the status JSON. */
    public int targetHzOverride() { return this.targetHzOverride; }

    /** Human-readable target cadence source ("auto(display)" or "120Hz(file)"). */
    public String targetHzSource() { return this.targetHzSource; }

    /**
     * Auto eye-scale adaptation from the renderer's own frame pacing against the display cadence the
     * compositor measured (or the operator's target-cadence override). Steps are small and gated: one
     * down-step on misses/slow p50, up only after consecutive headroom windows and never immediately
     * after a drop.
     */
    private void maybeAdaptEyeScale(VisionRenderSettings settings) {
        if (!this.eyeScaleAuto || this.frameIndex == 0L || (this.frameIndex % 240L) != 0L) return;
        final double targetMs = VisionRenderSettings.targetIntervalMsFor(settings.displayHz,
            this.targetHzOverride);
        VisionFrameStats.Snapshot stats = this.renderFrameStats.snapshotAndReset(targetMs);
        if (stats.samples <= 0) return;
        final boolean struggling = stats.missedTargetFrames >= Math.max(3, stats.samples / 10)
            || stats.p50Ms > targetMs * 1.25;
        final boolean headroom = stats.missedTargetFrames <= 1 && stats.p50Ms <= targetMs * 1.05;
        // Content-first pressure: broader than the resolution policy's "struggling" (any window
        // materially over budget counts), so scene cost is cut before resolution when frames drift
        // above the target; the governor also decays pressure instead of hard-resetting, so an
        // oscillating on/off-budget load still accumulates enough pressure to act.
        final boolean contentPressure = stats.missedTargetFrames >= Math.max(3, stats.samples / 10)
            || stats.p50Ms > targetMs * 1.05;
        // M8 frame trace: a device pull otherwise only sees the last line of each log. One CSV row per
        // window gives the resolution/refresh history for A/B analysis (best-effort, never fatal).
        appendTraceRow(settings, stats);
        // Target-cadence guardrail: never chase a cadence the display does not provide. If the
        // compositor keeps reporting a lower measured cadence, revert to auto so the policy does not
        // crush resolution forever on hardware that never promotes (operator can change the file to
        // retry). targetMs above still used the pre-revert override for this one window.
        if (this.targetHzOverride > 0 &&
            VisionTargetGuardrail.displayBelowTarget(this.targetHzOverride, settings.displayHz)) {
            this.targetLowWindows++;
            if (VisionTargetGuardrail.shouldRevert(this.targetLowWindows)) {
                System.out.println(String.format(java.util.Locale.ROOT,
                    "[VRMC-M8] target cadence: %d Hz unreachable (measured display stayed %.1f Hz for "
                        + "%d windows); reverting to auto (measured display). Change "
                        + "Documents/instances/default/vrmc-target-hz.txt to retry.",
                    this.targetHzOverride, settings.displayHz, this.targetLowWindows));
                this.revertedTargetHz = this.targetHzOverride;
                this.targetReverted = true;
                this.targetHzOverride = 0;
                this.targetHzSource = "auto(display)";
                this.targetLowWindows = 0;
            }
        } else if (this.targetLowWindows != 0) {
            this.targetLowWindows = 0;
        }
        final float previous = this.eyeScale;
        // M8 content-first: prefer cutting scene cost over cutting the eye-target resolution. Runs on
        // every window (it also resets its streak on non-struggling windows); null = no content change.
        int renderDistance = -1;
        int simulationDistance = -1;
        try {
            renderDistance = Minecraft.getInstance().options.renderDistance().get();
            simulationDistance = Minecraft.getInstance().options.simulationDistance().get();
        } catch (RuntimeException | LinkageError ignored) {
            // options unavailable: the governor simply finds no room and the resolution policy applies
        }
        int[] contentReduction = this.contentGovernor.decide(contentPressure, renderDistance,
            simulationDistance);
        if (contentReduction != null) {
            try {
                Minecraft.getInstance().options.renderDistance().set(contentReduction[0]);
                Minecraft.getInstance().options.simulationDistance().set(contentReduction[1]);
                System.out.println(String.format(java.util.Locale.ROOT,
                    "[VRMC-M8] content governor: renderDistance %d->%d simulationDistance %d->%d "
                        + "(keeps eye target %dx%d; target=%.2fms %s; p50=%.2fms missed=%d/%d; "
                        + "reductions=%d/%d)",
                    renderDistance, contentReduction[0], simulationDistance, contentReduction[1],
                    this.currentEyeWidth, this.currentEyeHeight, targetMs, this.targetHzSource,
                    stats.p50Ms, stats.missedTargetFrames, stats.samples,
                    this.contentGovernor.reductions(), VisionContentGovernor.MAX_REDUCTIONS));
            } catch (RuntimeException | LinkageError applyError) {
                System.out.println("[VRMC-M8][WARN] content governor could not apply the distance "
                    + "reduction: " + applyError);
            }
            this.headroomWindows = 0;
            this.raiseHoldWindows = 3;
            return;
        }
        if (struggling) {
            this.eyeScale = VisionRenderSettings.nextAutoScale(this.eyeScale,
                stats.missedTargetFrames, stats.samples, stats.p50Ms, targetMs);
            this.headroomWindows = 0;
            this.raiseHoldWindows = 3;
        } else if (this.raiseHoldWindows > 0) {
            this.raiseHoldWindows--;
        } else if (headroom) {
            this.headroomWindows++;
            if (this.headroomWindows >= 2) {
                this.eyeScale = VisionRenderSettings.nextAutoScale(this.eyeScale, 0, stats.samples,
                    stats.p50Ms, targetMs);
                this.headroomWindows = 0;
                this.raiseHoldWindows = 1;
            }
        } else {
            this.headroomWindows = 0;
        }
        if (Math.abs(this.eyeScale - previous) > 1.0e-3f) {
            System.out.println(String.format(java.util.Locale.ROOT,
                "[VRMC-M8] eye scale auto: %.2f -> %.2f (displayHz=%.1f target=%.2fms %s p50=%.2fms "
                    + "p95=%.2fms missed=%d/%d)", previous, this.eyeScale, settings.displayHz,
                targetMs, this.targetHzSource, stats.p50Ms, stats.p95Ms,
                stats.missed90HzFrames, stats.samples));
        }
    }

    /**
     * M8 resize safety wrapper: an experimental render-target rebuild must never crash the render loop.
     * If it throws, keep the previous target (the VRRenderer state is not trusted after a failed
     * rebuild), disable the auto eye scale so the same failing rebuild is not retried every 240 frames,
     * and log once. A fixed eye scale keeps working.
     */
    private void maybeResizeEyeTargets(VisionRenderSettings settings) {
        try {
            maybeResizeEyeTargetsUnchecked(settings);
        } catch (RuntimeException | LinkageError resizeError) {
            if (!this.loggedResizeFailure) {
                this.loggedResizeFailure = true;
                System.out.println("[VRMC-M8][WARN] eye-target rebuild failed (" + resizeError
                    + "); keeping the current target " + this.currentEyeWidth + "x"
                    + this.currentEyeHeight + " and disabling the auto eye scale to avoid a resize loop");
            }
            this.eyeScaleAuto = false;
            this.eyeScaleSource = "auto(disabled-after-resize-failure)";
        }
    }

    /** Resize the stereo eye targets to the current logical display size x eye scale. */
    private void maybeResizeEyeTargetsUnchecked(VisionRenderSettings settings) {
        int[] target = VisionRenderSettings.eyeTarget(settings, this.eyeScale);
        if (target == null) return;
        if (!VisionRenderSettings.isChangeSignificant(this.currentEyeWidth, this.currentEyeHeight,
            target[0], target[1])) {
            return;
        }
        // A resize destroys/recreates both eye VkImages and rebuilds every render target: keep it out
        // of world loading, wait for session warm-up, and rate-limit it to one per 240 frames
        // (~2 s at 120 Hz). The pending target stays queued because currentEye* only changes below.
        final boolean levelLoaded = this.levelLoadedFrame >= 0L;
        final long framesSinceLevelLoad = levelLoaded ? this.frameIndex - this.levelLoadedFrame : -1L;
        boolean inMenuRoom = false;
        try {
            inMenuRoom = MethodHolder.isInMenuRoom();
        } catch (RuntimeException | LinkageError ignored) {
            // menu-room probe is best-effort; without it only an in-world stable level allows a resize
        }
        if (!VisionRenderSettings.canResizeNow(levelLoaded, framesSinceLevelLoad, inMenuRoom,
            this.frameIndex)) {
            return;
        }
        if (this.frameIndex - this.lastEyeResizeFrame < 240L) return;
        final int oldWidth = this.currentEyeWidth;
        final int oldHeight = this.currentEyeHeight;
        this.lastEyeResizeFrame = this.frameIndex;
        this.currentEyeWidth = target[0];
        this.currentEyeHeight = target[1];
        this.resolution = new Vector2i(target[0], target[1]);
        this.eyeResizeCount++;
        System.out.println(String.format(java.util.Locale.ROOT,
            "[VRMC-M8] eye target resize #%d: %dx%d -> %dx%d (logical=%dx%d scale=%.2f %s; "
                + "displayHz=%.1f quality=%.2f/%.2f)",
            this.eyeResizeCount, oldWidth, oldHeight, target[0], target[1],
            settings.leftLogicalWidth, settings.leftLogicalHeight, this.eyeScale, this.eyeScaleSource,
            settings.displayHz, settings.renderQuality, settings.maxRenderQuality));
        // SAFETY: the resize destroys the current eye VkImages and rebuilds every render target. Stop
        // handing the old (soon freed) MTLTextures to the compositor before the destroy: clear the
        // shared eye frame so the compositor shows its fallback pattern for the one or two frames
        // until the new targets are submitted, instead of acquiring destroyed memory. The compositor
        // already retains in-flight textures for the command buffer it already encoded, so the only
        // unsafe window is "acquire after destroy before the next submit" - which this closes.
        try {
            VrmcBridge.clearEyeTextures();
            System.out.println("[VRMC-M8] cleared the shared eye frame before the eye-target rebuild "
                + "(compositor shows its fallback pattern until the new targets are submitted)");
        } catch (RuntimeException | LinkageError clearError) {
            System.out.println("[VRMC-M8][WARN] clearEyeTextures before resize failed: " + clearError);
        }
        reinitFrameBuffers("VRMC M8 eye target " + target[0] + "x" + target[1]);
    }

    @Override
    public void destroy() {
        GpuEyeSync sync = this.gpuSync;
        this.gpuSync = null;
        if (sync != null) {
            sync.close();
        }
        super.destroy();
    }

    void markPolled() {
        this.polled = true;
    }

    @Override public boolean providesStencilMask() { return false; }
    @Override public String getName() { return "VRMC M2"; }
}
