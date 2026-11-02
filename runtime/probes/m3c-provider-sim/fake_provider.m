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

int32_t vrmc_shared_acquire_eyes(vrmc_shared_eye_frame *out) {
    if (out == NULL) return -1;
    memset(out, 0, sizeof(*out));
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
    out->texture_generation = gTextureGeneration;
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
