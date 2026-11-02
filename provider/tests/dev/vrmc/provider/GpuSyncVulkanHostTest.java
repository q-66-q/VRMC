package dev.vrmc.provider;

import org.lwjgl.PointerBuffer;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.vulkan.VkApplicationInfo;
import org.lwjgl.vulkan.VkDevice;
import org.lwjgl.vulkan.VkDeviceCreateInfo;
import org.lwjgl.vulkan.VkDeviceQueueCreateInfo;
import org.lwjgl.vulkan.VkExtensionProperties;
import org.lwjgl.vulkan.VkInstance;
import org.lwjgl.vulkan.VkInstanceCreateInfo;
import org.lwjgl.vulkan.VkPhysicalDevice;
import org.lwjgl.vulkan.VkPhysicalDeviceFeatures;
import org.lwjgl.vulkan.VkPhysicalDeviceVulkan12Features;
import org.lwjgl.vulkan.VkQueueFamilyProperties;

import java.nio.FloatBuffer;
import java.nio.IntBuffer;

import static org.lwjgl.vulkan.VK10.*;
import static org.lwjgl.vulkan.VK12.*;

/**
 * Optional host test (macOS MoltenVK) for the exact reflective Vulkan calls the provider makes on device:
 * create a real VkInstance/VkDevice with VK_EXT_metal_objects + timeline semaphores, then hand the VkDevice
 * to {@link VkReflect#createExportableTimelineEvent(Object)} and verify it returns a non-zero timeline
 * semaphore AND a non-zero MTLSharedEvent; finally {@link VkReflect#destroySemaphore(Object, long)}.
 *
 * <p>This proves the reflection call path (vkCreateSemaphore with the export-create-info chain +
 * vkExportMetalObjectsEXT) against a real MoltenVK, not just struct assembly. It needs a Vulkan loader:
 * run with {@code -Dorg.lwjgl.vulkan.libname=<path>/libMoltenVK.dylib} (see provider/tests/run_tests.sh).
 * Device (visionOS) behaviour is still NOT RUN.
 */
public final class GpuSyncVulkanHostTest {
    public static void main(String[] args) {
        try (MemoryStack stack = MemoryStack.stackPush()) {
            VkApplicationInfo app = VkApplicationInfo.calloc(stack).sType$Default()
                .pApplicationName(stack.UTF8("VRMC provider GPU sync host test"))
                .apiVersion(VK_API_VERSION_1_2);
            VkInstanceCreateInfo instanceInfo = VkInstanceCreateInfo.calloc(stack).sType$Default()
                .pApplicationInfo(app);
            PointerBuffer instanceHandle = stack.mallocPointer(1);
            check(vkCreateInstance(instanceInfo, null, instanceHandle) == VK_SUCCESS, "vkCreateInstance");
            VkInstance instance = new VkInstance(instanceHandle.get(0), instanceInfo);

            IntBuffer count = stack.mallocInt(1);
            check(vkEnumeratePhysicalDevices(instance, count, null) == VK_SUCCESS && count.get(0) > 0,
                "vkEnumeratePhysicalDevices");
            PointerBuffer devices = stack.mallocPointer(count.get(0));
            check(vkEnumeratePhysicalDevices(instance, count, devices) == VK_SUCCESS,
                "vkEnumeratePhysicalDevices(list)");
            VkPhysicalDevice physical = new VkPhysicalDevice(devices.get(0), instance);
            check(hasExtension(physical, "VK_EXT_metal_objects"), "VK_EXT_metal_objects available");

            VkPhysicalDeviceVulkan12Features vk12 = VkPhysicalDeviceVulkan12Features.calloc(stack)
                .sType$Default().timelineSemaphore(true);
            VkPhysicalDeviceFeatures features = VkPhysicalDeviceFeatures.calloc(stack);
            VkDeviceQueueCreateInfo.Buffer queueInfo = VkDeviceQueueCreateInfo.calloc(1, stack);
            FloatBuffer priority = stack.floats(1.0f);
            queueInfo.get(0).sType$Default().queueFamilyIndex(0).pQueuePriorities(priority);
            PointerBuffer extensionNames = stack.mallocPointer(1);
            extensionNames.put(0, stack.UTF8("VK_EXT_metal_objects"));
            VkDeviceCreateInfo deviceInfo = VkDeviceCreateInfo.calloc(stack).sType$Default()
                .pNext(vk12).pEnabledFeatures(features)
                .pQueueCreateInfos(queueInfo).ppEnabledExtensionNames(extensionNames);
            PointerBuffer deviceHandle = stack.mallocPointer(1);
            check(vkCreateDevice(physical, deviceInfo, null, deviceHandle) == VK_SUCCESS, "vkCreateDevice");
            VkDevice device = new VkDevice(deviceHandle.get(0), physical, deviceInfo);

            long[] handles = VkReflect.createExportableTimelineEvent(device);
            System.out.printf("[provider-vk-host-test] exportable timeline VkSemaphore=0x%x MTLSharedEvent=0x%x%n",
                handles[0], handles[1]);
            check(handles[0] != 0L, "non-zero timeline VkSemaphore");
            check(handles[1] != 0L, "non-zero MTLSharedEvent (VK_EXT_metal_objects export)");
            check(VkReflect.allCommandsStageMask() == VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, "stage mask constant");
            VkReflect.destroySemaphore(device, handles[0]);
            System.out.println("[provider-vk-host-test] destroySemaphore: ok");

            vkDestroyDevice(device, null);
            vkDestroyInstance(instance, null);
            System.out.println("[provider-vk-host-test] PASS (real MoltenVK: semaphore create + event export)");
        } catch (Throwable t) {
            System.out.println("FAIL: " + t);
            t.printStackTrace(System.out);
            System.exit(1);
        }
    }

    private static boolean hasExtension(VkPhysicalDevice physical, String name) {
        try (MemoryStack stack = MemoryStack.stackPush()) {
            IntBuffer count = stack.mallocInt(1);
            vkEnumerateDeviceExtensionProperties(physical, (String) null, count, null);
            VkExtensionProperties.Buffer properties = VkExtensionProperties.malloc(count.get(0), stack);
            vkEnumerateDeviceExtensionProperties(physical, (String) null, count, properties);
            for (int i = 0; i < properties.capacity(); i++) {
                if (properties.get(i).extensionNameString().equals(name)) return true;
            }
            return false;
        }
    }

    private static void check(boolean ok, String what) {
        System.out.println("[provider-vk-host-test] " + (ok ? "ok  " : "FAIL") + " " + what);
        if (!ok) throw new IllegalStateException(what);
    }
}
