/*
 * Cross-language ABI fixture: writes three raw vrmc_render_settings records (68 bytes each) exactly as
 * the visionOS compositor publishes them into the native-shared channel. The Java host test
 * (VisionRenderSettingsFixtureTest) parses the same bytes and must recover the values below, so a
 * layout/offset mismatch between the C struct and the provider's byte offsets fails the build instead
 * of silently breaking M8 display feedback on device.
 *
 * Usage: make_render_settings_fixture <out.bin>
 * Output: three 68-byte little-endian records:
 *   0: valid, foveated 120 Hz at max quality, provider recommendation 3664x3200
 *   1: valid, non-foveated 90 Hz at quality 0.75, no rate maps, no recommendation
 *   2: invalid (valid=0) - the parser must reject the record
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "vrmc_native_shared.h"

_Static_assert(sizeof(vrmc_render_settings) == 68, "vrmc_render_settings must stay 68 bytes");

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <out.bin>\n", argv[0]);
        return 2;
    }
    vrmc_render_settings cases[3];
    memset(cases, 0, sizeof(cases));

    cases[0].version = VRMC_RENDER_SETTINGS_VERSION;
    cases[0].valid = 1;
    cases[0].frame_index = 1234;
    cases[0].foveation_enabled = 1;
    cases[0].rate_map_count = 2;
    cases[0].left_logical_width = 3660;
    cases[0].left_logical_height = 3200;
    cases[0].right_logical_width = 3660;
    cases[0].right_logical_height = 3200;
    cases[0].drawable_width = 2412;
    cases[0].drawable_height = 2108;
    cases[0].render_quality = 1.0f;
    cases[0].max_render_quality = 1.0f;
    cases[0].display_hz = 120.0f;
    cases[0].frame_time_ms = 8.345f;
    cases[0].provider_eye_width = 3664;
    cases[0].provider_eye_height = 3200;

    cases[1].version = VRMC_RENDER_SETTINGS_VERSION;
    cases[1].valid = 1;
    cases[1].frame_index = 90;
    cases[1].foveation_enabled = 0;
    cases[1].rate_map_count = 0;
    cases[1].left_logical_width = 1888;
    cases[1].left_logical_height = 1792;
    cases[1].right_logical_width = 1888;
    cases[1].right_logical_height = 1792;
    cases[1].drawable_width = 1888;
    cases[1].drawable_height = 1792;
    cases[1].render_quality = 0.75f;
    cases[1].max_render_quality = 0.75f;
    cases[1].display_hz = 90.0f;
    cases[1].frame_time_ms = 11.111f;
    cases[1].provider_eye_width = 0;
    cases[1].provider_eye_height = 0;

    // Case 2: the compositor has not published yet; valid=0 must be rejected even with sane geometry.
    cases[2].version = VRMC_RENDER_SETTINGS_VERSION;
    cases[2].valid = 0;
    cases[2].frame_index = 7;
    cases[2].foveation_enabled = 1;
    cases[2].rate_map_count = 1;
    cases[2].left_logical_width = 3660;
    cases[2].left_logical_height = 3200;
    cases[2].right_logical_width = 3660;
    cases[2].right_logical_height = 3200;
    cases[2].drawable_width = 2412;
    cases[2].drawable_height = 2108;
    cases[2].render_quality = 1.0f;
    cases[2].max_render_quality = 1.0f;
    cases[2].display_hz = 120.0f;
    cases[2].frame_time_ms = 8.3f;

    FILE *file = fopen(argv[1], "wb");
    if (file == NULL) {
        perror("fopen");
        return 1;
    }
    if (fwrite(cases, sizeof(cases), 1, file) != 1) {
        perror("fwrite");
        fclose(file);
        return 1;
    }
    fclose(file);
    printf("[m8-rs-fixture] cases=3 record_bytes=%zu total_bytes=%zu\n",
           sizeof(vrmc_render_settings), sizeof(cases));
    return 0;
}
