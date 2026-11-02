/*
 * VRMC bridge stub — M2 scaffold, extended for the M3 eye-frame handoff (M3-W3/W4) and the M4
 * immersive input channel (M4-W1).
 *
 * Implements ABI v3 with deterministic fake tracking/hand input so the provider mod can be developed
 * and tested on a desktop Fabric harness before the real ARKit/Metal implementation lands. The stub is
 * NOT shipped on device once the real bridge exists; it exists to prove the handshake, the eye-frame
 * publication contract, the native-shared synchronization/lifetime surface and the ABI v3 input
 * snapshot channel (vrmc_poll_input / vrmc_shared_{publish,acquire}_input / input sequence).
 *
 * Threading: the provider publishes from the JVM render thread; the CompositorServices renderer
 * (compositor thread, same process) acquires from its own thread. All shared state below is
 * published/read under a mutex so readers can never observe a torn eye frame, a torn tracking
 * override, or a torn input snapshot (e.g. hands from frame N mixed with the other hand from
 * frame N+1).
 *
 * GPU sync contract: see bridge/abi/vrmc_native_shared.h (vrmc_shared_publish_eyes /
 * vrmc_shared_acquire_eyes). The bridge only transports the (MTLSharedEvent, timeline value) pair;
 * the provider exports it from a timeline VkSemaphore, the compositor waits on it before sampling.
 */
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <pthread.h>

static int32_t g_initialized = 0;
static uint64_t g_frames = 0;
/* The ABI header promises vrmc_last_error() is "valid until the next call on the same thread";
 * making the buffer thread-local makes that true for the JVM render thread and the compositor. */
static _Thread_local char g_error[256] = "no error";
static vrmc_tracking_state g_tracking;

/* M3-W3/W4 native-side shared state (same-process app <-> bridge; additive, outside the Java ABI). */
static pthread_mutex_t g_frame_mutex = PTHREAD_MUTEX_INITIALIZER;
static vrmc_shared_eye_frame g_latest_frame;
static int g_has_frame = 0;
static uint64_t g_publish_sequence = 0;
static uint32_t g_texture_generation = 0;

/* Tracking override: written by the compositor thread, read by the JVM render thread. */
static pthread_mutex_t g_tracking_mutex = PTHREAD_MUTEX_INITIALIZER;
static vrmc_tracking_state g_tracking_override;
static int g_has_tracking_override = 0;

/* Display views: written by the compositor thread, read by the JVM render thread. */
static pthread_mutex_t g_display_views_mutex = PTHREAD_MUTEX_INITIALIZER;
static vrmc_display_views g_display_views;
static uint32_t g_display_generation = 0;

/* M4-W1 immersive input (ABI v3): one vrmc_input_state snapshot written by the compositor frame loop
 * and read by the JVM render thread through vrmc_poll_input / vrmc_shared_acquire_input. The whole
 * 752-byte snapshot is copied under one mutex so a reader can never mix two frames. g_input_state is
 * zeroed by vrmc_init, so polling before the first publish returns the documented "safe, no hands"
 * snapshot (valid_mask = 0) rather than an error. Publication is allowed before vrmc_init: the
 * compositor can start the immersive space (and ARKit hand tracking) before the JVM/Minecraft VR
 * initialization runs vrmc_init; init then resets the channel to the same safe zero state. */
static pthread_mutex_t g_input_mutex = PTHREAD_MUTEX_INITIALIZER;
static vrmc_input_state g_input_state;
static int g_has_input_publish = 0;
static uint64_t g_input_sequence = 0;

static int32_t set_error(const char *msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
    return -1;
}

int32_t vrmc_abi_version(void) { return VRMC_ABI_VERSION; }

const char *vrmc_last_error(void) { return g_error; }

int32_t vrmc_init(const char *caps_json, size_t caps_len) {
    if (caps_json == NULL || caps_len == 0) return set_error("caps_json missing");
    if (strstr(caps_json, "\"abi\"") == NULL) return set_error("caps_json lacks abi capability");
    /* The real bridge will validate the advertised numbers; the stub only checks the ABI major.
     * ABI v2 (or anything that is not v3) FAILS CLOSED: no cross-version compatibility window. */
    if (strstr(caps_json, "\"abi\": 3") == NULL && strstr(caps_json, "\"abi\":3") == NULL) {
        return set_error("abi version mismatch (expected 3)");
    }
    memset(&g_tracking, 0, sizeof(g_tracking));
    g_tracking.ipd_m = 0.064f;
    g_tracking.head.orientation.w = 1.0f;
    g_tracking.controllers[0].orientation.w = 1.0f;
    g_tracking.controllers[1].orientation.w = 1.0f;
    pthread_mutex_lock(&g_frame_mutex);
    memset(&g_latest_frame, 0, sizeof(g_latest_frame));
    g_has_frame = 0;
    g_publish_sequence = 0;
    g_texture_generation = 0;
    g_frames = 0;
    pthread_mutex_unlock(&g_frame_mutex);
    /* Safe first poll: any pre-init publication (compositor started before the JVM) is dropped, so
     * the first vrmc_poll_input after init reports "no hands" until the next frame is published. */
    pthread_mutex_lock(&g_input_mutex);
    memset(&g_input_state, 0, sizeof(g_input_state));
    g_has_input_publish = 0;
    g_input_sequence = 0;
    pthread_mutex_unlock(&g_input_mutex);
    g_initialized = 1;
    printf("[vrmc-stub] init ok, abi=%d\n", VRMC_ABI_VERSION);
    return 0;
}

int32_t vrmc_get_tracking(vrmc_tracking_state *out, uint64_t timestamp_ns) {
    if (!g_initialized) return set_error("not initialized");
    if (out == NULL) return set_error("out is null");
    pthread_mutex_lock(&g_tracking_mutex);
    if (g_has_tracking_override) {
        *out = g_tracking_override;
        pthread_mutex_unlock(&g_tracking_mutex);
        return 0;
    }
    pthread_mutex_unlock(&g_tracking_mutex);
    g_tracking.presentation_time_ns = timestamp_ns;
    *out = g_tracking;
    return 0;
}

/* ABI v3 input polling (JVM render thread through JNI nativePollInput).
 * Contract (bridge/abi/vrmc_abi.h + docs/analysis/immersive-input.md §3.3):
 *   - uninitialized bridge / NULL out / out_len < sizeof(vrmc_input_state) fail closed;
 *   - before the first publish (or after vrmc_init reset) returns 0 with a ZEROED snapshot
 *     (frame_index 0, valid_mask 0, all hands untracked) -- "safe, no hands", not an error;
 *   - otherwise copies exactly sizeof(vrmc_input_state) bytes from the latest snapshot. A larger
 *     out_len is accepted and its tail is left untouched. */
int32_t vrmc_poll_input(void *out, size_t out_len) {
    if (!g_initialized) return set_error("not initialized");
    if (out == NULL) return set_error("input buffer missing");
    if (out_len < sizeof(vrmc_input_state)) {
        return set_error("input buffer too small (need sizeof(vrmc_input_state)=752)");
    }
    pthread_mutex_lock(&g_input_mutex);
    memcpy(out, &g_input_state, sizeof(g_input_state));
    pthread_mutex_unlock(&g_input_mutex);
    return 0;
}

/* Publish one eye frame under the frame lock. Caller must hold g_frame_mutex. */
static int32_t publish_eyes_locked(const vrmc_eye_targets *targets, const vrmc_shared_frame_sync *sync) {
    if (targets->left_texture == 0 || targets->right_texture == 0) {
        return set_error("eye texture handles missing");
    }
    if (sync != NULL && sync->valid != 0 && (sync->shared_event == 0 || sync->signal_value == 0)) {
        return set_error("invalid frame sync pair");
    }
    vrmc_shared_eye_frame frame;
    memset(&frame, 0, sizeof(frame));
    frame.eyes = *targets;
    if (sync != NULL && sync->valid != 0) {
        frame.sync = *sync;
        frame.sync.valid = 1;
    }
    /* A new texture generation means the provider replaced the eye render targets (resize /
     * render-target reinit). Consumers must treat previously acquired handles as potentially dead. */
    if (g_texture_generation == 0 ||
        g_latest_frame.eyes.left_texture != frame.eyes.left_texture ||
        g_latest_frame.eyes.right_texture != frame.eyes.right_texture ||
        g_latest_frame.eyes.left_width != frame.eyes.left_width ||
        g_latest_frame.eyes.left_height != frame.eyes.left_height ||
        g_latest_frame.eyes.right_width != frame.eyes.right_width ||
        g_latest_frame.eyes.right_height != frame.eyes.right_height) {
        g_texture_generation++;
    }
    frame.texture_generation = g_texture_generation;
    frame.publish_sequence = ++g_publish_sequence;
    g_frames++;
    g_latest_frame = frame;
    g_has_frame = 1;
    return 0;
}

int32_t vrmc_submit_eyes(const vrmc_eye_targets *targets) {
    if (!g_initialized) return set_error("not initialized");
    if (targets == NULL) return set_error("targets is null");
    pthread_mutex_lock(&g_frame_mutex);
    int32_t rc = publish_eyes_locked(targets, NULL);
    pthread_mutex_unlock(&g_frame_mutex);
    return rc;
}

int32_t vrmc_shared_publish_eyes(const vrmc_eye_targets *targets, const vrmc_shared_frame_sync *sync) {
    if (!g_initialized) return set_error("not initialized");
    if (targets == NULL) return set_error("targets is null");
    pthread_mutex_lock(&g_frame_mutex);
    int32_t rc = publish_eyes_locked(targets, sync);
    pthread_mutex_unlock(&g_frame_mutex);
    return rc;
}

int32_t vrmc_shared_acquire_eyes(vrmc_shared_eye_frame *out) {
    if (!g_initialized) return set_error("not initialized");
    if (out == NULL) return set_error("bad shared eye frame output");
    pthread_mutex_lock(&g_frame_mutex);
    if (!g_has_frame) {
        pthread_mutex_unlock(&g_frame_mutex);
        return set_error("no eye frame published yet");
    }
    *out = g_latest_frame;
    pthread_mutex_unlock(&g_frame_mutex);
    return 0;
}

int32_t vrmc_shared_eye_textures(vrmc_eye_targets *out) {
    if (out == NULL) return set_error("bad shared eye output");
    vrmc_shared_eye_frame frame;
    int32_t rc = vrmc_shared_acquire_eyes(&frame);
    if (rc != 0) return rc;
    *out = frame.eyes;
    return 0;
}

int32_t vrmc_shared_get_frame_sync(vrmc_shared_frame_sync *out) {
    if (out == NULL) return set_error("bad frame sync output");
    if (!g_initialized) return set_error("not initialized");
    pthread_mutex_lock(&g_frame_mutex);
    if (!g_has_frame) {
        pthread_mutex_unlock(&g_frame_mutex);
        return set_error("no eye frame published yet");
    }
    *out = g_latest_frame.sync;
    pthread_mutex_unlock(&g_frame_mutex);
    return 0;
}

int32_t vrmc_shared_set_tracking(const vrmc_tracking_state *state) {
    if (state == NULL) return set_error("bad shared tracking state");
    pthread_mutex_lock(&g_tracking_mutex);
    g_tracking_override = *state;
    g_has_tracking_override = 1;
    pthread_mutex_unlock(&g_tracking_mutex);
    return 0;
}

void vrmc_shared_clear_tracking(void) {
    pthread_mutex_lock(&g_tracking_mutex);
    g_has_tracking_override = 0;
    pthread_mutex_unlock(&g_tracking_mutex);
}

void vrmc_shared_clear_eye_textures(void) {
    pthread_mutex_lock(&g_frame_mutex);
    memset(&g_latest_frame, 0, sizeof(g_latest_frame));
    g_has_frame = 0;
    g_publish_sequence = 0;
    g_texture_generation = 0;
    pthread_mutex_unlock(&g_frame_mutex);
}

int32_t vrmc_shared_set_display_views(const vrmc_display_views *views) {
    if (views == NULL) return set_error("bad display views");
    vrmc_display_views copy = *views;
    copy.generation = 0;
    pthread_mutex_lock(&g_display_views_mutex);
    if (g_display_generation != 0 &&
        memcmp((const char *)&copy + sizeof(uint32_t),
               (const char *)&g_display_views + sizeof(uint32_t),
               sizeof(copy) - sizeof(uint32_t)) == 0) {
        pthread_mutex_unlock(&g_display_views_mutex);
        return 0; /* unchanged */
    }
    copy.generation = ++g_display_generation;
    g_display_views = copy;
    pthread_mutex_unlock(&g_display_views_mutex);
    return 0;
}

uint32_t vrmc_shared_get_display_views(vrmc_display_views *out) {
    if (out == NULL) return 0;
    pthread_mutex_lock(&g_display_views_mutex);
    *out = g_display_views;
    uint32_t gen = g_display_generation;
    pthread_mutex_unlock(&g_display_views_mutex);
    return gen;
}

/* ------------------------------------------------------------------------------------------- */
/* M4-W1 native-shared input channel (vrmc_native_shared.h "Input" section).                    */
/* ------------------------------------------------------------------------------------------- */

/* Publish one per-frame input snapshot (compositor thread only). Allowed before vrmc_init: the
 * compositor can start the immersive space before the JVM provider initializes, and an early publish
 * must not be "rejected" (that could drop the release-on-exit snapshot). Only a NULL state fails. */
int32_t vrmc_shared_publish_input(const vrmc_input_state *state) {
    if (state == NULL) return set_error("bad input state");
    pthread_mutex_lock(&g_input_mutex);
    g_input_state = *state;
    g_has_input_publish = 1;
    g_input_sequence++;
    pthread_mutex_unlock(&g_input_mutex);
    return 0;
}

/* Acquire the latest snapshot (JVM/other threads). Fails closed before the first publish; consumers
 * that need the documented pre-publish zero state use vrmc_poll_input (the Java ABI path). */
int32_t vrmc_shared_acquire_input(vrmc_input_state *out) {
    if (out == NULL) return set_error("bad input state output");
    pthread_mutex_lock(&g_input_mutex);
    if (!g_has_input_publish) {
        pthread_mutex_unlock(&g_input_mutex);
        return set_error("no input published yet");
    }
    *out = g_input_state;
    pthread_mutex_unlock(&g_input_mutex);
    return 0;
}

/* Monotonic publish counter (0 before the first publish, 1 after the first successful publish).
 * Consumers use it only for change/staleness detection, never as a clock. */
uint64_t vrmc_shared_input_sequence(void) {
    pthread_mutex_lock(&g_input_mutex);
    uint64_t seq = g_input_sequence;
    pthread_mutex_unlock(&g_input_mutex);
    return seq;
}

typedef void (*PFN_vrmc_vkGetMTLTextureMVK)(uint64_t image, void **out_texture);

static PFN_vrmc_vkGetMTLTextureMVK resolve_get_mtl_texture(void) {
    static PFN_vrmc_vkGetMTLTextureMVK fn;
    if (fn != NULL) return fn;
    fn = (PFN_vrmc_vkGetMTLTextureMVK)dlsym(RTLD_DEFAULT, "vkGetMTLTextureMVK");
    if (fn != NULL) return fn;
    const char *bundle = getenv("BUNDLE_PATH");
    char path[4096];
    if (bundle != NULL) {
        snprintf(path, sizeof(path), "%s/Frameworks/libMoltenVK.dylib", bundle);
        void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (h == NULL) {
            snprintf(path, sizeof(path), "%s/libMoltenVK.dylib", bundle);
            h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        }
        if (h != NULL) fn = (PFN_vrmc_vkGetMTLTextureMVK)dlsym(h, "vkGetMTLTextureMVK");
    }
    return fn;
}

int32_t vrmc_export_mtl_texture(uint64_t vk_image, uint64_t *out_mtl_texture) {
    if (!g_initialized) return set_error("not initialized");
    if (vk_image == 0 || out_mtl_texture == NULL) return set_error("bad export arguments");
    PFN_vrmc_vkGetMTLTextureMVK fn = resolve_get_mtl_texture();
    if (fn == NULL) return set_error("vkGetMTLTextureMVK unavailable (MoltenVK missing)");
    void *texture = NULL;
    fn(vk_image, &texture);
    if (texture == NULL) return set_error("vkGetMTLTextureMVK returned null (image not exported)");
    *out_mtl_texture = (uint64_t)(uintptr_t)texture;
    return 0;
}

int32_t vrmc_frame_timing(vrmc_frame_timing_t *out) {
    if (!g_initialized) return set_error("not initialized");
    if (out == NULL) return set_error("out is null");
    pthread_mutex_lock(&g_frame_mutex);
    uint64_t frames = g_frames;
    pthread_mutex_unlock(&g_frame_mutex);
    memset(out, 0, sizeof(*out));
    out->frame_index = (uint32_t)frames;
    return 0;
}

int32_t vrmc_recenter(int32_t mode) {
    if (!g_initialized) return set_error("not initialized");
    printf("[vrmc-stub] recenter mode=%d\n", mode);
    return 0;
}

int32_t vrmc_haptic(int32_t hand, float amplitude, float frequency_hz, float duration_s) {
    if (!g_initialized) return set_error("not initialized");
    printf("[vrmc-stub] haptic hand=%d amp=%.2f freq=%.1f dur=%.3f\n",
           hand, amplitude, frequency_hz, duration_s);
    return 0;
}

#ifdef VRMC_STUB_TEST
int main(void) {
    vrmc_tracking_state t;
    vrmc_eye_targets e;
    vrmc_input_state in;
    memset(&e, 0, sizeof(e));
    vrmc_frame_timing_t ft;
    if (vrmc_abi_version() != VRMC_ABI_VERSION) return 1;
    /* ABI v3 handshake: a v2 caps string must FAIL CLOSED; v3 must be accepted. */
    if (vrmc_init("{\"abi\":2,\"eyes\":2,\"hands\":2,\"input\":1}",
                  strlen("{\"abi\":2,\"eyes\":2,\"hands\":2,\"input\":1}")) == 0) {
        printf("abi 2 init must fail (got OK)\n"); return 2;
    }
    if (vrmc_poll_input(&in, sizeof(in)) == 0) { printf("poll input before init must fail\n"); return 23; }
    /* Pre-init publication is allowed (compositor may open the immersive space first)... */
    vrmc_input_state pre;
    memset(&pre, 0, sizeof(pre));
    pre.valid_mask = 3;
    if (vrmc_shared_publish_input(&pre) != 0) {
        printf("pre-init publish must be allowed: %s\n", vrmc_last_error()); return 24;
    }
    if (vrmc_shared_input_sequence() != 1) { printf("pre-init publish did not bump the sequence\n"); return 25; }
    /* ...and vrmc_init drops it so the first poll is the safe zero snapshot. */
    if (vrmc_init("{\"abi\":3,\"eyes\":2,\"hands\":2,\"input\":1}",
                  strlen("{\"abi\":3,\"eyes\":2,\"hands\":2,\"input\":1}")) != 0) {
        printf("init fail: %s\n", vrmc_last_error()); return 2;
    }
    vrmc_eye_targets shared;
    vrmc_shared_eye_frame frame;
    if (vrmc_shared_eye_textures(&shared) == 0) { printf("shared eyes before submit should fail\n"); return 6; }
    if (vrmc_shared_acquire_eyes(&frame) == 0) { printf("acquire before submit should fail\n"); return 14; }
    vrmc_tracking_state ov;
    memset(&ov, 0, sizeof(ov));
    ov.head.position.x = 1.25f;
    ov.ipd_m = 0.063f;
    if (vrmc_shared_set_tracking(&ov) != 0) { printf("set tracking fail: %s\n", vrmc_last_error()); return 7; }
    e.frame_index = 1; e.left_texture = 0xAAA; e.right_texture = 0xBBB;
    e.left_width = e.right_width = 1024; e.left_height = e.right_height = 1024;
    e.left_fov[0] = -1.0f; e.left_fov[1] = 1.0f; e.left_fov[2] = 1.0f; e.left_fov[3] = -1.0f;
    e.right_fov[0] = -1.0f; e.right_fov[1] = 1.0f; e.right_fov[2] = 1.0f; e.right_fov[3] = -1.0f;
    if (vrmc_submit_eyes(&e) != 0) { printf("submit fail: %s\n", vrmc_last_error()); return 3; }
    if (vrmc_get_tracking(&t, 123) != 0) return 4;
    if (vrmc_frame_timing(&ft) != 0) return 5;
    vrmc_shared_clear_eye_textures();
    if (vrmc_shared_eye_textures(&shared) == 0) { printf("shared eyes not cleared\n"); return 14; }
    e.frame_index = 2; e.left_texture = 0xAAA; e.right_texture = 0xBBB;
    if (vrmc_submit_eyes(&e) != 0) { printf("resubmit fail: %s\n", vrmc_last_error()); return 3; }
    if (vrmc_shared_eye_textures(&shared) != 0 || shared.left_texture != 0xAAA || shared.right_texture != 0xBBB) {
        printf("shared eyes after submit failed\n"); return 8;
    }
    /* Atomic acquire: eyes + sequence + texture generation + sync in one copy. */
    if (vrmc_shared_acquire_eyes(&frame) != 0 || frame.eyes.left_texture != 0xAAA ||
        frame.publish_sequence != 1 || frame.texture_generation != 1 || frame.sync.valid != 0) {
        printf("acquire after submit failed\n"); return 15;
    }
    vrmc_shared_frame_sync sync;
    memset(&sync, 0, sizeof(sync));
    sync.shared_event = 0xE7E7; sync.signal_value = 42; sync.frame_index = 2; sync.valid = 1;
    e.frame_index = 2;
    if (vrmc_shared_publish_eyes(&e, &sync) != 0) { printf("synced publish failed: %s\n", vrmc_last_error()); return 16; }
    if (vrmc_shared_acquire_eyes(&frame) != 0 || frame.publish_sequence != 2 ||
        frame.texture_generation != 1 || frame.sync.valid != 1 ||
        frame.sync.shared_event != 0xE7E7 || frame.sync.signal_value != 42) {
        printf("synced acquire failed\n"); return 17;
    }
    vrmc_shared_frame_sync got;
    if (vrmc_shared_get_frame_sync(&got) != 0 || got.signal_value != 42) { printf("frame sync getter failed\n"); return 18; }
    /* Texture generation bumps when the render targets are replaced... */
    e.left_texture = 0xCCC; e.right_texture = 0xDDD;
    if (vrmc_shared_publish_eyes(&e, NULL) != 0) { printf("generation publish failed\n"); return 19; }
    if (vrmc_shared_acquire_eyes(&frame) != 0 || frame.publish_sequence != 3 ||
        frame.texture_generation != 2 || frame.sync.valid != 0) {
        printf("texture generation did not bump on handle change\n"); return 20;
    }
    /* ...but not when the handles are unchanged. */
    if (vrmc_shared_publish_eyes(&e, NULL) != 0) { printf("repeat publish failed\n"); return 21; }
    if (vrmc_shared_acquire_eyes(&frame) != 0 || frame.publish_sequence != 4 ||
        frame.texture_generation != 2) {
        printf("texture generation bumped without a handle change\n"); return 22;
    }
    if (t.head.position.x != 1.25f || t.ipd_m != 0.063f) { printf("tracking override not honored\n"); return 9; }
    vrmc_shared_clear_tracking();
    if (vrmc_get_tracking(&t, 456) != 0 || t.ipd_m != 0.064f) { printf("tracking clear failed\n"); return 10; }
    vrmc_display_views dv; memset(&dv, 0, sizeof(dv));
    dv.left_tangents[0] = -1.0f; dv.left_tangents[1] = 1.0f; dv.left_tangents[2] = 1.0f; dv.left_tangents[3] = -1.0f;
    dv.right_tangents[0] = -1.0f; dv.right_tangents[1] = 1.0f; dv.right_tangents[2] = 1.0f; dv.right_tangents[3] = -1.0f;
    dv.ipd_m = 0.063f;
    if (vrmc_shared_set_display_views(&dv) != 0) { printf("set display views failed\n"); return 11; }
    if (vrmc_shared_get_display_views(&dv) == 0 || dv.ipd_m != 0.063f) { printf("display views not honored\n"); return 12; }
    uint32_t gen1 = vrmc_shared_get_display_views(&dv);
    if (vrmc_shared_set_display_views(&dv) != 0 || vrmc_shared_get_display_views(&dv) != gen1) {
        printf("display views generation changed without payload change\n"); return 13;
    }
    /* ABI v3 input channel: safe zero before publish, round-trip, sequence, release snapshot. */
    memset(&in, 0xAA, sizeof(in));
    if (vrmc_poll_input(&in, sizeof(in)) != 0) {
        printf("poll input pre-publish failed: %s\n", vrmc_last_error()); return 26;
    }
    for (size_t i = 0; i < sizeof(in); i++) {
        if (((const unsigned char *)&in)[i] != 0) { printf("pre-publish input snapshot not zeroed\n"); return 27; }
    }
    if (vrmc_shared_input_sequence() != 0) { printf("input sequence not reset by init\n"); return 28; }
    if (vrmc_shared_acquire_input(&in) == 0) { printf("acquire input before publish must fail\n"); return 29; }
    if (vrmc_poll_input(NULL, sizeof(in)) == 0) { printf("poll input with NULL must fail\n"); return 30; }
    if (vrmc_poll_input(&in, sizeof(in) - 1) == 0) { printf("poll input with short buffer must fail\n"); return 31; }
    vrmc_input_state ipub;
    memset(&ipub, 0, sizeof(ipub));
    ipub.frame_index = 7;
    ipub.valid_mask = 3;
    ipub.timestamp_ns = 0x1122334455667788ull;
    ipub.hands[0].tracked = 1;
    ipub.hands[0].chirality = 0; /* ARKit: 0 = left */
    ipub.hands[1].tracked = 1;
    ipub.hands[1].chirality = 1; /* ARKit: 1 = right */
    ipub.hands[1].wrist_position.x = 0.125f;
    ipub.hands[0].joints[9].y = 0.75f;
    if (vrmc_shared_publish_input(&ipub) != 0) {
        printf("publish input failed: %s\n", vrmc_last_error()); return 32;
    }
    if (vrmc_shared_input_sequence() != 1) { printf("input sequence after publish != 1\n"); return 33; }
    memset(&in, 0, sizeof(in));
    if (vrmc_poll_input(&in, sizeof(in)) != 0 || memcmp(&in, &ipub, sizeof(in)) != 0) {
        printf("input poll round-trip mismatch\n"); return 34;
    }
    if (vrmc_shared_acquire_input(&in) != 0 || memcmp(&in, &ipub, sizeof(in)) != 0) {
        printf("input acquire round-trip mismatch\n"); return 35;
    }
    vrmc_input_state release;
    memset(&release, 0, sizeof(release)); /* release-on-exit shape: valid_mask = 0, hands untracked */
    if (vrmc_shared_publish_input(&release) != 0) { printf("release publish failed\n"); return 36; }
    if (vrmc_poll_input(&in, sizeof(in)) != 0 || in.valid_mask != 0 || in.frame_index != 0) {
        printf("release snapshot not published\n"); return 37;
    }
    if (vrmc_shared_input_sequence() != 2) { printf("input sequence after release != 2\n"); return 38; }
    printf("[vrmc-stub-test] ok version=%d frames=%llu ipd=%.3f shared_left=0x%llx display_gen=%u "
           "publish_seq=%llu texture_gen=%u input_seq=%llu\n",
           vrmc_abi_version(), (unsigned long long)ft.frame_index, t.ipd_m,
           (unsigned long long)shared.left_texture, gen1,
           (unsigned long long)frame.publish_sequence, frame.texture_generation,
           (unsigned long long)vrmc_shared_input_sequence());
    return 0;
}
#endif
