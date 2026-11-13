package dev.vrmc.provider.mixin;

import com.mojang.blaze3d.vertex.PoseStack;
import dev.vrmc.provider.VisionVR;
import net.minecraft.client.player.AbstractClientPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.item.ItemStack;
import org.joml.Quaternionf;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.vivecraft.client_vr.provider.MCVR;
import org.vivecraft.client_vr.render.VivecraftItemRendering;

/**
 * Bow grip roll for VRMC hand poses, applied to the bow model only. Up to 1.3.7 the roll rotated the
 * whole controller pose of the bow hand; with the bow in the left hand that also rotated Vivecraft's
 * wrist hotbar (it hangs off the left controller) away from the eye. At the head of the first-person
 * item transforms the pose stack is still the hand (controller) frame, so a Z rotation here equals the
 * old controller roll for the item and nothing else.
 */
@Mixin(VivecraftItemRendering.class)
public class VivecraftItemRenderingMixin {
    @Inject(method = "applyFirstPersonItemTransforms", at = @At("HEAD"), require = 0)
    private static void vrmc$bowGripRoll(PoseStack poseStack,
                                         VivecraftItemRendering.VivecraftItemTransformType type,
                                         boolean mainHand, AbstractClientPlayer player, float a, float b,
                                         ItemStack stack, InteractionHand hand, CallbackInfo ci) {
        if (!(MCVR.get() instanceof VisionVR vision)) return;
        float roll = vision.m7BowRenderRollDeg(stack, hand == InteractionHand.OFF_HAND);
        if (Float.isNaN(roll) || roll == 0.0F) return;
        poseStack.mulPose(new Quaternionf().rotateZ((float) Math.toRadians(roll)));
    }
}
