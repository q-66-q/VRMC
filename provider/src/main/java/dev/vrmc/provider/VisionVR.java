package dev.vrmc.provider;

import net.minecraft.client.Minecraft;
import net.minecraft.client.KeyMapping;
import org.joml.Matrix4fc;
import org.joml.Vector2f;
import org.joml.Vector2fc;
import org.vivecraft.client.VivecraftVRMod;
import org.vivecraft.client_vr.ClientDataHolderVR;
import org.vivecraft.client_vr.provider.ControllerType;
import org.vivecraft.client_vr.provider.MCVR;
import org.vivecraft.client_vr.provider.VRRenderer;
import org.vivecraft.client_vr.provider.openvr_lwjgl.VRInputAction;

import java.util.List;

/**
 * VRMC's Vivecraft provider for visionOS.
 *
 * M2 scaffold: substituted by VRStateMixin in place of MCOpenVR. init() intentionally fails closed
 * until the native bridge handshake (vrmc_init, ABI v1) and the renderer stub are wired (M2-W1/W4).
 */
public class VisionVR extends MCVR {
    public VisionVR(Minecraft mc, ClientDataHolderVR dh) {
        super(mc, dh, VivecraftVRMod.INSTANCE);
        this.initStatus = "VRMC M2 scaffold: bridge not wired";
        System.out.println("[VRMC-M2] VisionVR constructed");
    }

    @Override
    public boolean init() {
        // TODO(M2-W4): load libvrmc_bridge.dylib, call vrmc_init(caps_json) and fail closed on error.
        System.out.println("[VRMC-M2] VisionVR.init() skeleton reached; failing closed until bridge is wired");
        this.initStatus = "VRMC M2: native bridge not wired yet";
        this.initSuccess = false;
        return false;
    }

    @Override public String getName() { return "VRMC"; }
    @Override public void processInputs() { /* M2-W5 */ }
    @Override protected ControllerType findActiveBindingControllerType(KeyMapping keyMapping) { return null; }
    @Override public void poll(long frameIndex) { /* M2-W4/W5 */ }
    @Override public Vector2fc getPlayAreaSize() { return new Vector2f(1.0F, 1.0F); }
    @Override public void refreshControllerTransforms() { /* M2-W4 */ }
    @Override public Matrix4fc getControllerComponentTransform(int controllerIndex, String componentName) { return null; }
    @Override public List<Long> getOrigins(VRInputAction action) { return List.of(); }
    @Override public String getOriginName(long origin) { return "VRMC"; }
    @Override public VRRenderer createVRRenderer() { return new VisionRenderer(this); }
    @Override public boolean isActive() { return true; }
    @Override public float getIPD() { return 0.064F; }
    @Override public String getRuntimeName() { return "VRMC visionOS bridge"; }
}
