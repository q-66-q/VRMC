package dev.vrmc.provider;

/**
 * Host self-test for {@link VkReflect} (provider/tests/run_tests.sh), run twice:
 * <ul>
 *   <li>with LWJGL on the classpath: {@link VkReflect#available()} must be true and {@link
 *       VkReflect#smokeTest()} must allocate/chain the SemaphoreType + ExportMetalObject create-info
 *       structs and resolve all constants (this is the exact reflection plumbing used on device,
 *       minus the Vulkan device);</li>
 *   <li>without LWJGL (the provider-jar compile classpath): {@link VkReflect#available()} must be false
 *       and {@link VkReflect#smokeTest()} must fail closed with {@code UnavailableException}, which is
 *       what {@link GpuEyeSync} converts into a warning + unsynchronized fallback.</li>
 * </ul>
 */
public final class VkReflectSmokeTest {
    public static void main(String[] args) {
        boolean expectLwjgl = args.length > 0 && args[0].equals("--expect-lwjgl");
        boolean available = VkReflect.available();
        System.out.println("[provider-vkreflect-test] available()=" + available
            + " expectLwjgl=" + expectLwjgl);
        if (expectLwjgl) {
            if (!available) {
                System.out.println("FAIL: LWJGL classes were expected on the classpath");
                System.exit(1);
            }
            try {
                String summary = VkReflect.smokeTest();
                System.out.println("[provider-vkreflect-test] smokeTest: " + summary);
                if (VkReflect.allCommandsStageMask() == 0) {
                    System.out.println("FAIL: VK_PIPELINE_STAGE_ALL_COMMANDS_BIT resolved to 0");
                    System.exit(2);
                }
                System.out.println("[provider-vkreflect-test] PASS (reflection plumbing live)");
            } catch (Throwable t) {
                System.out.println("FAIL: smokeTest threw " + t);
                System.exit(3);
            }
        } else {
            if (available) {
                System.out.println("FAIL: LWJGL unexpectedly present (run this mode with the provider jar classpath)");
                System.exit(4);
            }
            try {
                VkReflect.smokeTest();
                System.out.println("FAIL: smokeTest did not fail closed without LWJGL");
                System.exit(5);
            } catch (VkReflect.UnavailableException e) {
                System.out.println("[provider-vkreflect-test] expected fail-closed: " + e.getMessage());
                System.out.println("[provider-vkreflect-test] PASS (graceful UnavailableException)");
            }
        }
    }
}
