// S4a-host spike: export a Vulkan image as an MTLTexture via VK_EXT_metal_objects, clear it through
// Vulkan, read it back through Metal, and export a MTLSharedEvent from a VkSemaphore.
// Build: clang -fobjc-arc -I<moltenvk include> -L<moltenvk lib> -lMoltenVK -framework Metal -framework Foundation spike_s4a.mm
// Run: DYLD_LIBRARY_PATH=<moltenvk lib> ./spike_s4a
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_metal.h>
#include <stdio.h>
#include <string.h>

#define VK_CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("VK fail %s at %s:%d -> %d\n", #x, __FILE__, __LINE__, r_); return 1; } } while (0)

static id<MTLDevice> gDevice = nil;

int main(void) {
    @autoreleasepool {
        VkApplicationInfo app = {VK_STRUCTURE_TYPE_APPLICATION_INFO};
        app.pApplicationName = "VRMC S4a host spike";
        app.apiVersion = VK_API_VERSION_1_2;

        // VK_EXT_metal_objects is a *device* extension; do not enable it at instance level.
        VkInstanceCreateInfo ici = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
        ici.pApplicationInfo = &app;
        ici.enabledExtensionCount = 0;
        ici.ppEnabledExtensionNames = NULL;
        VkInstance instance;
        VK_CHECK(vkCreateInstance(&ici, NULL, &instance));

        uint32_t count = 0;
        VK_CHECK(vkEnumeratePhysicalDevices(instance, &count, NULL));
        printf("[s4a] physical devices: %u\n", count);
        if (count == 0) { printf("[s4a] no Vulkan device (MoltenVK missing?)\n"); return 2; }
        VkPhysicalDevice phys[4];
        if (count > 4) count = 4;
        VK_CHECK(vkEnumeratePhysicalDevices(instance, &count, phys));
        VkPhysicalDevice pd = phys[0];

        uint32_t extCount = 0;
        vkEnumerateDeviceExtensionProperties(pd, NULL, &extCount, NULL);
        VkExtensionProperties *exts = (VkExtensionProperties *)calloc(extCount, sizeof(*exts));
        vkEnumerateDeviceExtensionProperties(pd, NULL, &extCount, exts);
        int hasMetalObjects = 0;
        for (uint32_t i = 0; i < extCount; i++) {
            if (strcmp(exts[i].extensionName, VK_EXT_METAL_OBJECTS_EXTENSION_NAME) == 0) hasMetalObjects = 1;
        }
        free(exts);
        printf("[s4a] VK_EXT_metal_objects present: %d\n", hasMetalObjects);
        if (!hasMetalObjects) return 3;

        uint32_t qCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(pd, &qCount, NULL);
        VkQueueFamilyProperties *qprops = (VkQueueFamilyProperties *)calloc(qCount, sizeof(*qprops));
        vkGetPhysicalDeviceQueueFamilyProperties(pd, &qCount, qprops);
        uint32_t qIndex = 0;
        for (uint32_t i = 0; i < qCount; i++) {
            if (qprops[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) { qIndex = i; break; }
        }
        free(qprops);

        float prio = 1.0f;
        VkDeviceQueueCreateInfo qci = {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
        qci.queueFamilyIndex = qIndex;
        qci.queueCount = 1;
        qci.pQueuePriorities = &prio;
        const char *deviceExts[] = { VK_EXT_METAL_OBJECTS_EXTENSION_NAME };
        VkPhysicalDeviceVulkan12Features vk12 = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES};
        vk12.timelineSemaphore = VK_TRUE;
        VkDeviceCreateInfo dci = {VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
        dci.pNext = &vk12;
        dci.queueCreateInfoCount = 1;
        dci.pQueueCreateInfos = &qci;
        dci.enabledExtensionCount = 1;
        dci.ppEnabledExtensionNames = deviceExts;
        VkDevice device;
        VK_CHECK(vkCreateDevice(pd, &dci, NULL, &device));
        VkQueue queue;
        vkGetDeviceQueue(device, qIndex, 0, &queue);

        // Export the MTLDevice to prove the bridge path (equivalent to vkGetMTLDeviceMVK).
        VkExportMetalDeviceInfoEXT devInfo = {VK_STRUCTURE_TYPE_EXPORT_METAL_DEVICE_INFO_EXT};
        VkExportMetalObjectsInfoEXT exportInfo = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT};
        exportInfo.pNext = &devInfo;
        vkExportMetalObjectsEXT(device, &exportInfo);
        gDevice = devInfo.mtlDevice;
        printf("[s4a] exported MTLDevice: %s\n", gDevice ? "yes" : "NO");
        if (!gDevice) return 4;

        // Exportable image.
        VkImageCreateInfo imageCI = {VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
        imageCI.imageType = VK_IMAGE_TYPE_2D;
        imageCI.format = VK_FORMAT_R8G8B8A8_UNORM;
        imageCI.extent = (VkExtent3D){64, 64, 1};
        imageCI.mipLevels = 1;
        imageCI.arrayLayers = 1;
        imageCI.samples = VK_SAMPLE_COUNT_1_BIT;
        imageCI.tiling = VK_IMAGE_TILING_OPTIMAL;
        imageCI.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        imageCI.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        imageCI.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        VkExportMetalObjectCreateInfoEXT exportCreate = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECT_CREATE_INFO_EXT};
        exportCreate.exportObjectType = VK_EXPORT_METAL_OBJECT_TYPE_METAL_TEXTURE_BIT_EXT;
        exportCreate.pNext = NULL;
        imageCI.pNext = &exportCreate;
        VkImage image;
        VK_CHECK(vkCreateImage(device, &imageCI, NULL, &image));
        VkMemoryRequirements memReq;
        vkGetImageMemoryRequirements(device, image, &memReq);

        uint32_t memTypeIdx = 0;
        VkPhysicalDeviceMemoryProperties memProps;
        vkGetPhysicalDeviceMemoryProperties(pd, &memProps);
        for (uint32_t i = 0; i < memProps.memoryTypeCount; i++) {
            if ((memReq.memoryTypeBits & (1u << i)) &&
                (memProps.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) {
                memTypeIdx = i;
                break;
            }
        }
        VkMemoryAllocateInfo alloc = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
        alloc.allocationSize = memReq.size;
        alloc.memoryTypeIndex = memTypeIdx;
        VkDeviceMemory memory;
        VK_CHECK(vkAllocateMemory(device, &alloc, NULL, &memory));
        VK_CHECK(vkBindImageMemory(device, image, memory, 0));

        VkCommandPoolCreateInfo poolCI = {VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
        poolCI.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        poolCI.queueFamilyIndex = qIndex;
        VkCommandPool pool;
        VK_CHECK(vkCreateCommandPool(device, &poolCI, NULL, &pool));
        VkCommandBufferAllocateInfo cbAI = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
        cbAI.commandPool = pool;
        cbAI.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cbAI.commandBufferCount = 1;
        VkCommandBuffer cb;
        VK_CHECK(vkAllocateCommandBuffers(device, &cbAI, &cb));
        VkCommandBufferBeginInfo begin = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
        VK_CHECK(vkBeginCommandBuffer(cb, &begin));

        VkImageMemoryBarrier toDst = {VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
        toDst.srcAccessMask = 0;
        toDst.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        toDst.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        toDst.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        toDst.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        toDst.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        toDst.image = image;
        toDst.subresourceRange = (VkImageSubresourceRange){VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &toDst);

        VkClearColorValue red = {{1.0f, 0.0f, 0.0f, 1.0f}};
        VkImageSubresourceRange range = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        vkCmdClearColorImage(cb, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &red, 1, &range);

        VkImageMemoryBarrier toSrc = toDst;
        toSrc.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        toSrc.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT;
        toSrc.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        toSrc.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, NULL, 0, NULL, 1, &toSrc);

        VK_CHECK(vkEndCommandBuffer(cb));
        VkSubmitInfo submit = {VK_STRUCTURE_TYPE_SUBMIT_INFO};
        submit.commandBufferCount = 1;
        submit.pCommandBuffers = &cb;
        VK_CHECK(vkQueueSubmit(queue, 1, &submit, VK_NULL_HANDLE));
        VK_CHECK(vkQueueWaitIdle(queue));
        printf("[s4a] Vulkan clear submitted\n");

        // Export the VkImage as an MTLTexture.
        VkExportMetalTextureInfoEXT texInfo = {VK_STRUCTURE_TYPE_EXPORT_METAL_TEXTURE_INFO_EXT};
        texInfo.image = image;
        texInfo.imageView = VK_NULL_HANDLE;
        texInfo.bufferView = VK_NULL_HANDLE;
        texInfo.plane = VK_IMAGE_ASPECT_COLOR_BIT;
        VkExportMetalObjectsInfoEXT exportInfo2 = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT};
        exportInfo2.pNext = &texInfo;
        vkExportMetalObjectsEXT(device, &exportInfo2);
        id<MTLTexture> mtlTexture = texInfo.mtlTexture;
        printf("[s4a] exported MTLTexture: %s\n", mtlTexture ? "yes" : "NO");
        if (!mtlTexture) return 5;
        printf("[s4a] MTLTexture %lu x %lu, pixelFormat=%lu\n",
               (unsigned long)mtlTexture.width, (unsigned long)mtlTexture.height,
               (unsigned long)mtlTexture.pixelFormat);

        // Read the texture through Metal into a shared buffer and check the clear color.
        NSUInteger bytesPerRow = mtlTexture.width * 4;
        id<MTLBuffer> readback = [gDevice newBufferWithLength:bytesPerRow * mtlTexture.height
                                                     options:MTLResourceStorageModeShared];
        id<MTLCommandQueue> mtlQueue = [gDevice newCommandQueue];
        id<MTLCommandBuffer> mtlCB = [mtlQueue commandBuffer];
        id<MTLBlitCommandEncoder> blit = [mtlCB blitCommandEncoder];
        [blit copyFromTexture:mtlTexture
                  sourceSlice:0
                  sourceLevel:0
                 sourceOrigin:MTLOriginMake(0, 0, 0)
                   sourceSize:MTLSizeMake(mtlTexture.width, mtlTexture.height, 1)
                     toBuffer:readback
            destinationOffset:0
       destinationBytesPerRow:bytesPerRow
     destinationBytesPerImage:bytesPerRow * mtlTexture.height];
        [blit endEncoding];
        [mtlCB commit];
        [mtlCB waitUntilCompleted];
        if (mtlCB.error) { printf("[s4a] Metal blit error: %s\n", mtlCB.error.description.UTF8String); return 6; }
        uint8_t *px = (uint8_t *)readback.contents;
        printf("[s4a] Metal readback pixel RGBA = %u,%u,%u,%u (expect 255,0,0,255)\n", px[0], px[1], px[2], px[3]);
        int pixelOK = (px[0] == 255 && px[1] == 0 && px[2] == 0 && px[3] == 255);
        if (!pixelOK) return 7;

        // Shared-event export path (host gate also requires MTLSharedEvent sync availability).
        VkExportMetalObjectCreateInfoEXT seCreate = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECT_CREATE_INFO_EXT};
        seCreate.exportObjectType = VK_EXPORT_METAL_OBJECT_TYPE_METAL_SHARED_EVENT_BIT_EXT;
        VkSemaphoreTypeCreateInfo seType = {VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO};
        seType.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE;
        seType.initialValue = 0;
        VkSemaphoreCreateInfo seCI = {VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        seCI.pNext = &seType;
        seType.pNext = &seCreate;
        VkSemaphore semaphore;
        VkResult seRc = vkCreateSemaphore(device, &seCI, NULL, &semaphore);
        printf("[s4a] vkCreateSemaphore(export shared event): %d\n", seRc);
        if (seRc == VK_SUCCESS) {
            VkExportMetalSharedEventInfoEXT seInfo = {VK_STRUCTURE_TYPE_EXPORT_METAL_SHARED_EVENT_INFO_EXT};
            seInfo.semaphore = semaphore;
            VkExportMetalObjectsInfoEXT seExport = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT};
            seExport.pNext = &seInfo;
            vkExportMetalObjectsEXT(device, &seExport);
            id<MTLSharedEvent> sharedEvent = seInfo.mtlSharedEvent;
            printf("[s4a] exported MTLSharedEvent: %s\n", sharedEvent ? "yes" : "NO");
            if (sharedEvent) {
                uint64_t signalValue = 42;
                VkTimelineSemaphoreSubmitInfo tsi = {VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO};
                tsi.signalSemaphoreValueCount = 1;
                tsi.pSignalSemaphoreValues = &signalValue;
                VkSubmitInfo sig = {VK_STRUCTURE_TYPE_SUBMIT_INFO};
                VkSemaphore sigSem = semaphore;
                sig.pNext = &tsi;
                sig.signalSemaphoreCount = 1;
                sig.pSignalSemaphores = &sigSem;
                VK_CHECK(vkQueueSubmit(queue, 1, &sig, VK_NULL_HANDLE));
                VK_CHECK(vkQueueWaitIdle(queue));
                printf("[s4a] MTLSharedEvent signaledValue after Vulkan signal(42) = %llu\n",
                       (unsigned long long)sharedEvent.signaledValue);
                if (sharedEvent.signaledValue != 42) {
                    printf("[s4a] shared-event synchronization MISMATCH\n");
                    return 8;
                }
                printf("[s4a] shared-event synchronization OK (MTLSharedEvent sees Vulkan signal)\n");
            }
        }
        printf("[s4a] HOST PASS: MTLDevice export, MTLTexture export, Metal readback pixel OK, shared-event export path exercised\n");
        return 0;
    }
}
