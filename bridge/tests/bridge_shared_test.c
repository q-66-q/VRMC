/*
 * Host concurrency test for the additive native-shared channels written after ABI v3:
 * display views, gaze mailbox, game-stopping signal, tracking override and the M8 render-feedback
 * channel (compositor -> provider display geometry/cadence).
 *
 * One writer thread publishes display views/gaze/tracking/game-stopping/render settings while one
 * reader thread consumes them; checks generation monotonicity, payload sanity, gaze consumption,
 * render-settings round-trip/validation and no crashes. Also run under ThreadSanitizer by
 * bridge/tests/run_tests.sh: any data race is fatal.
 */
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* M8 render-feedback wire layout: the Java side mirrors these exact sizes/offsets
 * (provider/tests/.../VisionRenderSettingsTest.java + VrmcBridge.RS_OFF_*), so a field reorder here
 * that is not propagated breaks the build instead of silently mis-sizing the provider's eye targets. */
_Static_assert(VRMC_RENDER_SETTINGS_VERSION == 1u, "render settings version must stay 1");
_Static_assert(sizeof(vrmc_render_settings) == 68, "vrmc_render_settings must stay 68 bytes");
_Static_assert(offsetof(vrmc_render_settings, version) == 0, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, valid) == 4, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, frame_index) == 8, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, foveation_enabled) == 12, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, rate_map_count) == 16, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, left_logical_width) == 20, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, left_logical_height) == 24, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, right_logical_width) == 28, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, right_logical_height) == 32, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, drawable_width) == 36, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, drawable_height) == 40, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, render_quality) == 44, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, max_render_quality) == 48, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, display_hz) == 52, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, frame_time_ms) == 56, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, provider_eye_width) == 60, "render settings offsets");
_Static_assert(offsetof(vrmc_render_settings, provider_eye_height) == 64, "render settings offsets");

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

        /* M8 render feedback: compositor-style publication of display geometry/cadence. */
        vrmc_render_settings rs;
        memset(&rs, 0, sizeof(rs));
        rs.version = VRMC_RENDER_SETTINGS_VERSION;
        rs.valid = 1;
        rs.frame_index = (uint32_t)i;
        rs.foveation_enabled = (i & 1) ? 1u : 0u;
        rs.rate_map_count = rs.foveation_enabled ? 2u : 0u;
        rs.left_logical_width = 3660u;
        rs.left_logical_height = 3200u;
        rs.right_logical_width = 3660u;
        rs.right_logical_height = 3200u;
        rs.drawable_width = 2412u;
        rs.drawable_height = 2108u;
        rs.render_quality = 0.25f + (float)(i % 4) * 0.25f;
        rs.max_render_quality = 1.0f;
        rs.display_hz = (i & 1) ? 120.0f : 90.0f;
        rs.frame_time_ms = 1000.0f / rs.display_hz;
        if (vrmc_shared_publish_render_settings(&rs) != 0) fail("publish render settings rc", i, 0);
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

        vrmc_render_settings rs;
        int rsrc = vrmc_shared_acquire_render_settings(&rs);
        if (rsrc != 0) fail("acquire render settings rc", rsrc, 0);
        if (rs.valid != 0 && rs.valid != 1) fail("render settings valid not boolean", (long)rs.valid, 0);
        if (rs.version != VRMC_RENDER_SETTINGS_VERSION) fail("render settings version", (long)rs.version, 0);
        if (rs.valid) {
            if (rs.left_logical_width != 3660u || rs.left_logical_height != 3200u ||
                rs.right_logical_width != 3660u || rs.right_logical_height != 3200u) {
                fail("render settings logical size torn", (long)rs.left_logical_width, (long)rs.left_logical_height);
            }
            if (!(rs.render_quality >= 0.0f && rs.render_quality <= 1.0f) ||
                !(rs.max_render_quality >= rs.render_quality)) {
                fail("render settings quality out of range",
                     (long)(rs.render_quality * 1000.0f), (long)(rs.max_render_quality * 1000.0f));
            }
            if (!(rs.display_hz == 90.0f || rs.display_hz == 120.0f)) {
                fail("render settings cadence torn", (long)(rs.display_hz * 10.0f), 0);
            }
            if ((rs.foveation_enabled == 1u) != (rs.rate_map_count == 2u)) {
                fail("render settings foveation/rate-map mismatch",
                     (long)rs.foveation_enabled, (long)rs.rate_map_count);
            }
        }
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
    // M8 render feedback: the last publication is retained (same lifetime rule as display views; it is
    // deliberately NOT cleared by vrmc_init so a compositor publication made before the JVM starts
    // survives the provider handshake).
    vrmc_render_settings rs;
    if (vrmc_shared_acquire_render_settings(&rs) != 0 || rs.valid != 1 ||
        rs.frame_index != (uint32_t)(PUBLISHES - 1)) {
        fail("final render settings publication", (long)rs.valid, (long)rs.frame_index);
    }

    // Pose stamp (head-turn judder fix): an eye publish carries the pose time of the tracking state
    // last served to the provider; an explicit provider value wins; the fallback stub path does not
    // leak the caller's timestamp into the shared state.
    {
        vrmc_tracking_state served;
        memset(&served, 0, sizeof(served));
        served.presentation_time_ns = 123456789ull;
        served.head.orientation.w = 1.0f;
        served.ipd_m = 0.063f;
        if (vrmc_shared_set_tracking(&served) != 0) fail("pose stamp: set tracking", 0, 0);
        vrmc_tracking_state got;
        if (vrmc_get_tracking(&got, 7) != 0 || got.presentation_time_ns != 123456789ull) {
            fail("pose stamp: served pose time", (long)got.presentation_time_ns, 0);
        }
        vrmc_eye_targets e;
        memset(&e, 0, sizeof(e));
        e.left_texture = 0x111; e.right_texture = 0x222;
        e.left_width = e.right_width = 64; e.left_height = e.right_height = 64;
        vrmc_shared_eye_frame f;
        if (vrmc_submit_eyes(&e) != 0 || vrmc_shared_acquire_eyes(&f) != 0 ||
            f.eyes.presentation_deadline_ns != 123456789) {
            fail("pose stamp: eye frame not stamped", (long)f.eyes.presentation_deadline_ns, 0);
        }
        e.presentation_deadline_ns = 42;
        if (vrmc_submit_eyes(&e) != 0 || vrmc_shared_acquire_eyes(&f) != 0 ||
            f.eyes.presentation_deadline_ns != 42) {
            fail("pose stamp: explicit provider value overwritten", (long)f.eyes.presentation_deadline_ns, 0);
        }
        vrmc_shared_clear_tracking();
        vrmc_tracking_state stub1, stub2;
        if (vrmc_get_tracking(&stub1, 999) != 0 || stub1.presentation_time_ns != 999) {
            fail("stub tracking timestamp", (long)stub1.presentation_time_ns, 0);
        }
        if (vrmc_get_tracking(&stub2, 5) != 0 || stub2.presentation_time_ns != 5) {
            fail("stub tracking timestamp leaked", (long)stub2.presentation_time_ns, 0);
        }
    }

    int failures = atomic_load(&g_failures);
    printf("[bridge-shared-test] publishes=%d gazeConsumed=%d failures=%d\n",
           PUBLISHES, atomic_load(&g_gaze_consumed), failures);
    printf(failures == 0 ? "[bridge-shared-test] PASS\n" : "[bridge-shared-test] FAIL\n");
    return failures == 0 ? 0 : 1;
}
