package dev.vrmc.provider;

import com.mojang.blaze3d.GpuFormat;
import com.mojang.blaze3d.systems.RenderSystem;
import net.minecraft.util.Mth;
import org.joml.Matrix4f;
import org.joml.Vector2i;
import org.joml.Vector2ic;
import org.vivecraft.client_vr.ClientDataHolderVR;
import org.vivecraft.client_vr.VRTextureTarget;
import org.vivecraft.client_vr.provider.MCVR;
import org.vivecraft.client_vr.provider.VRRenderer;
import org.vivecraft.client_vr.render.helpers.graphics.GraphicsHelper;
import org.vivecraft.client_vr.settings.VRSettings;
import dev.vrmc.provider.bridge.VrmcBridge;

/**
 * M2 stereo renderer: creates the two eye targets and hands their texture handles to the bridge.
 * The OpenGL build (desktop harness) can export GL texture ids today; the Vulkan/MoltenVK path on
 * visionOS uses the S4a interop decision (docs/mvp/S4A_FINDINGS.md) instead.
 */
public class VisionRenderer extends VRRenderer {
    private static final int EYE_WIDTH = Integer.getInteger("vrmc.eyeWidth", 1024);
    private static final int EYE_HEIGHT = Integer.getInteger("vrmc.eyeHeight", 1024);
    private long frameIndex;
    private boolean polled;
    private boolean loggedNoHandle;

    public VisionRenderer(MCVR vr) {
        super(vr);
        System.out.println("[VRMC-M2] VisionRenderer created");
    }

    @Override
    public Vector2ic getRenderTextureSizes() {
        return new Vector2i(EYE_WIDTH, EYE_HEIGHT);
    }

    @Override
    protected Matrix4f getProjectionMatrix(int eyeType, float nearClip, float farClip) {
        boolean zZeroToOne = RenderSystem.getDevice().getDeviceInfo().isZZeroToOne();
        ClientDataHolderVR dh = ClientDataHolderVR.getInstance();
        return new Matrix4f().setPerspectiveOffCenter(
            Mth.DEG_TO_RAD * dh.vrSettings.nullvrFOV,
            Mth.DEG_TO_RAD * dh.vrSettings.nullvrEyeAngle * (eyeType == 0 ? -1F : 1F), 0F,
            1.0F, nearClip, farClip, zZeroToOne);
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
            int rc = VrmcBridge.submitEyes(lt, rt, (int) this.frameIndex, EYE_WIDTH, EYE_HEIGHT);
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
        this.frameIndex++;
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

    void markPolled() {
        this.polled = true;
    }

    @Override public boolean providesStencilMask() { return false; }
    @Override public String getName() { return "VRMC M2"; }
}
