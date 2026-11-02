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
    private static final int EYE_WIDTH = Integer.getInteger("vrmc.eyeWidth", 1024);
    private static final int EYE_HEIGHT = Integer.getInteger("vrmc.eyeHeight", 1024);
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
            this.resolution = new Vector2i(EYE_WIDTH, EYE_HEIGHT);
            this.ss = -1.0F;
            System.out.println("[VRMC-M2] render texture size " + EYE_WIDTH + "x" + EYE_HEIGHT);
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
            int rc = submitEyes(lt, rt);
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
    private int submitEyes(long lt, long rt) {
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
                int rc = VrmcBridge.submitEyesSynced(lt, rt, (int) this.frameIndex, EYE_WIDTH, EYE_HEIGHT,
                    EYE_HALF_FOV_RAD, syncEvent, syncValue);
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
        return VrmcBridge.submitEyes(lt, rt, (int) this.frameIndex, EYE_WIDTH, EYE_HEIGHT,
            EYE_HALF_FOV_RAD);
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
