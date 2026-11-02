package dev.vrmc.provider.mixin;

import dev.vrmc.provider.VisionVR;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;
import org.vivecraft.client_vr.provider.ControllerType;
import org.vivecraft.client_vr.provider.HandedKeyBinding;
import org.vivecraft.client_vr.provider.MCVR;
import org.vivecraft.client_vr.provider.openvr_lwjgl.VRInputAction;

/**
 * M4-W1 {@code isEnabled} generic-backend fix (design §5.5).
 *
 * <p>Vivecraft's unmodified {@link VRInputAction#isEnabled()} hard-codes
 * {@code if (MCOpenVR.get() == null) return false}, which would disable EVERY action for a non-OpenVR
 * backend - including VRMC's VisionVR. This port of macstream's proven fix (LGPL-3.0, upstream
 * ec5a851c..., ADR-0009) takes over the method only while {@code MCVR.get() instanceof VisionVR}:
 * the same priority/origin checks are then performed through the ACTIVE backend instead of the
 * (null) OpenVR backend. The MCOpenVR path is untouched: for any other backend the injected method
 * returns immediately and the original body runs unchanged.
 *
 * <p>The priority loop mirrors the original exactly (higher-priority action on the same origin, in
 * an active action set, disables this action; handed bindings may override via
 * {@link HandedKeyBinding#isPriorityOnController(ControllerType)}). It reads only public API so it
 * compiles against the pinned Vivecraft 26.2 classes; a Vivecraft drift that removes the target
 * method fails the provider build / mixin apply (fail closed, never silent).
 */
@Mixin(VRInputAction.class)
public class VRInputActionMixin {
    @Inject(method = "isEnabled", at = @At("HEAD"), cancellable = true)
    private void vrmc$genericIsEnabled(CallbackInfoReturnable<Boolean> cir) {
        MCVR backend = MCVR.get();
        if (!(backend instanceof VisionVR vision)) {
            return; // MCOpenVR (or any other backend): original body stays in charge
        }
        VRInputAction self = (VRInputAction) (Object) this;

        ControllerType currentHand = self.getCurrentHand();
        if (!self.isEnabledRaw(currentHand)) {
            cir.setReturnValue(false);
            return;
        }
        long lastOrigin = self.getLastOrigin();
        ControllerType hand = VisionVR.originControllerType(lastOrigin);
        if (hand == null && self.isHanded()) {
            cir.setReturnValue(false);
            return;
        }
        // generic backend/origin/priority logic (same shape as the original OpenVR branch)
        for (VRInputAction other : backend.getInputActions()) {
            if (other != self && other.isEnabledRaw(hand) && other.isActive()
                && other.getPriority() > self.getPriority()
                && backend.getOrigins(other).contains(lastOrigin))
            {
                if (other.isHanded()) {
                    cir.setReturnValue(!((HandedKeyBinding) other.keyBinding).isPriorityOnController(hand));
                } else {
                    cir.setReturnValue(false);
                }
                return;
            }
        }
        cir.setReturnValue(true);
    }
}
