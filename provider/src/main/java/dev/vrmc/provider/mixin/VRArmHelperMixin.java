package dev.vrmc.provider.mixin;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;
import dev.vrmc.provider.VisionHandMesh;
import dev.vrmc.provider.VisionVR;
import net.minecraft.client.renderer.SubmitNodeCollector;
import net.minecraft.client.renderer.state.level.CameraRenderState;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.item.ItemStack;
import org.joml.Quaternionf;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;
import org.vivecraft.client_vr.ClientDataHolderVR;
import org.vivecraft.client_vr.VRData;
import org.vivecraft.client_vr.provider.MCVR;
import org.vivecraft.client_vr.render.helpers.RenderHelper;
import org.vivecraft.client_vr.render.helpers.VRArmHelper;
import org.vivecraft.client_vr.render.renderstates.VRRenderState;
import org.vivecraft.client_vr.render.rendertypes.VRRenderTypes;

/**
 * Two VRMC presentation hooks on Vivecraft's first-person hand rendering. Both use require = 0, so a
 * Vivecraft update that renames a helper can never stop the game from starting (VisionVR logs a
 * warning when the bow hook never ran).
 *
 * <p><b>Gesture bow</b> ({@code getBowOverride}): shown the way Vivecraft shows its own roomscale
 * bow - the selected main-hand bow in the LEFT (off-hand) controller, the arrow it would shoot in the
 * RIGHT hand, the right hand empty while drawing. Only the render item changes; controller poses
 * stay put, so the wrist hotbar stays on the left wrist. Item lookups go through VisionVR
 * (reflection) so this class only touches ItemStack/InteractionHand.
 *
 * <p><b>Hand model</b> ({@code renderVRHands}): the VRMC hand model (VisionHandMesh - arm, palm and
 * five articulated fingers from the ARKit joints, coloured with gesture feedback) is drawn in room
 * space under Vivecraft's room-to-world transform, and Vivecraft's own blocky arms are hidden for the
 * duration of the call only (showPlayerHands is restored at RETURN, so the setting is never saved
 * modified). Menu hands (a screen is open) are left to Vivecraft.
 */
@Mixin(VRArmHelper.class)
public class VRArmHelperMixin {
    @Unique private static boolean vrmc$handsOverridden;
    @Unique private static boolean vrmc$savedShowPlayerHands;

    @Inject(method = "getBowOverride", at = @At("HEAD"), cancellable = true, require = 0)
    private static void vrmc$gestureBowHands(ItemStack stack, InteractionHand hand,
                                             CallbackInfoReturnable<ItemStack> cir) {
        if (!(MCVR.get() instanceof VisionVR vision) || !vision.m7BowInLeftHand()) return;
        Object shown = vision.m7BowRenderStack(hand == InteractionHand.OFF_HAND);
        cir.setReturnValue(shown instanceof ItemStack s ? s : ItemStack.EMPTY);
    }

    @Inject(method = "renderVRHands", at = @At("HEAD"), require = 0)
    private static void vrmc$handModel(SubmitNodeCollector collector, VRRenderState state,
                                       CameraRenderState camera, PoseStack poseStack,
                                       boolean renderMain, boolean renderOff,
                                       boolean menuMain, boolean menuOff, int order,
                                       CallbackInfoReturnable<Integer> cir) {
        if (!(MCVR.get() instanceof VisionVR vision) || !vision.handModelEnabled()) return;
        ClientDataHolderVR dh = ClientDataHolderVR.getInstance();
        if (dh.vrSettings == null || dh.vrPlayer == null) return;
        // Vivecraft's own arms off for this call only (restored at RETURN).
        if (!vrmc$handsOverridden) {
            vrmc$savedShowPlayerHands = dh.vrSettings.showPlayerHands;
            vrmc$handsOverridden = true;
        }
        dh.vrSettings.showPlayerHands = false;
        vision.noteHandModelRendered();
        VisionHandMesh right = renderMain && !menuMain ? vision.handMesh(true) : null;
        VisionHandMesh left = renderOff && !menuOff ? vision.handMesh(false) : null;
        if ((right == null && left == null) || camera == null || camera.pos == null) return;
        VRData d = dh.vrPlayer.vrdata_world_render;
        if (d == null || d.origin == null) return;
        float light = 1.0F;
        if (state != null && state.armsState != null) {
            int packed = state.armsState.headLight;
            int block = (packed >> 4) & 0xF;
            int sky = (packed >> 20) & 0xF;
            light = 0.35F + 0.65F * Math.max(block, sky) / 15.0F;
        }
        final float f = light;
        poseStack.pushPose();
        // room -> world (VRData.VRDevicePose.getPosition): origin + rotateY(rotation) * room * scale,
        // made camera-relative like Vivecraft's own menu hands.
        poseStack.translate(d.origin.x - camera.pos.x, d.origin.y - camera.pos.y,
            d.origin.z - camera.pos.z);
        poseStack.mulPose(new Quaternionf().rotationY(d.rotation_radians));
        poseStack.scale(d.worldScale, d.worldScale, d.worldScale);
        RenderHelper.submitLateCustomGeometry(collector.order(order), poseStack, VRRenderTypes.quads(false),
            (pose, vc) -> {
                vrmc$emit(right, pose, vc, f);
                vrmc$emit(left, pose, vc, f);
            });
        poseStack.popPose();
    }

    @Inject(method = "renderVRHands", at = @At("RETURN"), require = 0)
    private static void vrmc$handModelRestore(SubmitNodeCollector collector, VRRenderState state,
                                              CameraRenderState camera, PoseStack poseStack,
                                              boolean renderMain, boolean renderOff,
                                              boolean menuMain, boolean menuOff, int order,
                                              CallbackInfoReturnable<Integer> cir) {
        if (!vrmc$handsOverridden) return;
        vrmc$handsOverridden = false;
        ClientDataHolderVR dh = ClientDataHolderVR.getInstance();
        if (dh.vrSettings != null) dh.vrSettings.showPlayerHands = vrmc$savedShowPlayerHands;
    }

    /** Emit every quad double-sided (no dependence on the pipeline's cull/winding). */
    @Unique
    private static void vrmc$emit(VisionHandMesh mesh, PoseStack.Pose pose, VertexConsumer vc, float light) {
        if (mesh == null || !mesh.valid) return;
        float[] p = mesh.positions;
        int[] c = mesh.colors;
        int n = mesh.vertexCount - (mesh.vertexCount % 4);
        for (int q = 0; q < n; q += 4) {
            for (int k = 0; k < 4; k++) vrmc$vertex(vc, pose, p, c, q + k, light);
            for (int k = 3; k >= 0; k--) vrmc$vertex(vc, pose, p, c, q + k, light);
        }
    }

    @Unique
    private static void vrmc$vertex(VertexConsumer vc, PoseStack.Pose pose, float[] p, int[] c, int i,
                                    float light) {
        int color = c[i];
        int r = Math.min(255, (int) (((color >> 16) & 0xFF) * light));
        int g = Math.min(255, (int) (((color >> 8) & 0xFF) * light));
        int b = Math.min(255, (int) ((color & 0xFF) * light));
        vc.addVertex(pose, p[i * 3], p[i * 3 + 1], p[i * 3 + 2]).setColor(r, g, b, 255);
    }
}
