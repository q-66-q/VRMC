import com.mojang.blaze3d.systems.GpuDevice;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vulkan.VulkanCommandEncoder;
import com.mojang.blaze3d.vulkan.VulkanDevice;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.vulkan.*;
import java.lang.reflect.Field;
import java.nio.LongBuffer;

/**
 * Compile-only proof that MC 26.2's public Vulkan API is sufficient for the provider-side eye-sync wiring:
 *  - create an exportable timeline VkSemaphore on the game's VkDevice;
 *  - export its MTLSharedEvent through VK_EXT_metal_objects;
 *  - append a timeline signal to the game's own frame submission.
 * No mixin needed; GpuDevice.backend is private (Vivecraft reads it through vivecraft.accesswidener), so a
 * standalone provider either adds the same access-widener entry or uses reflection as below.
 */
public final class ProviderSyncReachability {
    static VulkanDevice gameDevice() throws ReflectiveOperationException {
        Field backend = GpuDevice.class.getDeclaredField("backend");
        backend.setAccessible(true);
        return (VulkanDevice) backend.get(RenderSystem.getDevice());
    }

    static long createExportableTimeline(VulkanDevice device) {
        VkDevice vk = device.vkDevice();
        try (MemoryStack stack = MemoryStack.stackPush()) {
            VkExportMetalObjectCreateInfoEXT export = VkExportMetalObjectCreateInfoEXT.calloc(stack)
                .sType$Default()
                .exportObjectType(EXTMetalObjects.VK_EXPORT_METAL_OBJECT_TYPE_METAL_SHARED_EVENT_BIT_EXT);
            VkSemaphoreTypeCreateInfo type = VkSemaphoreTypeCreateInfo.calloc(stack)
                .sType$Default()
                .semaphoreType(VK12.VK_SEMAPHORE_TYPE_TIMELINE)
                .initialValue(0L);
            type.pNext(export.address());
            VkSemaphoreCreateInfo ci = VkSemaphoreCreateInfo.calloc(stack).sType$Default().pNext(type.address());
            LongBuffer out = stack.mallocLong(1);
            if (VK12.vkCreateSemaphore(vk, ci, null, out) != VK10.VK_SUCCESS) return 0L;
            long semaphore = out.get(0);
            VkExportMetalSharedEventInfoEXT seInfo = VkExportMetalSharedEventInfoEXT.calloc(stack)
                .sType$Default().semaphore(semaphore);
            VkExportMetalObjectsInfoEXT exportInfo = VkExportMetalObjectsInfoEXT.calloc(stack).sType$Default();
            exportInfo.pNext(seInfo.address());
            EXTMetalObjects.vkExportMetalObjectsEXT(vk, exportInfo);
            return seInfo.mtlSharedEvent();
        }
    }

    /** Appends "signal timeline semaphore = value" to the game's current frame submission (no submit). */
    static void signalOnGameFrameSubmit(VulkanDevice device, long semaphore, long value) {
        VulkanCommandEncoder encoder = device.createCommandEncoder();
        encoder.signalSemaphore(semaphore, value, VK12.VK_PIPELINE_STAGE_ALL_COMMANDS_BIT);
    }

    public static void main(String[] args) throws Exception {
        VulkanDevice device = gameDevice();
        long event = createExportableTimeline(device);
        System.out.println("compile-only reachability proof: device=" + device + " event=" + event);
    }
}
