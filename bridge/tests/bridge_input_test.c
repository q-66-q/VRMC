/*
 * Host test for the VRMC bridge ABI v3 immersive input channel (M4-W1, no device, no Metal).
 *
 * Contract under test (bridge/abi/vrmc_abi.h + bridge/abi/vrmc_native_shared.h +
 * docs/analysis/immersive-input.md §3):
 *   - vrmc_hand_state = 368 B, vrmc_input_state = 752 B and every documented offset/stride
 *     (compile-time static asserts; a layout drift is a compile error);
 *   - vrmc_poll_input: fail closed on uninitialized bridge / NULL / short buffer; safe ZEROED
 *     snapshot before the compositor ever published; exact copy afterwards; accepts a larger buffer
 *     without touching the tail;
 *   - native-shared vrmc_shared_publish_input / vrmc_shared_acquire_input / vrmc_shared_input_sequence:
 *     round-trip, monotonic sequence (starts at 1), release snapshot (valid_mask = 0);
 *   - pre-init publication is allowed (the compositor may open the immersive space before the JVM
 *     provider initializes) and vrmc_init resets the channel to the safe zero state;
 *   - ABI version handshake: v2 caps fail closed, v3 caps accepted;
 *   - 1 writer x N reader torn-snapshot detection over 500k publishes (also run under
 *     ThreadSanitizer by bridge/tests/run_tests.sh).
 *
 * Build/run: bridge/tests/run_tests.sh (normal + TSan). Zero-failure exit code; any check failure
 * prints "FAIL <file>:<line> ..." and the process exits 1.
 */
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* --- ABI v3 layout invariants (must match VrmcBridge.java / VisionInput.java / design doc §3) --- */
_Static_assert(sizeof(vrmc_vec3) == 12, "vrmc_vec3 must stay 3 packed floats");
_Static_assert(sizeof(vrmc_quat) == 16, "vrmc_quat must stay 4 packed floats");
_Static_assert(sizeof(vrmc_hand_state) == 368, "vrmc_hand_state size changed; ABI bump + Java constants");
_Static_assert(offsetof(vrmc_hand_state, tracked) == 0, "hand.tracked offset");
_Static_assert(offsetof(vrmc_hand_state, chirality) == 4, "hand.chirality offset");
_Static_assert(offsetof(vrmc_hand_state, timestamp_ns) == 8, "hand.timestamp_ns offset");
_Static_assert(offsetof(vrmc_hand_state, wrist_orientation) == 16, "hand.wrist_orientation offset");
_Static_assert(offsetof(vrmc_hand_state, wrist_position) == 32, "hand.wrist_position offset");
_Static_assert(offsetof(vrmc_hand_state, joints) == 44, "hand.joints offset");
_Static_assert(sizeof(((vrmc_hand_state *)0)->joints[0]) == 12, "joint stride must be 12");
_Static_assert(sizeof(vrmc_input_state) == 752, "vrmc_input_state size changed; ABI bump + Java constants");
_Static_assert(offsetof(vrmc_input_state, frame_index) == 0, "input.frame_index offset");
_Static_assert(offsetof(vrmc_input_state, valid_mask) == 4, "input.valid_mask offset");
_Static_assert(offsetof(vrmc_input_state, timestamp_ns) == 8, "input.timestamp_ns offset");
_Static_assert(offsetof(vrmc_input_state, hands) == 16, "input.hands offset");
_Static_assert(offsetof(vrmc_input_state, hands[1]) == 384, "input.hands[1] offset (HAND_STRIDE)");
_Static_assert(VRMC_HAND_JOINT_COUNT == 27, "27 ARKit joints");
_Static_assert(VRMC_INPUT_HAND_COUNT == 2, "two hands");
_Static_assert(VRMC_INPUT_LEFT_HAND == 0 && VRMC_INPUT_RIGHT_HAND == 1, "hands[0]=left, hands[1]=right");

static int g_failures = 0;

#define CHECK(cond, ...) do { \
    if (!(cond)) { \
        printf("FAIL %s:%d: ", __FILE__, __LINE__); \
        printf(__VA_ARGS__); \
        printf("\n"); \
        g_failures++; \
    } \
} while (0)

static const char *CAPS_V3 = "{\"abi\":3,\"eyes\":2,\"hands\":2,\"input\":1}";
static const char *CAPS_V2 = "{\"abi\":2,\"eyes\":2,\"hands\":2,\"input\":1}";

static int init_bridge(void) {
    int rc = vrmc_init(CAPS_V3, strlen(CAPS_V3));
    if (rc != 0) {
        printf("FAIL init v3: %s\n", vrmc_last_error());
        return rc;
    }
    return 0;
}

static int is_zero(const void *p, size_t n) {
    const unsigned char *b = (const unsigned char *)p;
    for (size_t i = 0; i < n; i++) {
        if (b[i] != 0) return 0;
    }
    return 1;
}

/* Fill a snapshot whose every field encodes the token, so a torn copy is detectable. */
static void fill_tagged_state(vrmc_input_state *s, uint32_t token) {
    memset(s, 0, sizeof(*s));
    s->frame_index = token;
    s->valid_mask = 3;
    s->timestamp_ns = (uint64_t)token;
    for (int h = 0; h < VRMC_INPUT_HAND_COUNT; h++) {
        vrmc_hand_state *hand = &s->hands[h];
        hand->tracked = 1;
        hand->chirality = (uint32_t)h; /* 0 = left, 1 = right */
        hand->timestamp_ns = (uint64_t)token;
        hand->wrist_orientation.x = 0.0f;
        hand->wrist_orientation.y = 0.0f;
        hand->wrist_orientation.z = 0.0f;
        hand->wrist_orientation.w = 1.0f;
        hand->wrist_position.x = (float)token;
        hand->wrist_position.y = 1.0f;
        hand->wrist_position.z = -1.0f;
        for (int j = 0; j < VRMC_HAND_JOINT_COUNT; j++) {
            hand->joints[j].x = (float)token;
            hand->joints[j].y = (float)j;
            hand->joints[j].z = (float)(h * 100 + j);
        }
    }
}

/* Coherence check: all token-bearing fields must agree, and the hand slots/chirality must be right. */
static int state_is_coherent(const vrmc_input_state *s, uint64_t *out_token) {
    if (s->valid_mask != 3) return 0;
    if (s->hands[0].chirality != 0 || s->hands[1].chirality != 1) return 0;
    if (s->hands[0].tracked != 1 || s->hands[1].tracked != 1) return 0;
    if (s->timestamp_ns != (uint64_t)s->frame_index) return 0;
    if (s->hands[0].timestamp_ns != s->timestamp_ns) return 0;
    if (s->hands[1].timestamp_ns != s->timestamp_ns) return 0;
    float f = (float)s->frame_index;
    if (s->hands[0].wrist_position.x != f || s->hands[1].wrist_position.x != f) return 0;
    /* Sample the joint array (first/last + a mid index per hand): a torn 752-byte copy would mix. */
    for (int j = 0; j < VRMC_HAND_JOINT_COUNT; j++) {
        if (j != 0 && j != 9 && j != 26) continue;
        for (int h = 0; h < VRMC_INPUT_HAND_COUNT; h++) {
            const vrmc_hand_state *hand = &s->hands[h];
            if (hand->joints[j].x != f) return 0;
            if (hand->joints[j].y != (float)j) return 0;
            if (hand->joints[j].z != (float)(h * 100 + j)) return 0;
        }
    }
    *out_token = s->timestamp_ns;
    return 1;
}

/* 1. Pre-init behavior, ABI handshake and init reset. Must run first (process is fresh). */
static void test_before_init(void) {
    vrmc_input_state in;
    CHECK(vrmc_abi_version() == 3, "abi version %d (want 3)", vrmc_abi_version());
    CHECK(vrmc_poll_input(&in, sizeof(in)) != 0, "poll before init must fail closed");
    CHECK(vrmc_shared_acquire_input(&in) != 0, "acquire before any publish must fail");

    /* The compositor may publish before the JVM provider calls vrmc_init; that is allowed. */
    vrmc_input_state pre;
    memset(&pre, 0, sizeof(pre));
    pre.frame_index = 1;
    pre.valid_mask = 3;
    CHECK(vrmc_shared_publish_input(&pre) == 0, "pre-init publish must be allowed: %s", vrmc_last_error());
    CHECK(vrmc_shared_input_sequence() == 1, "pre-init publish sequence=%llu (want 1)",
          (unsigned long long)vrmc_shared_input_sequence());
    CHECK(vrmc_shared_acquire_input(&in) == 0 && memcmp(&in, &pre, sizeof(pre)) == 0,
          "pre-init acquire round-trip mismatch");
    CHECK(vrmc_poll_input(&in, sizeof(in)) != 0, "poll must still fail before init");

    /* ABI v2 caps must fail closed (no cross-version compatibility window). */
    CHECK(vrmc_init(CAPS_V2, strlen(CAPS_V2)) != 0, "abi v2 init must fail closed");
    CHECK(vrmc_poll_input(&in, sizeof(in)) != 0, "poll must still fail after a rejected init");

    /* ABI v3 init accepted; it drops the pre-init snapshot and resets the sequence. */
    CHECK(vrmc_init(CAPS_V3, strlen(CAPS_V3)) == 0, "abi v3 init failed: %s", vrmc_last_error());
    CHECK(vrmc_shared_input_sequence() == 0, "init must reset the input sequence");
    CHECK(vrmc_shared_acquire_input(&in) != 0, "acquire after init reset must fail");
    memset(&in, 0xAA, sizeof(in));
    CHECK(vrmc_poll_input(&in, sizeof(in)) == 0, "poll after init failed: %s", vrmc_last_error());
    CHECK(is_zero(&in, sizeof(in)), "first poll after init must be the zeroed safe snapshot");
    printf("[bridge-input-test] before-init/reset/abi handshake: PASS\n");
}

/* 2. Safe zero snapshot before the compositor has ever published. */
static void test_pre_publish_zero(void) {
    if (init_bridge() != 0) { g_failures++; return; }
    vrmc_input_state in;
    memset(&in, 0xAA, sizeof(in));
    CHECK(vrmc_poll_input(&in, sizeof(in)) == 0, "poll before first publish failed: %s", vrmc_last_error());
    CHECK(is_zero(&in, sizeof(in)), "snapshot before first publish must be all zero");
    CHECK(in.valid_mask == 0 && in.hands[0].tracked == 0 && in.hands[1].tracked == 0,
          "pre-publish snapshot must report both hands untracked");
    vrmc_input_state acq;
    CHECK(vrmc_shared_acquire_input(&acq) != 0, "native acquire before first publish must fail");
    CHECK(vrmc_shared_input_sequence() == 0, "sequence before first publish must be 0");
    printf("[bridge-input-test] safe zero snapshot before first publish: PASS\n");
}

/* 3. Publish/acquire/poll round-trip, sequence monotonicity, release snapshot. */
static void test_roundtrip_sequence(void) {
    if (init_bridge() != 0) { g_failures++; return; }
    vrmc_input_state pub;
    fill_tagged_state(&pub, 42);
    CHECK(vrmc_shared_publish_input(&pub) == 0, "publish failed: %s", vrmc_last_error());
    CHECK(vrmc_shared_input_sequence() == 1, "sequence after first publish=%llu (want 1)",
          (unsigned long long)vrmc_shared_input_sequence());

    vrmc_input_state got;
    memset(&got, 0, sizeof(got));
    CHECK(vrmc_poll_input(&got, sizeof(got)) == 0, "poll after publish failed: %s", vrmc_last_error());
    CHECK(memcmp(&got, &pub, sizeof(pub)) == 0, "polled snapshot differs from the published one");
    memset(&got, 0, sizeof(got));
    CHECK(vrmc_shared_acquire_input(&got) == 0, "native acquire failed: %s", vrmc_last_error());
    CHECK(memcmp(&got, &pub, sizeof(pub)) == 0, "acquired snapshot differs from the published one");

    fill_tagged_state(&pub, 43);
    CHECK(vrmc_shared_publish_input(&pub) == 0, "second publish failed");
    CHECK(vrmc_shared_input_sequence() == 2, "sequence after second publish=%llu (want 2)",
          (unsigned long long)vrmc_shared_input_sequence());
    CHECK(vrmc_poll_input(&got, sizeof(got)) == 0 && got.frame_index == 43,
          "second publish not visible through poll");

    /* Release-on-exit snapshot: valid_mask = 0, everything else zeroed. Consumers must see no hands. */
    vrmc_input_state release;
    memset(&release, 0, sizeof(release));
    CHECK(vrmc_shared_publish_input(&release) == 0, "release publish failed");
    CHECK(vrmc_shared_input_sequence() == 3, "sequence after release=%llu (want 3)",
          (unsigned long long)vrmc_shared_input_sequence());
    CHECK(vrmc_poll_input(&got, sizeof(got)) == 0, "poll after release failed");
    CHECK(got.valid_mask == 0 && got.frame_index == 0 && got.timestamp_ns == 0 &&
          got.hands[0].tracked == 0 && got.hands[1].tracked == 0,
          "release snapshot must report no tracked hands (stuck-input safety)");
    printf("[bridge-input-test] publish/poll/acquire round-trip + sequence + release: PASS\n");
}

/* 4. Bad arguments: uninitialized/NULL/short buffers fail closed; larger buffers are accepted and
 *    the tail beyond sizeof(vrmc_input_state) is not modified. */
static void test_bad_buffers(void) {
    if (init_bridge() != 0) { g_failures++; return; }
    vrmc_input_state pub;
    fill_tagged_state(&pub, 7);
    CHECK(vrmc_shared_publish_input(&pub) == 0, "publish failed");

    vrmc_input_state in;
    CHECK(vrmc_poll_input(NULL, sizeof(in)) != 0, "NULL output must fail");
    CHECK(vrmc_poll_input(&in, 0) != 0, "zero-length output must fail");
    CHECK(vrmc_poll_input(&in, 1) != 0, "1-byte output must fail");
    CHECK(vrmc_poll_input(&in, sizeof(in) - 1) != 0, "751-byte output must fail (needs 752)");
    CHECK(vrmc_shared_publish_input(NULL) != 0, "NULL publish must fail");
    CHECK(vrmc_shared_acquire_input(NULL) != 0, "NULL acquire must fail");
    CHECK(vrmc_shared_input_sequence() == 1, "failed calls must not bump the sequence");
    /* Short buffer must not have written a partial snapshot. */
    memset(&in, 0xAA, sizeof(in));
    CHECK(vrmc_poll_input(&in, sizeof(in) - 1) != 0, "short output must fail");
    CHECK(!is_zero(&in, sizeof(in)) && ((unsigned char *)&in)[0] == 0xAA,
          "short-buffer poll must not write a partial snapshot");

    /* Exact size and larger buffers: copy exactly 752 bytes, leave the tail untouched. */
    CHECK(vrmc_poll_input(&in, sizeof(in)) == 0 && memcmp(&in, &pub, sizeof(pub)) == 0,
          "exact-size poll mismatch");
    unsigned char big[sizeof(vrmc_input_state) + 48];
    memset(big, 0xA5, sizeof(big));
    CHECK(vrmc_poll_input(big, sizeof(big)) == 0, "oversized poll failed: %s", vrmc_last_error());
    CHECK(memcmp(big, &pub, sizeof(pub)) == 0, "oversized poll body mismatch");
    int tail_touched = 0;
    for (size_t i = sizeof(vrmc_input_state); i < sizeof(big); i++) {
        if (big[i] != 0xA5) tail_touched++;
    }
    CHECK(tail_touched == 0, "poll wrote %d bytes past sizeof(vrmc_input_state)", tail_touched);
    printf("[bridge-input-test] NULL/short/uninitialized rejection + oversized buffer: PASS\n");
}

/* 5. Concurrent 1 writer x N readers: a reader must never observe a torn snapshot, and the publish
 *    sequence must never go backwards. 500k publishes by default. */
#define INPUT_STRESS_PUBLISHES 500000
#define INPUT_STRESS_READERS 4

typedef struct {
    atomic_int stop;
    atomic_ulong reads;
    atomic_int torn;
    atomic_int seq_regressions;
} InputStressState;

static void *input_reader(void *arg) {
    InputStressState *st = (InputStressState *)arg;
    uint64_t last_seq = 0;
    while (!atomic_load(&st->stop)) {
        vrmc_input_state a;
        if (vrmc_shared_acquire_input(&a) == 0) {
            uint64_t token = 0;
            if (!state_is_coherent(&a, &token)) atomic_fetch_add(&st->torn, 1);
            uint64_t seq = vrmc_shared_input_sequence();
            if (seq < last_seq) atomic_fetch_add(&st->seq_regressions, 1);
            last_seq = seq;
            atomic_fetch_add(&st->reads, 1);
        }
        vrmc_input_state p;
        if (vrmc_poll_input(&p, sizeof(p)) == 0) {
            uint64_t token = 0;
            /* Before the writer's first publish, poll must return the documented zeroed safe
             * snapshot; it is not a torn frame. */
            if (!is_zero(&p, sizeof(p)) && !state_is_coherent(&p, &token)) {
                atomic_fetch_add(&st->torn, 1);
            }
            atomic_fetch_add(&st->reads, 1);
        }
    }
    return NULL;
}

static void test_concurrent_input(void) {
    if (init_bridge() != 0) { g_failures++; return; }
    InputStressState st;
    memset(&st, 0, sizeof(st));
    pthread_t readers[INPUT_STRESS_READERS];
    for (int i = 0; i < INPUT_STRESS_READERS; i++) {
        CHECK(pthread_create(&readers[i], NULL, input_reader, &st) == 0, "reader thread create failed");
    }
    int publish_failures = 0;
    for (uint32_t i = 1; i <= INPUT_STRESS_PUBLISHES; i++) {
        vrmc_input_state s;
        fill_tagged_state(&s, i);
        if (vrmc_shared_publish_input(&s) != 0) publish_failures++;
    }
    atomic_store(&st.stop, 1);
    for (int i = 0; i < INPUT_STRESS_READERS; i++) pthread_join(readers[i], NULL);
    CHECK(publish_failures == 0, "publish failures: %d", publish_failures);
    CHECK(atomic_load(&st.torn) == 0, "torn input snapshots observed: %d", atomic_load(&st.torn));
    CHECK(atomic_load(&st.seq_regressions) == 0, "sequence regressions: %d", atomic_load(&st.seq_regressions));
    CHECK(atomic_load(&st.reads) > 0, "readers never observed a snapshot");
    CHECK(vrmc_shared_input_sequence() == INPUT_STRESS_PUBLISHES,
          "final sequence=%llu (want %u)", (unsigned long long)vrmc_shared_input_sequence(), INPUT_STRESS_PUBLISHES);
    printf("[bridge-input-test] concurrent (%u publishes x %d readers, %lu reads, no torn state): PASS\n",
           (unsigned int)INPUT_STRESS_PUBLISHES, INPUT_STRESS_READERS, (unsigned long)atomic_load(&st.reads));
}

int main(void) {
    printf("[bridge-input-test] bridge=libvrmc_bridge(stub) abi=%d sizeof(hand)=%zu sizeof(input)=%zu\n",
           vrmc_abi_version(), sizeof(vrmc_hand_state), sizeof(vrmc_input_state));
    test_before_init();
    test_pre_publish_zero();
    test_roundtrip_sequence();
    test_bad_buffers();
    test_concurrent_input();
    if (g_failures != 0) {
        printf("[bridge-input-test] FAILED (%d checks)\n", g_failures);
        return 1;
    }
    printf("[bridge-input-test] ALL PASS\n");
    return 0;
}
