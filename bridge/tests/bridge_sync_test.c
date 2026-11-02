/*
 * Host test for the VRMC bridge eye-frame handoff (bridge/tests, no device, no Metal).
 *
 * Exercises the additive native-shared API in bridge/abi/vrmc_native_shared.h:
 *   - publish/acquire protocol, publish_sequence, texture_generation, sync round-trip;
 *   - concurrent producer/consumer behavior (1 writer thread, N reader threads) under the bridge
 *     mutex, asserting that no reader ever observes a torn frame;
 *   - concurrent tracking override + display-view publication against the JVM-render-thread reader.
 *
 * Build/run:  bridge/tests/run_tests.sh  (includes a ThreadSanitizer build).
 */
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* --- ABI/Java layout invariants (mirror of VrmcBridge.java / VisionVR.java) ------------------ */
/* VrmcBridge.TRACKING_BYTES = 8 + 28 + 28 + 28 + 4 = 96; VisionVR reads head@8, c0@36, c1@64, ipd@92. */
_Static_assert(sizeof(vrmc_tracking_state) == 96, "tracking state size changed; bump Java constant");
_Static_assert(offsetof(vrmc_tracking_state, head) == 8, "tracking head offset");
_Static_assert(offsetof(vrmc_tracking_state, controllers) == 36, "tracking controllers offset");
_Static_assert(offsetof(vrmc_tracking_state, ipd_m) == 92, "tracking ipd offset");
/* VrmcBridge.DISPLAY_VIEWS_BYTES = 164 = sizeof(vrmc_display_views) - sizeof(uint32_t generation). */
_Static_assert(sizeof(vrmc_display_views) == 168, "display views size changed; bump Java constant");
_Static_assert(offsetof(vrmc_display_views, left_tangents) == 4, "display views left tangents offset");
/* vrmc_eye_targets is the Java ABI v2 struct: left/right MTLTexture handles at offsets 16/24. */
_Static_assert(sizeof(vrmc_eye_targets) == 80, "eye targets size changed; ABI v2 layout");
_Static_assert(offsetof(vrmc_eye_targets, left_texture) == 16, "eye targets left texture offset");
_Static_assert(offsetof(vrmc_eye_targets, right_texture) == 24, "eye targets right texture offset");
_Static_assert(offsetof(vrmc_eye_targets, left_fov) == 48, "eye targets left fov offset");
_Static_assert(sizeof(vrmc_shared_frame_sync) == 24, "frame sync struct layout");
_Static_assert(sizeof(vrmc_shared_eye_frame) == 120, "shared eye frame struct layout");

static int g_failures = 0;

#define CHECK(cond, ...) do {     if (!(cond)) {         printf("FAIL %s:%d: ", __FILE__, __LINE__);         printf(__VA_ARGS__);         printf("\n");         g_failures++;     } } while (0)

#define EYES_LEFT_TAG  0xA000000000000000ull
#define EYES_RIGHT_TAG 0xB000000000000000ull
#define SYNC_EVENT_TAG 0xCAFEF00DDEADBEEFull

static int init_bridge(void) {
    /* ABI v3 is current; this test only exercises the v2 eye-frame handoff surface. */
    static const char *caps = "{\"abi\":3,\"eyes\":2}";
    int rc = vrmc_init(caps, strlen(caps));
    if (rc != 0) {
        printf("FAIL init: %s\n", vrmc_last_error());
        return rc;
    }
    return 0;
}

/* 1. Protocol: nothing published -> acquire fails; publish -> exact copy; generation semantics. */
static void test_protocol(void) {
    if (init_bridge() != 0) { g_failures++; return; }
    vrmc_shared_eye_frame frame;
    CHECK(vrmc_shared_acquire_eyes(&frame) != 0, "acquire must fail before any publish");
    CHECK(vrmc_shared_get_frame_sync(&frame.sync) != 0, "frame sync getter must fail before any publish");

    vrmc_eye_targets eyes;
    memset(&eyes, 0, sizeof(eyes));
    eyes.frame_index = 1;
    eyes.left_texture = 0x1111;
    eyes.right_texture = 0x2222;
    eyes.left_width = eyes.right_width = 1024;
    eyes.left_height = eyes.right_height = 1024;
    eyes.left_fov[0] = -1.0f; eyes.left_fov[1] = 1.0f; eyes.left_fov[2] = 1.0f; eyes.left_fov[3] = -1.0f;
    memcpy(eyes.right_fov, eyes.left_fov, sizeof(eyes.left_fov));

    CHECK(vrmc_shared_publish_eyes(&eyes, NULL) == 0, "publish failed: %s", vrmc_last_error());
    CHECK(vrmc_shared_acquire_eyes(&frame) == 0, "acquire failed: %s", vrmc_last_error());
    CHECK(frame.eyes.left_texture == 0x1111 && frame.eyes.right_texture == 0x2222, "textures not copied");
    CHECK(frame.publish_sequence == 1, "publish_sequence=%llu want 1", (unsigned long long)frame.publish_sequence);
    CHECK(frame.texture_generation == 1, "texture_generation=%u want 1", frame.texture_generation);
    CHECK(frame.sync.valid == 0, "unsynchronized publish must have sync.valid=0");

    /* Same handles -> generation stable, sequence increments. */
    eyes.frame_index = 2;
    CHECK(vrmc_shared_publish_eyes(&eyes, NULL) == 0, "second publish failed");
    CHECK(vrmc_shared_acquire_eyes(&frame) == 0, "second acquire failed");
    CHECK(frame.publish_sequence == 2 && frame.texture_generation == 1,
          "same handles: seq=%llu gen=%u (want 2/1)",
          (unsigned long long)frame.publish_sequence, frame.texture_generation);

    /* New handles -> generation bumps (framebuffer reinit detection). */
    eyes.left_texture = 0x3333;
    eyes.right_texture = 0x4444;
    eyes.frame_index = 3;
    CHECK(vrmc_shared_publish_eyes(&eyes, NULL) == 0, "third publish failed");
    CHECK(vrmc_shared_acquire_eyes(&frame) == 0, "third acquire failed");
    CHECK(frame.publish_sequence == 3 && frame.texture_generation == 2,
          "handle change: seq=%llu gen=%u (want 3/2)",
          (unsigned long long)frame.publish_sequence, frame.texture_generation);

    /* Sync round-trip. */
    vrmc_shared_frame_sync sync;
    memset(&sync, 0, sizeof(sync));
    sync.shared_event = SYNC_EVENT_TAG;
    sync.signal_value = 77;
    sync.frame_index = 4;
    sync.valid = 1;
    eyes.frame_index = 4;
    CHECK(vrmc_shared_publish_eyes(&eyes, &sync) == 0, "synced publish failed: %s", vrmc_last_error());
    CHECK(vrmc_shared_acquire_eyes(&frame) == 0, "synced acquire failed");
    CHECK(frame.sync.valid == 1 && frame.sync.shared_event == SYNC_EVENT_TAG && frame.sync.signal_value == 77 &&
          frame.sync.frame_index == 4, "sync pair not copied exactly");
    CHECK(frame.publish_sequence == 4 && frame.texture_generation == 2, "sequence/generation after synced publish");
    vrmc_shared_frame_sync got;
    CHECK(vrmc_shared_get_frame_sync(&got) == 0 && got.shared_event == SYNC_EVENT_TAG && got.signal_value == 77,
          "frame sync getter mismatch");

    /* Invalid sync pair fails closed instead of publishing a half-populated pair. */
    sync.shared_event = 0;
    CHECK(vrmc_shared_publish_eyes(&eyes, &sync) != 0, "publish with valid=1 and event=0 must fail");
    sync.valid = 0;
    CHECK(vrmc_shared_publish_eyes(&eyes, &sync) == 0, "unsynchronized sync struct must publish");

    /* Legacy accessor stays compatible. */
    vrmc_eye_targets legacy;
    CHECK(vrmc_shared_eye_textures(&legacy) == 0 && legacy.left_texture == 0x3333 &&
          legacy.right_texture == 0x4444, "legacy vrmc_shared_eye_textures mismatch");
    printf("[bridge-sync-test] protocol: PASS\n");
}

/* 2. Concurrent producer/consumer: a reader must never observe mismatched fields. */
#define STRESS_FRAMES 200000
#define STRESS_READERS 4

typedef struct {
    atomic_int stop;
    atomic_ulong acquisitions;
    atomic_int torn;
} StressState;

static void *frame_reader(void *arg) {
    StressState *st = (StressState *)arg;
    uint64_t last_seq = 0;
    while (!atomic_load(&st->stop)) {
        vrmc_shared_eye_frame f;
        if (vrmc_shared_acquire_eyes(&f) != 0) continue;
        uint64_t tag = f.eyes.frame_index;
        if (f.eyes.left_texture != EYES_LEFT_TAG + tag ||
            f.eyes.right_texture != EYES_RIGHT_TAG + tag ||
            f.sync.signal_value != tag ||
            f.sync.frame_index != (uint32_t)tag ||
            f.sync.valid != 1 ||
            f.sync.shared_event != SYNC_EVENT_TAG ||
            f.publish_sequence != tag ||
            f.eyes.left_width != 1024 || f.eyes.right_height != 1024) {
            atomic_fetch_add(&st->torn, 1);
        }
        if (f.publish_sequence < last_seq) atomic_fetch_add(&st->torn, 1);
        last_seq = f.publish_sequence;
        atomic_fetch_add(&st->acquisitions, 1);
    }
    return NULL;
}

static void test_concurrent_frames(void) {
    if (init_bridge() != 0) { g_failures++; return; }
    StressState st;
    memset(&st, 0, sizeof(st));
    pthread_t readers[STRESS_READERS];
    for (int i = 0; i < STRESS_READERS; i++) pthread_create(&readers[i], NULL, frame_reader, &st);
    int publish_failures = 0;
    for (uint64_t seq = 1; seq <= STRESS_FRAMES; seq++) {
        vrmc_eye_targets eyes;
        memset(&eyes, 0, sizeof(eyes));
        eyes.frame_index = (uint32_t)seq;
        eyes.left_texture = EYES_LEFT_TAG + seq;
        eyes.right_texture = EYES_RIGHT_TAG + seq;
        eyes.left_width = eyes.right_width = 1024;
        eyes.left_height = eyes.right_height = 1024;
        eyes.left_fov[0] = -1.0f; eyes.left_fov[1] = 1.0f; eyes.left_fov[2] = 1.0f; eyes.left_fov[3] = -1.0f;
        vrmc_shared_frame_sync sync;
        memset(&sync, 0, sizeof(sync));
        sync.shared_event = SYNC_EVENT_TAG;
        sync.signal_value = seq;
        sync.frame_index = (uint32_t)seq;
        sync.valid = 1;
        if (vrmc_shared_publish_eyes(&eyes, &sync) != 0) publish_failures++;
    }
    atomic_store(&st.stop, 1);
    for (int i = 0; i < STRESS_READERS; i++) pthread_join(readers[i], NULL);
    CHECK(publish_failures == 0, "publish failures: %d", publish_failures);
    CHECK(atomic_load(&st.torn) == 0, "torn frames observed: %d", atomic_load(&st.torn));
    CHECK(atomic_load(&st.acquisitions) > 0, "readers never acquired a frame");
    printf("[bridge-sync-test] concurrent frames (%llu publishes x %d readers, %lu acquires): PASS\n",
           (unsigned long long)STRESS_FRAMES, STRESS_READERS,
           (unsigned long)atomic_load(&st.acquisitions));
}

/* 3. Concurrent tracking override + display views (compositor thread -> JVM render thread). */
#define TRACKING_ITERS 500000

typedef struct {
    atomic_int stop;
    atomic_int torn;
    atomic_int reads;
} TrackState;

static void *tracking_reader(void *arg) {
    TrackState *st = (TrackState *)arg;
    while (!atomic_load(&st->stop)) {
        vrmc_tracking_state t;
        if (vrmc_get_tracking(&t, 0) != 0) continue;
        uint64_t tag = t.presentation_time_ns;
        /* The writer encodes the same token in the head position and both controller positions:
         * a torn 96-byte copy would mix tokens. */
        if ((uint64_t)(int64_t)t.head.position.x != tag ||
            (uint64_t)(int64_t)t.controllers[0].position.x != tag ||
            (uint64_t)(int64_t)t.controllers[1].position.x != tag ||
            t.head.orientation.w != 1.0f) {
            atomic_fetch_add(&st->torn, 1);
        }
        atomic_fetch_add(&st->reads, 1);
    }
    return NULL;
}

static void test_concurrent_tracking(void) {
    if (init_bridge() != 0) { g_failures++; return; }
    TrackState st;
    memset(&st, 0, sizeof(st));
    pthread_t reader;
    pthread_create(&reader, NULL, tracking_reader, &st);
    int torn_views = 0;
    for (uint64_t i = 1; i <= TRACKING_ITERS; i++) {
        vrmc_tracking_state t;
        memset(&t, 0, sizeof(t));
        t.presentation_time_ns = i;
        t.head.position.x = (float)i;
        t.head.orientation.w = 1.0f;
        t.controllers[0].position.x = (float)i;
        t.controllers[0].orientation.w = 1.0f;
        t.controllers[1].position.x = (float)i;
        t.controllers[1].orientation.w = 1.0f;
        t.ipd_m = 0.064f;
        if (vrmc_shared_set_tracking(&t) != 0) torn_views++;
        if ((i % 64) == 0) {
            vrmc_display_views dv;
            memset(&dv, 0, sizeof(dv));
            dv.ipd_m = (float)i;
            dv.left_eye_to_head[0] = -(float)i;
            vrmc_shared_set_display_views(&dv);
            vrmc_display_views got;
            if (vrmc_shared_get_display_views(&got) != 0) {
                /* A torn display-view copy would mix the ipd token with the matrix token. */
                if (got.ipd_m != -got.left_eye_to_head[0]) torn_views++;
            }
        }
    }
    atomic_store(&st.stop, 1);
    pthread_join(reader, NULL);
    CHECK(atomic_load(&st.torn) == 0, "torn tracking reads: %d", atomic_load(&st.torn));
    CHECK(atomic_load(&st.reads) > 0, "tracking reader never read");
    CHECK(torn_views == 0, "display-view coherence failures: %d", torn_views);
    printf("[bridge-sync-test] concurrent tracking+display views (%llu writes, %lu reads): PASS\n",
           (unsigned long long)TRACKING_ITERS, (unsigned long)atomic_load(&st.reads));
}

int main(void) {
    printf("[bridge-sync-test] bridge=%s abi=%d\n",
           "libvrmc_bridge(stub)", vrmc_abi_version());
    test_protocol();
    test_concurrent_frames();
    test_concurrent_tracking();
    if (g_failures != 0) {
        printf("[bridge-sync-test] FAILED (%d checks)\n", g_failures);
        return 1;
    }
    printf("[bridge-sync-test] ALL PASS\n");
    return 0;
}
