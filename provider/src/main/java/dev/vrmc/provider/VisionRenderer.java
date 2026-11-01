package dev.vrmc.provider;

import org.joml.Matrix4f;
import org.joml.Vector2i;
import org.joml.Vector2ic;
import org.vivecraft.client_vr.provider.MCVR;
import org.vivecraft.client_vr.provider.VRRenderer;
import org.vivecraft.client_vr.render.RenderConfigException;

/**
 * M2 scaffold renderer. The real implementation creates two eye targets through Minecraft's GPU
 * abstraction and hands the eye textures to the native bridge (S4a decides zero-copy vs blit).
 */
public class VisionRenderer extends VRRenderer {
    public VisionRenderer(MCVR vr) {
        super(vr);
        System.out.println("[VRMC-M2] VisionRenderer created");
    }

    @Override
    public void createRenderTexture(int width, int height) {
        System.out.printf("[VRMC-M2] createRenderTexture %dx%d (TODO: eye targets)%n", width, height);
    }

    @Override
    protected Matrix4f getProjectionMatrix(int eyeType, float nearClip, float farClip) {
        return new Matrix4f();
    }

    @Override
    public void endFrame() throws RenderConfigException {
        // TODO(M2-W5): submit both eye targets via vrmc_submit_eyes.
    }

    @Override
    public boolean providesStencilMask() { return false; }

    @Override
    public String getName() { return "VRMC M2 scaffold"; }

    @Override
    public Vector2ic getRenderTextureSizes() { return new Vector2i(0, 0); }
}
