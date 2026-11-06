/*
 * Host-harness-only render-feedback publisher (M8).
 *
 * The M8 provider reads display geometry/cadence from the compositor through the native-shared
 * vrmc_render_settings channel. On the desktop Fabric host harness there is no CompositorServices
 * compositor, so without a publisher the provider logs "no display feedback yet" and never exercises
 * its eye-target resize path. This file is linked ONLY into a host test dylib
 * (see docs/mvp/M8_HOST_HARNESS.md / the build command in scripts/... usage): when the environment
 * variable VRMC_HOST_TEST_RENDER_SETTINGS=1 is set it waits for the game to boot, then publishes
 * fake 4K-class display geometry at 120 Hz, exercising the real provider poll -> policy -> resize
 * path in a real Minecraft client. Never compiled into the device bridge.
 */
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void *publish_loop(void *arg) {
    (void)arg;
    // Give Minecraft/JVM/Vivecraft time to boot to the title screen and initialize the provider.
    sleep(30);
    for (int i = 0; i < 100000; i++) {
        vrmc_render_settings rs;
        memset(&rs, 0, sizeof(rs));
        rs.version = VRMC_RENDER_SETTINGS_VERSION;
        rs.valid = 1;
        rs.frame_index = (uint32_t)i;
        rs.foveation_enabled = 1;
        rs.rate_map_count = 2;
        rs.left_logical_width = 3660;
        rs.left_logical_height = 3200;
        rs.right_logical_width = 3660;
        rs.right_logical_height = 3200;
        rs.drawable_width = 2412;
        rs.drawable_height = 2108;
        rs.render_quality = 1.0f;
        rs.max_render_quality = 1.0f;
        rs.display_hz = 120.0f;
        /* Host-only test knob (harness): publish a lower measured display cadence to exercise the
           provider's "target cadence unreachable" guardrail (e.g. VRMC_HOST_TEST_DISPLAY_HZ=90 while
           vrmc-target-hz.txt asks for 120). Never compiled into the device bridge. */
        const char *display_hz_env = getenv("VRMC_HOST_TEST_DISPLAY_HZ");
        if (display_hz_env != NULL && *display_hz_env != '\0') {
            char *end = NULL;
            float parsed_hz = (float)strtod(display_hz_env, &end);
            if (end != display_hz_env && parsed_hz >= 30.0f && parsed_hz <= 240.0f) {
                rs.display_hz = parsed_hz;
            }
        } else {
            /* Gradle's runClient forks a long-lived daemon that may not carry new environment
               variables; the harness therefore also writes the requested simulated display cadence
               into the game directory. The publisher's working directory is that run directory. */
            FILE *hz_file = fopen("vrmc-host-display-hz.txt", "r");
            if (hz_file != NULL) {
                float file_hz = 0.0f;
                if (fscanf(hz_file, "%f", &file_hz) == 1 && file_hz >= 30.0f && file_hz <= 240.0f) {
                    rs.display_hz = file_hz;
                }
                fclose(hz_file);
            }
        }
        rs.frame_time_ms = 8.33f;
        vrmc_shared_publish_render_settings(&rs);
        usleep(16000); // ~60 Hz publication is plenty; the provider polls every frame
    }
    return NULL;
}

__attribute__((constructor)) static void vrmc_host_test_render_settings_start(void) {
    const char *enable = getenv("VRMC_HOST_TEST_RENDER_SETTINGS");
    if (enable == NULL || strcmp(enable, "1") != 0) return;
    pthread_t thread;
    if (pthread_create(&thread, NULL, publish_loop, NULL) == 0) {
        pthread_detach(thread);
    }
}
