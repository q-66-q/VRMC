package dev.vrmc.provider.mixin;

import dev.vrmc.provider.VisionVR;
import net.minecraft.client.Minecraft;
import org.objectweb.asm.Opcodes;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;
import org.vivecraft.client_vr.ClientDataHolderVR;
import org.vivecraft.client_vr.VRState;
import org.vivecraft.client_vr.provider.MCVR;

/**
 * Substitutes VRMC's VisionVR for the MCOpenVR construction inside VRState.initializeVR.
 * Injection point evidenced in EV-0006 and proven on desktop in EV-0009.
 */
@Mixin(VRState.class)
public class VRStateMixin {
    @Redirect(
        method = "initializeVR",
        at = @At(
            value = "FIELD",
            target = "Lorg/vivecraft/client_vr/ClientDataHolderVR;vr:Lorg/vivecraft/client_vr/provider/MCVR;",
            opcode = Opcodes.PUTFIELD,
            ordinal = 0))
    private static void vrmc$substituteProvider(ClientDataHolderVR dh, MCVR original) {
        System.out.println("[VRMC-M2] provider redirect; original="
            + (original == null ? "null" : original.getClass().getName()));
        dh.vr = new VisionVR(Minecraft.getInstance(), dh);
        System.out.println("[VRMC-M2] dh.vr is now " + dh.vr.getClass().getName());
    }
}
