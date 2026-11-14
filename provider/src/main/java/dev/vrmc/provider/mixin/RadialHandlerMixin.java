package dev.vrmc.provider.mixin;

import dev.vrmc.provider.VisionVR;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.vivecraft.client_vr.gameplay.screenhandlers.RadialHandler;
import org.vivecraft.client_vr.provider.MCVR;

/**
 * Radial (shortcut) menu with one head-ray cursor. Vivecraft's processGui moves a cursor for EACH
 * hand controller every frame (device report 1.3.8: "the shortcut menu has two cursors, use only
 * head-ray"). While VRMC drives hand tracking, VisionVR projects the head ray onto the radial plane
 * into the cursor slot of the hand that opened the menu (cursor 2 for the right hand: the slot
 * Vivecraft's hold-mode release clicks with) and hides the other one; the original method is
 * skipped. require = 0: a renamed method only loses the head cursor.
 */
@Mixin(RadialHandler.class)
public class RadialHandlerMixin {
    @Inject(method = "processGui", at = @At("HEAD"), cancellable = true, require = 0)
    private static void vrmc$headRayCursor(CallbackInfo ci) {
        if (MCVR.get() instanceof VisionVR vision && vision.m7RadialHeadCursor()) {
            ci.cancel();
        }
    }
}
