/*
 * HelloJit — minimal JIT probe for VRMC spike S1.
 *
 * A hot method is called long enough to be compiled by C2 and then executed many
 * times. With -XX:+PrintCompilation the JVM prints compile events; the probe also
 * reports its own iteration count so the run can be checked for execution, not just
 * compilation. Keep this class dependency-free.
 */
public final class HelloJit {

    private static volatile long sink;

    /** Hot method: small enough to compile, called in a long loop. */
    static long hot(long x) {
        long y = x * 0x5DEECE66DL + 0xBL;
        y ^= (y >>> 33);
        y *= 0xff51afd7ed558ccdL;
        y ^= (y >>> 33);
        return y;
    }

    public static void main(String[] args) throws Exception {
        long iterations = 200_000_000L;
        long acc = 1;
        long start = System.nanoTime();
        for (long i = 0; i < iterations; i++) {
            acc = hot(acc);
        }
        long elapsedMs = (System.nanoTime() - start) / 1_000_000L;
        sink = acc;
        System.out.println("HELLOJIT iterations=" + iterations + " acc=" + acc + " elapsed_ms=" + elapsedMs);
        System.out.println("HELLOJIT java=" + System.getProperty("java.version")
                + " vm=" + System.getProperty("java.vm.name"));
        // Keep the process alive briefly so logs are flushed and the enabler can detach.
        System.out.flush();
        Thread.sleep(1500);
        System.out.println("HELLOJIT done");
        System.out.flush();
    }
}
