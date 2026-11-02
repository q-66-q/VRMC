package dev.vrmc.provider;

import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;

/**
 * M4-W2 hand-pose smoothing (pure Java; no Minecraft/Vivecraft imports).
 *
 * <p>W1 mapped the raw 27-joint pose once per frame; on-device the operator asked for continuous,
 * stable hand motion. This is a One-Euro filter (Casiez et al. 2012) on the controller translation and
 * an angle-adaptive slerp on the orientation:
 *
 * <ul>
 *   <li>position: cutoff = posMinCutoff + posBeta * |filtered velocity|; low speed = heavy smoothing
 *       (stable pointer), fast motion = light smoothing (low lag);</li>
 *   <li>rotation: slerp factor from angular speed with the same min-cutoff + beta shape, so slow aim
 *       changes are damped and fast swipes are not;</li>
 *   <li>tracking loss/reset drops all history so a newly acquired hand never snaps from a stale
 *       pose (and never lags behind a teleporting wrist);</li>
 *   <li>non-finite input fails safe by resetting and passing the raw pose through.</li>
 * </ul>
 *
 * <p>All state is preallocated; {@link #apply(Matrix4f, long)} allocates nothing on the steady-state
 * path. Host-tested by {@code VisionPoseSmootherTest}.
 */
public final class VisionPoseSmoother {
    /** Tuning for the filter (all times in seconds, cutoffs in Hz). */
    public static final class Config {
        public boolean enabled = true;
        public float posMinCutoff = 1.5F;
        public float posBeta = 0.5F;
        public float derivativeCutoff = 1.0F;
        public float rotMinCutoff = 1.0F;
        public float rotBeta = 0.03F; // rad/s unit; keeps fast head/hand rotation responsive but damps jitter
        /** Sample interval used when the caller's timestamps are missing/duplicated. */
        public float fallbackDt = 1.0F / 90.0F;
        public float minDt = 1.0F / 240.0F;
        public float maxDt = 0.05F;

        public Config copy() {
            Config c = new Config();
            c.enabled = this.enabled;
            c.posMinCutoff = this.posMinCutoff;
            c.posBeta = this.posBeta;
            c.derivativeCutoff = this.derivativeCutoff;
            c.rotMinCutoff = this.rotMinCutoff;
            c.rotBeta = this.rotBeta;
            c.fallbackDt = this.fallbackDt;
            c.minDt = this.minDt;
            c.maxDt = this.maxDt;
            return c;
        }
    }

    private final Config config;

    private final Vector3f rawPos = new Vector3f();
    private final Vector3f filteredPos = new Vector3f();
    private final Vector3f filteredVel = new Vector3f();
    private final Quaternionf rawQuat = new Quaternionf();
    private final Quaternionf filteredQuat = new Quaternionf();
    private boolean hasPosition;
    private boolean hasRotation;
    private long lastTimestampNs;

    public VisionPoseSmoother(Config config) {
        this.config = config == null ? new Config() : config.copy();
    }

    public Config config() {
        return this.config;
    }

    public boolean enabled() {
        return this.config.enabled;
    }

    /** Drop all history (tracking loss, teleport, mode change). */
    public void reset() {
        this.hasPosition = false;
        this.hasRotation = false;
        this.lastTimestampNs = 0L;
        this.filteredVel.set(0.0F);
    }

    /**
     * Smooth the pose in place.
     *
     * @param pose        controller pose (translation + orthonormal rotation), mutated to the smoothed value
     * @param timestampNs input snapshot/render timestamp; <= 0 or non-monotonic uses the fallback dt
     */
    public void apply(Matrix4f pose, long timestampNs) {
        if (!this.config.enabled) {
            return;
        }
        this.rawPos.set(pose.m30(), pose.m31(), pose.m32());
        pose.getNormalizedRotation(this.rawQuat);
        if (!finite(this.rawPos) || !finite(this.rawQuat)) {
            reset();
            return;
        }

        float dt = this.timeStep(timestampNs);
        this.lastTimestampNs = timestampNs;

        if (!this.hasPosition) {
            this.filteredPos.set(this.rawPos);
            this.filteredVel.set(0.0F);
            this.hasPosition = true;
        } else {
            // Raw velocity (finite-difference), then the One-Euro derivative filter.
            float vx = (this.rawPos.x - this.filteredPos.x) / dt;
            float vy = (this.rawPos.y - this.filteredPos.y) / dt;
            float vz = (this.rawPos.z - this.filteredPos.z) / dt;
            float alphaD = alpha(dt, this.config.derivativeCutoff);
            this.filteredVel.x += alphaD * (vx - this.filteredVel.x);
            this.filteredVel.y += alphaD * (vy - this.filteredVel.y);
            this.filteredVel.z += alphaD * (vz - this.filteredVel.z);

            float speed = this.filteredVel.length();
            float cutoff = this.config.posMinCutoff + this.config.posBeta * speed;
            float alphaP = alpha(dt, cutoff);
            this.filteredPos.x += alphaP * (this.rawPos.x - this.filteredPos.x);
            this.filteredPos.y += alphaP * (this.rawPos.y - this.filteredPos.y);
            this.filteredPos.z += alphaP * (this.rawPos.z - this.filteredPos.z);
        }

        if (!this.hasRotation) {
            this.filteredQuat.set(this.rawQuat);
            this.hasRotation = true;
        } else {
            // Angle between the raw and filtered rotations (dot magnitude handles the quaternion double cover).
            float dot = Math.abs(this.rawQuat.x * this.filteredQuat.x + this.rawQuat.y * this.filteredQuat.y
                + this.rawQuat.z * this.filteredQuat.z + this.rawQuat.w * this.filteredQuat.w);
            dot = Math.min(1.0F, Math.max(0.0F, dot));
            float angle = 2.0F * (float) Math.acos(dot);
            float angularSpeed = angle / dt;
            float cutoff = this.config.rotMinCutoff + this.config.rotBeta * angularSpeed;
            float alphaR = alpha(dt, cutoff);
            this.filteredQuat.slerp(this.rawQuat, alphaR);
        }

        pose.rotation(this.filteredQuat);
        pose.setTranslation(this.filteredPos);
    }

    private float timeStep(long timestampNs) {
        if (this.lastTimestampNs <= 0L || timestampNs <= 0L || timestampNs <= this.lastTimestampNs) {
            return this.config.fallbackDt;
        }
        float dt = (timestampNs - this.lastTimestampNs) * 1.0E-9F;
        if (!Float.isFinite(dt) || dt <= 0.0F) return this.config.fallbackDt;
        return Math.min(this.config.maxDt, Math.max(this.config.minDt, dt));
    }

    /** One-Euro exponential smoothing factor for a cutoff (Hz) over dt (s). */
    private static float alpha(float dt, float cutoffHz) {
        float cutoff = Math.max(1.0E-3F, cutoffHz);
        float tau = 1.0F / (float) (2.0 * Math.PI * cutoff);
        return (float) (1.0 - Math.exp(-dt / tau));
    }

    private static boolean finite(Vector3f v) {
        return Float.isFinite(v.x) && Float.isFinite(v.y) && Float.isFinite(v.z);
    }

    private static boolean finite(Quaternionf q) {
        return Float.isFinite(q.x) && Float.isFinite(q.y) && Float.isFinite(q.z) && Float.isFinite(q.w);
    }
}
