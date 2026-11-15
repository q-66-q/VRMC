package dev.vrmc.provider;

/** Host tests for the VRMC hand model geometry (VisionHandMesh). Synthetic joints, not device data. */
public final class VisionHandMeshTest {
    private static int checks;
    private static int failures;
    private static void check(String name, boolean ok) {
        checks++;
        if (!ok) { failures++; System.out.println("  FAIL " + name); }
    }

    /** Open right hand in front of the chest, fingers pointing forward (-Z), palm down. */
    static float[] hand(float wx, float wy, float wz, boolean fist) {
        float[] j = new float[27 * 3];
        set(j, 0, wx, wy, wz);
        // thumb out to the left (towards the body midline for a right hand)
        set(j, 1, wx - 0.03F, wy, wz - 0.03F);
        set(j, 2, wx - 0.05F, wy, wz - 0.05F);
        set(j, 3, wx - 0.06F, wy, wz - 0.07F);
        set(j, 4, wx - 0.065F, wy, wz - 0.09F);
        float[] xs = {-0.02F, 0.0F, 0.02F, 0.04F};
        for (int f = 0; f < 4; f++) {
            int base = 5 + f * 5;
            float x = wx + xs[f];
            set(j, base, x, wy, wz - 0.03F);       // metacarpal
            set(j, base + 1, x, wy, wz - 0.09F);   // knuckle
            float curl = fist ? 0.02F : 0.0F;
            set(j, base + 2, x, wy - curl, wz - 0.13F + curl);
            set(j, base + 3, x, wy - curl * 2, wz - 0.155F + curl * 2);
            set(j, base + 4, x, wy - curl * 3, wz - 0.175F + curl * 3);
        }
        set(j, 25, wx, wy, wz + 0.03F);
        set(j, 26, wx, wy, wz + 0.10F);
        return j;
    }

    static void set(float[] j, int i, float x, float y, float z) {
        j[i * 3] = x; j[i * 3 + 1] = y; j[i * 3 + 2] = z;
    }

    public static void main(String[] args) {
        VisionHandMesh m = new VisionHandMesh();
        float[] j = hand(0.25F, 1.20F, -0.30F, false);
        boolean ok = m.build(j, true, 0.0F, 1.60F, 0.0F, 1.0F, 0.0F, null);
        check("open hand builds", ok && m.valid);
        check("mesh is whole quads", m.vertexCount > 0 && m.vertexCount % 4 == 0);
        // forearm + upper arm + palm + 4 thumb + 12 finger = 19 boxes
        check("arm, palm, thumb and four fingers", m.vertexCount == 19 * VisionHandMesh.VERTS_PER_BOX);
        boolean finite = true;
        float minZ = Float.MAX_VALUE, maxZ = -Float.MAX_VALUE;
        for (int i = 0; i < m.vertexCount * 3; i++) finite &= Float.isFinite(m.positions[i]);
        for (int i = 0; i < m.vertexCount; i++) {
            minZ = Math.min(minZ, m.positions[i * 3 + 2]);
            maxZ = Math.max(maxZ, m.positions[i * 3 + 2]);
        }
        check("all vertices finite", finite);
        check("fingers reach the fingertips", minZ < -0.30F - 0.17F);
        check("forearm reaches back toward the elbow", maxZ > -0.30F + 0.20F);

        // Feedback colours
        VisionHandMesh.Feedback fb = new VisionHandMesh.Feedback();
        m.build(j, true, 0.0F, 1.60F, 0.0F, 1.0F, 0.0F, fb);
        int[] plain = m.colors.clone();
        fb.pinchHeld = true;
        m.build(j, true, 0.0F, 1.60F, 0.0F, 1.0F, 0.0F, fb);
        boolean changed = false;
        for (int i = 0; i < m.vertexCount; i++) changed |= plain[i] != m.colors[i];
        check("held pinch recolours the fingertips", changed);
        fb.clear();
        fb.radialProgress = 1.0F;
        m.build(j, true, 0.0F, 1.60F, 0.0F, 1.0F, 0.0F, fb);
        int palmColor = m.colors[2 * VisionHandMesh.VERTS_PER_BOX]; // palm is the 3rd box
        check("radial hold tints the hand", palmColor != plain[2 * VisionHandMesh.VERTS_PER_BOX]);

        check("proximity 1 when touching", VisionHandMesh.pinchProximity(0.01F, 0.025F, 0.06F) == 1.0F);
        check("proximity 0 when apart", VisionHandMesh.pinchProximity(0.08F, 0.025F, 0.06F) == 0.0F);
        check("proximity 0 for NaN", VisionHandMesh.pinchProximity(Float.NaN, 0.025F, 0.06F) == 0.0F);

        // Missing forearm joints fall back to the hand axis.
        float[] nf = hand(0.25F, 1.20F, -0.30F, false);
        for (int k = 75; k < 81; k++) nf[k] = Float.NaN;
        check("forearm fallback builds", m.build(nf, true, 0.0F, 1.60F, 0.0F, 1.0F, 0.0F, null)
            && m.vertexCount == 19 * VisionHandMesh.VERTS_PER_BOX);

        // Garbage never builds.
        float[] bad = hand(0.25F, 1.20F, -0.30F, false);
        bad[9 * 3] = Float.NaN;
        check("NaN finger joint rejects the frame", !m.build(bad, true, 0, 1.6F, 0, 1, 0, null) && !m.valid);
        check("zeroed hand rejected", !m.build(new float[81], true, 0, 1.6F, 0, 1, 0, null));
        check("short array rejected", !m.build(new float[10], true, 0, 1.6F, 0, 1, 0, null));
        check("NaN head rejected", !m.build(j, true, Float.NaN, 1.6F, 0, 1, 0, null));

        // Upper arm skipped when the shoulder estimate is implausibly far.
        float[] far = hand(0.25F, 1.20F, -1.50F, false);
        m.build(far, true, 0.0F, 1.60F, 0.0F, 1.0F, 0.0F, null);
        check("no stretched upper arm", m.vertexCount == 18 * VisionHandMesh.VERTS_PER_BOX);

        // Random fuzz: never throws, never emits non-finite vertices.
        java.util.Random r = new java.util.Random(7);
        boolean fuzzOk = true;
        for (int it = 0; it < 20000; it++) {
            float[] jj = new float[81];
            for (int k = 0; k < 81; k++) jj[k] = r.nextInt(50) == 0 ? Float.NaN : (r.nextFloat() - 0.5F) * 0.4F;
            try {
                if (m.build(jj, r.nextBoolean(), 0, 1.6F, 0, 1, 0, null)) {
                    for (int i = 0; i < m.vertexCount * 3; i++) fuzzOk &= Float.isFinite(m.positions[i]);
                }
            } catch (Throwable t) {
                fuzzOk = false;
            }
        }
        check("fuzz: finite and no exceptions", fuzzOk);

        System.out.println("[hand-mesh-test] " + checks + " checks, " + failures + " failed");
        System.out.println(failures == 0 ? "[hand-mesh-test] PASS" : "[hand-mesh-test] FAIL");
        if (failures != 0) System.exit(1);
    }
}
