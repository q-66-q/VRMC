package dev.vrmc.provider.mixin;

import dev.vrmc.provider.VisionVR;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.item.ItemStack;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;
import org.vivecraft.client_vr.provider.MCVR;
import org.vivecraft.client_vr.render.helpers.VRArmHelper;

/**
 * VRMC gesture bow, shown the way Vivecraft shows its own roomscale bow: the selected main-hand bow
 * is drawn in the LEFT (off-hand) controller and the arrow it would shoot in the RIGHT hand; while
 * drawing, the right hand is empty (the drawn bow model carries the arrow).
 *
 * <p>Vivecraft only does this when its roomscale bow tracker is active, which VRMC turns off
 * (bowMode OFF - its notch geometry never triggered with hand tracking). Overriding only the render
 * item keeps every controller pose where it is, so the wrist hotbar stays on the left wrist (the
 * 1.3.7 pose swap moved it) and nothing else that reads controller poses changes. Item lookups go
 * through VisionVR (reflection) so this class only touches ItemStack/InteractionHand.
 */
@Mixin(VRArmHelper.class)
public class VRArmHelperMixin {
    // require = 0: a Vivecraft update that renames this helper must not stop the game from starting;
    // VisionVR logs a warning when the bow is shown in the left hand but this hook never ran.
    @Inject(method = "getBowOverride", at = @At("HEAD"), cancellable = true, require = 0)
    private static void vrmc$gestureBowHands(ItemStack stack, InteractionHand hand,
                                             CallbackInfoReturnable<ItemStack> cir) {
        if (!(MCVR.get() instanceof VisionVR vision) || !vision.m7BowInLeftHand()) return;
        Object shown = vision.m7BowRenderStack(hand == InteractionHand.OFF_HAND);
        cir.setReturnValue(shown instanceof ItemStack s ? s : ItemStack.EMPTY);
    }
}
