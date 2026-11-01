#ifndef VRMC_ABI_H
#define VRMC_ABI_H
/*
 * VRMC native bridge ABI (AGENT.md §3.4).
 *
 * ABI EVOLUTION POLICY (binding from M2; see docs/mvp/M2_PLAN.md §9):
 * 1. ANY struct layout/field/function signature change bumps VRMC_ABI_VERSION by a major version,
 *    including additive fields (struct sizes are part of the contract; no "optional field in v1").
 * 2. Unknown/mismatched major => FAIL CLOSED. vrmc_init returns an error and the provider aborts VR
 *    initialization with a visible message. vrmc_init(caps_json) version mismatch is a hard reject,
 *    never warn-and-continue.
 * 3. No cross-version compatibility window: v1 provider + v2 bridge and v2 provider + v1 bridge both
 *    fail; a v1->v2 transition ships provider + bridge in the same app build.
 * 4. Capabilities are negotiated in caps_json; absence of a required capability fails closed. Adding a
 *    capability string without a layout change is not a version bump.
 * 5. Removal/deprecation only in the next major bump; one major version of documented overlap is
 *    allowed by keeping both symbols.
 *
 * VRMC native bridge ABI v1 details:
 *
 * The JVM-side provider mod talks to the visionOS bridge through these C entry points (JNI wrapper on
 * the Java side). The ABI is versioned and FAILS CLOSED: an unknown version or a missing capability must
 * abort VR initialization, never silently fall back.
 */
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VRMC_ABI_VERSION 1

typedef struct { float x, y, z; } vrmc_vec3;
typedef struct { float x, y, z, w; } vrmc_quat;
typedef struct { vrmc_quat orientation; vrmc_vec3 position; } vrmc_pose;

typedef struct {
    uint64_t presentation_time_ns; /* ARKit/Compositor predicted time */
    vrmc_pose head;                /* device anchor, world space */
    vrmc_pose controllers[2];      /* PSVR2 Sense / tracked controllers */
    float ipd_m;
} vrmc_tracking_state;

typedef struct {
    uint32_t frame_index;
    int64_t presentation_deadline_ns;
    uint64_t left_texture;  /* opaque Metal texture handle exported by the bridge/renderer */
    uint64_t right_texture; /* opaque Metal texture handle */
    uint32_t left_width, left_height, right_width, right_height;
    float left_fov[4];  /* left, right, up, down, radians */
    float right_fov[4];
} vrmc_eye_targets;

typedef struct {
    uint64_t frame_index;
    int64_t cpu_time_ns;
    int64_t gpu_time_ns;
    int64_t presentation_time_ns;
    uint32_t dropped_frames;
} vrmc_frame_timing_t;

/* ABI/version handshake. Must be called before anything else. */
int32_t vrmc_abi_version(void);

/* caps_json is a UTF-8 JSON object; init fails closed on version mismatch or malformed caps. */
int32_t vrmc_init(const char *caps_json, size_t caps_len);

int32_t vrmc_get_tracking(vrmc_tracking_state *out, uint64_t timestamp_ns);
int32_t vrmc_poll_input(void *out, size_t out_len);
int32_t vrmc_submit_eyes(const vrmc_eye_targets *targets);
int32_t vrmc_frame_timing(vrmc_frame_timing_t *out);
int32_t vrmc_recenter(int32_t mode);
int32_t vrmc_haptic(int32_t hand, float amplitude, float frequency_hz, float duration_s);

/* Human-readable last error, never NULL; valid until the next call on the same thread. */
const char *vrmc_last_error(void);

#ifdef __cplusplus
}
#endif
#endif /* VRMC_ABI_H */
