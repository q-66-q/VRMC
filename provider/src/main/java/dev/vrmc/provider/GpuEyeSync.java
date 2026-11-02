package dev.vrmc.provider;

import com.mojang.blaze3d.systems.DeviceInfo;
import com.mojang.blaze3d.systems.GpuDevice;
import com.mojang.blaze3d.systems.RenderSystem;
import org.vivecraft.client_vr.ClientDataHolderVR;

import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * Provider-side half of the zero-copy eye-frame GPU synchronization (M3-W5, flag-gated).
 *
 * <p>Creates ONE exportable timeline VkSemaphore on the game's MoltenVK device, exports its
 * {@code MTLSharedEvent} through {@code VK_EXT_metal_objects}, and appends a monotonically increasing
 * signal to MC 26.2's own frame submission ({@code VulkanCommandEncoder.signalSemaphore}, i.e. no
 * competing queue submission). {@link VisionRenderer} publishes the event/value through
 * {@code VrmcBridge.submitEyesSynced}, so the CompositorServices renderer can wait on the exact GPU
 * frame before sampling the eye textures (native-shared API:
 * {@code vrmc_shared_publish_eyes}/{@code vrmc_shared_acquire_eyes}, see docs/analysis/bridge-sync.md).
 *
 * <p><b>Safety contract:</b> this class is off unless {@link GpuSyncFlags} says otherwise, every step
 * is best-effort, and ANY failure (extension not enabled, missing LWJGL classes, reflection failure,
 * semaphore/export failure, encoder signal failure) logs exactly one clear warning and returns the
 * provider to the existing unsynchronized {@code submitEyes} path. The game must keep running.
 *
 * <p>Activation is deliberately per-launch and reversible: delete {@code vrmc-gpu-sync.flag} and
 * restart. The synthetic ABI/JNI surface ({@code VrmcBridge.submitEyesSynced}) is additive; the Java
 * ABI version is unchanged.
 *
 * <p>Threading: only called from the JVM render thread (renderer constructor / endFrame / destroy).
 */
final class GpuEyeSync {
    private static final String EXTENSION = "VK_EXT_metal_objects";
    private static final String LOG_PREFIX = "[VRMC-M2][gpu-sync] ";

    private final Object vkDevice;          // org.lwjgl.vulkan.VkDevice, held as Object (no LWJGL imports)
    private final Object commandEncoder;    // com.mojang.blaze3d.vulkan.VulkanCommandEncoder
    private final Method signalSemaphore;   // VulkanCommandEncoder.signalSemaphore(long, long, long)
    private final long vkSemaphore;
    private final long sharedEvent;
    private final int stageMask;
    private long nextValue;
    private boolean closed;
    private boolean disabled;
    private boolean loggedFirstSignal;

    private GpuEyeSync(Object vkDevice, Object commandEncoder, Method signalSemaphore, long vkSemaphore,
                       long sharedEvent, int stageMask) {
        this.vkDevice = vkDevice;
        this.commandEncoder = commandEncoder;
        this.signalSemaphore = signalSemaphore;
        this.vkSemaphore = vkSemaphore;
        this.sharedEvent = sharedEvent;
        this.stageMask = stageMask;
    }

    /**
     * Resolve the flag and try to enable the sync path. Returns {@code null} when disabled (flag not
     * requested, or any step unavailable); logs at most one warning line in that case when it was
     * requested but could not be fully enabled. Never throws.
     */
    static GpuEyeSync tryEnable(File gameDirectory) {
        try {
            if (!GpuSyncFlags.isRequested(gameDirectory)) {
                return null; // off by default; stay silent
            }
            GpuDevice device = RenderSystem.getDevice();
            if (device == null) {
                warn("no GpuDevice available; falling back to unsynchronized eye submission");
                return null;
            }
            DeviceInfo info = device.getDeviceInfo();
            String backendName = info != null ? info.backendName() : null;
            if (backendName == null || !backendName.toLowerCase(java.util.Locale.ROOT).contains("vulkan")) {
                warn("backend is not Vulkan (backend=" + backendName
                    + "); falling back to unsynchronized eye submission");
                return null;
            }
            if (!extensionEnabled(info)) {
                boolean requested = requestExtensionForNextLaunch();
                warn(EXTENSION + " is not enabled on the current Vulkan device; "
                    + (requested
                        ? "requested it in VRSettings for the next launch (ONE GAME RESTART required, the setting is saved now)."
                        : "could not record the request in VRSettings.")
                    + " Falling back to unsynchronized eye submission for this launch.");
                return null;
            }
            if (!VkReflect.available()) {
                warn("LWJGL Vulkan classes not reachable by reflection; falling back to unsynchronized "
                    + "eye submission");
                return null;
            }

            Object backend = backendOf(device);
            if (backend == null) {
                warn("GpuDevice.backend is not reachable by reflection; falling back to unsynchronized "
                    + "eye submission");
                return null;
            }
            Class<?> vulkanDeviceClass = Class.forName("com.mojang.blaze3d.vulkan.VulkanDevice");
            if (!vulkanDeviceClass.isInstance(backend)) {
                warn("Vulkan device class mismatch (" + backend.getClass().getName()
                    + "); falling back to unsynchronized eye submission");
                return null;
            }
            Object vkDevice = vulkanDeviceClass.getMethod("vkDevice").invoke(backend);
            long[] handles = VkReflect.createExportableTimelineEvent(vkDevice);
            long vkSemaphore = handles[0];
            long sharedEvent = handles[1];

            Object commandEncoder = vulkanDeviceClass.getMethod("createCommandEncoder").invoke(backend);
            Method signal = commandEncoder.getClass()
                .getMethod("signalSemaphore", long.class, long.class, long.class);
            signal.setAccessible(true);

            GpuEyeSync sync = new GpuEyeSync(vkDevice, commandEncoder, signal, vkSemaphore, sharedEvent,
                VkReflect.allCommandsStageMask());
            System.out.printf(LOG_PREFIX + "ENABLED: timeline VkSemaphore=0x%x -> MTLSharedEvent=0x%x; "
                + "each %s ends with signalSemaphore(value) on MC's own frame submission and "
                + "submitEyesSynced(event,value); first wait value=1%n",
                vkSemaphore, sharedEvent, "endFrame()");
            return sync;
        } catch (Throwable t) {
            warn("enable failed: " + t.getClass().getSimpleName()
                + (t.getMessage() != null ? " (" + t.getMessage() + ")" : "")
                + "; falling back to unsynchronized eye submission");
            return null;
        }
    }

    /** True while the sync path is usable. */
    boolean enabled() {
        return !this.closed && !this.disabled;
    }

    /** Opaque id<MTLSharedEvent> handle the compositor must wait on; 0 when unavailable. */
    long sharedEvent() {
        return enabled() ? this.sharedEvent : 0L;
    }

    /** Next monotonic timeline value (starts at 1; the semaphore/event start at 0). */
    long nextSignalValue() {
        return ++this.nextValue;
    }

    /**
     * Append "signal timeline semaphore = value" to MC's current frame submission. Must be called on the
     * render thread, after the eye render passes were recorded and before {@code submitEyesSynced}.
     * Returns false (and permanently disables the path for this renderer) if MC's encoder rejects it.
     */
    boolean signalOnGameFrameSubmit(long value) {
        if (!enabled()) return false;
        try {
            this.signalSemaphore.invoke(this.commandEncoder, this.vkSemaphore, value, this.stageMask);
            if (!this.loggedFirstSignal) {
                this.loggedFirstSignal = true;
                System.out.printf(LOG_PREFIX + "first frame signaled through MC's submission: value=%d%n",
                    value);
            }
            return true;
        } catch (Throwable t) {
            disable("VulkanCommandEncoder.signalSemaphore failed: " + t.getClass().getSimpleName()
                + (t.getMessage() != null ? " (" + t.getMessage() + ")" : ""));
            return false;
        }
    }

    /** Destroy the exportable semaphore; called from {@link VisionRenderer#destroy()}. */
    void close() {
        if (this.closed) return;
        this.closed = true;
        try {
            VkReflect.destroySemaphore(this.vkDevice, this.vkSemaphore);
            System.out.println(LOG_PREFIX + "closed (timeline VkSemaphore destroyed)");
        } catch (Throwable t) {
            warn("close failed: " + t);
        }
    }

    private void disable(String reason) {
        if (this.disabled) return;
        this.disabled = true;
        warn("disabling GPU sync for the rest of this renderer: " + reason
            + "; reverting to unsynchronized eye submission");
    }

    private static boolean extensionEnabled(DeviceInfo info) {
        try {
            java.util.Set<String> extensions = info.underlyingExtensions();
            if (extensions == null) return false;
            return extensions.contains(EXTENSION + " (D)") || extensions.contains(EXTENSION);
        } catch (RuntimeException e) {
            return false;
        }
    }

    /**
     * Ask Vivecraft to enable the extension at the next vkCreateDevice (same mechanism
     * OpenVRStereoRenderer uses: VulkanBackendVRMixin adds vrSettings.requiredVulkanDeviceExtensions to
     * the device extension set). Persists the setting immediately so a restart picks it up.
     */
    private static boolean requestExtensionForNextLaunch() {
        try {
            ClientDataHolderVR holder = ClientDataHolderVR.getInstance();
            if (holder == null || holder.vrSettings == null) return false;
            String current = holder.vrSettings.requiredVulkanDeviceExtensions;
            if (current == null) current = "";
            if (!hasToken(current, EXTENSION)) {
                holder.vrSettings.requiredVulkanDeviceExtensions =
                    current.isEmpty() ? EXTENSION : current + " " + EXTENSION;
                holder.vrSettings.saveOptions();
            }
            return hasToken(holder.vrSettings.requiredVulkanDeviceExtensions, EXTENSION);
        } catch (Throwable t) {
            return false;
        }
    }

    private static boolean hasToken(String list, String token) {
        if (list == null || list.isEmpty()) return false;
        for (String part : list.trim().split("\\s+")) {
            if (part.equals(token)) return true;
        }
        return false;
    }

    /** Read the private GpuDevice.backend field (Vivecraft uses an access widener for this). */
    private static Object backendOf(GpuDevice device) {
        try {
            Field field = GpuDevice.class.getDeclaredField("backend");
            field.setAccessible(true);
            return field.get(device);
        } catch (Throwable t) {
            return null;
        }
    }

    private static void warn(String message) {
        System.out.println(LOG_PREFIX + "WARNING: " + message);
    }
}
