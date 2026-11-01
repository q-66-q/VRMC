// MoltenVK capability probe for VRMC S2 research (scratch, not project code).
// Loads libMoltenVK.dylib directly (as LWJGL does on macOS) and reports whether it
// advertises the extensions/features required by Minecraft 26.2's Vulkan backend.
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_metal.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static PFN_vkGetInstanceProcAddr GIPA;

#define LOAD2(fn, type, name) do { fn = (type)GIPA(instance, name); } while (0)

static PFN_vkCreateInstance pCreateInstance;
static PFN_vkEnumerateInstanceExtensionProperties pEnumInstExt;
static PFN_vkEnumeratePhysicalDevices pEnumPhys;
static PFN_vkGetPhysicalDeviceProperties2 pGetProps2;
static PFN_vkGetPhysicalDeviceFeatures2 pGetFeat2;
static PFN_vkEnumerateDeviceExtensionProperties pEnumDevExt;
static PFN_vkGetPhysicalDeviceQueueFamilyProperties pGetQueueFam;
static PFN_vkDestroyInstance pDestroyInstance;

static const char *REQ_EXT[] = {
    "VK_KHR_dynamic_rendering", "VK_KHR_push_descriptor", "VK_KHR_synchronization2",
    "VK_EXT_vertex_attribute_divisor", "VK_KHR_swapchain", NULL };
static const char *OPT_EXT[] = {
    "VK_KHR_portability_subset", "VK_EXT_multi_draw", "VK_AMD_buffer_marker",
    "VK_NV_device_diagnostic_checkpoints", "VK_EXT_metal_objects",
    "VK_EXT_metal_surface", "VK_KHR_portability_enumeration", "VK_EXT_layer_settings",
    "VK_EXT_debug_utils", "VK_KHR_surface", NULL };


// ---------------------------------------------------------------------------
// Minimal device render test: clear a 64x64 RGBA8 image to a known colour with
// vkCmdClearColorImage, copy it to a host-visible buffer, and verify the pixel.
// Proves the device actually executes work through MoltenVK on this OS, not
// just that the extensions are advertised.
// ---------------------------------------------------------------------------
static int vrmc_find_mem_type(VkPhysicalDevice phys, uint32_t bits, VkMemoryPropertyFlags want) {
    VkPhysicalDeviceMemoryProperties mp;
    PFN_vkGetPhysicalDeviceMemoryProperties gpm =
        (PFN_vkGetPhysicalDeviceMemoryProperties)GIPA(NULL, "vkGetPhysicalDeviceMemoryProperties");
    if (!gpm) gpm = (PFN_vkGetPhysicalDeviceMemoryProperties)GIPA(NULL, "vkGetPhysicalDeviceMemoryProperties");
    // GIPA(NULL, ...) may not return it on some loaders; caller passes via global below instead.
    (void)gpm; (void)phys; (void)bits; (void)want;
    return -1;
}

static int vrmc_render_test(VkInstance instance, VkPhysicalDevice phys, uint32_t gfx_family) {
    PFN_vkCreateDevice pCreateDevice = (PFN_vkCreateDevice)GIPA(instance, "vkCreateDevice");
    PFN_vkGetDeviceProcAddr GDPA = (PFN_vkGetDeviceProcAddr)GIPA(instance, "vkGetDeviceProcAddr");
    if (!pCreateDevice || !GDPA) { printf("  RENDER-TEST FAIL (no device funcs)\n"); return 1; }

    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = {0};
    qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    qci.queueFamilyIndex = gfx_family;
    qci.queueCount = 1;
    qci.pQueuePriorities = &prio;
    VkDeviceCreateInfo dci = {0};
    dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    VkDevice dev = NULL;
    if (pCreateDevice(phys, &dci, NULL, &dev) != VK_SUCCESS) { printf("  RENDER-TEST FAIL (vkCreateDevice)\n"); return 1; }

#define DFN(name) PFN_##name name = (PFN_##name)GDPA(dev, #name)
    DFN(vkGetDeviceQueue); DFN(vkCreateImage); DFN(vkGetImageMemoryRequirements);
    DFN(vkAllocateMemory); DFN(vkBindImageMemory); DFN(vkCreateBuffer);
    DFN(vkGetBufferMemoryRequirements); DFN(vkBindBufferMemory); DFN(vkCreateCommandPool);
    DFN(vkAllocateCommandBuffers); DFN(vkBeginCommandBuffer); DFN(vkCmdPipelineBarrier);
    DFN(vkCmdClearColorImage); DFN(vkCmdCopyImageToBuffer); DFN(vkEndCommandBuffer);
    DFN(vkQueueSubmit); DFN(vkQueueWaitIdle); DFN(vkMapMemory); DFN(vkUnmapMemory);
    DFN(vkDestroyCommandPool); DFN(vkDestroyDevice); DFN(vkDestroyImage); DFN(vkDestroyBuffer);
    DFN(vkFreeMemory);
#undef DFN
    PFN_vkGetPhysicalDeviceMemoryProperties vkGetPhysicalDeviceMemoryProperties =
        (PFN_vkGetPhysicalDeviceMemoryProperties)GIPA(instance, "vkGetPhysicalDeviceMemoryProperties");
    if (!vkCreateImage || !vkAllocateMemory || !vkGetPhysicalDeviceMemoryProperties) {
        printf("  RENDER-TEST FAIL (missing device entry points)\n"); vkDestroyDevice(dev, NULL); return 1;
    }

    const uint32_t W = 64, H = 64;
    VkImageCreateInfo ici = {0};
    ici.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ici.imageType = VK_IMAGE_TYPE_2D;
    ici.format = VK_FORMAT_R8G8B8A8_UNORM;
    ici.extent.width = W; ici.extent.height = H; ici.extent.depth = 1;
    ici.mipLevels = 1; ici.arrayLayers = 1;
    ici.samples = VK_SAMPLE_COUNT_1_BIT;
    ici.tiling = VK_IMAGE_TILING_OPTIMAL;
    ici.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    VkImage img = NULL;
    if (vkCreateImage(dev, &ici, NULL, &img) != VK_SUCCESS) { printf("  RENDER-TEST FAIL (vkCreateImage)\n"); vkDestroyDevice(dev,NULL); return 1; }
    VkMemoryRequirements imr; vkGetImageMemoryRequirements(dev, img, &imr);
    VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(phys, &mp);
    int img_type = -1;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
        if ((imr.memoryTypeBits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) { img_type = (int)i; break; }
    if (img_type < 0) { printf("  RENDER-TEST FAIL (no device-local memory)\n"); vkDestroyImage(dev,img,NULL); vkDestroyDevice(dev,NULL); return 1; }
    VkMemoryAllocateInfo mai = {0}; mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mai.allocationSize = imr.size; mai.memoryTypeIndex = (uint32_t)img_type;
    VkDeviceMemory img_mem = NULL;
    if (vkAllocateMemory(dev, &mai, NULL, &img_mem) != VK_SUCCESS) { printf("  RENDER-TEST FAIL (image memory)\n"); vkDestroyImage(dev,img,NULL); vkDestroyDevice(dev,NULL); return 1; }
    vkBindImageMemory(dev, img, img_mem, 0);

    VkBufferCreateInfo bci = {0}; bci.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bci.size = (VkDeviceSize)W * H * 4; bci.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    VkBuffer buf = NULL;
    if (vkCreateBuffer(dev, &bci, NULL, &buf) != VK_SUCCESS) { printf("  RENDER-TEST FAIL (vkCreateBuffer)\n"); return 1; }
    VkMemoryRequirements bmr; vkGetBufferMemoryRequirements(dev, buf, &bmr);
    int buf_type = -1;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
        if ((bmr.memoryTypeBits & (1u << i)) && ((mp.memoryTypes[i].propertyFlags & (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) == (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT))) { buf_type = (int)i; break; }
    if (buf_type < 0) { printf("  RENDER-TEST FAIL (no host-visible memory)\n"); return 1; }
    VkMemoryAllocateInfo bmai = {0}; bmai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    bmai.allocationSize = bmr.size; bmai.memoryTypeIndex = (uint32_t)buf_type;
    VkDeviceMemory buf_mem = NULL;
    if (vkAllocateMemory(dev, &bmai, NULL, &buf_mem) != VK_SUCCESS) { printf("  RENDER-TEST FAIL (buffer memory)\n"); return 1; }
    vkBindBufferMemory(dev, buf, buf_mem, 0);

    VkCommandPoolCreateInfo cpci = {0}; cpci.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    cpci.queueFamilyIndex = gfx_family;
    VkCommandPool pool = NULL;
    if (vkCreateCommandPool(dev, &cpci, NULL, &pool) != VK_SUCCESS) { printf("  RENDER-TEST FAIL (command pool)\n"); return 1; }
    VkCommandBufferAllocateInfo cbai = {0}; cbai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cbai.commandPool = pool; cbai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cbai.commandBufferCount = 1;
    VkCommandBuffer cb = NULL;
    vkAllocateCommandBuffers(dev, &cbai, &cb);
    VkCommandBufferBeginInfo cbbi = {0}; cbbi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    cbbi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cb, &cbbi);

    VkImageMemoryBarrier b1 = {0}; b1.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    b1.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; b1.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    b1.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; b1.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b1.image = img; b1.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    b1.subresourceRange.levelCount = 1; b1.subresourceRange.layerCount = 1;
    b1.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b1);

    VkClearColorValue color = {0}; color.float32[0] = 0.25f; color.float32[1] = 0.5f; color.float32[2] = 0.75f; color.float32[3] = 1.0f;
    VkImageSubresourceRange sr = {0}; sr.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT; sr.levelCount = 1; sr.layerCount = 1;
    vkCmdClearColorImage(cb, img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &color, 1, &sr);

    VkImageMemoryBarrier b2 = b1;
    b2.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; b2.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    b2.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; b2.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b2);

    VkBufferImageCopy bic = {0};
    bic.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    bic.imageSubresource.layerCount = 1;
    bic.imageExtent.width = W; bic.imageExtent.height = H; bic.imageExtent.depth = 1;
    vkCmdCopyImageToBuffer(cb, img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buf, 1, &bic);

    VkBufferMemoryBarrier bb = {0}; bb.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
    bb.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; bb.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    bb.buffer = buf; bb.offset = 0; bb.size = bci.size;
    bb.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; bb.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
    vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 0, NULL, 1, &bb, 0, NULL);
    vkEndCommandBuffer(cb);

    VkQueue queue = NULL; vkGetDeviceQueue(dev, gfx_family, 0, &queue);
    VkSubmitInfo si = {0}; si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1; si.pCommandBuffers = &cb;
    int ok = 0;
    if (vkQueueSubmit(queue, 1, &si, NULL) == VK_SUCCESS && vkQueueWaitIdle(queue) == VK_SUCCESS) {
        void *mapped = NULL;
        if (vkMapMemory(dev, buf_mem, 0, VK_WHOLE_SIZE, 0, &mapped) == VK_SUCCESS) {
            const unsigned char *px = (const unsigned char *)mapped;
            printf("  RENDER-TEST pixel = (%u,%u,%u,%u)\n", px[0], px[1], px[2], px[3]);
            ok = (px[0] >= 62 && px[0] <= 66 && px[1] >= 126 && px[1] <= 130 &&
                  px[2] >= 189 && px[2] <= 193 && px[3] >= 253);
            vkUnmapMemory(dev, buf_mem);
        }
    }
    printf("  RENDER-TEST %s\n", ok ? "PASS" : "FAIL");
    vkDestroyCommandPool(dev, pool, NULL);
    vkDestroyDevice(dev, NULL);
    return ok ? 0 : 1;
}

int vrmc_probe_main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 2) { fprintf(stderr, "usage: probe <libMoltenVK.dylib>\n"); return 2; }
    void *h = dlopen(argv[1], RTLD_LOCAL | RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 1; }
    GIPA = (PFN_vkGetInstanceProcAddr)dlsym(h, "vkGetInstanceProcAddr");
    if (!GIPA) { fprintf(stderr, "no vkGetInstanceProcAddr\n"); return 1; }
    pCreateInstance = (PFN_vkCreateInstance)GIPA(NULL, "vkCreateInstance");
    pEnumInstExt = (PFN_vkEnumerateInstanceExtensionProperties)GIPA(NULL, "vkEnumerateInstanceExtensionProperties");
    printf("gipa=%p createInstance=%p enumInstExt=%p\n", (void*)GIPA, (void*)pCreateInstance, (void*)pEnumInstExt);

    printf("## instance extensions\n");
    uint32_t n = 0;
    pEnumInstExt(NULL, &n, NULL);
    VkExtensionProperties *ie = calloc(n, sizeof(*ie));
    pEnumInstExt(NULL, &n, ie);
    for (uint32_t i = 0; i < n; i++) printf("  %s (rev %u)\n", ie[i].extensionName, ie[i].specVersion);
    int has_port = 0, has_metal_surface = 0;
    for (uint32_t i = 0; i < n; i++) {
        if (!strcmp(ie[i].extensionName, "VK_KHR_portability_enumeration")) has_port = 1;
        if (!strcmp(ie[i].extensionName, "VK_EXT_metal_surface")) has_metal_surface = 1;
    }
    free(ie);

    const char *ien[3]; uint32_t ienc = 0;
    ien[ienc++] = VK_KHR_SURFACE_EXTENSION_NAME;
    if (has_metal_surface) ien[ienc++] = VK_EXT_METAL_SURFACE_EXTENSION_NAME;
    if (has_port) ien[ienc++] = VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME;

    VkApplicationInfo app = {0};
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.pApplicationName = "VRMC-S2-probe";
    app.apiVersion = VK_API_VERSION_1_2; // matches Minecraft 26.2
    VkInstanceCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ci.pApplicationInfo = &app;
    ci.enabledExtensionCount = ienc;
    ci.ppEnabledExtensionNames = ien;
    if (has_port) ci.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    VkInstance instance = VK_NULL_HANDLE;
    VkResult r = pCreateInstance(&ci, NULL, &instance);
    printf("## vkCreateInstance(VK_API_VERSION_1_2, portability_enumeration=%d) -> %d\n", has_port, r);
    if (r != VK_SUCCESS) return 1;

    LOAD2(pEnumPhys, PFN_vkEnumeratePhysicalDevices, "vkEnumeratePhysicalDevices");
    LOAD2(pGetProps2, PFN_vkGetPhysicalDeviceProperties2, "vkGetPhysicalDeviceProperties2");
    LOAD2(pGetFeat2, PFN_vkGetPhysicalDeviceFeatures2, "vkGetPhysicalDeviceFeatures2");
    LOAD2(pEnumDevExt, PFN_vkEnumerateDeviceExtensionProperties, "vkEnumerateDeviceExtensionProperties");
    LOAD2(pGetQueueFam, PFN_vkGetPhysicalDeviceQueueFamilyProperties, "vkGetPhysicalDeviceQueueFamilyProperties");
    LOAD2(pDestroyInstance, PFN_vkDestroyInstance, "vkDestroyInstance");
    printf("fn ptrs: enumPhys=%p props2=%p feat2=%p enumDevExt=%p\n", (void*)pEnumPhys, (void*)pGetProps2, (void*)pGetFeat2, (void*)pEnumDevExt);

    uint32_t pdn = 0;
    pEnumPhys(instance, &pdn, NULL);
    printf("## physical devices: %u\n", pdn);
    if (pdn == 0) return 1;
    VkPhysicalDevice *pds = calloc(pdn, sizeof(*pds));
    pEnumPhys(instance, &pdn, pds);

    for (uint32_t d = 0; d < pdn; d++) {
        VkPhysicalDeviceProperties2 p2 = {0};
        p2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
        VkPhysicalDeviceDriverProperties drv = {0};
        drv.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES;
        VkPhysicalDevicePushDescriptorPropertiesKHR pushp = {0};
        pushp.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PUSH_DESCRIPTOR_PROPERTIES_KHR;
        drv.pNext = &pushp;
        p2.pNext = &drv;
        pGetProps2(pds[d], &p2);
        VkPhysicalDeviceProperties *p = &p2.properties;
        printf("\n## device[%u] %s | apiVersion %u.%u.%u | driverID %u (%s) | type %u\n", d,
               p->deviceName, VK_VERSION_MAJOR(p->apiVersion), VK_VERSION_MINOR(p->apiVersion),
               VK_VERSION_PATCH(p->apiVersion), drv.driverID, drv.driverName, p->deviceType);

        // Required feature set, chained exactly like VulkanBackend.REQUIRED_DEVICE_FEATURES
        VkPhysicalDeviceFeatures2 f2 = {0};
        f2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
        VkPhysicalDeviceVulkan11Features f11 = {0};
        f11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
        VkPhysicalDeviceVulkan12Features f12 = {0};
        f12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
        VkPhysicalDeviceSynchronization2Features s2 = {0};
        s2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES;
        VkPhysicalDeviceDynamicRenderingFeatures dyn = {0};
        dyn.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES;
        VkPhysicalDeviceVertexAttributeDivisorFeaturesEXT vad = {0};
        vad.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VERTEX_ATTRIBUTE_DIVISOR_FEATURES_EXT;
        VkPhysicalDeviceMultiDrawFeaturesEXT md = {0};
        md.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MULTI_DRAW_FEATURES_EXT;
        f2.pNext = &f11; f11.pNext = &f12; f12.pNext = &s2; s2.pNext = &dyn; dyn.pNext = &vad;
        vad.pNext = &md;
        pGetFeat2(pds[d], &f2);
        printf("  REQ multiDrawIndirect=%u fillModeNonSolid=%u samplerAnisotropy=%u\n",
               f2.features.multiDrawIndirect, f2.features.fillModeNonSolid, f2.features.samplerAnisotropy);
        printf("  REQ shaderDrawParameters=%u timelineSemaphore=%u hostQueryReset=%u\n",
               f11.shaderDrawParameters, f12.timelineSemaphore, f12.hostQueryReset);
        printf("  REQ synchronization2=%u dynamicRendering=%u vertexAttributeInstanceRateDivisor=%u\n",
               s2.synchronization2, dyn.dynamicRendering, vad.vertexAttributeInstanceRateDivisor);
        printf("  OPT multiDraw=%u\n", md.multiDraw);

        uint32_t qn = 0;
        pGetQueueFam(pds[d], &qn, NULL);
        VkQueueFamilyProperties *q = calloc(qn, sizeof(*q));
        pGetQueueFam(pds[d], &qn, q);
        int gfx = 0, gfx_index = 0;
        for (uint32_t i = 0; i < qn; i++) if (q[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) { gfx = 1; gfx_index = (int)i; break; }
        printf("  graphics queue family: %s (families=%u)\n", gfx ? "yes" : "NO", qn);
        free(q);

        uint32_t en = 0;
        pEnumDevExt(pds[d], NULL, &en, NULL);
        VkExtensionProperties *de = calloc(en, sizeof(*de));
        pEnumDevExt(pds[d], NULL, &en, de);
        printf("  DEVICE EXTENSIONS (%u):\n", en);
        for (uint32_t i = 0; i < en; i++) printf("    %s\n", de[i].extensionName);
        printf("  REQUIRED-EXT CHECK:\n");
        for (int i = 0; REQ_EXT[i]; i++) {
            int found = 0;
            for (uint32_t j = 0; j < en; j++) if (!strcmp(de[j].extensionName, REQ_EXT[i])) found = 1;
            printf("    %-34s %s\n", REQ_EXT[i], found ? "OK" : "MISSING");
        }
        for (int i = 0; OPT_EXT[i]; i++) {
            int found = 0;
            for (uint32_t j = 0; j < en; j++) if (!strcmp(de[j].extensionName, OPT_EXT[i])) found = 1;
            printf("    [opt] %-28s %s\n", OPT_EXT[i], found ? "present" : "absent");
        }
        printf("  limits: maxPushDescriptors=%u maxMemoryAllocationCount=%u maxImageDimension2D=%u\n",
               pushp.maxPushDescriptors, p->limits.maxMemoryAllocationCount,
               p->limits.maxImageDimension2D);
        if (gfx) vrmc_render_test(instance, pds[d], (uint32_t)gfx_index);
        free(de);
    }
    pDestroyInstance(instance, NULL);
    printf("\n## done\n");
    return 0;
}
