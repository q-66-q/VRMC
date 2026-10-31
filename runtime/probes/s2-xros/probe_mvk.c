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
        int gfx = 0;
        for (uint32_t i = 0; i < qn; i++) if (q[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) gfx = 1;
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
        free(de);
    }
    pDestroyInstance(instance, NULL);
    printf("\n## done\n");
    return 0;
}
