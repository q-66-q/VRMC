/*
 * Fake provider dylib for the M3c simulator provider-sampling harness.
 *
 * The real VRMC compositor dlopens Frameworks/libvrmc_bridge.dylib and asks it for the provider's two
 * eye MTLTextures through the native-shared API. This dylib implements that API without any JVM/game:
 * it creates two real MTLTextures with a known high-contrast pattern and publishes them every frame.
 * Running VRMCShell.framework in the visionOS simulator with this dylib in place therefore exercises the
 * full sampled path (acquire -> flat shader -> drawable) and lets a screenshot / drawable readback prove
 * orientation, eye assignment and flat mapping without a headset.
 *
 * Left texture:  black 100-px top strip, then quadrants TL red / TR green / BL blue / BR white.
 * Right texture: black 100-px top strip, then quadrants TL cyan / TR magenta / BL yellow / BR dark grey.
 * (The simulator drawable is mono, so only the left texture is sampled there; the right pattern is for a
 * future stereo assertion / device-side inspection.)
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"

static id<MTLDevice> gDevice;
static id<MTLTexture> gLeft;
static id<MTLTexture> gRight;
static dispatch_once_t gOnce;
static uint64_t gPublishSequence = 0;
static uint32_t gTextureGeneration = 0;
static uint32_t gFrameIndex = 0;
static vrmc_display_views gDisplayViews;
static uint32_t gDisplayViewsGen = 0;
// Optional GPU-sync exercise (Documents/vrmc-fake-provider-sync.flag): publish a real MTLSharedEvent
// whose signaled value is already current, so the compositor's encodeWaitForEvent path executes.
static id<MTLSharedEvent> gSharedEvent;
static uint64_t gSignalValue = 0;
static int gSyncMode = -1;

// -------------------------------------------------------------------------------------------
// M4-W1 immersive input surface (docs/analysis/immersive-input.md §3.3 / §4).
//
// The REAL compositor publishes one vrmc_input_state per frame through vrmc_shared_publish_input
// (dlsym'd from this dylib). This fake provider records every published snapshot to
// Documents/vrmc-input-capture.txt so check.py --require-input can assert the real publication path
// (rate, valid_mask framing, pinch/fist threshold crossings, final release snapshot) without a JVM.
//
// CSV shape (one line per successful publish; '#' header lines are comments):
//   seq, frame_index, valid_mask, timestamp_ns,
//   right_pinch_m, left_pinch_m, right_fist_ratio, left_fist_ratio
// Distances/ratios are computed from the published joints with the SAME formulas the provider uses
// (design §5.3), so the capture proves the wire bytes carry the expected gesture geometry.
// -------------------------------------------------------------------------------------------
static pthread_mutex_t gInputMutex = PTHREAD_MUTEX_INITIALIZER;
static vrmc_input_state gInputState;
static uint64_t gInputSequence = 0;
static int gInputPublished = 0;
static FILE *gInputCapture = NULL;
static uint64_t gInputCaptureLines = 0;

static BOOL fakeSyncEnabled(void) {
    if (gSyncMode >= 0) return gSyncMode != 0;
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *flagPath = [docs.firstObject stringByAppendingPathComponent:@"vrmc-fake-provider-sync.flag"];
    gSyncMode = [[NSFileManager defaultManager] fileExistsAtPath:flagPath] ? 1 : 0;
    return gSyncMode != 0;
}

static void fillPattern(uint8_t *px, size_t rowBytes, NSUInteger w, NSUInteger h,
                        int rTL, int gTL, int bTL,
                        int rTR, int gTR, int bTR,
                        int rBL, int gBL, int bBL,
                        int rBR, int gBR, int bBR) {
    memset(px, 0, rowBytes * h);
    for (NSUInteger y = 0; y < h; y++) {
        for (NSUInteger x = 0; x < w; x++) {
            uint8_t *p = px + y * rowBytes + x * 4;
            if (y < 100) { p[0] = p[1] = p[2] = 0; }          // top strip: black (orientation marker)
            else if (x < w / 2 && y < h / 2) { p[0] = rTL; p[1] = gTL; p[2] = bTL; }
            else if (x >= w / 2 && y < h / 2) { p[0] = rTR; p[1] = gTR; p[2] = bTR; }
            else if (x < w / 2) { p[0] = rBL; p[1] = gBL; p[2] = bBL; }
            else { p[0] = rBR; p[1] = gBR; p[2] = bBR; }
            p[3] = 255;
        }
    }
}

static id<MTLTexture> makeTexture(int rTL, int gTL, int bTL, int rTR, int gTR, int bTR,
                                  int rBL, int gBL, int bBL, int rBR, int gBR, int bBR) {
    if (gDevice == nil) gDevice = MTLCreateSystemDefaultDevice();
    if (gDevice == nil) return nil;
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                 width:1024 height:1024 mipmapped:NO];
    d.usage = MTLTextureUsageShaderRead;
    d.storageMode = MTLStorageModeShared;
    id<MTLTexture> tex = [gDevice newTextureWithDescriptor:d];
    if (tex == nil) return nil;
    const NSUInteger rowBytes = 1024 * 4;
    uint8_t *px = (uint8_t *)calloc(1, rowBytes * 1024);
    fillPattern(px, rowBytes, 1024, 1024, rTL, gTL, bTL, rTR, gTR, bTR, rBL, gBL, bBL, rBR, gBR, bBR);
    [tex replaceRegion:MTLRegionMake2D(0, 0, 1024, 1024) mipmapLevel:0 withBytes:px bytesPerRow:rowBytes];
    free(px);
    return tex;
}

static void ensureTextures(void) {
    dispatch_once(&gOnce, ^{
        gLeft = makeTexture(220, 40, 40, 40, 200, 40, 40, 60, 220, 235, 235, 235);
        gRight = makeTexture(30, 220, 220, 220, 30, 220, 220, 220, 40, 90, 90, 90);
        if (fakeSyncEnabled()) {
            gSharedEvent = [gDevice newSharedEvent];
            gSignalValue = 1;
            [gSharedEvent setSignaledValue:gSignalValue];
            NSLog(@"[fake-provider] GPU sync mode: event=%p signaledValue=%llu",
                  (__bridge void *)gSharedEvent, (unsigned long long)gSignalValue);
        }
        NSLog(@"[fake-provider] textures L=%p R=%p device=%s", (__bridge void *)gLeft,
              (__bridge void *)gRight, gDevice.name.UTF8String);
    });
}

static void fillEyeTargets(vrmc_eye_targets *out) {
    memset(out, 0, sizeof(*out));
    ensureTextures();
    out->frame_index = gFrameIndex++;
    out->left_texture = (uint64_t)(uintptr_t)(__bridge void *)gLeft;
    out->right_texture = (uint64_t)(uintptr_t)(__bridge void *)gRight;
    out->left_width = out->right_width = 1024;
    out->left_height = out->right_height = 1024;
    const float t = 1.428f; // ~110 deg symmetric frustum, OpenXR-style signs
    out->left_fov[0] = -t; out->left_fov[1] = t; out->left_fov[2] = t; out->left_fov[3] = -t;
    out->right_fov[0] = -t; out->right_fov[1] = t; out->right_fov[2] = t; out->right_fov[3] = -t;
}

int32_t vrmc_abi_version(void) { return VRMC_ABI_VERSION; }
int32_t vrmc_init(const char *caps_json, size_t caps_len) { (void)caps_json; (void)caps_len; return 0; }
const char *vrmc_last_error(void) { return "fake provider (simulator harness)"; }

int32_t vrmc_get_tracking(vrmc_tracking_state *out, uint64_t timestamp_ns) {
    (void)timestamp_ns;
    if (out) memset(out, 0, sizeof(*out));
    return -1;
}

int32_t vrmc_shared_set_tracking(const vrmc_tracking_state *state) { (void)state; return 0; }
void vrmc_shared_clear_tracking(void) {}

int32_t vrmc_shared_set_display_views(const vrmc_display_views *views) {
    if (views) { gDisplayViews = *views; gDisplayViewsGen++; }
    return 0;
}

uint32_t vrmc_shared_get_display_views(vrmc_display_views *out) {
    if (out) *out = gDisplayViews;
    return gDisplayViewsGen;
}

int32_t vrmc_shared_publish_eyes(const vrmc_eye_targets *targets, const vrmc_shared_frame_sync *sync) {
    (void)targets; (void)sync;
    return 0;
}

// Optional M8 eye-drop exercise (Documents/vrmc-fake-eyes-drop.flag): the real provider clears the
// shared eye frame before an eye-target rebuild, so the compositor must reuse its last sampled frame
// for a short grace window instead of flashing the test pattern. This mimics that window: after
// ~2 s of normal frames it withholds the frame for 60 acquire calls, then resumes with a bumped
// texture generation. The fake provider keeps its textures alive (like a real in-flight pair), so the
// compositor's retained last-frame pair is still valid to sample.
static int gEyesDropMode = -1;
static uint32_t gEyesDropAcquires = 0;
static uint32_t gEyesDropGeneration = 0;

static BOOL fakeEyesDropEnabled(void) {
    if (gEyesDropMode >= 0) return gEyesDropMode != 0;
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *flagPath = [docs.firstObject stringByAppendingPathComponent:@"vrmc-fake-eyes-drop.flag"];
    gEyesDropMode = [[NSFileManager defaultManager] fileExistsAtPath:flagPath] ? 1 : 0;
    return gEyesDropMode != 0;
}

int32_t vrmc_shared_acquire_eyes(vrmc_shared_eye_frame *out) {
    if (out == NULL) return -1;
    memset(out, 0, sizeof(*out));
    if (fakeEyesDropEnabled()) {
        gEyesDropAcquires++;
        if (gEyesDropAcquires == 120) {
            NSLog(@"[fake-provider] eyes-drop: withholding the eye frame for 60 acquire calls "
                  "(simulated provider clear for an eye-target rebuild)");
        }
        if (gEyesDropAcquires > 120 && gEyesDropAcquires <= 180) {
            return -1;   // no eye frame: the compositor must reuse its last sampled pair
        }
        if (gEyesDropAcquires == 181) {
            gEyesDropGeneration++;
            NSLog(@"[fake-provider] eyes-drop: eye frames resumed after 60 missing calls "
                  "(texture generation=%u)", gEyesDropGeneration);
        }
    }
    fillEyeTargets(&out->eyes);
    if (gSharedEvent != nil) {
        gSignalValue++;
        [gSharedEvent setSignaledValue:gSignalValue];
        out->sync.valid = 1;
        out->sync.shared_event = (uint64_t)(uintptr_t)(__bridge void *)gSharedEvent;
        out->sync.signal_value = gSignalValue;
    } else {
        out->sync.valid = 0;
        out->sync.shared_event = 0;
        out->sync.signal_value = 0;
    }
    out->sync.frame_index = out->eyes.frame_index;
    out->publish_sequence = ++gPublishSequence;
    out->texture_generation = gTextureGeneration + gEyesDropGeneration;
    return 0;
}

int32_t vrmc_shared_eye_textures(vrmc_eye_targets *out) {
    if (out == NULL) return -1;
    fillEyeTargets(out);
    return 0;
}

int32_t vrmc_shared_get_frame_sync(vrmc_shared_frame_sync *out) {
    if (out == NULL) return -1;
    memset(out, 0, sizeof(*out));
    return 0;
}

/* ------------------------------------------------------------------------------------------- */
/* M4-W1 immersive input surface: publish / acquire / sequence (real compositor -> capture file) */
/* ------------------------------------------------------------------------------------------- */

static double fakeJointDistance(const vrmc_vec3 *a, const vrmc_vec3 *b) {
    const double dx = (double)a->x - (double)b->x;
    const double dy = (double)a->y - (double)b->y;
    const double dz = (double)a->z - (double)b->z;
    return sqrt(dx * dx + dy * dy + dz * dz);
}

// Provider pinch metric (design §5.3): d = |joint4 (thumb tip) - joint9 (index tip)|.
static double fakePinchDistance(const vrmc_hand_state *hand) {
    return fakeJointDistance(&hand->joints[4], &hand->joints[9]);
}

// Provider fist metric (design §5.3): avg(|joints 9,14,19,24 - joint0|) / |joint11 - joint0|.
static double fakeFistRatio(const vrmc_hand_state *hand) {
    const double palm = fakeJointDistance(&hand->joints[11], &hand->joints[0]);
    if (!(palm > 1e-9)) return 0.0;
    const double tips = fakeJointDistance(&hand->joints[9], &hand->joints[0]) +
                        fakeJointDistance(&hand->joints[14], &hand->joints[0]) +
                        fakeJointDistance(&hand->joints[19], &hand->joints[0]) +
                        fakeJointDistance(&hand->joints[24], &hand->joints[0]);
    return (tips / 4.0) / palm;
}

static FILE *fakeInputCaptureFile(void) {
    if (gInputCapture != NULL) return gInputCapture;
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [docs.firstObject stringByAppendingPathComponent:@"vrmc-input-capture.txt"];
    gInputCapture = fopen(path.UTF8String, "w");
    if (gInputCapture == NULL) {
        NSLog(@"[fake-provider] input capture: cannot open %@", path);
        return NULL;
    }
    fprintf(gInputCapture, "# vrmc-input-capture v1 (fake provider, visionOS simulator): "
                           "seq,frame_index,valid_mask,timestamp_ns,"
                           "right_pinch_m,left_pinch_m,right_fist_ratio,left_fist_ratio\n");
    fprintf(gInputCapture, "# Published by the real VRMC compositor from synthetic input "
                           "(Documents/vrmc-input-sim.flag). Plumbing evidence only - NOT hands evidence.\n");
    fflush(gInputCapture);
    NSLog(@"[fake-provider] input capture: %@", path);
    return gInputCapture;
}

int32_t vrmc_shared_publish_input(const vrmc_input_state *state) {
    if (state == NULL) return -1;
    if (state->valid_mask > 3u) {
        NSLog(@"[fake-provider] input publish rejected: invalid valid_mask=%u", state->valid_mask);
        return -1;
    }
    pthread_mutex_lock(&gInputMutex);
    gInputState = *state;
    gInputPublished = 1;
    gInputSequence++;
    const uint64_t sequence = gInputSequence;
    FILE *capture = fakeInputCaptureFile();
    if (capture != NULL) {
        const vrmc_hand_state *left = &state->hands[VRMC_INPUT_LEFT_HAND];
        const vrmc_hand_state *right = &state->hands[VRMC_INPUT_RIGHT_HAND];
        fprintf(capture, "%llu,%u,%u,%llu,%.6f,%.6f,%.6f,%.6f\n",
                (unsigned long long)sequence, state->frame_index, state->valid_mask,
                (unsigned long long)state->timestamp_ns,
                fakePinchDistance(right), fakePinchDistance(left),
                fakeFistRatio(right), fakeFistRatio(left));
        fflush(capture);
        gInputCaptureLines++;
        if (gInputCaptureLines == 1 || (gInputCaptureLines % 300) == 0 || state->valid_mask == 0) {
            NSLog(@"[fake-provider] input capture line=%llu seq=%llu frame=%u valid_mask=%u",
                  (unsigned long long)gInputCaptureLines, (unsigned long long)sequence,
                  state->frame_index, state->valid_mask);
        }
    }
    pthread_mutex_unlock(&gInputMutex);
    return 0;
}

int32_t vrmc_shared_acquire_input(vrmc_input_state *out) {
    if (out == NULL) return -1;
    pthread_mutex_lock(&gInputMutex);
    *out = gInputState;
    const int published = gInputPublished;
    pthread_mutex_unlock(&gInputMutex);
    return published ? 0 : -1;
}

uint64_t vrmc_shared_input_sequence(void) {
    pthread_mutex_lock(&gInputMutex);
    const uint64_t sequence = gInputSequence;
    pthread_mutex_unlock(&gInputMutex);
    return sequence;
}
/* ------------------------------------------------------------------------------------------- */
/* M8 render feedback: the REAL compositor publishes display geometry/cadence into this dylib.  */
/*                                                                                             */
/* vrmc_shared_publish_render_settings is called once per compositor frame (rate-limited by the  */
/* compositor to ~every 10 frames + immediately on geometry/quality change). The fake provider     */
/* records every payload to Documents/vrmc-render-capture.txt so check.py can assert that the     */
/* compositor actually measured the layer's logical per-eye size, foveation/rate-map state and   */
/* display cadence, and that the wire layout survives the native round-trip.                      */
/*                                                                                             */
/* CSV shape (one line per publish; '#' lines are comments):                                     */
/*   publishes_count,frame_index,valid,left_logical_w,left_logical_h,right_logical_w,             */
/*   right_logical_h,drawable_w,drawable_h,foveation,rate_maps,render_quality,max_render_quality, */
/*   display_hz,frame_time_ms                                                                     */
/* ------------------------------------------------------------------------------------------- */
static pthread_mutex_t gRenderMutex = PTHREAD_MUTEX_INITIALIZER;
static vrmc_render_settings gRenderSettings;
static int gRenderPublished = 0;
static FILE *gRenderCapture = NULL;
static uint64_t gRenderCaptureLines = 0;
static uint32_t gRenderLastLogicalW = 0;
static uint32_t gRenderLastLogicalH = 0;

static FILE *fakeRenderCaptureFile(void) {
    if (gRenderCapture != NULL) return gRenderCapture;
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [docs.firstObject stringByAppendingPathComponent:@"vrmc-render-capture.txt"];
    gRenderCapture = fopen(path.UTF8String, "w");
    if (gRenderCapture == NULL) {
        NSLog(@"[fake-provider] render capture: cannot open %@", path);
        return NULL;
    }
    fprintf(gRenderCapture,
            "# vrmc-render-capture v1 (fake provider, visionOS simulator): "
            "publishes,frame_index,valid,left_logical_w,left_logical_h,right_logical_w,"
            "right_logical_h,drawable_w,drawable_h,foveation,rate_maps,render_quality,"
            "max_render_quality,display_hz,frame_time_ms\n");
    fprintf(gRenderCapture,
            "# Published by the real VRMC compositor (M8 render feedback). Plumbing evidence only - "
            "display geometry/cadence values in the simulator are not device optics evidence.\n");
    fflush(gRenderCapture);
    NSLog(@"[fake-provider] render capture: %@", path);
    return gRenderCapture;
}

int32_t vrmc_shared_publish_render_settings(const vrmc_render_settings *settings) {
    if (settings == NULL) return -1;
    if (settings->version != VRMC_RENDER_SETTINGS_VERSION) return -2;
    pthread_mutex_lock(&gRenderMutex);
    gRenderSettings = *settings;
    gRenderPublished = 1;
    FILE *capture = fakeRenderCaptureFile();
    if (capture != NULL) {
        fprintf(capture, "%llu,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%.3f,%.3f,%.2f,%.2f\n",
                (unsigned long long)(gRenderCaptureLines + 1), settings->frame_index, settings->valid,
                settings->left_logical_width, settings->left_logical_height,
                settings->right_logical_width, settings->right_logical_height,
                settings->drawable_width, settings->drawable_height,
                settings->foveation_enabled, settings->rate_map_count,
                (double)settings->render_quality, (double)settings->max_render_quality,
                (double)settings->display_hz, (double)settings->frame_time_ms);
        fflush(capture);
        gRenderCaptureLines++;
        if (settings->left_logical_width != gRenderLastLogicalW ||
            settings->left_logical_height != gRenderLastLogicalH) {
            gRenderLastLogicalW = settings->left_logical_width;
            gRenderLastLogicalH = settings->left_logical_height;
            NSLog(@"[fake-provider] render geometry logical L=%ux%u R=%ux%u drawable=%ux%u "
                  "foveation=%u rateMaps=%u quality=%.2f/%.2f displayHz=%.1f",
                  settings->left_logical_width, settings->left_logical_height,
                  settings->right_logical_width, settings->right_logical_height,
                  settings->drawable_width, settings->drawable_height,
                  settings->foveation_enabled, settings->rate_map_count,
                  (double)settings->render_quality, (double)settings->max_render_quality,
                  (double)settings->display_hz);
        }
    }
    pthread_mutex_unlock(&gRenderMutex);
    return 0;
}

int32_t vrmc_shared_acquire_render_settings(vrmc_render_settings *out) {
    if (out == NULL) return -1;
    memset(out, 0, sizeof(*out));
    out->version = VRMC_RENDER_SETTINGS_VERSION;
    pthread_mutex_lock(&gRenderMutex);
    if (gRenderPublished) *out = gRenderSettings;
    pthread_mutex_unlock(&gRenderMutex);
    return 0;
}
