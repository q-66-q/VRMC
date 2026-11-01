/*
 * VRMC bridge stub — M2 scaffold.
 *
 * Implements ABI v1 with deterministic fake tracking so the provider mod can be developed and tested
 * on a desktop Fabric harness before the real ARKit/Metal implementation lands. The stub is NOT
 * shipped in the device build once the real bridge exists; it exists to prove the handshake and the
 * eye-submission contract.
 */
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

static int32_t g_initialized = 0;
static uint64_t g_frames = 0;
static char g_error[256] = "no error";
static vrmc_tracking_state g_tracking;

/* M3-W2/W3/W4 native-side shared state (same-process app <-> bridge; Java ABI v2 unchanged). */
static vrmc_eye_targets g_eye_targets;
static int g_has_eye_targets = 0;
static vrmc_tracking_state g_tracking_override;
static int g_has_tracking_override = 0;

static int32_t set_error(const char *msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
    return -1;
}

int32_t vrmc_abi_version(void) { return VRMC_ABI_VERSION; }

const char *vrmc_last_error(void) { return g_error; }

int32_t vrmc_init(const char *caps_json, size_t caps_len) {
    if (caps_json == NULL || caps_len == 0) return set_error("caps_json missing");
    if (strstr(caps_json, "\"abi\"") == NULL) return set_error("caps_json lacks abi capability");
    /* The real bridge will validate the advertised numbers; the stub only checks the ABI token. */
    if (strstr(caps_json, "\"abi\": 2") == NULL && strstr(caps_json, "\"abi\":2") == NULL) {
        return set_error("abi version mismatch (expected 2)");
    }
    memset(&g_tracking, 0, sizeof(g_tracking));
    g_tracking.ipd_m = 0.064f;
    g_tracking.head.orientation.w = 1.0f;
    g_tracking.controllers[0].orientation.w = 1.0f;
    g_tracking.controllers[1].orientation.w = 1.0f;
    g_initialized = 1;
    printf("[vrmc-stub] init ok, abi=%d\n", VRMC_ABI_VERSION);
    return 0;
}

int32_t vrmc_get_tracking(vrmc_tracking_state *out, uint64_t timestamp_ns) {
    if (!g_initialized) return set_error("not initialized");
    if (out == NULL) return set_error("out is null");
    if (g_has_tracking_override) {
        *out = g_tracking_override;
        return 0;
    }
    g_tracking.presentation_time_ns = timestamp_ns;
    *out = g_tracking;
    return 0;
}

int32_t vrmc_poll_input(void *out, size_t out_len) {
    if (!g_initialized) return set_error("not initialized");
    if (out == NULL || out_len == 0) return set_error("input buffer missing");
    memset(out, 0, out_len);
    return 0;
}

int32_t vrmc_submit_eyes(const vrmc_eye_targets *targets) {
    if (!g_initialized) return set_error("not initialized");
    if (targets == NULL) return set_error("targets is null");
    if (targets->left_texture == 0 || targets->right_texture == 0) {
        return set_error("eye texture handles missing");
    }
    g_frames++;
    g_eye_targets = *targets;
    g_has_eye_targets = 1;
    return 0;
}

int32_t vrmc_shared_eye_textures(vrmc_eye_targets *out) {
    if (!g_initialized) return set_error("not initialized");
    if (out == NULL) return set_error("bad shared eye output");
    if (!g_has_eye_targets) return set_error("no eye targets submitted yet");
    *out = g_eye_targets;
    return 0;
}

int32_t vrmc_shared_set_tracking(const vrmc_tracking_state *state) {
    if (!g_initialized) return set_error("not initialized");
    if (state == NULL) return set_error("bad shared tracking state");
    g_tracking_override = *state;
    g_has_tracking_override = 1;
    return 0;
}

void vrmc_shared_clear_tracking(void) {
    g_has_tracking_override = 0;
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
    memset(out, 0, sizeof(*out));
    out->frame_index = (uint32_t)g_frames;
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
    vrmc_eye_targets e = {0};
    vrmc_frame_timing_t ft;
    if (vrmc_abi_version() != VRMC_ABI_VERSION) return 1;
    if (vrmc_init("{\"abi\":2,\"eyes\":2}", 18) != 0) { printf("init fail: %s\n", vrmc_last_error()); return 2; }
    vrmc_eye_targets shared;
    if (vrmc_shared_eye_textures(&shared) == 0) { printf("shared eyes before submit should fail\n"); return 6; }
    vrmc_tracking_state ov = {0};
    ov.head.position.x = 1.25f;
    ov.ipd_m = 0.063f;
    if (vrmc_shared_set_tracking(&ov) != 0) { printf("set tracking fail: %s\n", vrmc_last_error()); return 7; }
    e.frame_index = 1; e.left_texture = 0xAAA; e.right_texture = 0xBBB;
    if (vrmc_submit_eyes(&e) != 0) { printf("submit fail: %s\n", vrmc_last_error()); return 3; }
    if (vrmc_get_tracking(&t, 123) != 0) return 4;
    if (vrmc_frame_timing(&ft) != 0) return 5;
    if (vrmc_shared_eye_textures(&shared) != 0 || shared.left_texture != 0xAAA || shared.right_texture != 0xBBB) {
        printf("shared eyes after submit failed\n"); return 8;
    }
    if (t.head.position.x != 1.25f || t.ipd_m != 0.063f) { printf("tracking override not honored\n"); return 9; }
    vrmc_shared_clear_tracking();
    if (vrmc_get_tracking(&t, 456) != 0 || t.ipd_m != 0.064f) { printf("tracking clear failed\n"); return 10; }
    printf("[vrmc-stub-test] ok version=%d frames=%llu ipd=%.3f shared_left=0x%llx\n", vrmc_abi_version(), (unsigned long long)ft.frame_index, t.ipd_m, (unsigned long long)shared.left_texture);
    return 0;
}
#endif
