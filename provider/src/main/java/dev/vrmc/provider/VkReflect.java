package dev.vrmc.provider;

import java.lang.reflect.Method;
import java.nio.LongBuffer;

/**
 * Minimal reflection shim for the few LWJGL Vulkan calls needed by the provider-side GPU eye-frame sync
 * (create an exportable timeline VkSemaphore, export its MTLSharedEvent, destroy it).
 *
 * <p>Why reflection: the provider jar is compiled by {@code scripts/build_provider.sh} against the MC
 * client jar + Vivecraft classes only (no LWJGL jars on the compile classpath), while the running game
 * always has LWJGL on its classpath. Keeping the compile-time dependency at zero lets this file ship in
 * the normal provider jar; at runtime every lookup here is best-effort and any failure raises
 * {@link UnavailableException}, which {@link GpuEyeSync} turns into one warning + the existing
 * unsynchronized eye submission (the game must keep running).
 *
 * <p>Trace reflection with {@code -Dvrmc.gpuSync.debug=true} (also valuable for a device log if the
 * create/export path ever fails).
 *
 * <p>Contract verified by {@code provider/tests/VkReflectSmokeTest} (structs/constants) and, when a macOS
 * MoltenVK build is available, {@code provider/tests/dev/vrmc/provider/GpuSyncVulkanHostTest}
 * (the real vkCreateSemaphore + vkExportMetalObjectsEXT call path).
 */
final class VkReflect {
    /** Verbose reflection tracing for device debugging: -Dvrmc.gpuSync.debug=true. */
    private static final boolean DEBUG = Boolean.getBoolean("vrmc.gpuSync.debug");

    private VkReflect() {}

    private static final String VK10 = "org.lwjgl.vulkan.VK10";
    private static final String VK12 = "org.lwjgl.vulkan.VK12";
    private static final String EXT_METAL = "org.lwjgl.vulkan.EXTMetalObjects";
    private static final String MEMORY_STACK = "org.lwjgl.system.MemoryStack";

    /** Thrown when the reflective Vulkan path is unavailable; callers must degrade gracefully. */
    static final class UnavailableException extends RuntimeException {
        UnavailableException(String message) { super(message); }
        UnavailableException(String message, Throwable cause) { super(message, cause); }
    }

    /** True when the LWJGL Vulkan + struct classes can be loaded (i.e. the game runtime, not the build). */
    static boolean available() {
        return classOrNull(VK10) != null && classOrNull(VK12) != null
            && classOrNull(EXT_METAL) != null && classOrNull(MEMORY_STACK) != null;
    }

    /** VK_PIPELINE_STAGE_ALL_COMMANDS_BIT used as the semaphore signal stage mask on MC's submission. */
    static int allCommandsStageMask() {
        return constantInt(require(VK10), "VK_PIPELINE_STAGE_ALL_COMMANDS_BIT");
    }

    /**
     * Build the exportable timeline semaphore and export its MTLSharedEvent.
     *
     * @param vkDevice the game's {@code org.lwjgl.vulkan.VkDevice} object (held as {@code Object} so this
     *                 class has no compile-time LWJGL dependency)
     * @return {@code { semaphoreHandle, mtlSharedEventHandle }}; both non-zero
     * @throws UnavailableException when any class/constant/method is missing or a Vulkan call fails
     */
    static long[] createExportableTimelineEvent(Object vkDevice) {
        if (vkDevice == null) throw new UnavailableException("VkDevice is null");
        Class<?> vk10 = require(VK10);
        Class<?> vk12 = require(VK12);
        Class<?> extMetal = require(EXT_METAL);
        Class<?> memoryStack = require(MEMORY_STACK);
        Class<?> exportCreateC = require("org.lwjgl.vulkan.VkExportMetalObjectCreateInfoEXT");
        Class<?> semaphoreTypeC = require("org.lwjgl.vulkan.VkSemaphoreTypeCreateInfo");
        Class<?> semaphoreInfoC = require("org.lwjgl.vulkan.VkSemaphoreCreateInfo");
        Class<?> sharedEventInfoC = require("org.lwjgl.vulkan.VkExportMetalSharedEventInfoEXT");
        Class<?> exportObjectsC = require("org.lwjgl.vulkan.VkExportMetalObjectsInfoEXT");

        int sharedEventBit = constantInt(extMetal,
            "VK_EXPORT_METAL_OBJECT_TYPE_METAL_SHARED_EVENT_BIT_EXT");
        int timelineType = constantInt(vk12, "VK_SEMAPHORE_TYPE_TIMELINE");
        int success = constantInt(vk10, "VK_SUCCESS");
        debug("constants: sharedEventBit=" + sharedEventBit + " timelineType=" + timelineType
            + " success=" + success);

        Object stack = invokeStatic(memoryStack, "stackPush");
        long semaphore = 0L;
        try {
            // VkExportMetalObjectCreateInfoEXT { exportObjectType = METAL_SHARED_EVENT }
            Object exportCreate = staticCall(exportCreateC, "calloc", stack);
            call(exportCreate, "sType$Default");
            call(exportCreate, "exportObjectType", sharedEventBit);

            // VkSemaphoreTypeCreateInfo { semaphoreType = TIMELINE, initialValue = 0 } -> pNext exportCreate
            Object semaphoreType = staticCall(semaphoreTypeC, "calloc", stack);
            call(semaphoreType, "sType$Default");
            call(semaphoreType, "semaphoreType", timelineType);
            callLong(semaphoreType, "initialValue", 0L);
            callLong(semaphoreType, "pNext", address(exportCreate));

            // VkSemaphoreCreateInfo { pNext = semaphoreType }
            Object semaphoreInfo = staticCall(semaphoreInfoC, "calloc", stack);
            call(semaphoreInfo, "sType$Default");
            callLong(semaphoreInfo, "pNext", address(semaphoreType));
            debug("create-info built: exportCreate=0x" + Long.toHexString(address(exportCreate))
                + " semType=0x" + Long.toHexString(address(semaphoreType))
                + " semInfo=0x" + Long.toHexString(address(semaphoreInfo)));

            // MUST be a direct buffer: LWJGL passes the native address of output buffers straight to
            // the driver; a heap LongBuffer (LongBuffer.allocate) makes MoltenVK write to a bogus address.
            LongBuffer out = java.nio.ByteBuffer.allocateDirect(Long.BYTES)
                .order(java.nio.ByteOrder.nativeOrder()).asLongBuffer();
            Object rc = invokeStatic(vk10, "vkCreateSemaphore", vkDevice, semaphoreInfo, null, out);
            if (((Number) rc).intValue() != success) {
                throw new UnavailableException("vkCreateSemaphore failed rc=" + rc);
            }
            semaphore = out.get(0);
            if (semaphore == 0L) throw new UnavailableException("vkCreateSemaphore returned a null handle");
            debug("vkCreateSemaphore ok handle=0x" + Long.toHexString(semaphore));

            // VkExportMetalSharedEventInfoEXT { semaphore } -> vkExportMetalObjectsEXT
            Object sharedEventInfo = staticCall(sharedEventInfoC, "calloc", stack);
            call(sharedEventInfo, "sType$Default");
            callLong(sharedEventInfo, "semaphore", semaphore);
            Object exportObjects = staticCall(exportObjectsC, "calloc", stack);
            call(exportObjects, "sType$Default");
            callLong(exportObjects, "pNext", address(sharedEventInfo));
            invokeStatic(extMetal, "vkExportMetalObjectsEXT", vkDevice, exportObjects);
            long sharedEvent = ((Number) call(sharedEventInfo, "mtlSharedEvent")).longValue();
            debug("vkExportMetalObjectsEXT mtlSharedEvent=0x" + Long.toHexString(sharedEvent));
            if (sharedEvent == 0L) {
                throw new UnavailableException("vkExportMetalObjectsEXT returned no MTLSharedEvent"
                    + " (VK_EXT_metal_objects must be enabled at vkCreateDevice time; restart required)");
            }
            return new long[] { semaphore, sharedEvent };
        } catch (RuntimeException e) {
            if (semaphore != 0L) {
                try { destroySemaphore(vkDevice, semaphore); } catch (Throwable ignored) { /* best effort */ }
            }
            throw e;
        } finally {
            closeQuietly(stack);
        }
    }

    /** vkDestroySemaphore; safe to call with a handle previously returned by this class. */
    static void destroySemaphore(Object vkDevice, long semaphore) {
        if (vkDevice == null || semaphore == 0L) return;
        Class<?> vk10 = require(VK10);
        Object stack = invokeStatic(require(MEMORY_STACK), "stackPush");
        try {
            invokeStatic(vk10, "vkDestroySemaphore", vkDevice, semaphore, null);
        } finally {
            closeQuietly(stack);
        }
    }

    /**
     * Reflection plumbing self-test that does not need a Vulkan device: resolves the classes/constants,
     * allocates the create-info structs, chains pNext and checks the addresses. Used by
     * {@code provider/tests/VkReflectSmokeTest}. Returns a short summary string.
     */
    static String smokeTest() {
        Class<?> vk10 = require(VK10);
        Class<?> vk12 = require(VK12);
        Class<?> extMetal = require(EXT_METAL);
        Class<?> memoryStack = require(MEMORY_STACK);
        int sharedEventBit = constantInt(extMetal,
            "VK_EXPORT_METAL_OBJECT_TYPE_METAL_SHARED_EVENT_BIT_EXT");
        int timelineType = constantInt(vk12, "VK_SEMAPHORE_TYPE_TIMELINE");
        int success = constantInt(vk10, "VK_SUCCESS");
        int allCommands = constantInt(vk10, "VK_PIPELINE_STAGE_ALL_COMMANDS_BIT");
        Object stack = invokeStatic(memoryStack, "stackPush");
        try {
            Object exportCreate = staticCall(require("org.lwjgl.vulkan.VkExportMetalObjectCreateInfoEXT"),
                "calloc", stack);
            call(exportCreate, "sType$Default");
            call(exportCreate, "exportObjectType", sharedEventBit);
            Object semaphoreType = staticCall(require("org.lwjgl.vulkan.VkSemaphoreTypeCreateInfo"),
                "calloc", stack);
            call(semaphoreType, "sType$Default");
            call(semaphoreType, "semaphoreType", timelineType);
            callLong(semaphoreType, "initialValue", 0L);
            callLong(semaphoreType, "pNext", address(exportCreate));
            Object semaphoreInfo = staticCall(require("org.lwjgl.vulkan.VkSemaphoreCreateInfo"),
                "calloc", stack);
            call(semaphoreInfo, "sType$Default");
            callLong(semaphoreInfo, "pNext", address(semaphoreType));
            if (address(semaphoreInfo) == 0L || address(semaphoreType) == 0L
                || address(exportCreate) == 0L) {
                throw new UnavailableException("struct allocation returned a null address");
            }
            return "vk classes+structs ok: exportCreate=0x" + Long.toHexString(address(exportCreate))
                + " semType=0x" + Long.toHexString(address(semaphoreType))
                + " semInfo=0x" + Long.toHexString(address(semaphoreInfo))
                + " sharedEventBit=" + sharedEventBit + " timeline=" + timelineType
                + " success=" + success + " allCommands=0x" + Integer.toHexString(allCommands);
        } finally {
            closeQuietly(stack);
        }
    }

    // ----------------------------------------------------------------------------------------
    // Reflection helpers (deliberately name/count based so opaque LWJGL types stay unimported)
    // ----------------------------------------------------------------------------------------

    private static Class<?> classOrNull(String name) {
        try {
            return Class.forName(name);
        } catch (Throwable t) {
            return null;
        }
    }

    private static Class<?> require(String name) {
        Class<?> type = classOrNull(name);
        if (type == null) throw new UnavailableException("class not found: " + name);
        return type;
    }

    private static int constantInt(Class<?> owner, String name) {
        try {
            return owner.getField(name).getInt(null);
        } catch (ReflectiveOperationException e) {
            throw new UnavailableException("constant not found: " + owner.getSimpleName() + "." + name, e);
        }
    }

    private static Method find(Class<?> owner, String name, int parameterCount, Object[] args) {
        for (Method method : owner.getMethods()) {
            if (!method.getName().equals(name) || method.getParameterCount() != parameterCount) continue;
            Class<?>[] types = method.getParameterTypes();
            boolean matches = true;
            for (int i = 0; i < parameterCount && matches; i++) {
                Object arg = args[i];
                if (arg == null) continue; // null matches any reference parameter
                matches = boxed(types[i]).isInstance(arg);
            }
            if (matches) return method;
        }
        throw new UnavailableException("method not found: " + owner.getSimpleName() + "." + name
            + "/" + parameterCount);
    }

    private static Class<?> boxed(Class<?> type) {
        if (!type.isPrimitive()) return type;
        if (type == int.class) return Integer.class;
        if (type == long.class) return Long.class;
        if (type == float.class) return Float.class;
        if (type == double.class) return Double.class;
        if (type == boolean.class) return Boolean.class;
        throw new UnavailableException("unsupported primitive parameter: " + type);
    }

    private static Object invokeStatic(Class<?> owner, String name, Object... args) {
        try {
            Method method = find(owner, name, args.length, args);
            method.setAccessible(true);
            if (DEBUG) {
                StringBuilder summary = new StringBuilder("[VRMC-M2][gpu-sync][debug] invoke ")
                    .append(owner.getSimpleName()).append('.').append(name).append('(');
                Class<?>[] parameterTypes = method.getParameterTypes();
                for (int i = 0; i < parameterTypes.length; i++) {
                    if (i > 0) summary.append(", ");
                    summary.append(parameterTypes[i].getSimpleName());
                }
                System.out.println(summary.append(')'));
            }
            return method.invoke(null, args);
        } catch (ReflectiveOperationException e) {
            throw new UnavailableException("static call failed: " + owner.getSimpleName() + "." + name,
                e.getCause() == null ? e : e.getCause());
        }
    }

    private static Object call(Object target, String name, Object... args) {
        if (target == null) throw new UnavailableException(name + " called on null");
        try {
            Method method = find(target.getClass(), name, args.length, args);
            method.setAccessible(true);
            if (DEBUG) {
                System.out.println("[VRMC-M2][gpu-sync][debug] call " + target.getClass().getSimpleName()
                    + "." + name + " args=" + java.util.Arrays.toString(args));
            }
            return method.invoke(target, args);
        } catch (ReflectiveOperationException e) {
            throw new UnavailableException("call failed: " + target.getClass().getSimpleName()
                + "." + name, e.getCause() == null ? e : e.getCause());
        }
    }

    private static Object staticCall(Class<?> owner, String name, Object... args) {
        return invokeStatic(owner, name, args);
    }

    private static long callLong(Object target, String name, long value) {
        Object result = call(target, name, value);
        return result instanceof Number number ? number.longValue() : 0L;
    }

    private static long address(Object struct) {
        Object result = call(struct, "address");
        return ((Number) result).longValue();
    }

    private static void closeQuietly(Object stack) {
        if (stack instanceof AutoCloseable closeable) {
            try {
                closeable.close();
            } catch (Exception ignored) {
                // stack teardown is best effort
            }
        }
    }

    private static void debug(String message) {
        if (DEBUG) System.out.println("[VRMC-M2][gpu-sync][debug] " + message);
    }
}
