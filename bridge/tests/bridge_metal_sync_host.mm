/*
 * Host (macOS) integration probe for the VRMC eye-frame handoff with GPU synchronization.
 *
 * Goal: prove on the host, with real MoltenVK + Metal, that:
 *   1. the bridge export path (vrmc_export_mtl_texture: VkImage -> MTLTexture through
 *      vkGetMTLTextureMVK) returns a texture whose Metal usage includes MTLTextureUsageShaderRead
 *      for the exact VkImage usage flags Minecraft 26.2 uses for VR render targets
 *      (SAMPLED|COLOR_ATTACHMENT|TRANSFER_SRC|TRANSFER_DST) -- i.e. "sampling returns black because
 *      the texture was exported without shader-read usage" is NOT a real explanation;
 *   2. a timeline VkSemaphore exported as MTLSharedEvent, published through the bridge together with
 *      the exported eye textures (vrmc_shared_publish_eyes), lets a *separate compositor thread* on
 *      a separate MTLCommandQueue encode a wait and then sample the texture in a render pass -- the
 *      exact protocol the visionOS compositor must implement -- and read back the expected pixels;
 *   3. the wait is value-correct across two frames (Vulkan signals 5 then 6; Metal waits 5 then 6).
 *
 * This is a host gate only: it does not prove visionOS behavior (EV-0065 covers device MoltenVK).
 *
 * Build/run: bridge/tests/run_tests.sh (downloads nothing; set MVK_ROOT to a MoltenVK macOS SDK,
 * default /tmp/vrmc-host-mvk).
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_metal.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vrmc_abi.h"
#include "vrmc_native_shared.h"

#define VK_CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) {     printf("FAIL %s at %s:%d -> %d\n", #x, __FILE__, __LINE__, (int)r_); return 1; } } while (0)
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL %s:%d: ", __FILE__, __LINE__);     printf(__VA_ARGS__); printf("\n"); g_failures++; } } while (0)

static int g_failures = 0;

/* ---- Vulkan/Metal process-wide objects ----------------------------------------------------- */
static VkDevice gVkDevice;
static VkQueue gVkQueue;
static VkPhysicalDevice gPhys;
static VkCommandBuffer gClearCB;
static VkSemaphore gTimelineSem;
static id<MTLDevice> gMtlDevice;
static id<MTLTexture> gProviderTexture;
static id<MTLSharedEvent> gSharedEvent;
static uint64_t gCurrentSignalValue;

/* ---- Compositor-side (separate thread + queue) --------------------------------------------- */
typedef struct {
    int expectedValid;
    uint64_t expectedValue;
    uint8_t expectedRGB[3];
    int failures;
    int acquired;
    int sawSync;
    int sawShaderReadUsage;
    uint64_t acquiredSequence;
    uint64_t metalSignaledAfterWait;
    char error[512];
} CompositorResult;

static const char *kShaderSource =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct VOut { float4 pos [[position]]; };\n"
    "vertex VOut vmain(uint vid [[vertex_id]]) {\n"
    "  float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };\n"
    "  VOut o; o.pos = float4(p[vid], 0, 1); return o;\n"
    "}\n"
    // Shader-read of the provider texture: read() requires MTLTextureUsageShaderRead, so Metal
    // validation (MTL_DEBUG_LAYER=1) fails loudly if MoltenVK exported a render-target-only texture.
    "fragment float4 fmain(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {\n"
    "  uint2 p = uint2(in.pos.xy);\n"
    "  return float4(tex.read(p).rgb, 1.0);\n"
    "}\n";

static void *compositor_thread(void *arg) {
    CompositorResult *res = (CompositorResult *)arg;
    @autoreleasepool {
        vrmc_shared_eye_frame frame;
        memset(&frame, 0, sizeof(frame));
        if (vrmc_shared_acquire_eyes(&frame) != 0) {
            snprintf(res->error, sizeof(res->error), "acquire failed: %s", vrmc_last_error());
            return NULL;
        }
        res->acquired = 1;
        res->acquiredSequence = frame.publish_sequence;
        if (frame.eyes.left_texture == 0 || frame.eyes.right_texture == 0) {
            snprintf(res->error, sizeof(res->error), "acquired frame has no texture handles");
            return NULL;
        }
        id<MTLTexture> tex = (__bridge id<MTLTexture>)(void *)(uintptr_t)frame.eyes.left_texture;
        res->sawShaderReadUsage = (tex.usage & MTLTextureUsageShaderRead) ? 1 : 0;
        if (res->expectedValid) {
            if (frame.sync.valid != 1 || frame.sync.signal_value != res->expectedValue) {
                snprintf(res->error, sizeof(res->error), "bad sync pair valid=%u value=%llu (want %llu)",
                         frame.sync.valid, (unsigned long long)frame.sync.signal_value,
                         (unsigned long long)res->expectedValue);
                return NULL;
            }
            id<MTLSharedEvent> ev = (__bridge id<MTLSharedEvent>)(void *)(uintptr_t)frame.sync.shared_event;
            if (ev == nil || ![ev conformsToProtocol:@protocol(MTLSharedEvent)]) {
                snprintf(res->error, sizeof(res->error), "published event is not an MTLSharedEvent");
                return NULL;
            }
            res->sawSync = 1;
        }

        id<MTLCommandQueue> queue = [gMtlDevice newCommandQueue];
        NSError *err = nil;
        id<MTLLibrary> lib = [gMtlDevice newLibraryWithSource:[NSString stringWithUTF8String:kShaderSource]
                                                      options:nil error:&err];
        if (lib == nil) {
            snprintf(res->error, sizeof(res->error), "shader compile failed: %s", err.description.UTF8String);
            return NULL;
        }
        id<MTLRenderPipelineState> pipeline = nil;
        {
            MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
            pd.vertexFunction = [lib newFunctionWithName:@"vmain"];
            pd.fragmentFunction = [lib newFunctionWithName:@"fmain"];
            pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
            pipeline = [gMtlDevice newRenderPipelineStateWithDescriptor:pd error:&err];
            if (pipeline == nil) {
                snprintf(res->error, sizeof(res->error), "pipeline failed: %s", err.description.UTF8String);
                return NULL;
            }
        }
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                      width:tex.width
                                                                                     height:tex.height
                                                                                  mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        td.storageMode = MTLStorageModePrivate;
        id<MTLTexture> dst = [gMtlDevice newTextureWithDescriptor:td];
        if (dst == nil) {
            snprintf(res->error, sizeof(res->error), "destination texture allocation failed");
            return NULL;
        }
        const NSUInteger rowBytes = tex.width * 4;
        id<MTLBuffer> readback = [gMtlDevice newBufferWithLength:rowBytes * tex.height
                                                         options:MTLResourceStorageModeShared];

        id<MTLCommandBuffer> cb = [queue commandBuffer];
        if (res->expectedValid) {
            // THE fix: cross-queue GPU dependency on the provider's frame timeline.
            [cb encodeWaitForEvent:(__bridge id<MTLSharedEvent>)(void *)(uintptr_t)frame.sync.shared_event
                             value:frame.sync.signal_value];
        }
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = dst;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        if (enc == nil) {
            snprintf(res->error, sizeof(res->error), "render command encoder was nil");
            return NULL;
        }
        [enc setRenderPipelineState:pipeline];
        [enc setFragmentTexture:tex atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [enc endEncoding];
        id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
        [blit copyFromTexture:dst sourceSlice:0 sourceLevel:0
                sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(tex.width, tex.height, 1)
                 toBuffer:readback destinationOffset:0 destinationBytesPerRow:rowBytes
       destinationBytesPerImage:rowBytes * tex.height];
        [blit endEncoding];
        [cb commit];
        [cb waitUntilCompleted];
        if (cb.status != MTLCommandBufferStatusCompleted) {
            snprintf(res->error, sizeof(res->error), "Metal command buffer status=%ld error=%s",
                     (long)cb.status, cb.error ? cb.error.description.UTF8String : "none");
            return NULL;
        }
        if (res->expectedValid) {
            id<MTLSharedEvent> ev =
                (__bridge id<MTLSharedEvent>)(void *)(uintptr_t)frame.sync.shared_event;
            res->metalSignaledAfterWait = (uint64_t)[ev signaledValue];
        }
        const uint8_t *px = (const uint8_t *)readback.contents;
        if (px == NULL) {
            snprintf(res->error, sizeof(res->error), "readback buffer contents null");
            return NULL;
        }
        if (abs((int)px[0] - (int)res->expectedRGB[0]) > 1 ||
            abs((int)px[1] - (int)res->expectedRGB[1]) > 1 ||
            abs((int)px[2] - (int)res->expectedRGB[2]) > 1) {
            snprintf(res->error, sizeof(res->error), "pixel mismatch: got %u,%u,%u want %u,%u,%u",
                     px[0], px[1], px[2], res->expectedRGB[0], res->expectedRGB[1], res->expectedRGB[2]);
            return NULL;
        }
    }
    return NULL;
}

static int run_probe(void) {
    printf("[bridge-mvk] MoltenVK/Metal host probe (host gate only; device = EV-0065)\n");

    /* 0. Bridge init (ABI v2 unchanged). */
    if (vrmc_init("{\"abi\":2,\"eyes\":2}", 18) != 0) {
        printf("FAIL vrmc_init: %s\n", vrmc_last_error());
        return 1;
    }

    /* 1. Vulkan instance/device with VK_EXT_metal_objects + timeline semaphores. Enable
     * VK_KHR_portability_enumeration only when the driver advertises it (no error spam). */
    const char *instanceExts[] = { VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME };
    int hasPortability = 0;
    {
        uint32_t ieCount = 0;
        vkEnumerateInstanceExtensionProperties(NULL, &ieCount, NULL);
        VkExtensionProperties *ie = (VkExtensionProperties *)calloc(ieCount, sizeof(*ie));
        vkEnumerateInstanceExtensionProperties(NULL, &ieCount, ie);
        for (uint32_t i = 0; i < ieCount; i++) {
            if (strcmp(ie[i].extensionName, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME) == 0) hasPortability = 1;
        }
        free(ie);
    }
    VkApplicationInfo app = {VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "VRMC bridge metal sync host probe";
    app.apiVersion = VK_API_VERSION_1_2;
    VkInstanceCreateInfo ici = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ici.pApplicationInfo = &app;
    ici.enabledExtensionCount = hasPortability ? 1u : 0u;
    ici.ppEnabledExtensionNames = instanceExts;
    ici.flags = hasPortability ? VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR : 0;
    VkInstance instance;
    VK_CHECK(vkCreateInstance(&ici, NULL, &instance));
    uint32_t count = 0;
    VK_CHECK(vkEnumeratePhysicalDevices(instance, &count, NULL));
    if (count == 0) { printf("FAIL no Vulkan physical device (MoltenVK missing?)\n"); return 1; }
    VkPhysicalDevice phys[4];
    if (count > 4) count = 4;
    VK_CHECK(vkEnumeratePhysicalDevices(instance, &count, phys));
    gPhys = phys[0];

    uint32_t extCount = 0;
    vkEnumerateDeviceExtensionProperties(gPhys, NULL, &extCount, NULL);
    VkExtensionProperties *exts = (VkExtensionProperties *)calloc(extCount, sizeof(*exts));
    vkEnumerateDeviceExtensionProperties(gPhys, NULL, &extCount, exts);
    int hasMetalObjects = 0;
    for (uint32_t i = 0; i < extCount; i++) {
        if (strcmp(exts[i].extensionName, VK_EXT_METAL_OBJECTS_EXTENSION_NAME) == 0) hasMetalObjects = 1;
    }
    free(exts);
    CHECK(hasMetalObjects != 0, "VK_EXT_metal_objects not available");
    if (!hasMetalObjects) return 1;

    uint32_t qCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(gPhys, &qCount, NULL);
    VkQueueFamilyProperties *qprops = (VkQueueFamilyProperties *)calloc(qCount, sizeof(*qprops));
    vkGetPhysicalDeviceQueueFamilyProperties(gPhys, &qCount, qprops);
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
    VK_CHECK(vkCreateDevice(gPhys, &dci, NULL, &gVkDevice));
    vkGetDeviceQueue(gVkDevice, qIndex, 0, &gVkQueue);

    /* Export the MTLDevice (same device the provider's MoltenVK uses in-process). */
    VkExportMetalDeviceInfoEXT devInfo = {VK_STRUCTURE_TYPE_EXPORT_METAL_DEVICE_INFO_EXT};
    VkExportMetalObjectsInfoEXT exportDev = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT};
    exportDev.pNext = &devInfo;
    vkExportMetalObjectsEXT(gVkDevice, &exportDev);
    gMtlDevice = devInfo.mtlDevice;
    CHECK(gMtlDevice != nil, "MTLDevice export failed");
    if (gMtlDevice == nil) return 1;

    /* 2. Exported eye image with the EXACT usage Minecraft 26.2 uses for VR render targets:
     *    SAMPLED|COLOR_ATTACHMENT|TRANSFER_SRC|TRANSFER_DST (GpuTexture usage 15). */
    VkImageCreateInfo imageCI = {VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    imageCI.imageType = VK_IMAGE_TYPE_2D;
    imageCI.format = VK_FORMAT_R8G8B8A8_UNORM;
    imageCI.extent = (VkExtent3D){64, 64, 1};
    imageCI.mipLevels = 1;
    imageCI.arrayLayers = 1;
    imageCI.samples = VK_SAMPLE_COUNT_1_BIT;
    imageCI.tiling = VK_IMAGE_TILING_OPTIMAL;
    imageCI.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                    VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    imageCI.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    imageCI.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    VkExportMetalObjectCreateInfoEXT exportCreate = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECT_CREATE_INFO_EXT};
    exportCreate.exportObjectType = VK_EXPORT_METAL_OBJECT_TYPE_METAL_TEXTURE_BIT_EXT;
    imageCI.pNext = &exportCreate;
    VkImage image;
    VK_CHECK(vkCreateImage(gVkDevice, &imageCI, NULL, &image));
    VkMemoryRequirements memReq;
    vkGetImageMemoryRequirements(gVkDevice, image, &memReq);
    VkPhysicalDeviceMemoryProperties memProps;
    vkGetPhysicalDeviceMemoryProperties(gPhys, &memProps);
    uint32_t memTypeIdx = 0;
    for (uint32_t i = 0; i < memProps.memoryTypeCount; i++) {
        if ((memReq.memoryTypeBits & (1u << i)) &&
            (memProps.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) {
            memTypeIdx = i; break;
        }
    }
    VkMemoryAllocateInfo alloc = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    alloc.allocationSize = memReq.size;
    alloc.memoryTypeIndex = memTypeIdx;
    VkDeviceMemory imageMemory;
    VK_CHECK(vkAllocateMemory(gVkDevice, &alloc, NULL, &imageMemory));
    VK_CHECK(vkBindImageMemory(gVkDevice, image, imageMemory, 0));

    VkCommandPoolCreateInfo poolCI = {VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    poolCI.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolCI.queueFamilyIndex = qIndex;
    VkCommandPool pool;
    VK_CHECK(vkCreateCommandPool(gVkDevice, &poolCI, NULL, &pool));
    VkCommandBufferAllocateInfo cbAI = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    cbAI.commandPool = pool;
    cbAI.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cbAI.commandBufferCount = 1;
    VK_CHECK(vkAllocateCommandBuffers(gVkDevice, &cbAI, &gClearCB));

    /* 3. Export the MTLTexture through the BRIDGE (not directly) and check its usage flags. */
    uint64_t textureHandle = 0;
    if (vrmc_export_mtl_texture((uint64_t)(uintptr_t)image, &textureHandle) != 0 || textureHandle == 0) {
        printf("FAIL vrmc_export_mtl_texture: %s (fallback BUNDLE_PATH=%s)\n",
               vrmc_last_error(), getenv("BUNDLE_PATH") ? getenv("BUNDLE_PATH") : "(unset)");
        return 1;
    }
    id<MTLTexture> mtlTexture = (__bridge id<MTLTexture>)(void *)(uintptr_t)textureHandle;
    gProviderTexture = mtlTexture;
    printf("[bridge-mvk] exported MTLTexture: %lux%lu fmt=%lu usage=0x%lx (ShaderRead=%d RenderTarget=%d)\n",
           (unsigned long)mtlTexture.width, (unsigned long)mtlTexture.height,
           (unsigned long)mtlTexture.pixelFormat, (unsigned long)mtlTexture.usage,
           (mtlTexture.usage & MTLTextureUsageShaderRead) ? 1 : 0,
           (mtlTexture.usage & MTLTextureUsageRenderTarget) ? 1 : 0);
    CHECK(mtlTexture.usage & MTLTextureUsageShaderRead,
          "exported MTLTexture lacks MTLTextureUsageShaderRead despite VK_IMAGE_USAGE_SAMPLED_BIT");
    if (mtlTexture.width != 64 || mtlTexture.height != 64 || mtlTexture.pixelFormat != MTLPixelFormatRGBA8Unorm) {
        printf("FAIL exported texture geometry/format mismatch\n");
        return 1;
    }

    /* 4. Timeline semaphore -> MTLSharedEvent (S4a path). */
    VkExportMetalObjectCreateInfoEXT seCreate = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECT_CREATE_INFO_EXT};
    seCreate.exportObjectType = VK_EXPORT_METAL_OBJECT_TYPE_METAL_SHARED_EVENT_BIT_EXT;
    VkSemaphoreTypeCreateInfo seType = {VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO};
    seType.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE;
    seType.initialValue = 0;
    seType.pNext = &seCreate;
    VkSemaphoreCreateInfo seCI = {VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    seCI.pNext = &seType;
    VK_CHECK(vkCreateSemaphore(gVkDevice, &seCI, NULL, &gTimelineSem));
    VkExportMetalSharedEventInfoEXT seInfo = {VK_STRUCTURE_TYPE_EXPORT_METAL_SHARED_EVENT_INFO_EXT};
    seInfo.semaphore = gTimelineSem;
    VkExportMetalObjectsInfoEXT seExport = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT};
    seExport.pNext = &seInfo;
    vkExportMetalObjectsEXT(gVkDevice, &seExport);
    gSharedEvent = seInfo.mtlSharedEvent;
    CHECK(gSharedEvent != nil, "MTLSharedEvent export failed (timeline semaphore required)");
    if (gSharedEvent == nil) return 1;
    printf("[bridge-mvk] exported MTLSharedEvent: yes\n");

    /* 5. Two frames: clear the image via Vulkan, signal value V, publish through the bridge, and let
     *    the compositor thread (separate thread + separate MTLCommandQueue) wait on V and sample. */
    uint8_t frame1[3] = {64, 128, 191};
    uint8_t frame2[3] = {10, 200, 30};
    for (int f = 0; f < 2; f++) {
        uint8_t *rgb = (f == 0) ? frame1 : frame2;
        gCurrentSignalValue = (uint64_t)(f == 0 ? 5 : 6);
        /* Transition from shader-read (frame 0: undefined initially) to transfer-dst, clear, then
         * back to shader-read. */
        VkCommandBufferBeginInfo begin = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
        VK_CHECK(vkBeginCommandBuffer(gClearCB, &begin));
        VkImageSubresourceRange range = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        VkImageMemoryBarrier barrier = {VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
        barrier.srcAccessMask = (f == 0) ? 0 : VK_ACCESS_SHADER_READ_BIT;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.oldLayout = (f == 0) ? VK_IMAGE_LAYOUT_UNDEFINED : VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.image = image;
        barrier.subresourceRange = range;
        vkCmdPipelineBarrier(gClearCB, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
                             0, 0, NULL, 0, NULL, 1, &barrier);
        VkClearColorValue color;
        memset(&color, 0, sizeof(color));
        color.float32[0] = (float)rgb[0] / 255.0f;
        color.float32[1] = (float)rgb[1] / 255.0f;
        color.float32[2] = (float)rgb[2] / 255.0f;
        color.float32[3] = 1.0f;
        vkCmdClearColorImage(gClearCB, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &color, 1, &range);
        VkImageMemoryBarrier toRead = barrier;
        toRead.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        toRead.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        toRead.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        toRead.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        vkCmdPipelineBarrier(gClearCB, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                             0, 0, NULL, 0, NULL, 1, &toRead);
        VK_CHECK(vkEndCommandBuffer(gClearCB));

        uint64_t signalValue = gCurrentSignalValue;
        VkTimelineSemaphoreSubmitInfo tsi = {VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO};
        tsi.signalSemaphoreValueCount = 1;
        tsi.pSignalSemaphoreValues = &signalValue;
        VkSubmitInfo submit = {VK_STRUCTURE_TYPE_SUBMIT_INFO};
        submit.pNext = &tsi;
        submit.commandBufferCount = 1;
        submit.pCommandBuffers = &gClearCB;
        submit.signalSemaphoreCount = 1;
        submit.pSignalSemaphores = &gTimelineSem;
        VK_CHECK(vkQueueSubmit(gVkQueue, 1, &submit, VK_NULL_HANDLE));

        /* Publish exactly what VisionRenderer.endFrame() will publish (after its Vulkan signal):
         * eye handles + the exported event + the value the game's submission signals. */
        vrmc_eye_targets eyes;
        memset(&eyes, 0, sizeof(eyes));
        eyes.frame_index = (uint32_t)(f + 1);
        eyes.left_texture = (uint64_t)(uintptr_t)mtlTexture;
        eyes.right_texture = (uint64_t)(uintptr_t)mtlTexture;
        eyes.left_width = eyes.right_width = 64;
        eyes.left_height = eyes.right_height = 64;
        eyes.left_fov[0] = -1.0f; eyes.left_fov[1] = 1.0f; eyes.left_fov[2] = 1.0f; eyes.left_fov[3] = -1.0f;
        memcpy(eyes.right_fov, eyes.left_fov, sizeof(eyes.left_fov));
        vrmc_shared_frame_sync sync;
        memset(&sync, 0, sizeof(sync));
        sync.shared_event = (uint64_t)(uintptr_t)gSharedEvent;
        sync.signal_value = gCurrentSignalValue;
        sync.frame_index = eyes.frame_index;
        sync.valid = 1;
        if (vrmc_shared_publish_eyes(&eyes, &sync) != 0) {
            printf("FAIL vrmc_shared_publish_eyes: %s\n", vrmc_last_error());
            return 1;
        }
        vrmc_shared_frame_sync gotSync;
        if (vrmc_shared_get_frame_sync(&gotSync) != 0 || gotSync.signal_value != gCurrentSignalValue) {
            printf("FAIL frame sync getter after publish\n");
            return 1;
        }

        CompositorResult res;
        memset(&res, 0, sizeof(res));
        res.expectedValid = 1;
        res.expectedValue = gCurrentSignalValue;
        memcpy(res.expectedRGB, rgb, 3);
        pthread_t tid;
        pthread_create(&tid, NULL, compositor_thread, &res);
        pthread_join(tid, NULL);
        CHECK(res.acquired == 1, "frame %d: compositor did not acquire", f);
        CHECK(res.sawSync == 1, "frame %d: compositor did not see the sync pair", f);
        CHECK(res.acquiredSequence == (uint64_t)(f + 1), "frame %d: publish_sequence=%llu", f,
              (unsigned long long)res.acquiredSequence);
        CHECK(res.sawShaderReadUsage == 1, "frame %d: compositor saw no ShaderRead usage", f);
        CHECK(res.metalSignaledAfterWait >= gCurrentSignalValue,
              "frame %d: event value after wait %llu < %llu", f,
              (unsigned long long)res.metalSignaledAfterWait, (unsigned long long)gCurrentSignalValue);
        if (res.error[0] != '\0') printf("FAIL frame %d: %s\n", f, res.error);
        if (res.error[0] != '\0') g_failures++;
        if (res.error[0] == '\0') {
            printf("[bridge-mvk] frame %d (wait value %llu): sampled RGB=%u,%u,%u in a shader, "
                   "event seen=%llu: PASS\n", f, (unsigned long long)gCurrentSignalValue,
                   rgb[0], rgb[1], rgb[2], (unsigned long long)res.metalSignaledAfterWait);
        }
    }

    /* 6. Unsynchronized publication is still representable (legacy/GL behaviour). */
    vrmc_eye_targets eyes;
    memset(&eyes, 0, sizeof(eyes));
    eyes.frame_index = 3;
    eyes.left_texture = (uint64_t)(uintptr_t)mtlTexture;
    eyes.right_texture = (uint64_t)(uintptr_t)mtlTexture;
    eyes.left_width = eyes.right_width = 64;
    eyes.left_height = eyes.right_height = 64;
    if (vrmc_shared_publish_eyes(&eyes, NULL) != 0) {
        printf("FAIL legacy unsynchronized publish: %s\n", vrmc_last_error());
        g_failures++;
    } else {
        vrmc_shared_eye_frame legacy;
        if (vrmc_shared_acquire_eyes(&legacy) == 0 && legacy.sync.valid == 0) {
            printf("[bridge-mvk] unsynchronized publication (sync.valid=0): PASS\n");
        } else {
            printf("FAIL unsynchronized publication state\n");
            g_failures++;
        }
    }

    vkDeviceWaitIdle(gVkDevice);
    if (g_failures != 0) {
        printf("[bridge-mvk] FAILED (%d checks)\n", g_failures);
        return 1;
    }
    printf("[bridge-mvk] ALL PASS: exported MTLTexture is ShaderRead-capable; timeline MTLSharedEvent "
           "wait orders a foreign-queue shader read of the frame; two frame values verified.\n");
    return 0;
}

int main(void) {
    @autoreleasepool {
        return run_probe();
    }
}
