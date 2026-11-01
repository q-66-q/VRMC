// VRMC S4a-device probe — runs inside the VRMC app (native, no extra app slot).
// Trigger: create $AME_HOME/vrmc_s4a_device.flag, then launch the app. Results are written to
// $AME_HOME/s4a-device.log and NSLog. This is a probe, not product code.
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_metal.h>
#include <TargetConditionals.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define PROBE_LOG(fmt, ...) do { \
    printf("[s4a-dev] " fmt "\n", ##__VA_ARGS__); fflush(stdout); \
    NSLog(@"[s4a-dev] " fmt, ##__VA_ARGS__); \
} while (0)

static void *gMVK;
static PFN_vkGetInstanceProcAddr gipa;
static FILE *gLog;

static void openLog(void) {
    const char *home = getenv("AME_HOME");
    if (home == NULL) return;
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/s4a-device.log", home);
    gLog = fopen(path, "w");
    if (gLog != NULL) {
        int fd = fileno(gLog);
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
    }
}

typedef struct {
    PFN_vkCreateInstance pCreateInstance;
    PFN_vkEnumeratePhysicalDevices pEnumPhys;
    PFN_vkEnumerateDeviceExtensionProperties pEnumDevExt;
    PFN_vkGetPhysicalDeviceQueueFamilyProperties pGetQueueFam;
    PFN_vkGetPhysicalDeviceMemoryProperties pGetMemProps;
    PFN_vkCreateDevice pCreateDevice;
    PFN_vkGetDeviceQueue pGetDeviceQueue;
    PFN_vkCreateImage pCreateImage;
    PFN_vkGetImageMemoryRequirements pGetImageMemReq;
    PFN_vkAllocateMemory pAllocateMemory;
    PFN_vkBindImageMemory pBindImageMemory;
    PFN_vkCreateCommandPool pCreateCommandPool;
    PFN_vkAllocateCommandBuffers pAllocateCommandBuffers;
    PFN_vkBeginCommandBuffer pBeginCommandBuffer;
    PFN_vkCmdPipelineBarrier pCmdPipelineBarrier;
    PFN_vkCmdClearColorImage pCmdClearColorImage;
    PFN_vkEndCommandBuffer pEndCommandBuffer;
    PFN_vkQueueSubmit pQueueSubmit;
    PFN_vkQueueWaitIdle pQueueWaitIdle;
    PFN_vkCreateSemaphore pCreateSemaphore;
    PFN_vkExportMetalObjectsEXT pExportMetalObjectsEXT;
    PFN_vkDestroyDevice pDestroyDevice;
    PFN_vkDestroyInstance pDestroyInstance;
} VkProbe;

static int loadProbe(VkProbe *p, VkInstance instance) {
#define L(field, name) p->field = (typeof(p->field))gipa(instance, name); \
    if (p->field == NULL) { PROBE_LOG("missing %s", name); return -1; }
    L(pEnumDevExt, "vkEnumerateDeviceExtensionProperties");
    L(pGetQueueFam, "vkGetPhysicalDeviceQueueFamilyProperties");
    L(pGetMemProps, "vkGetPhysicalDeviceMemoryProperties");
    L(pCreateDevice, "vkCreateDevice");
    L(pGetDeviceQueue, "vkGetDeviceQueue");
    L(pCreateImage, "vkCreateImage");
    L(pGetImageMemReq, "vkGetImageMemoryRequirements");
    L(pAllocateMemory, "vkAllocateMemory");
    L(pBindImageMemory, "vkBindImageMemory");
    L(pCreateCommandPool, "vkCreateCommandPool");
    L(pAllocateCommandBuffers, "vkAllocateCommandBuffers");
    L(pBeginCommandBuffer, "vkBeginCommandBuffer");
    L(pCmdPipelineBarrier, "vkCmdPipelineBarrier");
    L(pCmdClearColorImage, "vkCmdClearColorImage");
    L(pEndCommandBuffer, "vkEndCommandBuffer");
    L(pQueueSubmit, "vkQueueSubmit");
    L(pQueueWaitIdle, "vkQueueWaitIdle");
    L(pCreateSemaphore, "vkCreateSemaphore");
    L(pExportMetalObjectsEXT, "vkExportMetalObjectsEXT");
    L(pDestroyDevice, "vkDestroyDevice");
    L(pDestroyInstance, "vkDestroyInstance");
#undef L
    return 0;
}

static int runProbe(void) {
    openLog();
    const char *libPath = [[[NSBundle mainBundle] pathForResource:@"libMoltenVK" ofType:@"dylib" inDirectory:@"Frameworks"] UTF8String];
    PROBE_LOG("moltenvk=%s", libPath ? libPath : "(missing)");
    if (libPath == NULL) return 10;
    gMVK = dlopen(libPath, RTLD_NOW | RTLD_LOCAL);
    if (gMVK == NULL) { PROBE_LOG("dlopen failed: %s", dlerror()); return 11; }
    gipa = (PFN_vkGetInstanceProcAddr)dlsym(gMVK, "vkGetInstanceProcAddr");
    if (gipa == NULL) { PROBE_LOG("no vkGetInstanceProcAddr"); return 12; }

    PFN_vkCreateInstance createInstance = (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
    if (createInstance == NULL) { PROBE_LOG("vkCreateInstance missing"); return 13; }

    VkApplicationInfo app = {VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "VRMC S4a device probe";
    app.apiVersion = VK_API_VERSION_1_2;
    VkInstanceCreateInfo ici = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ici.pApplicationInfo = &app;
    VkInstance instance = VK_NULL_HANDLE;
    VkResult rc = createInstance(&ici, NULL, &instance);
    PROBE_LOG("vkCreateInstance rc=%d", rc);
    if (rc != VK_SUCCESS) return 14;

    VkProbe p; memset(&p, 0, sizeof(p));
    if (loadProbe(&p, instance) != 0) { p.pDestroyInstance(instance, NULL); return 15; }
    PFN_vkEnumeratePhysicalDevices enumPhys = (PFN_vkEnumeratePhysicalDevices)gipa(instance, "vkEnumeratePhysicalDevices");
    if (enumPhys == NULL) { PROBE_LOG("vkEnumeratePhysicalDevices missing"); p.pDestroyInstance(instance, NULL); return 15; }

    uint32_t count = 0;
    rc = enumPhys(instance, &count, NULL);
    PROBE_LOG("physical devices=%u rc=%d", count, rc);
    if (count == 0) { p.pDestroyInstance(instance, NULL); return 16; }
    VkPhysicalDevice phys[4];
    if (count > 4) count = 4;
    enumPhys(instance, &count, phys);
    VkPhysicalDevice pd = phys[0];

    uint32_t extCount = 0;
    p.pEnumDevExt(pd, NULL, &extCount, NULL);
    VkExtensionProperties *exts = (VkExtensionProperties *)calloc(extCount, sizeof(*exts));
    p.pEnumDevExt(pd, NULL, &extCount, exts);
    int hasMetalObjects = 0;
    for (uint32_t i = 0; i < extCount; i++) {
        if (strcmp(exts[i].extensionName, VK_EXT_METAL_OBJECTS_EXTENSION_NAME) == 0) hasMetalObjects = 1;
    }
    free(exts);
    PROBE_LOG("VK_EXT_metal_objects=%d (devices ext count=%u)", hasMetalObjects, extCount);
    if (!hasMetalObjects) { p.pDestroyInstance(instance, NULL); return 17; }

    uint32_t qCount = 0;
    p.pGetQueueFam(pd, &qCount, NULL);
    VkQueueFamilyProperties *qp = (VkQueueFamilyProperties *)calloc(qCount, sizeof(*qp));
    p.pGetQueueFam(pd, &qCount, qp);
    uint32_t qIndex = 0;
    for (uint32_t i = 0; i < qCount; i++) if (qp[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) { qIndex = i; break; }
    free(qp);

    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qci.queueFamilyIndex = qIndex; qci.queueCount = 1; qci.pQueuePriorities = &prio;
    VkPhysicalDeviceVulkan12Features vk12 = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES};
    vk12.timelineSemaphore = VK_TRUE;
    const char *deviceExts[] = { VK_EXT_METAL_OBJECTS_EXTENSION_NAME };
    VkDeviceCreateInfo dci = {VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    dci.pNext = &vk12;
    dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
    dci.enabledExtensionCount = 1; dci.ppEnabledExtensionNames = deviceExts;
    VkDevice device = VK_NULL_HANDLE;
    rc = p.pCreateDevice(pd, &dci, NULL, &device);
    PROBE_LOG("vkCreateDevice rc=%d", rc);
    if (rc != VK_SUCCESS) { p.pDestroyInstance(instance, NULL); return 18; }
    VkQueue queue; p.pGetDeviceQueue(device, qIndex, 0, &queue);

    // MTLDevice export.
    VkExportMetalDeviceInfoEXT devInfo = {VK_STRUCTURE_TYPE_EXPORT_METAL_DEVICE_INFO_EXT};
    VkExportMetalObjectsInfoEXT exportInfo = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT};
    exportInfo.pNext = &devInfo;
    p.pExportMetalObjectsEXT(device, &exportInfo);
    id<MTLDevice> mtlDevice = devInfo.mtlDevice;
    PROBE_LOG("MTLDevice export=%s", mtlDevice ? "yes" : "NO");
    if (!mtlDevice) return 19;

    VkExportMetalObjectCreateInfoEXT exportCreate = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECT_CREATE_INFO_EXT};
    exportCreate.exportObjectType = VK_EXPORT_METAL_OBJECT_TYPE_METAL_TEXTURE_BIT_EXT;
    VkImageCreateInfo imageCI = {VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    imageCI.pNext = &exportCreate;
    imageCI.imageType = VK_IMAGE_TYPE_2D; imageCI.format = VK_FORMAT_R8G8B8A8_UNORM;
    imageCI.extent = (VkExtent3D){64, 64, 1}; imageCI.mipLevels = 1; imageCI.arrayLayers = 1;
    imageCI.samples = VK_SAMPLE_COUNT_1_BIT; imageCI.tiling = VK_IMAGE_TILING_OPTIMAL;
    imageCI.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    imageCI.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    VkImage image = VK_NULL_HANDLE;
    rc = p.pCreateImage(device, &imageCI, NULL, &image);
    PROBE_LOG("vkCreateImage rc=%d", rc);
    if (rc != VK_SUCCESS) return 20;
    VkMemoryRequirements req; p.pGetImageMemReq(device, image, &req);
    VkPhysicalDeviceMemoryProperties mp; p.pGetMemProps(pd, &mp);
    uint32_t mt = 0;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++) {
        if ((req.memoryTypeBits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) { mt = i; break; }
    }
    VkMemoryAllocateInfo mai = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    mai.allocationSize = req.size; mai.memoryTypeIndex = mt;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    rc = p.pAllocateMemory(device, &mai, NULL, &memory);
    if (rc != VK_SUCCESS) { PROBE_LOG("vkAllocateMemory rc=%d", rc); return 21; }
    p.pBindImageMemory(device, image, memory, 0);

    VkCommandPoolCreateInfo poolCI = {VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    poolCI.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT; poolCI.queueFamilyIndex = qIndex;
    VkCommandPool pool; p.pCreateCommandPool(device, &poolCI, NULL, &pool);
    VkCommandBufferAllocateInfo cbAI = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    cbAI.commandPool = pool; cbAI.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cbAI.commandBufferCount = 1;
    VkCommandBuffer cb; p.pAllocateCommandBuffers(device, &cbAI, &cb);
    VkCommandBufferBeginInfo begin = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    p.pBeginCommandBuffer(cb, &begin);
    VkImageSubresourceRange range = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    VkImageMemoryBarrier barrier = {VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = image; barrier.subresourceRange = range;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    p.pCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &barrier);
    VkClearColorValue red = {{1.0f, 0.0f, 0.0f, 1.0f}};
    p.pCmdClearColorImage(cb, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &red, 1, &range);
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; barrier.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT;
    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    p.pCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, NULL, 0, NULL, 1, &barrier);
    p.pEndCommandBuffer(cb);
    VkSubmitInfo submit = {VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.commandBufferCount = 1; submit.pCommandBuffers = &cb;
    p.pQueueSubmit(queue, 1, &submit, VK_NULL_HANDLE); p.pQueueWaitIdle(queue);
    PROBE_LOG("vulkan clear submitted");

    VkExportMetalTextureInfoEXT texInfo = {VK_STRUCTURE_TYPE_EXPORT_METAL_TEXTURE_INFO_EXT};
    texInfo.image = image; texInfo.plane = VK_IMAGE_ASPECT_COLOR_BIT;
    VkExportMetalObjectsInfoEXT ex2 = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT};
    ex2.pNext = &texInfo;
    p.pExportMetalObjectsEXT(device, &ex2);
    id<MTLTexture> mtlTexture = texInfo.mtlTexture;
    PROBE_LOG("MTLTexture export=%s", mtlTexture ? "yes" : "NO");
    if (!mtlTexture) return 22;
    PROBE_LOG("MTLTexture %lux%lu pixelFormat=%lu", (unsigned long)mtlTexture.width, (unsigned long)mtlTexture.height, (unsigned long)mtlTexture.pixelFormat);

    NSUInteger bytesPerRow = mtlTexture.width * 4;
    id<MTLBuffer> readback = [mtlDevice newBufferWithLength:bytesPerRow * mtlTexture.height options:MTLResourceStorageModeShared];
    id<MTLCommandQueue> mq = [mtlDevice newCommandQueue];
    id<MTLCommandBuffer> mcb = [mq commandBuffer];
    id<MTLBlitCommandEncoder> blit = [mcb blitCommandEncoder];
    [blit copyFromTexture:mtlTexture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
               sourceSize:MTLSizeMake(mtlTexture.width, mtlTexture.height, 1) toBuffer:readback
        destinationOffset:0 destinationBytesPerRow:bytesPerRow destinationBytesPerImage:bytesPerRow * mtlTexture.height];
    [blit endEncoding]; [mcb commit]; [mcb waitUntilCompleted];
    if (mcb.error) { PROBE_LOG("metal blit error: %s", mcb.error.description.UTF8String); return 23; }
    uint8_t *px = (uint8_t *)readback.contents;
    PROBE_LOG("metal readback pixel=%u,%u,%u,%u", px[0], px[1], px[2], px[3]);
    if (!(px[0] == 255 && px[1] == 0 && px[2] == 0 && px[3] == 255)) return 24;

    VkExportMetalObjectCreateInfoEXT seCreate = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECT_CREATE_INFO_EXT};
    seCreate.exportObjectType = VK_EXPORT_METAL_OBJECT_TYPE_METAL_SHARED_EVENT_BIT_EXT;
    VkSemaphoreTypeCreateInfo seType = {VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO};
    seType.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE; seType.initialValue = 0; seType.pNext = &seCreate;
    VkSemaphoreCreateInfo seCI = {VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO}; seCI.pNext = &seType;
    VkSemaphore sem = VK_NULL_HANDLE;
    rc = p.pCreateSemaphore(device, &seCI, NULL, &sem);
    PROBE_LOG("vkCreateSemaphore(timeline, shared-event export) rc=%d", rc);
    if (rc == VK_SUCCESS) {
        VkExportMetalSharedEventInfoEXT seInfo = {VK_STRUCTURE_TYPE_EXPORT_METAL_SHARED_EVENT_INFO_EXT};
        seInfo.semaphore = sem;
        VkExportMetalObjectsInfoEXT seEx = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT}; seEx.pNext = &seInfo;
        p.pExportMetalObjectsEXT(device, &seEx);
        id<MTLSharedEvent> se = seInfo.mtlSharedEvent;
        PROBE_LOG("MTLSharedEvent export=%s", se ? "yes" : "NO");
        if (se) {
            uint64_t val = 42;
            VkTimelineSemaphoreSubmitInfo tsi = {VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO};
            tsi.signalSemaphoreValueCount = 1; tsi.pSignalSemaphoreValues = &val;
            VkSubmitInfo sig = {VK_STRUCTURE_TYPE_SUBMIT_INFO};
            sig.pNext = &tsi; sig.signalSemaphoreCount = 1; sig.pSignalSemaphores = &sem;
            p.pQueueSubmit(queue, 1, &sig, VK_NULL_HANDLE); p.pQueueWaitIdle(queue);
            PROBE_LOG("MTLSharedEvent.signaledValue=%llu (expect 42)", (unsigned long long)se.signaledValue);
            if (se.signaledValue != 42) return 25;
        } else return 26;
    } else return 27;

    PROBE_LOG("S4a-DEVICE PASS: MTLDevice + MTLTexture export, Metal readback correct, timeline MTLSharedEvent sync OK");
    p.pDestroyDevice(device, NULL);
    p.pDestroyInstance(instance, NULL);
    return 0;
}

void vrmc_s4a_probe_maybe_run(void) {
    const char *home = getenv("AME_HOME");
    if (home == NULL) return;
    char flag[PATH_MAX];
    snprintf(flag, sizeof(flag), "%s/vrmc_s4a_device.flag", home);
    if (access(flag, F_OK) != 0) return;
    unlink(flag);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int rc = runProbe();
        PROBE_LOG("probe exit rc=%d", rc);
        if (gLog) { fflush(gLog); fclose(gLog); }
    });
}
