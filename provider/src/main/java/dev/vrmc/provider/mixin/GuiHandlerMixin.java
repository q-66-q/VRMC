package dev.vrmc.provider.mixin;

import dev.vrmc.provider.VisionVR;
import net.minecraft.client.Minecraft;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.vivecraft.client_vr.ClientDataHolderVR;
import org.vivecraft.client_vr.gameplay.screenhandlers.GuiHandler;
import org.vivecraft.client_vr.provider.MCVR;

/**
 * M7 head-ray GUI cursor: Vivecraft's GuiHandler.postPoll processGui() repositions the cursor from the
 * hand controller every frame, overwriting the M7 head-ray projection. Cancel only while M7 owns a GUI
 * cursor (a screen is open and the backend is VisionVR); MCOpenVR and non-M7 paths are untouched.
 */
@Mixin(GuiHandler.class)
public class GuiHandlerMixin {
    @Inject(method = "processGui", at = @At("HEAD"), cancellable = true)
    private static void vrmc$m7HeadCursor(CallbackInfo ci) {
        if (MCVR.get() instanceof VisionVR vision && vision.m7OwnsGuiCursor()) {
            ci.cancel();
        }
    }
}
