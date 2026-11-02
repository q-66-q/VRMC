#ifndef VRMC_ABI_H
#define VRMC_ABI_H
/*
 * VRMC native bridge ABI (AGENT.md §3.4).
 *
 * v2 adds vrmc_export_mtl_texture (VkImage -> MTLTexture export through the game's MoltenVK).
 * v3 adds the immersive input channel (M4-W1): vrmc_hand_state / vrmc_input_state and the
 * input payload of vrmc_poll_input (compositor ARKit hand tracking -> JVM provider gestures).
 * v1 was never shipped externally; provider + bridge ship together.
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

#define VRMC_ABI_VERSION 3

typedef struct { float x, y, z; } vrmc_vec3;
typedef struct { float x, y, z, w; } vrmc_quat;
typedef struct { vrmc_quat orientation; vrmc_vec3 position; } vrmc_pose;

typedef struct {
    uint64_t presentation_time_ns; /* ARKit/Compositor predicted time */
    vrmc_pose head;                /* device anchor, world space */
    vrmc_pose controllers[2];      /* PSVR2 Sense / tracked controllers */
    float ipd_m;
} vrmc_tracking_state;

/* ------------------------------------------------------------------------------------------ */
/* ABI v3: immersive input (M4-W1).                                                            */
/*                                                                                            */
/* The compositor owns ARKit hand tracking and publishes one vrmc_input_state per frame through */
/* the native-shared channel (vrmc_shared_publish_input in vrmc_native_shared.h). The JVM       */
/* provider polls the latest snapshot here (vrmc_poll_input / JNI nativePollInput) and turns     */
/* gestures into Vivecraft actions. Both structs are ABI: sizes/offsets are part of the contract */
/* and are asserted by bridge/tests/bridge_input_test.c and the provider layout test.           */
/*                                                                                            */
/* Coordinate space: the SAME device/anchor space as vrmc_tracking_state.head (ARKit origin,   */
/* y-up, -Z forward, metres). The publisher applies the hand anchor's origin transform, so no   */
/* extra transform is needed between head and hands.                                           */
/* ------------------------------------------------------------------------------------------ */

#define VRMC_HAND_JOINT_COUNT 27
#define VRMC_INPUT_HAND_COUNT 2
#define VRMC_INPUT_LEFT_HAND  0
#define VRMC_INPUT_RIGHT_HAND 1

/* One hand, one frame. ARKit joint index order: 0 wrist, 4 thumb tip, 9 index tip, 11 middle
 * knuckle (palm length), 14 middle tip, 19 ring tip, 24 little tip, 5 index metacarpal,
 * 20 little metacarpal. */
typedef struct {
    uint32_t tracked;        /* 1 = wrist/joints valid this frame, 0 = not tracked */
    uint32_t chirality;      /* NORMALIZED: 0 = left, 1 = right. NOTE: this is NOT the raw ARKit enum (ar_hand_chirality_right = 0, ar_hand_chirality_left = 1), so the publisher must map ar_hand_anchor_get_chirality() into this convention. */
    uint64_t timestamp_ns;   /* anchor-predicted timestamp the hand was queried at */
    vrmc_quat wrist_orientation;                 /* device space */
    vrmc_vec3 wrist_position;                    /* device space, meters */
    vrmc_vec3 joints[VRMC_HAND_JOINT_COUNT];     /* device space, meters */
} vrmc_hand_state;

/* One published input snapshot. hands[0] is always LEFT and hands[1] always RIGHT (independent of
 * the chirality field, which is still set for consumers that use it). */
typedef struct {
    uint32_t frame_index;    /* compositor frame counter */
    uint32_t valid_mask;     /* bit0 = hands[0] (left) tracked, bit1 = hands[1] (right) tracked */
    uint64_t timestamp_ns;   /* predicted anchor time of this snapshot */
    vrmc_hand_state hands[VRMC_INPUT_HAND_COUNT];
} vrmc_input_state;

typedef struct {
    uint32_t frame_index;
    int64_t presentation_deadline_ns;
    uint64_t left_texture;  /* opaque Metal texture handle exported by the bridge/renderer */
    uint64_t right_texture; /* opaque Metal texture handle */
    uint32_t left_width, left_height, right_width, right_height;
    float left_fov[4];  /* left, right, up, down half-angles, radians; left/down negative (OpenXR) */
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

/* v3: copy the latest vrmc_input_state into *out. Requires out_len >= sizeof(vrmc_input_state);
 * returns 0 with a zeroed snapshot (valid_mask = 0) before the compositor has ever published one
 * ("safe, no hands", not an error), and fails closed on a short buffer / uninitialized bridge. */
int32_t vrmc_poll_input(void *out, size_t out_len);
int32_t vrmc_submit_eyes(const vrmc_eye_targets *targets);
int32_t vrmc_frame_timing(vrmc_frame_timing_t *out);
int32_t vrmc_recenter(int32_t mode);
int32_t vrmc_haptic(int32_t hand, float amplitude, float frequency_hz, float duration_s);

/* v2: export an opaque MTLTexture handle from a VkImage (the image must belong to the process's
 * MoltenVK device). Writes a non-zero handle and returns 0 on success; fails closed otherwise. */
int32_t vrmc_export_mtl_texture(uint64_t vk_image, uint64_t *out_mtl_texture);

/* Human-readable last error, never NULL; valid until the next call on the same thread. */
const char *vrmc_last_error(void);

#ifdef __cplusplus
}
#endif
#endif /* VRMC_ABI_H */
