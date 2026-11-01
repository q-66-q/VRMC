package dev.vrmc.provider;

import dev.vrmc.provider.bridge.VrmcBridge;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import org.joml.Matrix4f;
import org.joml.Matrix4fc;
import org.joml.Quaternionf;
import org.joml.Vector2f;
import org.joml.Vector2fc;
import org.vivecraft.client.VivecraftVRMod;
import org.vivecraft.client_vr.ClientDataHolderVR;
import org.vivecraft.client_vr.provider.ControllerType;
import org.vivecraft.client_vr.provider.MCVR;
import org.vivecraft.client_vr.provider.VRRenderer;
import org.vivecraft.client_vr.provider.nullvr.NullVRHapticScheduler;
import org.vivecraft.client_vr.provider.openvr_lwjgl.VRInputAction;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.List;

/**
 * VRMC's Vivecraft provider for visionOS (M2).
 *
 * The provider is substituted for MCOpenVR by VRStateMixin (S3/EV-0006/0009) and talks to the native
 * VRMC bridge through the versioned ABI v1 (bridge/abi/vrmc_abi.h). It fails closed: if the bridge
 * cannot be loaded/initialised or the ABI version mismatches, init() returns false and Vivecraft shows
 * the failure instead of silently rendering without tracking.
 */
public class VisionVR extends MCVR {
    private static final int TRACKING_BYTES = VrmcBridge.TRACKING_BYTES;
    /** Host harness only: no real controllers exist, so identity component transforms are correct. */
    private static final Matrix4f IDENTITY = new Matrix4f();
    private static final boolean HOST_HARNESS = Boolean.getBoolean("vrmc.hostHarness");
    private final ByteBuffer tracking = ByteBuffer.allocateDirect(TRACKING_BYTES).order(ByteOrder.nativeOrder());
    private final Quaternionf rot = new Quaternionf();
    private boolean bridgeReady;
    private int trackedFrames;

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
            int rc = VrmcBridge.init("{\"abi\":1,\"eyes\":2}");
            if (rc != 0) {
                this.initStatus = "vrmc_init failed rc=" + rc + ": " + VrmcBridge.lastError();
                System.out.println("[VRMC-M2] " + this.initStatus);
                return false;
            }
            this.bridgeReady = true;
            this.initStatus = "VRMC bridge ABI v1";
            System.out.println("[VRMC-M2] bridge handshake ok (ABI v1)");
        } catch (Throwable t) {
            this.initStatus = "VRMC bridge load failed: " + t;
            System.out.println("[VRMC-M2] " + this.initStatus);
            return false;
        }

        // Identity pose until tracking arrives (matches NullVR/RemoteVR shape).
        this.headIsTracking = true;
        this.hmdPose.identity();
        this.hmdPose.m31(1.62F);
        float ipdHalf = this.dh.vrSettings.nullvrIPD * 0.5F;
        this.hmdPoseLeftEye.identity().m30(-ipdHalf);
        this.hmdPoseRightEye.identity().m30(ipdHalf);

        this.populateInputActions();
        this.initialized = true;
        this.initSuccess = true;
        System.out.println("[VRMC-M2] VisionVR.init() succeeded");
        return true;
    }

    @Override
    public void destroy() {
        this.initialized = false;
        super.destroy();
    }

    @Override
    public void poll(long frameIndex) {
        if (!this.initialized) {
            return;
        }
        if (this.bridgeReady) {
            int rc = VrmcBridge.getTracking(this.tracking);
            if (rc == 0) {
                int o = 0;
                // vrmc_tracking_state: u64 presentation_time_ns, then head pose (quat xyzw + pos xyz)
                o = 8;
                float qx = this.tracking.getFloat(o), qy = this.tracking.getFloat(o + 4);
                float qz = this.tracking.getFloat(o + 8), qw = this.tracking.getFloat(o + 12);
                float px = this.tracking.getFloat(o + 16), py = this.tracking.getFloat(o + 20), pz = this.tracking.getFloat(o + 24);
                this.hmdPose.rotation(this.rot.set(qx, qy, qz, qw));
                this.hmdPose.setTranslation(px, py, pz);
                this.hmdRotation.rotation(this.rot);
                this.headIsTracking = (qw != 0.0F);
                int c0 = 8 + 28;
                int c1 = 8 + 56;
                readPose(c0, this.controllerPose[LEFT_CONTROLLER]);
                readPose(c1, this.controllerPose[RIGHT_CONTROLLER]);
                this.controllerTracking[LEFT_CONTROLLER] = true;
                this.controllerTracking[RIGHT_CONTROLLER] = true;
                float ipd = this.tracking.getFloat(8 + 84);
                if (ipd > 0.0F) {
                    this.hmdPoseLeftEye.identity().m30(-ipd * 0.5F);
                    this.hmdPoseRightEye.identity().m30(ipd * 0.5F);
                }
                if ((this.trackedFrames++ % 300) == 0) {
                    System.out.printf("[VRMC-M2] tracking frame %d head=(%.2f, %.2f, %.2f)%n",
                        this.trackedFrames, px, py, pz);
                }
            }
        }
        this.updateAim();
        this.hmdSampling();
        if (this.dh.vrRenderer instanceof VisionRenderer r) {
            r.markPolled();
        }
    }

    private void readPose(int offset, Matrix4f out) {
        if (out == null) {
            return;
        }
        float qx = this.tracking.getFloat(offset), qy = this.tracking.getFloat(offset + 4);
        float qz = this.tracking.getFloat(offset + 8), qw = this.tracking.getFloat(offset + 12);
        float px = this.tracking.getFloat(offset + 16), py = this.tracking.getFloat(offset + 20), pz = this.tracking.getFloat(offset + 24);
        out.rotation(this.rot.set(qx, qy, qz, qw));
        out.setTranslation(px, py, pz);
    }

    @Override public String getName() { return "VRMC"; }
    @Override public String getRuntimeName() { return "VRMC visionOS bridge"; }
    @Override public void processInputs() { /* M4: action data from accessors/hands */ }
    @Override protected ControllerType findActiveBindingControllerType(KeyMapping keyMapping) { return null; }
    @Override public Vector2fc getPlayAreaSize() { return new Vector2f(1.0F, 1.0F); }
    @Override public void refreshControllerTransforms() { /* M3/M4 */ }
    @Override public Matrix4fc getControllerComponentTransform(int controllerIndex, String componentName) {
        // Host-only fallback (no real controller/hand data exists in the harness). On device, a null
        // transform means tracking data is missing: fail loudly instead of silently returning identity,
        // which would look like "hands in the wrong place" and hide the real defect.
        if (HOST_HARNESS) {
            return IDENTITY;
        }
        String msg = "VRMC: missing controller/hand transform on device (controller=" + controllerIndex
            + ", component=" + componentName + "); tracking data missing (identity fallback is host-only)";
        System.out.println("[VRMC-M2][FATAL] " + msg);
        throw new IllegalStateException(msg);
    }
    @Override public List<Long> getOrigins(VRInputAction action) { return List.of(); }
    @Override public String getOriginName(long origin) { return "VRMC"; }
    @Override public VRRenderer createVRRenderer() { return new VisionRenderer(this); }
    @Override public boolean isActive() { return this.initialized; }
    @Override public float getIPD() { return this.dh.vrSettings.nullvrIPD; }
}
