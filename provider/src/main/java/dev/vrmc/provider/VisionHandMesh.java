package dev.vrmc.provider;

/**
 * VRMC hand model: a simple blocky (Minecraft-style) arm, hand and five articulated fingers built
 * from the 27 ARKit hand joints every frame, in ROOM space (metres, the same space as the joints).
 *
 * <p>Pure Java and allocation-free after construction, so the host tests cover it. The renderer
 * (VRArmHelperMixin) pushes Vivecraft's room-to-world transform and emits the quads as they are.
 *
 * <p>Colours carry the gesture feedback the operator asked for ("give the player feedback for what
 * they do"): thumb and index tips light up as they approach a pinch and turn green while the pinch
 * is held (orange while it is breaking a block); a closed fist warms the whole hand; the right-fist
 * radial hold fills the hand with purple as it charges; a held middle pinch lights the middle tip.
 *
 * <p>Joint order (ARKit HandSkeleton.JointName): 0 wrist; 1-4 thumb knuckle..tip; 5-9 index
 * metacarpal, knuckle, intermediate base, intermediate tip, tip; 10-14 middle; 15-19 ring;
 * 20-24 little; 25 forearm wrist; 26 forearm arm.
 */
public final class VisionHandMesh {
    public static final int JOINTS = 27;
    public static final int MAX_BOXES = 24;
    /** 6 faces x 4 corners. */
    public static final int VERTS_PER_BOX = 24;

    /** Forearm length used to place the elbow (adult average ~0.25 m wrist to elbow). */
    public static final float FOREARM_LENGTH = 0.25F;
    /** Shoulder below / beside the head centre (adult averages). */
    public static final float SHOULDER_DROP = 0.23F;
    public static final float SHOULDER_SIDE = 0.17F;
    /** The upper arm is drawn from the elbow this fraction of the way to the shoulder (keeps the
     * box out of the camera near plane when looking down). */
    public static final float UPPER_ARM_DRAWN = 0.70F;

    // Base colours (RGB); Minecraft default-skin flavoured.
    static final int SKIN = rgb(214, 160, 120);
    static final int SKIN_DARK = rgb(184, 128, 92);
    static final int SLEEVE = rgb(0, 168, 168);
    static final int PINCH_NEAR = rgb(110, 210, 255);
    static final int PINCH_HELD = rgb(80, 230, 120);
    static final int BREAKING = rgb(255, 140, 60);
    static final int FIST = rgb(245, 190, 90);
    static final int RADIAL = rgb(185, 115, 255);
    static final int MIDDLE = rgb(255, 222, 80);

    /** Per-frame gesture feedback for one hand. */
    public static final class Feedback {
        /** 0 = fingers apart .. 1 = touching (thumb-index proximity). */
        public float pinchProximity;
        public boolean pinchHeld;
        public boolean breaking;
        public boolean fist;
        /** 0..1 charge of the right-fist radial hold; 1 = menu open. */
        public float radialProgress;
        public boolean middleHeld;

        public void clear() {
            this.pinchProximity = 0.0F;
            this.pinchHeld = false;
            this.breaking = false;
            this.fist = false;
            this.radialProgress = 0.0F;
            this.middleHeld = false;
        }
    }

    /** Quad corner positions (room space), 4 per face. */
    public final float[] positions = new float[MAX_BOXES * VERTS_PER_BOX * 3];
    /** Packed 0xRRGGBB colour per quad corner (already face-shaded, before world light). */
    public final int[] colors = new int[MAX_BOXES * VERTS_PER_BOX];
    public int vertexCount;
    public boolean valid;

    // scratch
    private final float[] j = new float[JOINTS * 3];
    private final float[] palmN = new float[3];
    private final float[] tmpA = new float[3];
    private final float[] tmpB = new float[3];
    private final float[] elbow = new float[3];
    private final float[] shoulder = new float[3];

    /** Proximity from a thumb-index distance: 0 at {@code far} or more, 1 at {@code near} or less. */
    public static float pinchProximity(float distance, float near, float far) {
        if (!Float.isFinite(distance) || !(far > near)) return 0.0F;
        float t = (far - distance) / (far - near);
        return t < 0.0F ? 0.0F : (t > 1.0F ? 1.0F : t);
    }

    /**
     * Rebuild the mesh. {@code headRightX/Z} is the horizontal head right vector (unit); the
     * shoulder is placed from it. Returns {@link #valid}.
     */
    public boolean build(float[] joints, boolean rightHand, float headX, float headY, float headZ,
                         float headRightX, float headRightZ, Feedback fb) {
        this.vertexCount = 0;
        this.valid = false;
        if (joints == null || joints.length < JOINTS * 3) return false;
        System.arraycopy(joints, 0, this.j, 0, JOINTS * 3);
        // Core joints must be finite and the hand plausibly sized (rejects zeroed/garbage frames).
        for (int k = 0; k <= 24; k++) {
            if (!finite(k)) return false;
        }
        float palmLen = dist(0, 11);
        if (!(palmLen > 0.03F && palmLen < 0.20F)) return false;
        if (!Float.isFinite(headX) || !Float.isFinite(headY) || !Float.isFinite(headZ)) return false;

        // Palm normal (sign is irrelevant for symmetric boxes).
        sub(6, 0, this.tmpA);
        sub(21, 0, this.tmpB);
        cross(this.tmpA, this.tmpB, this.palmN);
        if (!normalize(this.palmN)) {
            this.palmN[0] = 0.0F; this.palmN[1] = 1.0F; this.palmN[2] = 0.0F;
        }

        Feedback f = fb == null ? EMPTY : fb;
        int handColor = SKIN;
        if (f.fist) handColor = mix(handColor, FIST, 0.40F);
        if (f.radialProgress > 0.0F) handColor = mix(handColor, RADIAL, 0.25F + 0.55F * clamp01(f.radialProgress));

        int tipColor = handColor;
        if (f.breaking) tipColor = BREAKING;
        else if (f.pinchHeld) tipColor = PINCH_HELD;
        else if (f.pinchProximity > 0.0F) tipColor = mix(handColor, PINCH_NEAR, f.pinchProximity);
        int middleTip = f.middleHeld ? MIDDLE : handColor;

        // ---- arm: forearm from the ARKit forearm joints, upper arm to an estimated shoulder ----
        float ex = this.j[26 * 3] - this.j[25 * 3];
        float ey = this.j[26 * 3 + 1] - this.j[25 * 3 + 1];
        float ez = this.j[26 * 3 + 2] - this.j[25 * 3 + 2];
        float el = (float) Math.sqrt(ex * ex + ey * ey + ez * ez);
        if (!finite(25) || !finite(26) || !(el > 0.02F) || !Float.isFinite(el)) {
            // Forearm joints unavailable: the forearm continues the wrist -> middle knuckle line.
            ex = this.j[0] - this.j[11 * 3];
            ey = this.j[1] - this.j[11 * 3 + 1];
            ez = this.j[2] - this.j[11 * 3 + 2];
            el = (float) Math.sqrt(ex * ex + ey * ey + ez * ez);
        }
        this.elbow[0] = this.j[0] + ex / el * FOREARM_LENGTH;
        this.elbow[1] = this.j[1] + ey / el * FOREARM_LENGTH;
        this.elbow[2] = this.j[2] + ez / el * FOREARM_LENGTH;
        float side = rightHand ? 1.0F : -1.0F;
        this.shoulder[0] = headX + headRightX * SHOULDER_SIDE * side;
        this.shoulder[1] = headY - SHOULDER_DROP;
        this.shoulder[2] = headZ + headRightZ * SHOULDER_SIDE * side;
        box(this.j[0], this.j[1], this.j[2], this.elbow[0], this.elbow[1], this.elbow[2],
            0.058F, 0.050F, mix(handColor, SKIN_DARK, 0.35F), 0.0F);
        float ux = this.shoulder[0] - this.elbow[0];
        float uy = this.shoulder[1] - this.elbow[1];
        float uz = this.shoulder[2] - this.elbow[2];
        float ul = (float) Math.sqrt(ux * ux + uy * uy + uz * uz);
        if (ul > 0.12F && ul < 0.55F) {
            box(this.elbow[0], this.elbow[1], this.elbow[2],
                this.elbow[0] + ux * UPPER_ARM_DRAWN, this.elbow[1] + uy * UPPER_ARM_DRAWN,
                this.elbow[2] + uz * UPPER_ARM_DRAWN, 0.072F, 0.066F, SLEEVE, 0.02F);
        }

        // ---- palm: wrist -> knuckle line, as wide as index..little knuckles ----
        float kx = (this.j[6 * 3] + this.j[11 * 3] + this.j[16 * 3] + this.j[21 * 3]) * 0.25F;
        float ky = (this.j[6 * 3 + 1] + this.j[11 * 3 + 1] + this.j[16 * 3 + 1] + this.j[21 * 3 + 1]) * 0.25F;
        float kz = (this.j[6 * 3 + 2] + this.j[11 * 3 + 2] + this.j[16 * 3 + 2] + this.j[21 * 3 + 2]) * 0.25F;
        float palmWidth = Math.max(0.05F, Math.min(0.11F, dist(6, 21) + 0.022F));
        boxSide(this.j[0], this.j[1], this.j[2], kx, ky, kz, palmWidth, 0.028F,
            this.j[21 * 3] - this.j[6 * 3], this.j[21 * 3 + 1] - this.j[6 * 3 + 1],
            this.j[21 * 3 + 2] - this.j[6 * 3 + 2], handColor);

        // ---- thumb (thenar + 3 bones) and four fingers (3 bones each) ----
        seg(0, 1, 0.026F, handColor);
        seg(1, 2, 0.020F, handColor);
        seg(2, 3, 0.018F, handColor);
        seg(3, 4, 0.017F, tipColor);
        finger(6, 0.0175F, handColor, tipColor);
        finger(11, 0.0175F, handColor, middleTip);
        finger(16, 0.0165F, handColor, handColor);
        finger(21, 0.0150F, handColor, handColor);

        this.valid = this.vertexCount > 0;
        return this.valid;
    }

    private static final Feedback EMPTY = new Feedback();

    private void finger(int knuckle, float width, int color, int tipColor) {
        seg(knuckle, knuckle + 1, width, color);
        seg(knuckle + 1, knuckle + 2, width * 0.94F, color);
        seg(knuckle + 2, knuckle + 3, width * 0.88F, tipColor);
    }

    private void seg(int a, int b, float width, int color) {
        box(this.j[a * 3], this.j[a * 3 + 1], this.j[a * 3 + 2],
            this.j[b * 3], this.j[b * 3 + 1], this.j[b * 3 + 2], width, width * 0.9F, color, width * 0.45F);
    }

    /** Box between a and b; cross-section oriented by the palm normal. */
    private void box(float ax, float ay, float az, float bx, float by, float bz,
                     float width, float height, int color, float extend) {
        float dx = bx - ax, dy = by - ay, dz = bz - az;
        float len = (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (!(len > 1.0E-4F) || !Float.isFinite(len)) return;
        dx /= len; dy /= len; dz /= len;
        // side = dir x palmNormal
        float sx = dy * this.palmN[2] - dz * this.palmN[1];
        float sy = dz * this.palmN[0] - dx * this.palmN[2];
        float sz = dx * this.palmN[1] - dy * this.palmN[0];
        emitBox(ax, ay, az, dx, dy, dz, len, sx, sy, sz, width, height, color, extend);
    }

    /** Box between a and b with an explicit side direction (palm: across the knuckles). */
    private void boxSide(float ax, float ay, float az, float bx, float by, float bz,
                         float width, float height, float sx, float sy, float sz, int color) {
        float dx = bx - ax, dy = by - ay, dz = bz - az;
        float len = (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (!(len > 1.0E-4F) || !Float.isFinite(len)) return;
        dx /= len; dy /= len; dz /= len;
        // make side orthogonal to dir
        float d = sx * dx + sy * dy + sz * dz;
        sx -= d * dx; sy -= d * dy; sz -= d * dz;
        emitBox(ax, ay, az, dx, dy, dz, len, sx, sy, sz, width, height, color, 0.0F);
    }

    private void emitBox(float ax, float ay, float az, float dx, float dy, float dz, float len,
                         float sx, float sy, float sz, float width, float height, int color,
                         float extend) {
        if (this.vertexCount + VERTS_PER_BOX > MAX_BOXES * VERTS_PER_BOX) return;
        float sl = (float) Math.sqrt(sx * sx + sy * sy + sz * sz);
        if (!(sl > 1.0E-5F) || !Float.isFinite(sl)) {
            // dir parallel to the reference: any perpendicular works for a near-square section
            if (Math.abs(dy) < 0.9F) { sx = -dz; sy = 0.0F; sz = dx; } else { sx = 1.0F; sy = 0.0F; sz = 0.0F; }
            sl = (float) Math.sqrt(sx * sx + sy * sy + sz * sz);
        }
        sx /= sl; sy /= sl; sz /= sl;
        // n = side x dir
        float nx = sy * dz - sz * dy;
        float ny = sz * dx - sx * dz;
        float nz = sx * dy - sy * dx;
        float hw = width * 0.5F, hh = height * 0.5F;
        float a0x = ax - dx * extend, a0y = ay - dy * extend, a0z = az - dz * extend;
        float l = len + 2.0F * extend;
        float b0x = a0x + dx * l, b0y = a0y + dy * l, b0z = a0z + dz * l;
        // faces: +side, -side, +n, -n, end b (+dir), end a (-dir)
        face(b0x, b0y, b0z, a0x, a0y, a0z, sx, sy, sz, nx, ny, nz, hw, hh, color);
        face(b0x, b0y, b0z, a0x, a0y, a0z, -sx, -sy, -sz, nx, ny, nz, hw, hh, color);
        face(b0x, b0y, b0z, a0x, a0y, a0z, nx, ny, nz, sx, sy, sz, hh, hw, color);
        face(b0x, b0y, b0z, a0x, a0y, a0z, -nx, -ny, -nz, sx, sy, sz, hh, hw, color);
        cap(b0x, b0y, b0z, dx, dy, dz, sx, sy, sz, nx, ny, nz, hw, hh, color);
        cap(a0x, a0y, a0z, -dx, -dy, -dz, sx, sy, sz, nx, ny, nz, hw, hh, color);
    }

    /** Long side face whose outward normal is (ox,oy,oz) at offset {@code off} from the axis. */
    private void face(float bx, float by, float bz, float ax, float ay, float az,
                      float ox, float oy, float oz, float tx, float ty, float tz,
                      float off, float half, int color) {
        int c = shade(color, ox, oy, oz);
        float cx = ox * off, cy = oy * off, cz = oz * off;
        vertex(ax + cx - tx * half, ay + cy - ty * half, az + cz - tz * half, c);
        vertex(bx + cx - tx * half, by + cy - ty * half, bz + cz - tz * half, c);
        vertex(bx + cx + tx * half, by + cy + ty * half, bz + cz + tz * half, c);
        vertex(ax + cx + tx * half, ay + cy + ty * half, az + cz + tz * half, c);
    }

    private void cap(float px, float py, float pz, float ox, float oy, float oz,
                     float sx, float sy, float sz, float nx, float ny, float nz,
                     float hw, float hh, int color) {
        int c = shade(color, ox, oy, oz);
        vertex(px - sx * hw - nx * hh, py - sy * hw - ny * hh, pz - sz * hw - nz * hh, c);
        vertex(px + sx * hw - nx * hh, py + sy * hw - ny * hh, pz + sz * hw - nz * hh, c);
        vertex(px + sx * hw + nx * hh, py + sy * hw + ny * hh, pz + sz * hw + nz * hh, c);
        vertex(px - sx * hw + nx * hh, py - sy * hw + ny * hh, pz - sz * hw + nz * hh, c);
    }

    private void vertex(float x, float y, float z, int color) {
        int i = this.vertexCount;
        this.positions[i * 3] = x;
        this.positions[i * 3 + 1] = y;
        this.positions[i * 3 + 2] = z;
        this.colors[i] = color;
        this.vertexCount = i + 1;
    }

    /** Simple top light so the blocky shapes read in 3D (faces up are brighter). */
    static int shade(int color, float nx, float ny, float nz) {
        float l = 0.30F * nx + 0.90F * ny + 0.30F * nz; // light from above, slightly front-right
        float f = 0.62F + 0.38F * Math.max(0.0F, l) - 0.10F * Math.max(0.0F, -ny);
        return scale(color, f);
    }

    static int scale(int color, float f) {
        int r = Math.min(255, Math.max(0, Math.round(((color >> 16) & 0xFF) * f)));
        int g = Math.min(255, Math.max(0, Math.round(((color >> 8) & 0xFF) * f)));
        int b = Math.min(255, Math.max(0, Math.round((color & 0xFF) * f)));
        return (r << 16) | (g << 8) | b;
    }

    static int mix(int a, int b, float t) {
        float u = clamp01(t);
        int r = Math.round(((a >> 16) & 0xFF) * (1 - u) + ((b >> 16) & 0xFF) * u);
        int g = Math.round(((a >> 8) & 0xFF) * (1 - u) + ((b >> 8) & 0xFF) * u);
        int bl = Math.round((a & 0xFF) * (1 - u) + (b & 0xFF) * u);
        return (r << 16) | (g << 8) | bl;
    }

    static int rgb(int r, int g, int b) { return (r << 16) | (g << 8) | b; }

    private static float clamp01(float v) { return v < 0.0F ? 0.0F : (v > 1.0F ? 1.0F : v); }

    private boolean finite(int k) {
        return Float.isFinite(this.j[k * 3]) && Float.isFinite(this.j[k * 3 + 1])
            && Float.isFinite(this.j[k * 3 + 2]);
    }

    private float dist(int a, int b) {
        float x = this.j[a * 3] - this.j[b * 3];
        float y = this.j[a * 3 + 1] - this.j[b * 3 + 1];
        float z = this.j[a * 3 + 2] - this.j[b * 3 + 2];
        return (float) Math.sqrt(x * x + y * y + z * z);
    }

    private void sub(int a, int b, float[] out) {
        out[0] = this.j[a * 3] - this.j[b * 3];
        out[1] = this.j[a * 3 + 1] - this.j[b * 3 + 1];
        out[2] = this.j[a * 3 + 2] - this.j[b * 3 + 2];
    }

    private static void cross(float[] a, float[] b, float[] out) {
        out[0] = a[1] * b[2] - a[2] * b[1];
        out[1] = a[2] * b[0] - a[0] * b[2];
        out[2] = a[0] * b[1] - a[1] * b[0];
    }

    private static boolean normalize(float[] v) {
        float l = (float) Math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        if (!(l > 1.0E-6F) || !Float.isFinite(l)) return false;
        v[0] /= l; v[1] /= l; v[2] /= l;
        return true;
    }
}
