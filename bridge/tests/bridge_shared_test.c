/*
 * Host concurrency test for the additive native-shared channels written after ABI v3:
 * display views, gaze mailbox, game-stopping signal and tracking override.
 *
 * One writer thread publishes display views/gaze/tracking/game-stopping while one reader thread
 * consumes them; checks generation monotonicity, payload sanity, gaze consumption and no crashes.
 * Also run under ThreadSanitizer by bridge/tests/run_tests.sh: any data race is fatal.
 */
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define PUBLISHES 20000
static _Atomic int g_failures;
static _Atomic int g_done;
static _Atomic int g_gaze_consumed;

static void fail(const char *what, long a, long b) {
    int n = atomic_fetch_add(&g_failures, 1);
    if (n < 20) printf("FAIL %s: %ld %ld\n", what, a, b);
}

static void *writer(void *arg) {
    (void)arg;
    for (int i = 0; i < PUBLISHES; i++) {
        vrmc_display_views dv;
        memset(&dv, 0, sizeof(dv));
        dv.left_tangents[0] = -1.7f; dv.left_tangents[1] = 1.0f;
        dv.left_tangents[2] = 1.0f; dv.left_tangents[3] = -1.2f;
        dv.right_tangents[0] = -1.0f; dv.right_tangents[1] = 1.7f;
        dv.right_tangents[2] = 1.0f; dv.right_tangents[3] = -1.2f;
        dv.left_eye_to_head[0] = 1.0f; dv.right_eye_to_head[0] = 1.0f;
        dv.ipd_m = 0.060f + (float)(i % 10) * 1.0e-4f;
        if (vrmc_shared_set_display_views(&dv) != 0) fail("set display views rc", i, 0);

        vrmc_gaze_event ev;
        memset(&ev, 0, sizeof(ev));
        ev.tile_id = (uint64_t)(1 + i % (VRMC_GAZE_GRID_W * VRMC_GAZE_GRID_H));
        ev.phase = 1;
        ev.kind = 1;
        ev.grid_w = VRMC_GAZE_GRID_W;
        ev.grid_h = VRMC_GAZE_GRID_H;
        ev.timestamp_ns = (uint64_t)i;
        if (vrmc_shared_publish_gaze_event(&ev) != 0) fail("publish gaze rc", i, 0);

        if (i % 100 == 0) vrmc_shared_signal_game_stopping();
        if (i % 100 == 50) vrmc_shared_clear_game_stopping();

        vrmc_tracking_state t;
        memset(&t, 0, sizeof(t));
        t.head.position.x = (float)i;
        t.ipd_m = 0.064f;
        if (i % 7 == 0) vrmc_shared_clear_tracking();
        else if (vrmc_shared_set_tracking(&t) != 0) fail("set tracking rc", i, 0);
    }
    atomic_store(&g_done, 1);
    return NULL;
}

static void *reader(void *arg) {
    (void)arg;
    uint32_t last_gen = 0;
    long polls = 0;
    while (!atomic_load(&g_done)) {
        vrmc_display_views dv;
        uint32_t gen = vrmc_shared_get_display_views(&dv);
        if (gen < last_gen) fail("display generation went backwards", (long)gen, (long)last_gen);
        last_gen = gen;
        if (gen > 0) {
            if (!(dv.ipd_m > 0.05f && dv.ipd_m < 0.08f)) fail("display ipd out of range",
                (long)(dv.ipd_m * 1000000.0f), 0);
            for (int k = 0; k < 4; k++) {
                if (!(dv.left_tangents[k] == dv.left_tangents[k])) fail("display NaN", k, 0);
            }
        }

        vrmc_gaze_event ev;
        int rc = vrmc_shared_poll_gaze_event(&ev);
        if (rc == 1) {
            if (ev.tile_id == 0 || ev.tile_id > (uint64_t)(VRMC_GAZE_GRID_W * VRMC_GAZE_GRID_H)) {
                fail("gaze tile out of range", (long)ev.tile_id, 0);
            }
            atomic_fetch_add(&g_gaze_consumed, 1);
        } else if (rc < 0) {
            fail("gaze poll rc", rc, 0);
        }

        int stopping = vrmc_shared_game_stopping();
        if (stopping != 0 && stopping != 1) fail("game stopping not boolean", stopping, 0);

        vrmc_tracking_state t;
        int trc = vrmc_get_tracking(&t, (uint64_t)polls);
        if (trc != 0) fail("get tracking rc", trc, 0);
        if (t.ipd_m < 0.05f || t.ipd_m > 0.1f) fail("tracking ipd out of range", (long)(t.ipd_m * 1e6f), 0);
        polls++;
        if (polls % 1000 == 0) usleep(100);
    }
    return NULL;
}

int main(void) {
    const char *caps = "{\"abi\":3,\"eyes\":2,\"hands\":2,\"input\":1}";
    if (vrmc_init(caps, strlen(caps)) != 0) { printf("init failed: %s\n", vrmc_last_error()); return 2; }
    pthread_t w, r;
    pthread_create(&r, NULL, reader, NULL);
    pthread_create(&w, NULL, writer, NULL);
    pthread_join(w, NULL);
    usleep(20000);
    pthread_join(r, NULL);

    // Final state after the writer stopped: display views generation > 0, tracking default if cleared.
    vrmc_display_views dv;
    if (vrmc_shared_get_display_views(&dv) == 0) fail("final display generation", 0, 0);
    if (atomic_load(&g_gaze_consumed) <= 0) fail("no gaze events consumed", 0, 0);

    int failures = atomic_load(&g_failures);
    printf("[bridge-shared-test] publishes=%d gazeConsumed=%d failures=%d\n",
           PUBLISHES, atomic_load(&g_gaze_consumed), failures);
    printf(failures == 0 ? "[bridge-shared-test] PASS\n" : "[bridge-shared-test] FAIL\n");
    return failures == 0 ? 0 : 1;
}
