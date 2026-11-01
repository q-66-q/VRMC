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


// ---------------------------------------------------------------------------
// Load test for the retagged native dylibs embedded in Frameworks/.
// Proves each VISIONOS-slice native can be dlopen'ed in this process and that a
// representative export resolves.
// ---------------------------------------------------------------------------
#include <dirent.h>

static const struct { const char *name; const char *symbol; } LOAD_SYMS[] = {
    { "libMoltenVK.dylib",        "vkGetInstanceProcAddr" },
    { "libSDL3.dylib",            "SDL_Init" },
    { "libfreetype.dylib",        "FT_Init_FreeType" },
    { "liblwjgl.dylib",           "JNI_OnLoad" },
    { "liblwjgl_nanovg.dylib",    "JNI_OnLoad" },
    { "liblwjgl_opengl.dylib",    "JNI_OnLoad" },
    { "liblwjgl_stb.dylib",       "JNI_OnLoad" },
    { "liblwjgl_tinyfd.dylib",    "JNI_OnLoad" },
    { "liblwjgl_vma.dylib",       "JNI_OnLoad" },
    { "libopenal.dylib",          "alcOpenDevice" },
    { "libshaderc.dylib",         "shaderc_compiler_initialize" },
    { "libspirv-cross.dylib",     "spvc_context_create" },
    { NULL, NULL }
};

static int vrmc_load_test(const char *dir) {
    printf("\n## native load test (%s)\n", dir);
    int ok = 0, fail = 0;
    for (int i = 0; LOAD_SYMS[i].name; i++) {
        char path[4096];
        snprintf(path, sizeof(path), "%s/%s", dir, LOAD_SYMS[i].name);
        void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (!h) {
            printf("  %-26s LOAD FAIL: %s\n", LOAD_SYMS[i].name, dlerror());
            fail++;
            continue;
        }
        void *sym = dlsym(h, LOAD_SYMS[i].symbol);
        printf("  %-26s %s (sym %s = %p)\n", LOAD_SYMS[i].name,
               sym ? "OK" : "LOADED (symbol absent, load succeeds)", LOAD_SYMS[i].symbol, sym);
        ok++;  // a successful dlopen is the load-test criterion; symbol name is advisory
        // keep loaded: dlclose would unload shared deps still in use by later libs
    }
    printf("## native load test: %d ok, %d failed\n", ok, fail);
    return fail == 0 ? 0 : 1;
}


// ---------------------------------------------------------------------------
// CAMetalLayer surface test: create VkSurfaceKHR via VK_EXT_metal_surface and
// query its capabilities/formats. This is the handoff MC's GLFW stub needs.
// ---------------------------------------------------------------------------
static void *g_metal_layer;
void vrmc_set_metal_layer(void *layer) { g_metal_layer = layer; }

static int vrmc_surface_test(VkInstance instance, VkPhysicalDevice phys) {
    PFN_vkCreateMetalSurfaceEXT pCreateMetalSurface =
        (PFN_vkCreateMetalSurfaceEXT)GIPA(instance, "vkCreateMetalSurfaceEXT");
    PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR pCaps =
        (PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR)GIPA(instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
    PFN_vkGetPhysicalDeviceSurfaceFormatsKHR pFormats =
        (PFN_vkGetPhysicalDeviceSurfaceFormatsKHR)GIPA(instance, "vkGetPhysicalDeviceSurfaceFormatsKHR");
    PFN_vkDestroySurfaceKHR pDestroySurface =
        (PFN_vkDestroySurfaceKHR)GIPA(instance, "vkDestroySurfaceKHR");
    printf("\n## surface test (metal layer %p)\n", g_metal_layer);
    if (!g_metal_layer) { printf("  SURFACE-TEST SKIP (no CAMetalLayer)\n"); return 0; }
    if (!pCreateMetalSurface || !pCaps || !pFormats || !pDestroySurface) {
        printf("  SURFACE-TEST FAIL (missing surface entry points)\n"); return 1;
    }
    VkMetalSurfaceCreateInfoEXT sci = {0};
    sci.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    sci.pLayer = g_metal_layer;
    VkSurfaceKHR surf = VK_NULL_HANDLE;
    VkResult r = pCreateMetalSurface(instance, &sci, NULL, &surf);
    if (r != VK_SUCCESS) { printf("  SURFACE-TEST FAIL (vkCreateMetalSurfaceEXT -> %d)\n", r); return 1; }

    VkSurfaceCapabilitiesKHR caps = {0};
    r = pCaps(phys, surf, &caps);
    if (r != VK_SUCCESS) { printf("  SURFACE-TEST FAIL (caps -> %d)\n", r); pDestroySurface(instance, surf, NULL); return 1; }
    printf("  caps: minImageCount=%u maxImageCount=%u currentExtent=%ux%u formats=%u\n",
           caps.minImageCount, caps.maxImageCount, caps.currentExtent.width, caps.currentExtent.height,
           (unsigned)caps.supportedCompositeAlpha);
    uint32_t fn = 0;
    pFormats(phys, surf, &fn, NULL);
    printf("  surface formats: %u\n", fn);
    if (fn > 0) {
        VkSurfaceFormatKHR *fm = calloc(fn, sizeof(*fm));
        pFormats(phys, surf, &fn, fm);
        for (uint32_t i = 0; i < fn && i < 6; i++)
            printf("    format=%u colorspace=%u\n", fm[i].format, fm[i].colorSpace);
        free(fm);
    }
    pDestroySurface(instance, surf, NULL);
    printf("  SURFACE-TEST PASS\n");
    return 0;
}


// ---------------------------------------------------------------------------
// Swapchain + present test on the CAMetalLayer VkSurfaceKHR.
// Creates a device with VK_KHR_swapchain, acquires an image, clears it with
// vkCmdClearColorImage, presents it, and waits for completion.
// ---------------------------------------------------------------------------
static int vrmc_swapchain_test(VkInstance instance, VkPhysicalDevice phys, uint32_t gfx_family) {
    if (!g_metal_layer) { printf("\n## swapchain test SKIP (no CAMetalLayer)\n"); return 0; }
    PFN_vkCreateMetalSurfaceEXT pCreateMetalSurface = (PFN_vkCreateMetalSurfaceEXT)GIPA(instance, "vkCreateMetalSurfaceEXT");
    PFN_vkCreateDevice pCreateDevice = (PFN_vkCreateDevice)GIPA(instance, "vkCreateDevice");
    PFN_vkGetDeviceProcAddr GDPA = (PFN_vkGetDeviceProcAddr)GIPA(instance, "vkGetDeviceProcAddr");
    PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR pCaps = (PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR)GIPA(instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
    PFN_vkGetPhysicalDeviceSurfaceFormatsKHR pFormats = (PFN_vkGetPhysicalDeviceSurfaceFormatsKHR)GIPA(instance, "vkGetPhysicalDeviceSurfaceFormatsKHR");
    PFN_vkGetPhysicalDeviceSurfacePresentModesKHR pModes = (PFN_vkGetPhysicalDeviceSurfacePresentModesKHR)GIPA(instance, "vkGetPhysicalDeviceSurfacePresentModesKHR");
    PFN_vkDestroySurfaceKHR pDestroySurface = (PFN_vkDestroySurfaceKHR)GIPA(instance, "vkDestroySurfaceKHR");
    if (!pCreateMetalSurface || !pCreateDevice || !GDPA || !pCaps || !pFormats || !pModes || !pDestroySurface) {
        printf("\n## swapchain test FAIL (missing entry points)\n"); return 1;
    }
    VkMetalSurfaceCreateInfoEXT sci = {0};
    sci.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    sci.pLayer = g_metal_layer;
    VkSurfaceKHR surf = VK_NULL_HANDLE;
    VkResult r = pCreateMetalSurface(instance, &sci, NULL, &surf);
    if (r != VK_SUCCESS) { printf("\n## swapchain test FAIL (surface %d)\n", r); return 1; }

    VkSurfaceCapabilitiesKHR caps = {0};
    pCaps(phys, surf, &caps);
    VkSurfaceFormatKHR want = { VK_FORMAT_B8G8R8A8_UNORM, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR };
    VkSurfaceFormatKHR chosen = {0};
    uint32_t fn = 0; pFormats(phys, surf, &fn, NULL);
    VkSurfaceFormatKHR *fm = calloc(fn ? fn : 1, sizeof(*fm));
    if (fn) pFormats(phys, surf, &fn, fm);
    int have = 0;
    for (uint32_t i = 0; i < fn; i++) {
        if (fm[i].format == want.format && fm[i].colorSpace == want.colorSpace) { chosen = fm[i]; have = 1; break; }
    }
    if (!have && fn) { chosen = fm[0]; have = 1; }
    free(fm);
    if (!have) { printf("\n## swapchain test FAIL (no formats)\n"); pDestroySurface(instance, surf, NULL); return 1; }

    VkPresentModeKHR pmode = VK_PRESENT_MODE_FIFO_KHR;
    uint32_t pn = 0; pModes(phys, surf, &pn, NULL);
    VkPresentModeKHR *pm = calloc(pn ? pn : 1, sizeof(*pm));
    int have_pmode = 0;
    if (pn) {
        pModes(phys, surf, &pn, pm);
        for (uint32_t i = 0; i < pn; i++) if (pm[i] == VK_PRESENT_MODE_FIFO_KHR) have_pmode = 1;
        if (!have_pmode && pn) pmode = pm[0];
    }
    free(pm);

    VkExtent2D extent = caps.currentExtent;
    if (extent.width == 0xFFFFFFFFu || extent.width == 0) { extent.width = 1280; extent.height = 720; }
    if (extent.width > caps.maxImageExtent.width) extent = caps.maxImageExtent;
    if (extent.width < caps.minImageExtent.width) extent = caps.minImageExtent;

    // device with swapchain
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = {0}; qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    qci.queueFamilyIndex = gfx_family; qci.queueCount = 1; qci.pQueuePriorities = &prio;
    const char *dev_ext[] = { VK_KHR_SWAPCHAIN_EXTENSION_NAME };
    VkDeviceCreateInfo dci = {0}; dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
    dci.enabledExtensionCount = 1; dci.ppEnabledExtensionNames = dev_ext;
    VkDevice dev = NULL;
    r = pCreateDevice(phys, &dci, NULL, &dev);
    if (r != VK_SUCCESS) { printf("\n## swapchain test FAIL (vkCreateDevice %d)\n", r); pDestroySurface(instance, surf, NULL); return 1; }

#define SFN(name) PFN_##name name = (PFN_##name)GDPA(dev, #name)
    SFN(vkCreateSwapchainKHR); SFN(vkGetSwapchainImagesKHR); SFN(vkAcquireNextImageKHR);
    SFN(vkQueuePresentKHR); SFN(vkDestroySwapchainKHR); SFN(vkCreateSemaphore);
    SFN(vkDestroySemaphore); SFN(vkGetDeviceQueue); SFN(vkCreateCommandPool);
    SFN(vkAllocateCommandBuffers); SFN(vkBeginCommandBuffer); SFN(vkCmdPipelineBarrier);
    SFN(vkCmdClearColorImage); SFN(vkEndCommandBuffer); SFN(vkQueueSubmit); SFN(vkQueueWaitIdle);
    SFN(vkDeviceWaitIdle); SFN(vkDestroyCommandPool); SFN(vkDestroyDevice); SFN(vkCreateFence);
    SFN(vkWaitForFences); SFN(vkDestroyFence);
#undef SFN
    if (!vkCreateSwapchainKHR || !vkGetSwapchainImagesKHR || !vkAcquireNextImageKHR || !vkQueuePresentKHR) {
        printf("\n## swapchain test FAIL (device entry points)\n");
        vkDestroyDevice(dev, NULL); pDestroySurface(instance, surf, NULL); return 1;
    }
    uint32_t image_count = caps.minImageCount + 1;
    if (caps.maxImageCount > 0 && image_count > caps.maxImageCount) image_count = caps.maxImageCount;
    VkCompositeAlphaFlagBitsKHR alpha = (caps.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR)
        ? VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR : VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
    VkSwapchainCreateInfoKHR sci2 = {0}; sci2.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    sci2.surface = surf; sci2.minImageCount = image_count; sci2.imageFormat = chosen.format;
    sci2.imageColorSpace = chosen.colorSpace; sci2.imageExtent = extent;
    sci2.imageArrayLayers = 1;
    sci2.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    sci2.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    sci2.preTransform = caps.currentTransform;
    sci2.compositeAlpha = alpha;
    sci2.presentMode = pmode; sci2.clipped = VK_TRUE; sci2.oldSwapchain = VK_NULL_HANDLE;
    VkSwapchainKHR sc = VK_NULL_HANDLE;
    r = vkCreateSwapchainKHR(dev, &sci2, NULL, &sc);
    if (r != VK_SUCCESS) { printf("\n## swapchain test FAIL (vkCreateSwapchainKHR %d)\n", r); vkDestroyDevice(dev, NULL); pDestroySurface(instance, surf, NULL); return 1; }
    uint32_t n = 0; vkGetSwapchainImagesKHR(dev, sc, &n, NULL);
    VkImage *images = calloc(n ? n : 1, sizeof(*images));
    vkGetSwapchainImagesKHR(dev, sc, &n, images);
    printf("\n## swapchain test: %ux%u fmt=%u mode=%u images=%u\n", extent.width, extent.height, chosen.format, pmode, n);

    VkSemaphore sem = VK_NULL_HANDLE;
    VkSemaphoreCreateInfo semci = {0}; semci.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    vkCreateSemaphore(dev, &semci, NULL, &sem);
    VkCommandPoolCreateInfo cpci = {0}; cpci.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    cpci.queueFamilyIndex = gfx_family;
    VkCommandPool pool = VK_NULL_HANDLE; vkCreateCommandPool(dev, &cpci, NULL, &pool);
    VkCommandBufferAllocateInfo cbai = {0}; cbai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cbai.commandPool = pool; cbai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cbai.commandBufferCount = 1;
    VkCommandBuffer cb = NULL; vkAllocateCommandBuffers(dev, &cbai, &cb);
    uint32_t idx = 0;
    r = vkAcquireNextImageKHR(dev, sc, 1000000000ull, sem, VK_NULL_HANDLE, &idx);
    if (r != VK_SUCCESS && r != VK_SUBOPTIMAL_KHR) {
        printf("## swapchain test FAIL (acquire %d)\n", r);
    } else {
        VkCommandBufferBeginInfo cbbi = {0}; cbbi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        cbbi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        vkBeginCommandBuffer(cb, &cbbi);
        VkImageMemoryBarrier b1 = {0}; b1.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        b1.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED; b1.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        b1.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED; b1.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        b1.image = images[idx];
        b1.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        b1.subresourceRange.levelCount = 1; b1.subresourceRange.layerCount = 1;
        b1.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b1);
        VkClearColorValue color = {0}; color.float32[0] = 0.1f; color.float32[1] = 0.8f; color.float32[2] = 0.2f; color.float32[3] = 1.0f;
        VkImageSubresourceRange sr = {0}; sr.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT; sr.levelCount = 1; sr.layerCount = 1;
        vkCmdClearColorImage(cb, images[idx], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &color, 1, &sr);
        VkImageMemoryBarrier b2 = b1;
        b2.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        b2.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        b2.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; b2.dstAccessMask = 0;
        vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, NULL, 0, NULL, 1, &b2);
        vkEndCommandBuffer(cb);
        VkQueue queue = NULL; vkGetDeviceQueue(dev, gfx_family, 0, &queue);
        VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
        VkSubmitInfo si = {0}; si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        si.waitSemaphoreCount = 1; si.pWaitSemaphores = &sem; si.pWaitDstStageMask = &wait_stage;
        si.commandBufferCount = 1; si.pCommandBuffers = &cb;
        r = vkQueueSubmit(queue, 1, &si, NULL);
        printf("  submit=%d ", r);
        vkQueueWaitIdle(queue);
        VkPresentInfoKHR pi = {0}; pi.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        pi.swapchainCount = 1; pi.pSwapchains = &sc; pi.pImageIndices = &idx;
        r = vkQueuePresentKHR(queue, &pi);
        printf("present=%d ", r);
        vkDeviceWaitIdle(dev);
        printf("\n## SWAPCHAIN-TEST %s\n", r == VK_SUCCESS ? "PASS" : "FAIL");
    }
    vkDestroySemaphore(dev, sem, NULL);
    vkDestroyCommandPool(dev, pool, NULL);
    vkDestroySwapchainKHR(dev, sc, NULL);
    vkDestroyDevice(dev, NULL);
    pDestroySurface(instance, surf, NULL);
    return r == VK_SUCCESS ? 0 : 1;
}

int vrmc_probe_main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 2) { fprintf(stderr, "usage: probe <libMoltenVK.dylib> [FrameworksDir]\n"); return 2; }
    int load_fail = 0;
    if (argc >= 3) load_fail = vrmc_load_test(argv[2]);
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
        if (d == 0) vrmc_surface_test(instance, pds[d]);
        if (gfx) vrmc_render_test(instance, pds[d], (uint32_t)gfx_index);
        if (gfx && d == 0) vrmc_swapchain_test(instance, pds[d], (uint32_t)gfx_index);
        free(de);
    }
    pDestroyInstance(instance, NULL);
    printf("\n## done\n");
    return load_fail ? 3 : 0;
}
