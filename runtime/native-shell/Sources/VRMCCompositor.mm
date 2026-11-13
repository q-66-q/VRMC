// VRMC immersive compositor for the SwiftUI shell (M3-W2/W3/W4).
// CompositorServices loop + Metal per-eye reprojection of the provider's exported eye MTLTextures,
// plus ARKit device tracking pushed into the bridge for the provider (vrmc_shared_*).
//
// M3c hardening after EV-0090/EV-0091 (device run: 1080-6360 frames presented, provider eye textures
// measured bright, command buffer completed, and the operator still reported a PURE BLACK immersive):
//  - visionOS 26 deprecated cp_frame_query_drawable for cp_frame_query_drawables. The compositor now
//    renders AND presents every drawable the frame hands out, logs each drawable's target
//    (built_in / capture), view/texture/rasterization-rate-map counts, and prefers built_in for
//    tracking + display-view publication. Drawing only one drawable can leave the buffer the system
//    displays untouched -> black immersive while our command buffers complete.
//  - Pipelines are built from the layer configuration and then rebuilt from the ACTUAL drawable
//    attachment formats. A nil colour texture / nil render encoder / format mismatch is logged
//    loudly: with an invalid render pass even the load-action clears (bright red left, green right)
//    never reach the drawable, which is the only way to get black instead of red/green.
//  - DRAWN-DRAWABLE readback (the decisive present-path evidence): 64 strided full-width rows of each
//    eye's drawable colour texture are blitted inside the frame command buffer after the render
//    passes, decoded to a 64x64 RGBA8 image, logged (mean/max/luma/top-strip/centre) and written to
//    Documents/vrmc-drawable-L.raw / -R.raw (+ .meta). This proves what was presented without an
//    operator judgement call.
//  - New flag-driven probes: vrmc-present-proof.flag (bright checker border + magenta centre cross),
//    vrmc-clear-probe.flag (clear-only magenta left / cyan right, no draws), vrmc-drawable-dump.flag
//    (write the raw image on every probe frame), vrmc-present-wait.flag (wait for GPU completion
//    before end_submission, replicating the EV-0074 probe), vrmc-immersive-selftest.flag (force test
//    pattern + proof + raw dumps; the shell opens the immersive space without the game).
//  - cp_frame_end_submission is never called for a frame that presented no drawable, and the
//    rasterization-rate-map index is bounded by the drawable's own rate-map count.
//  - Composes VRMCCompositorRunning (first presented frame) so the shell parks windows only after a
//    frame actually reached the drawable, and never hides the windows (isHidden destabilises the
//    scene; alpha-only parking is used instead).
//
// M3b hardening after EV-0086 (device run showed a COMPLETELY BLACK immersive while eyes=1):
//  - CPU-side ray->UV diagnostics for the center/corners/grid of every view, logged once per session:
//    validates the invProjection/viewToDevice conventions, the d.z sign, and how much of the drawable
//    actually falls inside the provider frustum.
//  - Never silently black. The shader now clamps out-of-frustum UVs and falls back to a flat sample
//    when a ray is behind the camera / non-finite; a debug flag colours the failure branches instead
//    (magenta = outside the provider frustum, blue = behind camera, orange = non-finite).
//  - Provider eye-texture luminance readback (32x32 centre strip) every ~300 frames, so the next
//    device log distinguishes "provider texture is black" (game/render side) from "our mapping is
//    wrong" (compositor side). This is the decisive EV-0086 follow-up diagnostic.
//  - A procedural test pattern is drawn when no provider eye texture is available (or sampling is
//    disabled), so the operator can always tell the compositor is presenting.
//  - Diagnostic kill switches in Documents/: vrmc-reproj-off.flag (flat sampling), vrmc-reproj-on.flag
//    (force reprojection), vrmc-reproj-debug.flag (colour-coded failure branches), plus the existing
//    vrmc-no-sampling.flag (test pattern only).
//  - Mode badge: the top 1.5% of the image is tinted by the active path (red = reprojection,
//    green = flat sampling, blue = test pattern) so a device report can name the active path.
//
// M4-W1 immersive input (docs/analysis/immersive-input.md §4):
//  - ARKit hand tracking runs in the SAME ar_session_t as world tracking (guarded by
//    ar_hand_tracking_provider_is_supported(); a denied/unsupported provider degrades to a
//    world-only session so head tracking/presentation never regress).
//  - Once per frame, after the device-anchor query and before presenting, the hand anchors are
//    queried at cp_frame_timing_get_trackable_anchor_time -> ar_hand_tracking_provider_query_anchors_at_timestamp,
//    the 27 joints are composed into device/anchor space (anchor origin transform * anchor-from-joint)
//    and one vrmc_input_state snapshot is published through the dlsym-resolved
//    vrmc_shared_publish_input (bridge ABI v3 input channel; provider polls it via vrmc_poll_input).
//  - A zeroed release snapshot (valid_mask = 0) is published before ar_session_stop on every exit
//    path, so the provider releases every held action when the immersive space closes.
//  - Synthetic input (Documents/vrmc-input-sim.flag) publishes scripted, fabricated 27-joint hands
//    instead of ARKit data for the simulator harness and device A/B. Its log lines are prefixed
//    INPUT-SIM and say SYNTHETIC; it is plumbing evidence, never hands evidence.
#include "Bridging.h"
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <ARKit/ARKit.h>
#include <atomic>
#include <cmath>
#include <dlfcn.h>
#include <math.h>
#include <mutex>
#include <stdio.h>
#include <string.h>

static FILE *gLog;
static std::mutex gLogMutex;
static void *gBridge;
typedef int32_t (*eye_targets_fn)(vrmc_eye_targets *);
typedef int32_t (*acquire_eyes_fn)(vrmc_shared_eye_frame *);
typedef int32_t (*set_tracking_fn)(const vrmc_tracking_state *);
typedef int32_t (*set_display_views_fn)(const vrmc_display_views *);
// M4-W1 immersive input: the compositor publishes one vrmc_input_state per frame; the JVM provider
// polls it through vrmc_poll_input. Both symbols are resolved with dlsym so an OLD bridge dylib
// (v2, no input channel) never breaks the compositor: publishing is skipped with one log line.
typedef int32_t (*input_publish_fn)(const vrmc_input_state *);
typedef uint64_t (*input_sequence_fn)(void);
typedef int32_t (*game_stopping_fn)(void);
typedef void (*clear_game_stopping_fn)(void);
typedef int32_t (*publish_gaze_fn)(const vrmc_gaze_event *);
// M8 render feedback: compositor -> provider display geometry/cadence (additive native-shared
// channel). Optional: an old bridge without the symbol keeps the compositor running (one log line).
typedef int32_t (*publish_render_settings_fn)(const vrmc_render_settings *);
static eye_targets_fn gEyeFn;
static acquire_eyes_fn gAcquireFn;
// Per-eye LOGICAL (screen-space) size of the latest built_in drawable, captured by the render-feedback
// block and used by the sharpening decision in the draw loop (the foveated physical drawable is much
// smaller, so the draw-loop viewport alone cannot tell when the provider renders below display res).
static uint32_t gFrameLogicalW[2] = {0, 0};
static uint32_t gFrameLogicalH[2] = {0, 0};

// Cached sRGB texture views of the provider eye textures: the provider renders into RGBA8_UNORM
// but its pixel values are sRGB-encoded (the window path relies on OS conversion), while the
// compositor drawable is RGBA16Float which visionOS treats as linear. Sampling through an sRGB
// view decodes to linear in hardware (same result as the window path), avoiding the double
// encode that made the immersive image look washed out. Recreated only when the provider
// reallocates the eye textures (resize).
static id<MTLTexture> gSrgbColorViewL = nil;
static id<MTLTexture> gSrgbColorViewR = nil;
static uint64_t gSrgbColorHandleL = 0;
static uint64_t gSrgbColorHandleR = 0;

// Pose-matched presentation (head-turn judder fix). Every compositor frame queries the device
// anchor at its presentation time and publishes that pose to the provider; the provider renders a
// frame from the pose it read and the bridge stamps the frame with that pose's time. The anchor
// that belongs to the frame being shown is looked up here and set on the drawable, so visionOS
// reprojects the picture from the pose it was really rendered with. Before, the newest anchor was
// set on every drawable, so a game frame rendered 1-3 display frames earlier (or repeated while the
// game ran below 90 fps) was presented as if it matched the current head pose: the world swam with
// the head and snapped back - the judder during head rotation.
static const int kAnchorRingSize = 64;
static __strong ar_device_anchor_t gAnchorRing[kAnchorRingSize];
static uint64_t gAnchorRingNs[kAnchorRingSize];
static int gAnchorRingNext = 0;

static void rememberAnchor(uint64_t poseNs, ar_device_anchor_t anchor) {
    gAnchorRing[gAnchorRingNext] = anchor;
    gAnchorRingNs[gAnchorRingNext] = poseNs;
    gAnchorRingNext = (gAnchorRingNext + 1) % kAnchorRingSize;
}

static ar_device_anchor_t anchorForPose(uint64_t poseNs) {
    if (poseNs == 0) return nil;
    for (int i = 0; i < kAnchorRingSize; i++) {
        if (gAnchorRingNs[i] == poseNs && gAnchorRing[i] != nil) return gAnchorRing[i];
    }
    return nil;
}

static void clearAnchorRing(void) {
    for (int i = 0; i < kAnchorRingSize; i++) { gAnchorRing[i] = nil; gAnchorRingNs[i] = 0; }
    gAnchorRingNext = 0;
}
static set_tracking_fn gTrackFn;
static set_display_views_fn gDisplayViewsFn;
static input_publish_fn gInputPublishFn;
static input_sequence_fn gInputSequenceFn;
static game_stopping_fn gGameStoppingFn;
static clear_game_stopping_fn gClearGameStoppingFn;
static publish_gaze_fn gPublishGazeFn;
static publish_render_settings_fn gPublishRenderSettingsFn;
static std::atomic<int> gGameStoppedPosted{0};
// Each immersive session (CompositorLayer callback) gets a generation. A stop request applies to the
// generation that is current when it is made, so a late stop cannot kill the next session and a stale
// session's VRMCImmersiveEnded can be told apart from the current one by the shell.
static std::atomic<int32_t> gGeneration{0};
static std::atomic<int32_t> gStopGeneration{0};
// Provider eye-texture content probes (32x32 centre readbacks). If both eyes read back black for two
// consecutive probes (~600 frames), the compositor switches to the procedural test pattern so the
// operator can tell "compositor presentation works, provider image is black" from "presentation broken".
static std::atomic<float> gTexMeanL{0.0f};
static std::atomic<float> gTexMeanR{0.0f};
static std::atomic<int> gTexBlackStreakL{0};
static std::atomic<int> gTexBlackStreakR{0};

extern "C" void VRMCCompositor_RequestStop(void) {
    gStopGeneration.store(gGeneration.load());
}

extern "C" int32_t VRMCCompositor_CurrentGeneration(void) {
    return gGeneration.load();
}

/// M4-W2: a tracking-area activation from the SwiftUI onSpatialEvent closure. Published into the
/// bridge gaze mailbox for the JVM provider; no-op with one log line on an old bridge.
extern "C" void VRMCInput_PublishGazeEvent(uint64_t tileId, int32_t phase, int32_t kind) {
    if (tileId == 0) return;
    static int loggedPublish = 0;
    if (gPublishGazeFn == NULL) {
        if (!loggedPublish) {
            loggedPublish = 1;
            NSLog(@"[vrmc-comp] gaze event ignored: bridge has no publish_gaze_event (old bridge)");
        }
        return;
    }
    vrmc_gaze_event event;
    memset(&event, 0, sizeof(event));
    event.tile_id = tileId;
    event.phase = (uint32_t)phase;
    event.kind = (uint32_t)kind;
    event.timestamp_ns = clock_gettime_nsec_np(CLOCK_MONOTONIC);
    int32_t rc = gPublishGazeFn(&event);
    NSLog(@"[vrmc-comp] gaze event tile=%llu phase=%d kind=%d publishRc=%d",
          (unsigned long long)tileId, phase, kind, rc);
}

static void resolveBridge(void);

/// 1 when the provider has published a usable stereo eye frame. The shell polls this after the game
/// starts and opens the immersive space only once there is a real picture to show, instead of after
/// a fixed delay. Pure read: vrmc_shared_acquire_eyes copies the latest frame under the bridge mutex.
extern "C" int32_t VRMCCompositor_ProviderEyesReady(void) {
    resolveBridge();
    if (gAcquireFn == NULL) return 0;
    vrmc_shared_eye_frame frame;
    memset(&frame, 0, sizeof(frame));
    return (gAcquireFn(&frame) == 0 && frame.eyes.left_texture != 0 && frame.eyes.right_texture != 0) ? 1 : 0;
}

/// Provider teardown notification: post on the main queue so the SwiftUI shell can dismiss the
/// immersive space. The bridge calls this directly from nativeSignalGameStopping, and the frame loop
/// also polls the shared flag as a fallback.
extern "C" void VRMCCompositor_NotifyGameStopping(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[vrmc-comp] game stopping: posting VRMCGameStopped");
        [[NSNotificationCenter defaultCenter] postNotificationName:@"VRMCGameStopped" object:nil];
    });
}

static void compLog(const char *fmt, ...) {
    char line[1024];
    va_list args; va_start(args, fmt);
    vsnprintf(line, sizeof(line), fmt, args);
    va_end(args);
    {
        std::lock_guard<std::mutex> lock(gLogMutex);
        NSLog(@"[vrmc-comp] %s", line);
        if (gLog) { fprintf(gLog, "[vrmc-comp] %s\n", line); fflush(gLog); }
    }
}

static void openLog(void) {
    if (gLog) return;
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = paths.firstObject;
    NSString *path = [dir stringByAppendingPathComponent:@"vrmc-compositor.log"];
    // B1 (audit): rotate the append-only session log once per process so one file = one app launch.
    // Whole-file evidence triage otherwise mixes 18+ compositor sessions (false PASS/REGRESSION risk).
    static dispatch_once_t rotateOnce;
    dispatch_once(&rotateOnce, ^{
        NSString *prev = [dir stringByAppendingPathComponent:@"vrmc-compositor.prev.log"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:prev error:nil];
        if ([fm fileExistsAtPath:path]) {
            [fm moveItemAtPath:path toPath:prev error:nil];
        }
    });
    gLog = fopen(path.UTF8String, "a");
}

static void resolveBridge(void) {
    // Called from the compositor thread and (VRMCCompositor_ProviderEyesReady) from the main thread.
    static std::mutex resolveMutex;
    std::lock_guard<std::mutex> resolveLock(resolveMutex);
    if (gEyeFn != NULL) return;
    NSString *path = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/libvrmc_bridge.dylib"];
    void *h = dlopen(path.UTF8String, RTLD_NOW);
    if (h == NULL) {
        h = dlopen("libvrmc_bridge.dylib", RTLD_NOW);
    }
    if (h != NULL) {
        gBridge = h;
        gEyeFn = (eye_targets_fn)dlsym(h, "vrmc_shared_eye_textures");
        gTrackFn = (set_tracking_fn)dlsym(h, "vrmc_shared_set_tracking");
        gDisplayViewsFn = (set_display_views_fn)dlsym(h, "vrmc_shared_set_display_views");
        gAcquireFn = (acquire_eyes_fn)dlsym(h, "vrmc_shared_acquire_eyes");
        gInputPublishFn = (input_publish_fn)dlsym(h, "vrmc_shared_publish_input");
        gInputSequenceFn = (input_sequence_fn)dlsym(h, "vrmc_shared_input_sequence");
        gGameStoppingFn = (game_stopping_fn)dlsym(h, "vrmc_shared_game_stopping");
        gClearGameStoppingFn = (clear_game_stopping_fn)dlsym(h, "vrmc_shared_clear_game_stopping");
        gPublishGazeFn = (publish_gaze_fn)dlsym(h, "vrmc_shared_publish_gaze_event");
        gPublishRenderSettingsFn =
            (publish_render_settings_fn)dlsym(h, "vrmc_shared_publish_render_settings");
        compLog("bridge resolved handle=%p eye=%p tracking=%p displayViews=%p acquireEyes=%p "
                "publishInput=%p inputSeq=%p gameStopping=%p publishRenderSettings=%p",
                h, gEyeFn, gTrackFn, gDisplayViewsFn, gAcquireFn, gInputPublishFn, gInputSequenceFn,
                gGameStoppingFn, gPublishRenderSettingsFn);
        if (gPublishRenderSettingsFn == NULL) {
            compLog("render feedback: bridge dylib has no vrmc_shared_publish_render_settings "
                    "(old bridge?); the provider keeps its own eye-target sizing, presentation "
                    "unaffected");
        }
        if (gInputPublishFn == NULL) {
            // Fail safe on an old bridge: log once and keep presenting. The provider sees no fresh
            // snapshots and releases everything (its stale-input timer), so this can never stick input.
            compLog("input: bridge dylib has no vrmc_shared_publish_input (old v2 bridge?); immersive "
                    "input publication disabled, presentation unaffected");
        }
    }
}

/// Comfort vignette strength from Documents/vrmc-vignette.flag: absent = off; empty content = 0.5;
/// numeric content is clamped to 0..0.9. Read once per immersive session.
static float readVignetteStrength(void) {
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [docs.firstObject stringByAppendingPathComponent:@"vrmc-vignette.flag"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return 0.0f;
    NSString *raw = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSString *trimmed = [(raw ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    float value = trimmed.length == 0 ? 0.5f : trimmed.floatValue;
    if (!(value >= 0.0f)) value = 0.5f;
    return MIN(0.9f, value);
}

/// M6 watchdog heartbeat: written at most ~1 Hz while frames are presenting. The shell treats a stale
/// file as a stalled compositor even if the process is still alive (no crash log otherwise).
static void writeCompositorHeartbeat(int generation, int frameCount, size_t presented,
                                     size_t drawableCount, long layerState) {
    static double lastWrite = 0.0;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    double now = (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
    if (now - lastWrite < 1.0) return;
    lastWrite = now;
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [docs.firstObject stringByAppendingPathComponent:@"vrmc-heartbeat.txt"];
    NSString *text = [NSString stringWithFormat:@"generation=%d frame=%d presented=%zu drawables=%zu layerState=%ld time=%.3f\n",
                      generation, frameCount, presented, drawableCount, layerState, now];
    // Keep filesystem I/O off the render thread. Writes are throttled to <=1 Hz above; a dropped final
    // queued write on abrupt process death is harmless (the watchdog then reports a stale heartbeat).
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    });
}

static BOOL documentFlag(NSString *name) {
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [docs.firstObject stringByAppendingPathComponent:name];
    return [[NSFileManager defaultManager] fileExistsAtPath:path] ? YES : NO;
}

// Release behaviour: every developer surface is OPT-IN. A player must never see the procedural test
// pattern, the coloured mode badge, the red/green clear colours or pay for periodic GPU readbacks
// because the game has not published a frame yet or because a stale flag file was left in Documents
// (device evidence 2026-11-07: two immersive opens showed the test pattern for 715 and 320 frames;
// a leftover vrmc-drawable-dump.flag was still in the container).
// Documents/vrmc-diagnostics.flag turns the diagnostics back on; the simulator/self-test harness
// flags imply it so the existing self-check scripts keep working unchanged.
static BOOL diagnosticsEnabled(void) {
    static int cached = -1;
    if (cached < 0) {
        cached = (documentFlag(@"vrmc-diagnostics.flag") || documentFlag(@"vrmc-immersive-selftest.flag") ||
                  documentFlag(@"vrmc-open-on-launch.flag") || documentFlag(@"vrmc-input-sim.flag")) ? 1 : 0;
    }
    return cached == 1;
}

/// A diagnostic flag file only counts while diagnostics are enabled.
static BOOL diagFlag(NSString *name) {
    return diagnosticsEnabled() && documentFlag(name);
}

// -------------------------------------------------------------------------------------------
// M8: foveated 4K/120 render feedback.
//
// The CompositorServices layer is the only side that knows what the display actually asks for.
// Rather than hardcoding a target (the old M2 provider rendered 1024x1024 per eye regardless of the
// panel), the compositor measures and publishes it through the additive native-shared channel
// (vrmc_render_settings -> vrmc_shared_publish_render_settings):
//
//  - per-eye LOGICAL view size at the current render quality (the size that maps 1:1 to displayed
//    pixels in the fovea; with foveation the PHYSICAL drawable is smaller and the system expands the
//    high-density centre back to the logical size);
//  - foveation / rasterization-rate-map state and the physical drawable extent;
//  - the current/configured render quality;
//  - measured display cadence from consecutive presentation times (display_hz) and the app frame
//    interval EWMA (frame_time_ms).
//
// Dynamic render quality (visionOS 26+): the layer has a configured MAX render quality; the app may
// move the runtime quality inside [0, max] and the system transitions resolution over time. The
// default here is the configured maximum ("4K both eyes" on a device whose panel supports it). The
// optional auto mode (Documents/vrmc-render-quality.txt = "auto" or vrmc-quality-auto.flag) lowers
// quality when measured presentation cadence shows repeated frames and raises it again with
// headroom. A numeric content in vrmc-render-quality.txt pins a fixed runtime quality for A/B.
// -------------------------------------------------------------------------------------------

#define VRMC_PRESENT_WINDOW 240

typedef struct {
    double intervalsMs[VRMC_PRESENT_WINDOW];
    int count;
    int writeIndex;
    double lastPresentationMs;   /* 0 = no previous presentation time yet */
    double baseMs;               /* median interval: the cadence the display actually presents at */
    double p50Ms;
    double p95Ms;
    double meanMs;
    int repeats;                 /* intervals >= 1.5x the median: a frame repeated on display */
    double displayHz;            /* 1000 / p50 (0 = unknown) */
} VRMCPresentationStats;

static void presentationStatsReset(VRMCPresentationStats *stats) {
    memset(stats, 0, sizeof(*stats));
}

static void presentationStatsRecord(VRMCPresentationStats *stats, CFTimeInterval presentationSeconds) {
    if (!isfinite(presentationSeconds)) return;
    const double ms = presentationSeconds * 1000.0;
    if (stats->lastPresentationMs > 0.0) {
        const double interval = ms - stats->lastPresentationMs;
        if (interval > 0.5 && interval < 200.0) {
            stats->intervalsMs[stats->writeIndex] = interval;
            stats->writeIndex = (stats->writeIndex + 1) % VRMC_PRESENT_WINDOW;
            if (stats->count < VRMC_PRESENT_WINDOW) stats->count++;
        }
    }
    stats->lastPresentationMs = ms;
}

/// Sort a copy of the window and compute median/p95/mean/repeats. Cheap enough for a summary every
/// ~120 frames; never called per frame.
static void presentationStatsSummarize(VRMCPresentationStats *stats) {
    if (stats->count <= 0) {
        stats->baseMs = stats->p50Ms = stats->p95Ms = stats->meanMs = stats->displayHz = 0.0;
        stats->repeats = 0;
        return;
    }
    double copy[VRMC_PRESENT_WINDOW];
    memcpy(copy, stats->intervalsMs, sizeof(double) * (size_t)stats->count);
    for (int i = 0; i < stats->count; i++) {
        for (int j = i + 1; j < stats->count; j++) {
            if (copy[j] < copy[i]) { double t = copy[i]; copy[i] = copy[j]; copy[j] = t; }
        }
    }
    double sum = 0.0;
    for (int i = 0; i < stats->count; i++) sum += copy[i];
    stats->meanMs = sum / (double)stats->count;
    stats->p50Ms = copy[(int)((double)(stats->count - 1) * 0.50)];
    stats->p95Ms = copy[(int)((double)(stats->count - 1) * 0.95)];
    stats->baseMs = stats->p50Ms;
    stats->displayHz = stats->baseMs > 0.0 ? 1000.0 / stats->baseMs : 0.0;
    int repeats = 0;
    for (int i = 0; i < stats->count; i++) {
        if (copy[i] > stats->baseMs * 1.5) repeats++;
    }
    stats->repeats = repeats;
}

/// Read a Documents text file; returns nil if absent. Caller gets the trimmed content ("" for an
/// empty flag file). Used by the M8 render-quality override/auto controls.
static NSString *readDocumentText(NSString *name) {
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [docs.firstObject stringByAppendingPathComponent:name];
    NSString *raw = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (raw == nil) return nil;
    return [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

typedef struct {
    BOOL autoMode;        /* adjust runtime quality from measured presentation cadence */
    float fixedQuality;   /* used when autoMode == NO; in [0, maxQuality] */
} VRMCQualityControl;

/// Parse the runtime render-quality override. Absent file => fixed at maxQuality. Content "auto"
/// (case-insensitive) or Documents/vrmc-quality-auto.flag => adaptive mode starting from a
/// conservative quality. Numeric content pins that value (clamped to [0.1, maxQuality]); a flag file
/// with unparsable content falls back to the fixed maximum (never fails the render loop).
static VRMCQualityControl readQualityControl(float maxQuality) {
    VRMCQualityControl control;
    control.autoMode = NO;
    control.fixedQuality = maxQuality > 0.0f ? maxQuality : 1.0f;
    NSString *text = readDocumentText(@"vrmc-render-quality.txt");
    if (text != nil && text.length > 0) {
        if ([text caseInsensitiveCompare:@"auto"] == NSOrderedSame) {
            control.autoMode = YES;
            control.fixedQuality = MIN(maxQuality, 0.75f);
        } else {
            float value = text.floatValue;
            if (value >= 0.0f && value <= 1.0f) {
                control.fixedQuality = MAX(0.1f, MIN(value, maxQuality));
            }
        }
    } else if (documentFlag(@"vrmc-quality-auto.flag")) {
        control.autoMode = YES;
        control.fixedQuality = maxQuality > 0.0f ? MIN(maxQuality, 0.75f) : 0.75f;
    }
    return control;
}

// M8 foveated sharpening control: Documents/vrmc-sharpening.txt = "auto" (default), "off"/"0"
// (disable) or a fixed strength 0.05..1.0. Re-read every ~300 frames so the on-device tuning script
// (scripts/push_m8_render_config.sh) can A/B it live. Default "auto" sharpens only when the provider
// renders below the logical view size (the normal 120 Hz case) and tapers off towards the periphery.
typedef struct {
    BOOL enabled;
    BOOL autoMode;
    float strength;   /* fixed strength when autoMode == NO, clamped to [0.05, 1.0] */
} VRMCSharpenControl;

static VRMCSharpenControl readSharpenControl(void) {
    VRMCSharpenControl control;
    control.enabled = YES;
    control.autoMode = YES;
    control.strength = 0.0f;
    NSString *text = readDocumentText(@"vrmc-sharpening.txt");
    if (text == nil || text.length == 0) return control;
    // NOTE: check "auto" FIRST. text.floatValue of "auto" is 0.0, so testing the numeric/off case
    // first silently disabled sharpening for the default file content (device bug: enabled=0).
    if ([text caseInsensitiveCompare:@"auto"] == NSOrderedSame) return control;
    if ([text caseInsensitiveCompare:@"off"] == NSOrderedSame || text.floatValue == 0.0f) {
        control.enabled = NO;
        return control;
    }
    float value = text.floatValue;
    if (value >= 0.05f && value <= 1.0f) {
        control.autoMode = NO;
        control.strength = value;
    }
    return control;
}

/// Apply a runtime render quality (visionOS 26+). Returns YES when the value was applied.
static BOOL applyRenderQuality(cp_layer_renderer_t lr, float quality, const char *reason) {
    const float clamped = MAX(0.0f, MIN(1.0f, quality));
    cp_layer_renderer_set_render_quality(lr, (cp_render_quality_t)clamped);
    const float applied = (float)cp_layer_renderer_get_render_quality(lr);
    compLog("render quality %.2f applied (requested %.2f, %s)", (double)applied, (double)clamped, reason);
    return YES;
}

// -------------------------------------------------------------------------------------------
// M4-W1 immersive input: ARKit hand tracking -> vrmc_input_state -> bridge (native-shared).
//
// The compositor owns hand tracking and publishes one snapshot per frame. The JVM provider polls it
// (vrmc_poll_input / nativePollInput) and turns pinches/fists into Vivecraft actions. Positions are
// copied in device/anchor space - the same space as vrmc_tracking_state.head - so no extra transform
// crosses the boundary.
//
// Synthetic mode (Documents/vrmc-input-sim.flag) publishes scripted, fabricated 27-joint hands for
// the simulator harness (the visionOS simulator has no ARKit hand data) and for device A/B without
// hands. It is independent of ARKit authorization and is NEVER hands evidence.
// -------------------------------------------------------------------------------------------

enum {
    VRMCInputSimCycle = 0,
    VRMCInputSimPinchRight = 1,
    VRMCInputSimPinchLeft = 2,
    VRMCInputSimFistLeft = 3,
    VRMCInputSimBoth = 4,
};

typedef struct {
    float duration_s;
    unsigned char pinch_left, pinch_right, fist_left, fist_right;
} VRMCInputSimPhase;

// The "cycle" script is what the simulator input scenario uses: it walks both-open -> right pinch ->
// release -> left fist -> release -> both fists -> release, so one lap exercises every gesture the
// provider thresholds distinguish. The per-gesture scripts are device A/B helpers (hold ~2 s).
static const VRMCInputSimPhase kSimCycle[] = {
    {0.35f, 0, 0, 0, 0}, // both hands open (pinch distance / fist ratio above the release thresholds)
    {0.90f, 0, 1, 0, 0}, // right pinch held
    {0.35f, 0, 0, 0, 0},
    {0.90f, 0, 0, 1, 0}, // left fist held
    {0.35f, 0, 0, 0, 0},
    {0.90f, 0, 0, 1, 1}, // both fists held
    {0.35f, 0, 0, 0, 0},
};
static const VRMCInputSimPhase kSimPinchRight[] = {
    {0.60f, 0, 0, 0, 0},
    {2.00f, 0, 1, 0, 0},
};
static const VRMCInputSimPhase kSimPinchLeft[] = {
    {0.60f, 0, 0, 0, 0},
    {2.00f, 1, 0, 0, 0},
};
static const VRMCInputSimPhase kSimFistLeft[] = {
    {0.60f, 0, 0, 0, 0},
    {2.00f, 0, 0, 1, 0},
};
static const VRMCInputSimPhase kSimBoth[] = {
    {0.60f, 0, 0, 0, 0},
    {2.00f, 0, 0, 1, 1},
};

typedef struct {
    const VRMCInputSimPhase *phases;
    int count;
    const char *name;
} VRMCInputSimScript;

static const VRMCInputSimScript kInputSimScripts[] = {
    {kSimCycle, (int)(sizeof(kSimCycle) / sizeof(kSimCycle[0])), "cycle"},
    {kSimPinchRight, (int)(sizeof(kSimPinchRight) / sizeof(kSimPinchRight[0])), "pinch-right"},
    {kSimPinchLeft, (int)(sizeof(kSimPinchLeft) / sizeof(kSimPinchLeft[0])), "pinch-left"},
    {kSimFistLeft, (int)(sizeof(kSimFistLeft) / sizeof(kSimFistLeft[0])), "fist-left"},
    {kSimBoth, (int)(sizeof(kSimBoth) / sizeof(kSimBoth[0])), "both"},
};

// Returns the synthetic-script index when Documents/vrmc-input-sim.flag exists, else -1.
// Content selects the script (pinch-right | pinch-left | fist-left | both | cycle); empty content or
// an unknown value falls back to "cycle".
static int readInputSimScript(const char **nameOut, BOOL *unknownOut) {
    *nameOut = "none";
    if (unknownOut != NULL) *unknownOut = NO;
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [docs.firstObject stringByAppendingPathComponent:@"vrmc-input-sim.flag"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return -1;
    NSString *raw = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSString *trimmed = [(raw ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *content = [trimmed lowercaseString];
    for (int i = 0; i < (int)(sizeof(kInputSimScripts) / sizeof(kInputSimScripts[0])); i++) {
        if ([content isEqualToString:[NSString stringWithUTF8String:kInputSimScripts[i].name]]) {
            *nameOut = kInputSimScripts[i].name;
            return i;
        }
    }
    if (unknownOut != NULL && content.length > 0) *unknownOut = YES;
    *nameOut = kInputSimScripts[VRMCInputSimCycle].name;
    return VRMCInputSimCycle;
}

static double inputSimScriptDuration(int script) {
    if (script < 0 || script >= (int)(sizeof(kInputSimScripts) / sizeof(kInputSimScripts[0]))) script = 0;
    const VRMCInputSimScript *s = &kInputSimScripts[script];
    double total = 0.0;
    for (int i = 0; i < s->count; i++) total += s->phases[i].duration_s;
    return total;
}

// Phase lookup for the scripted synthetic input. Phases loop forever (the provider only consumes
// gesture state, so a repeating diagnostic cycle is exactly what we want).
static void inputSimPhaseAt(int script, double elapsed_s, int *phaseOut) {
    if (script < 0 || script >= (int)(sizeof(kInputSimScripts) / sizeof(kInputSimScripts[0]))) script = 0;
    const VRMCInputSimScript *s = &kInputSimScripts[script];
    const double total = inputSimScriptDuration(script);
    *phaseOut = 0;
    if (!(total > 0.0)) return;
    double t = fmod(elapsed_s, total);
    if (!(t >= 0.0)) t = 0.0;
    double acc = 0.0;
    for (int i = 0; i < s->count; i++) {
        acc += (double)s->phases[i].duration_s;
        if (t < acc) { *phaseOut = i; return; }
    }
    *phaseOut = s->count - 1;
}

// Logging helper for the input channel. Synthetic lines are prefixed INPUT-SIM and say SYNTHETIC so
// a device/simulator log can never be mistaken for real hand tracking.
static void inputLog(BOOL synthetic, const char *fmt, ...) {
    char line[900];
    va_list args; va_start(args, fmt);
    vsnprintf(line, sizeof(line), fmt, args);
    va_end(args);
    if (synthetic) {
        compLog("INPUT-SIM SYNTHETIC %s", line);
    } else {
        compLog("%s", line);
    }
}

static const char *authorizationStatusName(intptr_t status) {
    if (status == (intptr_t)ar_authorization_status_allowed) return "allowed";
    if (status == (intptr_t)ar_authorization_status_denied) return "denied";
    if (status == (intptr_t)ar_authorization_status_not_determined) return "not_determined";
    return "unknown";
}

// Explicitly request hand-tracking authorization (ARKit does NOT prompt implicitly from
// ar_session_run). The handler only logs the result once and signals the wait; it never mutates
// render/session state. Returns the ARKit status, or -1 when no answer arrived in time.
static intptr_t requestHandAuthorization(ar_session_t session, double timeoutSeconds) {
    __block intptr_t status = -1;
    __block BOOL logged = NO;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    ar_session_request_authorization(session, ar_authorization_type_hand_tracking,
                                     ^(ar_authorization_results_t results, ar_error_t error) {
        __block intptr_t resolved = -1;
        if (results != nil && ar_authorization_results_get_count(results) > 0) {
            ar_authorization_results_enumerate_results(results, ^bool(ar_authorization_result_t result) {
                resolved = (intptr_t)ar_authorization_result_get_status(result);
                return false;
            });
        }
        status = resolved;
        if (!logged) {
            logged = YES;
            compLog("hand tracking authorization: request result status=%s errorCode=%ld "
                    "(allowed is required for real hands; synthetic input does not need it)",
                    authorizationStatusName(resolved),
                    error != nil ? (long)ar_error_get_error_code(error) : 0L);
        }
        dispatch_semaphore_signal(done);
    });
    long timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW,
                                                               (int64_t)(timeoutSeconds * 1e9)));
    if (timedOut != 0) {
        compLog("hand tracking authorization: no response within %.1f s (status unknown); "
                "continuing without a hand provider", timeoutSeconds);
        return -1;
    }
    return status;
}

// ABI v3 wire convention: chirality 0 = LEFT, 1 = RIGHT. ARKit's ar_hand_chirality enum is INVERTED
// (ar_hand_chirality_right == 0, ar_hand_chirality_left == 1), so never cast it through: map it.
static uint32_t abiChirality(ar_hand_chirality_t chirality) {
    return (chirality == ar_hand_chirality_left) ? 0u : 1u;
}

// Copy one ARKit hand anchor into the ABI layout (device/anchor space, metres). Returns YES when the
// hand is tracked. Joint transform = anchor origin transform * anchor-from-joint transform, which
// makes the positions directly comparable with vrmc_tracking_state.head (same ARKit origin).
static BOOL fillHandFromAnchor(vrmc_hand_state *hand, ar_hand_anchor_t anchor, uint64_t timestampNs) {
    memset(hand, 0, sizeof(*hand));
    hand->timestamp_ns = timestampNs;
    hand->chirality = abiChirality(ar_hand_anchor_get_chirality(anchor));
    if (!ar_hand_anchor_is_tracked(anchor)) return NO;
    ar_hand_skeleton_t skeleton = ar_hand_anchor_get_hand_skeleton(anchor);
    if (skeleton == nil) return NO;
    simd_float4x4 anchorTransform = ar_hand_anchor_get_origin_from_anchor_transform(anchor);
    simd_float4x4 wristTransform = anchorTransform;
    for (int i = 0; i < VRMC_HAND_JOINT_COUNT; i++) {
        ar_skeleton_joint_t joint =
            ar_hand_skeleton_get_joint_named(skeleton, (ar_hand_skeleton_joint_name_t)i);
        // Defensive: an incomplete skeleton must not publish a tracked hand with zeroed joints.
        if (joint == nil) return NO;
        simd_float4x4 jointTransform = simd_mul(anchorTransform,
                                                ar_skeleton_joint_get_anchor_from_joint_transform(joint));
        hand->joints[i].x = jointTransform.columns[3].x;
        hand->joints[i].y = jointTransform.columns[3].y;
        hand->joints[i].z = jointTransform.columns[3].z;
        if (i == (int)ar_hand_skeleton_joint_name_wrist) wristTransform = jointTransform;
    }
    hand->tracked = 1;
    hand->wrist_position = hand->joints[0];
    simd_quatf orientation = simd_normalize(simd_quaternion(wristTransform));
    hand->wrist_orientation.x = orientation.vector.x;
    hand->wrist_orientation.y = orientation.vector.y;
    hand->wrist_orientation.z = orientation.vector.z;
    hand->wrist_orientation.w = orientation.vector.w;
    return YES;
}

// Synthetic hand local layout (metres, x = wrist->fingers, y = index->little metacarpal,
// z = palm-back normal). Values are chosen so the provider's documented gesture metrics hold:
//  - pinch distance |joint4 - joint9|: 0.005 m pinched vs 0.068 m open (thresholds 0.030/0.045);
//  - fist ratio avg(|joints 9,14,19,24 - joint0|) / |joint11 - joint0|: 0.77 fist vs 1.88 open
//    (thresholds 1.25/1.55);
//  - joint20 - joint5 is a non-degenerate hand width, so the provider can build a pose basis.
static const float kSyntheticHandOpen[VRMC_HAND_JOINT_COUNT][3] = {
    {0.000f,  0.000f, 0.000f}, // 0  wrist
    {0.020f, -0.030f, 0.004f}, // 1  thumb knuckle
    {0.045f, -0.052f, 0.008f}, // 2  thumb intermediate base
    {0.072f, -0.064f, 0.010f}, // 3  thumb intermediate tip
    {0.100f, -0.070f, 0.012f}, // 4  thumb tip
    {0.020f, -0.026f, 0.000f}, // 5  index metacarpal
    {0.080f, -0.026f, 0.000f}, // 6  index knuckle
    {0.112f, -0.026f, 0.000f}, // 7  index intermediate base
    {0.134f, -0.026f, 0.000f}, // 8  index intermediate tip
    {0.150f, -0.026f, 0.000f}, // 9  index tip
    {0.020f,  0.000f, 0.000f}, // 10 middle metacarpal
    {0.080f,  0.000f, 0.000f}, // 11 middle knuckle (palm length)
    {0.112f,  0.000f, 0.000f}, // 12 middle intermediate base
    {0.134f,  0.000f, 0.000f}, // 13 middle intermediate tip
    {0.150f,  0.000f, 0.000f}, // 14 middle tip
    {0.020f,  0.009f, 0.000f}, // 15 ring metacarpal
    {0.080f,  0.009f, 0.000f}, // 16 ring knuckle
    {0.112f,  0.009f, 0.000f}, // 17 ring intermediate base
    {0.134f,  0.009f, 0.000f}, // 18 ring intermediate tip
    {0.150f,  0.009f, 0.000f}, // 19 ring tip
    {0.020f,  0.027f, 0.000f}, // 20 little metacarpal
    {0.080f,  0.027f, 0.000f}, // 21 little knuckle
    {0.112f,  0.027f, 0.000f}, // 22 little intermediate base
    {0.134f,  0.027f, 0.000f}, // 23 little intermediate tip
    {0.150f,  0.027f, 0.000f}, // 24 little tip
    {-0.040f, 0.000f, 0.000f}, // 25 forearm wrist
    {-0.120f, 0.000f, 0.000f}, // 26 forearm arm
};

static const float kSyntheticHandFist[VRMC_HAND_JOINT_COUNT][3] = {
    {0.000f,  0.000f, 0.000f}, // 0  wrist
    {0.020f, -0.030f, 0.004f}, // 1  thumb knuckle
    {0.045f, -0.052f, 0.008f}, // 2  thumb intermediate base
    {0.072f, -0.064f, 0.010f}, // 3  thumb intermediate tip
    {0.100f, -0.070f, 0.012f}, // 4  thumb tip (thumb stays out: no accidental pinch during a fist)
    {0.020f, -0.026f, 0.000f}, // 5  index metacarpal
    {0.080f, -0.026f, 0.000f}, // 6  index knuckle
    {0.100f, -0.026f, 0.012f}, // 7  curled
    {0.075f, -0.026f, 0.028f}, // 8  curled
    {0.045f, -0.026f, 0.036f}, // 9  index tip curled toward the wrist
    {0.020f,  0.000f, 0.000f}, // 10 middle metacarpal
    {0.080f,  0.000f, 0.000f}, // 11 middle knuckle
    {0.100f,  0.000f, 0.014f}, // 12 curled
    {0.075f,  0.000f, 0.030f}, // 13 curled
    {0.045f,  0.000f, 0.040f}, // 14 middle tip curled toward the wrist
    {0.020f,  0.009f, 0.000f}, // 15 ring metacarpal
    {0.080f,  0.009f, 0.000f}, // 16 ring knuckle
    {0.100f,  0.009f, 0.013f}, // 17 curled
    {0.075f,  0.009f, 0.029f}, // 18 curled
    {0.045f,  0.009f, 0.038f}, // 19 ring tip curled toward the wrist
    {0.020f,  0.027f, 0.000f}, // 20 little metacarpal
    {0.080f,  0.027f, 0.000f}, // 21 little knuckle
    {0.100f,  0.027f, 0.011f}, // 22 curled
    {0.075f,  0.027f, 0.026f}, // 23 curled
    {0.045f,  0.027f, 0.034f}, // 24 little tip curled toward the wrist
    {-0.040f, 0.000f, 0.000f}, // 25 forearm wrist
    {-0.120f, 0.000f, 0.000f}, // 26 forearm arm
};

// Build one fabricated hand in device space. The hand is placed in front of the head using the
// device-anchor transform (the same transform that becomes vrmc_tracking_state.head), so synthetic
// poses are plausible in the ABI space; sideSign -1 = left hand, +1 = right hand.
static void buildSyntheticHand(vrmc_hand_state *hand, simd_float4x4 deviceTransform, int sideSign,
                               BOOL pinched, BOOL fisted, uint64_t timestampNs) {
    memset(hand, 0, sizeof(*hand));
    hand->tracked = 1;
    hand->chirality = (sideSign < 0) ? 0u : 1u; // ABI v3: 0 = LEFT, 1 = RIGHT
    hand->timestamp_ns = timestampNs;
    simd_float3 origin = deviceTransform.columns[3].xyz;
    simd_float3 headRight = simd_normalize(deviceTransform.columns[0].xyz);
    simd_float3 headUp = simd_normalize(deviceTransform.columns[1].xyz);
    simd_float3 headForward = simd_normalize(-deviceTransform.columns[2].xyz);
    simd_float3 aim = headForward;
    simd_float3 side = headRight * (float)sideSign;
    simd_float3 up = simd_normalize(simd_cross(side, aim));
    simd_float3 wrist = origin + headForward * 0.32f + headRight * (0.13f * (float)sideSign)
                        + headUp * (-0.10f);
    const float (*local)[3] = fisted ? kSyntheticHandFist : kSyntheticHandOpen;
    float jointLocal[VRMC_HAND_JOINT_COUNT][3];
    memcpy(jointLocal, local, sizeof(jointLocal));
    if (pinched) {
        // Thumb tip exactly 0.005 m from the index tip: below pinchOn (0.030), never above pinchOff.
        simd_float3 indexTip = wrist + aim * jointLocal[9][0] + side * jointLocal[9][1]
                               + up * jointLocal[9][2];
        simd_float3 towardThumb = simd_normalize(simd_make_float3(0.52f, -0.80f, 0.30f));
        simd_float3 thumbTip = indexTip + towardThumb * 0.005f;
        simd_float3 rel = thumbTip - wrist;
        jointLocal[4][0] = simd_dot(rel, aim);
        jointLocal[4][1] = simd_dot(rel, side);
        jointLocal[4][2] = simd_dot(rel, up);
    }
    for (int i = 0; i < VRMC_HAND_JOINT_COUNT; i++) {
        simd_float3 p = wrist + aim * jointLocal[i][0] + side * jointLocal[i][1]
                        + up * jointLocal[i][2];
        hand->joints[i].x = p.x;
        hand->joints[i].y = p.y;
        hand->joints[i].z = p.z;
    }
    hand->wrist_position = hand->joints[0];
    // Orientation basis (x = side, y = up, z = -aim) so R*(0,0,-1) == aim, matching the provider's
    // pose derivation from joints.
    simd_float4x4 basis = simd_matrix(simd_make_float4(side.x, side.y, side.z, 0.0f),
                                      simd_make_float4(up.x, up.y, up.z, 0.0f),
                                      simd_make_float4(-aim.x, -aim.y, -aim.z, 0.0f),
                                      simd_make_float4(wrist.x, wrist.y, wrist.z, 1.0f));
    simd_quatf orientation = simd_normalize(simd_quaternion(basis));
    hand->wrist_orientation.x = orientation.vector.x;
    hand->wrist_orientation.y = orientation.vector.y;
    hand->wrist_orientation.z = orientation.vector.z;
    hand->wrist_orientation.w = orientation.vector.w;
}

// 0 = auto (reprojection unless the diagnostics say the mapping is unusable), 1 = force reprojection,
// 2 = force flat fullscreen sampling (the EV-0083/84/85 known-good path).
enum { VRMCReprojAuto = 0, VRMCReprojForced = 1, VRMCReprojFlat = 2 };

static int readReprojMode(void) {
    if (documentFlag(@"vrmc-reproj-off.flag")) return VRMCReprojFlat;
    if (documentFlag(@"vrmc-reproj-on.flag")) return VRMCReprojForced;
    return VRMCReprojAuto;
}

// Per-view reprojection parameters (must match ViewParams in kShaderSource).
typedef struct {
    simd_float4x4 invProjection; // drawable view NDC -> view space (cp_drawable_compute_projection, right_up_back)
    simd_float4x4 viewToDevice;  // cp_view_get_transform: eye relative to the device anchor
    simd_float4 sourceTangents;  // provider eye frustum: left, right, down, up (signed tangents, -Z forward)
    simd_float4 misc;            // x: > 0.5 -> colour-code failure branches instead of clamping
} VRMCViewParams;

// One CPU-side ray->UV evaluation, mirroring the fragment shader exactly.
typedef struct {
    BOOL finite;    // all intermediate values finite and w != 0
    BOOL behind;    // ray does not go through the provider camera (-Z) half-space
    BOOL inside;    // uv inside [0,1] (only meaningful when finite && !behind)
    simd_float3 dir; // device-space ray direction
    simd_float2 t;  // tangent (dir.xy / -dir.z)
    simd_float2 uv;
} VRMCRayDiag;

static VRMCRayDiag evaluateRay(simd_float4x4 invProjection, simd_float4x4 viewToDevice,
                               simd_float4 sourceTangents, float ndcX, float ndcY) {
    VRMCRayDiag r;
    memset(&r, 0, sizeof(r));
    simd_float4 v = simd_mul(invProjection, simd_make_float4(ndcX, ndcY, 0.5f, 1.0f));
    if (!(fabsf(v.w) > 1e-9f)) return r;
    simd_float3 vp = simd_make_float3(v.x / v.w, v.y / v.w, v.z / v.w);
    if (!isfinite(vp.x) || !isfinite(vp.y) || !isfinite(vp.z)) return r;
    simd_float4 d4 = simd_mul(viewToDevice, simd_make_float4(vp.x, vp.y, vp.z, 0.0f));
    simd_float3 d = simd_make_float3(d4.x, d4.y, d4.z);
    if (!isfinite(d.x) || !isfinite(d.y) || !isfinite(d.z)) return r;
    r.finite = YES;
    r.dir = d;
    if (!(d.z < -1e-4f)) {
        r.behind = YES;
        return r;
    }
    float invZ = 1.0f / -d.z;
    r.t = simd_make_float2(d.x * invZ, d.y * invZ);
    if (!isfinite(r.t.x) || !isfinite(r.t.y)) { r.finite = NO; return r; }
    simd_float2 uv = simd_make_float2((r.t.x - sourceTangents.x) / (sourceTangents.y - sourceTangents.x),
                                      (sourceTangents.w - r.t.y) / (sourceTangents.w - sourceTangents.z));
    r.uv = uv;
    if (!isfinite(uv.x) || !isfinite(uv.y)) { r.finite = NO; return r; }
    r.inside = (uv.x >= 0.0f && uv.x <= 1.0f && uv.y >= 0.0f && uv.y <= 1.0f) ? YES : NO;
    return r;
}

// The provider renders each eye with its own frustum relative to the head (device anchor) orientation.
// CompositorServices views have their own asymmetric frustum and may be rotated relative to the device,
// so stretching the eye image over the drawable puts the provider's "straight ahead" at the drawable
// centre, which on Vision Pro lies temporally of the optical axis -> both eyes diverge (exotropia).
// Instead, every drawable pixel is turned into a device-space ray and looked up in the provider's frustum.
static NSString *const kShaderBody =
    @"#include <metal_stdlib>\n"
     "using namespace metal;\n"
     "struct ViewParams { float4x4 invProjection; float4x4 viewToDevice; float4 sourceTangents; float4 misc; };\n"
     "struct VOut { float4 pos [[position]]; float2 ndc; };\n"
     "vertex VOut vmain(uint vid [[vertex_id]]) {\n"
     "  float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };\n"
     "  VOut o; o.pos = float4(p[vid], 0, 1); o.ndc = p[vid]; return o;\n"
     "}\n"
     // Mode badge: top 1.5% of the drawable is tinted by the active path so the operator can report it.
     // red = reprojection, green = flat sampling, blue = test pattern.
     "fragment float4 fmain_flat(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],\n"
     "                           sampler s [[sampler(0)]]) {\n"
     "#if VRMC_BADGE\n"
     "  if (in.ndc.y > 0.985) return float4(float3(0.1,0.8,0.1), 1.0);\n"
     "#endif\n"
     "  float2 uv = float2((in.ndc.x + 1.0) * 0.5, (1.0 - in.ndc.y) * 0.5);\n"
     "  return float4(tex.sample(s, uv).rgb, 1.0);\n"
     "}\n"
     // Comfort vignette (M5): darkens the periphery of the flat-sampled image by a configurable
     // amount. Uses the drawable NDC radius; centre remains unmodified, edges darken progressively.
     "fragment float4 fmain_flat_vignette(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],\n"
     "                                    sampler s [[sampler(0)]], constant float &vig [[buffer(1)]]) {\n"
     "  float2 uv = float2((in.ndc.x + 1.0) * 0.5, (1.0 - in.ndc.y) * 0.5);\n"
     "  float4 c = tex.sample(s, uv);\n"
     "  float r = length(in.ndc);\n"
     "  float f = 1.0 - clamp(vig, 0.0, 0.95) * smoothstep(0.55, 1.0, r);\n"
     "  return float4(c.rgb * f, 1.0);\n"
     "}\n"
     // M8 foveated sharpening (CAS-lite): used when the provider renders below the display's logical
     // view size (the normal case when holding 120 Hz at a 4K-class drawable), so the flat bilinear
     // upscale is sharpened back towards display resolution. Strength is highest at the view centre
     // (the fovea) and tapers off in the periphery, where the hardware foveation already gives fewer
     // physical pixels. Edge protection (soft clamp to the local neighbourhood + small headroom)
     // limits halos. Optional comfort vignette is folded into the same pass.
     "struct FlatFx { float strength; float vignette; float texelW; float texelH; float aa; };\n"
     "// Perceptual luma of the linear (sRGB-decoded) sample, for edge detection.\n"
     "static inline float vrmcLuma(float3 c) { return sqrt(max(dot(c, float3(0.299, 0.587, 0.114)), 0.0)); }\n"
     "static inline float vrmcL(texture2d<float> t, sampler s, float2 uv) { return vrmcLuma(t.sample(s, uv).rgb); }\n"
     "// Edge anti-aliasing at the GAME's resolution (FXAA-style), run once per new game frame into a\n"
     "// compositor-owned texture that the upscale pass then samples. Minecraft has no MSAA and the image\n"
     "// is upscaled ~2x to the display, so every block edge was a magnified stair-step. Fragment centres\n"
     "// are source texel centres here, so the edge search is exact.\n"
     "fragment float4 fmain_fxaa(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],\n"
     "                           sampler s [[sampler(0)]], constant float2 &px [[buffer(4)]]) {\n"
     "  float2 uv = float2((in.ndc.x + 1.0) * 0.5, (1.0 - in.ndc.y) * 0.5);\n"
     "  float3 c = tex.sample(s, uv).rgb;\n"
     "  float lM = vrmcLuma(c);\n"
     "  float lN = vrmcL(tex, s, uv + float2(0.0, -px.y)), lS = vrmcL(tex, s, uv + float2(0.0, px.y));\n"
     "  float lW = vrmcL(tex, s, uv + float2(-px.x, 0.0)), lE = vrmcL(tex, s, uv + float2(px.x, 0.0));\n"
     "  float lMin = min(lM, min(min(lN, lS), min(lW, lE)));\n"
     "  float lMax = max(lM, max(max(lN, lS), max(lW, lE)));\n"
     "  float range = lMax - lMin;\n"
     "  if (range < max(0.0312, lMax * 0.125)) return float4(c, 1.0);\n"
     "  float lNW = vrmcL(tex, s, uv + float2(-px.x, -px.y)), lNE = vrmcL(tex, s, uv + float2(px.x, -px.y));\n"
     "  float lSW = vrmcL(tex, s, uv + float2(-px.x, px.y)), lSE = vrmcL(tex, s, uv + float2(px.x, px.y));\n"
     "  float edgeH = abs(lNW + lNE - 2.0 * lN) + 2.0 * abs(lW + lE - 2.0 * lM) + abs(lSW + lSE - 2.0 * lS);\n"
     "  float edgeV = abs(lNW + lSW - 2.0 * lW) + 2.0 * abs(lN + lS - 2.0 * lM) + abs(lNE + lSE - 2.0 * lE);\n"
     "  bool horz = edgeH >= edgeV;\n"
     "  float l1 = horz ? lN : lW;\n"
     "  float l2 = horz ? lS : lE;\n"
     "  float g1 = l1 - lM, g2 = l2 - lM;\n"
     "  bool steep1 = abs(g1) >= abs(g2);\n"
     "  float gradScaled = 0.25 * max(abs(g1), abs(g2));\n"
     "  float stepLen = horz ? px.y : px.x;\n"
     "  float lLocal;\n"
     "  if (steep1) { stepLen = -stepLen; lLocal = 0.5 * (l1 + lM); } else { lLocal = 0.5 * (l2 + lM); }\n"
     "  float2 cuv = uv;\n"
     "  if (horz) cuv.y += stepLen * 0.5; else cuv.x += stepLen * 0.5;\n"
     "  float2 off = horz ? float2(px.x, 0.0) : float2(0.0, px.y);\n"
     "  float2 uv1 = cuv - off, uv2 = cuv + off;\n"
     "  float le1 = vrmcL(tex, s, uv1) - lLocal, le2 = vrmcL(tex, s, uv2) - lLocal;\n"
     "  bool d1 = abs(le1) >= gradScaled, d2 = abs(le2) >= gradScaled;\n"
     "  const float steps[10] = {1.0, 1.0, 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0};\n"
     "  for (int i = 0; i < 10 && !(d1 && d2); i++) {\n"
     "    if (!d1) { uv1 -= off * steps[i]; le1 = vrmcL(tex, s, uv1) - lLocal; d1 = abs(le1) >= gradScaled; }\n"
     "    if (!d2) { uv2 += off * steps[i]; le2 = vrmcL(tex, s, uv2) - lLocal; d2 = abs(le2) >= gradScaled; }\n"
     "  }\n"
     "  float dist1 = horz ? (uv.x - uv1.x) : (uv.y - uv1.y);\n"
     "  float dist2 = horz ? (uv2.x - uv.x) : (uv2.y - uv.y);\n"
     "  bool dir1 = dist1 < dist2;\n"
     "  float edgeLen = max(dist1 + dist2, 1e-6);\n"
     "  float pixOff = -min(dist1, dist2) / edgeLen + 0.5;\n"
     "  bool correct = ((dir1 ? le1 : le2) < 0.0) != (lM < lLocal);\n"
     "  float finalOff = correct ? pixOff : 0.0;\n"
     "  float lAvg = (2.0 * (lN + lS + lW + lE) + lNW + lNE + lSW + lSE) / 12.0;\n"
     "  float sub1 = clamp(abs(lAvg - lM) / max(range, 1e-4), 0.0, 1.0);\n"
     "  float sub2 = (-2.0 * sub1 + 3.0) * sub1 * sub1;\n"
     "  finalOff = max(finalOff, sub2 * sub2 * 0.75);\n"
     "  float2 fuv = uv;\n"
     "  if (horz) fuv.y += finalOff * stepLen; else fuv.x += finalOff * stepLen;\n"
     "  return float4(tex.sample(s, fuv).rgb, 1.0);\n"
     "}\n"
     "// Upscale pass: bilinear + fovea-weighted CAS-lite sharpening + optional comfort vignette.\n"
     "// fx.aa > 0.5 means the input was anti-aliased above: strong edges are then not sharpened again\n"
     "// (sharpening a stair-step is what made the jaggies stand out).\n"
     "fragment float4 fmain_flat_sharp(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],\n"
     "                                 sampler s [[sampler(0)]], constant FlatFx &fx [[buffer(3)]]) {\n"
     "#if VRMC_BADGE\n"
     "  if (in.ndc.y > 0.985) return float4(float3(0.1,0.8,0.1), 1.0);\n"
     "#endif\n"
     "  float2 uv = float2((in.ndc.x + 1.0) * 0.5, (1.0 - in.ndc.y) * 0.5);\n"
     "  float3 c = tex.sample(s, uv).rgb;\n"
     "  float3 n = tex.sample(s, uv + float2(0.0, -fx.texelH)).rgb;\n"
     "  float3 sN = tex.sample(s, uv + float2(0.0, fx.texelH)).rgb;\n"
     "  float3 w = tex.sample(s, uv + float2(-fx.texelW, 0.0)).rgb;\n"
     "  float3 e = tex.sample(s, uv + float2(fx.texelW, 0.0)).rgb;\n"
     "  float3 blur = (n + sN + w + e) * 0.25;\n"
     "  float3 lo = min(min(c, n), min(sN, min(w, e)));\n"
     "  float3 hi = max(max(c, n), max(sN, max(w, e)));\n"
     "  float r = length(in.ndc);\n"
     "  float foveal = 1.0 - smoothstep(0.50, 1.10, r);\n"
     "  float strength = fx.strength * foveal;\n"
     "  if (fx.aa > 0.5) {\n"
     "    float contrast = vrmcLuma(hi) - vrmcLuma(lo);\n"
     "    strength *= 1.0 - smoothstep(0.10, 0.30, contrast);\n"
     "  }\n"
     "  float3 sharp = c + (c - blur) * strength;\n"
     "  sharp = clamp(sharp, lo - 0.06, hi + 0.06);\n"
     "  float vig = 1.0 - clamp(fx.vignette, 0.0, 0.95) * smoothstep(0.55, 1.0, r);\n"
     "  return float4(clamp(sharp, 0.0, 1.0) * vig, 1.0);\n"
     "}\n"
     "fragment float4 fmain_reproj(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],\n"
     "                             sampler s [[sampler(0)]], constant ViewParams &vp [[buffer(0)]]) {\n"
     "#if VRMC_BADGE\n"
     "  if (in.ndc.y > 0.985) return float4(float3(0.9,0.1,0.1), 1.0);\n"
     "#endif\n"
     "  float flatU = (in.ndc.x + 1.0) * 0.5;\n"
     "  float flatV = (1.0 - in.ndc.y) * 0.5;\n"
     "  float4 v = vp.invProjection * float4(in.ndc, 0.5, 1.0);\n"
     "  float3 d = (vp.viewToDevice * float4(v.xyz / v.w, 0.0)).xyz;\n"
     "  bool debug = vp.misc.x > 0.5;\n"
     "  if (!(d.z < -1e-4)) return debug ? float4(0.0,0.0,1.0,1.0) : tex.sample(s, float2(flatU, flatV));\n"
     "  float2 t = d.xy / -d.z;\n"
     "  float4 st = vp.sourceTangents;\n"
     "  float2 uv = float2((t.x - st.x) / (st.y - st.x), (st.w - t.y) / (st.w - st.z));\n"
     "  if (any(isnan(uv)) || any(isinf(uv))) {\n"
     "    return debug ? float4(1.0,0.5,0.0,1.0) : tex.sample(s, float2(flatU, flatV));\n"
     "  }\n"
     "  if (any(uv < 0.0) || any(uv > 1.0)) {\n"
     "    if (debug) return float4(1.0,0.0,1.0,1.0);\n"
     "    uv = clamp(uv, 0.0, 1.0);\n"
     "  }\n"
     "  return float4(tex.sample(s, uv).rgb, 1.0);\n"
     "}\n"
     // Eye-distinct stereo / alignment test pattern. viewInfo = (eyeIndex 0=left/1=right, width, height, 0).\n"
     // - left eye gets a warm/red tint, right eye a green tint (fused correctly if the eyes are aligned;\n"
     //   a single-eye look also shows which image each eye receives);\n"
     // - a white centre cross is drawn in EACH eye at its image centre: with correct stereo optics the two\n"
     //   crosses fuse into one sharp cross; doubled crosses mean a per-eye offset / misalignment;\n"
     // - a corner marker (red left / green right) lets the operator close one eye and confirm eye order.\n"
     "fragment float4 fmain_test(VOut in [[stage_in]], constant float4 &viewInfo [[buffer(2)]]) {\n"
     "  float2 uv = in.ndc * 0.5 + 0.5;\n"
     "  bool isLeft = viewInfo.x < 0.5;\n"
     "  float2 px = uv * viewInfo.yz;\n"
     "  float3 col = isLeft ? float3(0.55 + 0.35 * uv.x, 0.20 + 0.15 * uv.y, 0.25)\n"
     "                     : float3(0.20, 0.45 + 0.35 * uv.y, 0.30 + 0.25 * uv.x);\n"
     "  float2 g = fract(uv * 10.0);\n"
     "  if (g.x < 0.02 || g.y < 0.02) col = float3(0.85, 0.85, 0.35);\n"
     // fused-alignment cross (white, ~3 px thick at the eye image centre)\n"
     "  float2 d = abs(px - viewInfo.yz * 0.5);\n"
     "  if ((d.x < 3.0 && d.y < 60.0) || (d.y < 3.0 && d.x < 60.0)) col = float3(1.0, 1.0, 1.0);\n"
     // eye marker: 90x90 px square 60 px inset from the top-left, red = left eye, green = right eye\n"
     "  float2 m = px - float2(60.0, 60.0);\n"
     "  if (m.x >= 0.0 && m.y >= 0.0 && m.x < 90.0 && m.y < 90.0) {\n"
     "    bool edge = (m.x < 4.0 || m.y < 4.0 || m.x > 86.0 || m.y > 86.0);\n"
     "    col = edge ? float3(1.0, 1.0, 1.0) : (isLeft ? float3(1.0, 0.1, 0.1) : float3(0.1, 1.0, 0.1));\n"
     "  }\n"
     "#if VRMC_BADGE\n"
     "  if (in.ndc.y > 0.985) return float4(float3(0.1,0.3,1.0), 1.0);\n"
     "#endif\n"
     "  return float4(col, 1.0);\n"
     "}\n"
     // Present-proof overlay (vrmc-present-proof.flag / vrmc-immersive-selftest.flag): an 8 px
     // white/cyan checker border plus a magenta centre cross. Drawn after the main draw, interior
     // fragments discarded, so it cannot change what the sampled path shows.
     // Present-proof overlay: only the 8 px border (the test pattern owns the centre cross so the\n"
     // operator can judge stereo fusion of two white crosses; an overlay cross would hide it).\n"
     "fragment float4 fmain_proof(VOut in [[stage_in]], constant float2 &vpSize [[buffer(2)]]) {\n"
     "  float2 px = (in.ndc * 0.5 + 0.5) * vpSize;\n"
     "  bool inBorder = (px.x < 8.0) || (px.y < 8.0) || (px.x > vpSize.x - 8.0) || (px.y > vpSize.y - 8.0);\n"
     "  if (!inBorder) discard_fragment();\n"
     "  float checker = fmod(floor(px.x / 8.0) + floor(px.y / 8.0), 2.0);\n"
     "  return checker > 0.5 ? float4(1.0, 1.0, 1.0, 1.0) : float4(0.0, 1.0, 1.0, 1.0);\n"
     "}\n"
     // M4-W2 tracking-area mask: each drawable pixel gets the unsigned render value of its grid tile.
     // The mask texture is tiny (grid_w x grid_h) and is nearest-sampled; RV 0 means "no area".
     "fragment uint fmain_tracking(VOut in [[stage_in]], texture2d<uint> mask [[texture(3)]],\n"
     "                             sampler s [[sampler(3)]]) {\n"
     "  float2 uv = float2((in.ndc.x + 1.0) * 0.5, (1.0 - in.ndc.y) * 0.5);\n"
     "  return mask.sample(s, uv).r;\n"
     "}\n"
     "fragment ushort fmain_tracking_u16(VOut in [[stage_in]], texture2d<uint> mask [[texture(3)]],\n"
     "                                   sampler s [[sampler(3)]]) {\n"
     "  float2 uv = float2((in.ndc.x + 1.0) * 0.5, (1.0 - in.ndc.y) * 0.5);\n"
     "  return (ushort)mask.sample(s, uv).r;\n"
     "}\n";

/// Shader source with the developer mode badge compiled in only while diagnostics are enabled.
static NSString *shaderSource(void) {
    return [NSString stringWithFormat:@"#define VRMC_BADGE %d\n%@", diagnosticsEnabled() ? 1 : 0, kShaderBody];
}

// Provider FOV is reported as half-angles in radians, OpenXR-style signs (left/down negative).
static simd_float4 sourceTangentsFromFov(const float fov[4]) {
    if (fov[0] == 0.0f && fov[1] == 0.0f && fov[2] == 0.0f && fov[3] == 0.0f) {
        // Provider did not report its frustum: assume the old NullVR 110 deg symmetric default.
        float t = tanf(55.0f * (float)M_PI / 180.0f);
        return simd_make_float4(-t, t, -t, t);
    }
    return simd_make_float4(tanf(fov[0]), tanf(fov[1]), tanf(fov[3]), tanf(fov[2]));
}

// View-space tangents (left, right, down, up) of a drawable view, from its inverse projection.
static simd_float4 viewTangents(simd_float4x4 invProjection) {
    simd_float4 tangents = simd_make_float4(0, 0, 0, 0);
    float ndc[4][2] = { {-1, 0}, {1, 0}, {0, -1}, {0, 1} };
    for (int k = 0; k < 4; k++) {
        simd_float4 v = simd_mul(invProjection, simd_make_float4(ndc[k][0], ndc[k][1], 0.5f, 1.0f));
        simd_float3 p = v.xyz / v.w;
        tangents[k] = (k < 2 ? p.x : p.y) / -p.z;
    }
    return tangents;
}

static void logMatrix(const char *label, simd_float4x4 m) {
    compLog("%s col0=(%.4f,%.4f,%.4f,%.4f) col1=(%.4f,%.4f,%.4f,%.4f)", label,
            m.columns[0].x, m.columns[0].y, m.columns[0].z, m.columns[0].w,
            m.columns[1].x, m.columns[1].y, m.columns[1].z, m.columns[1].w);
    compLog("%s col2=(%.4f,%.4f,%.4f,%.4f) col3=(%.4f,%.4f,%.4f,%.4f)", label,
            m.columns[2].x, m.columns[2].y, m.columns[2].z, m.columns[2].w,
            m.columns[3].x, m.columns[3].y, m.columns[3].z, m.columns[3].w);
}

// 32x32 centre-strip luminance readback of a provider eye texture. This distinguishes a black
// provider texture (game/renderer side) from a wrong compositor mapping - the decisive EV-0086
// follow-up. Runs at most once every ~300 frames per eye, asynchronous (never blocks the loop).
static void scheduleProviderTextureStats(id<MTLCommandQueue> queue, id<MTLTexture> tex,
                                         const char *label, int frameCount) {
    if (tex == nil || tex.pixelFormat != MTLPixelFormatRGBA8Unorm) return;
    if (tex.width < 64 || tex.height < 64) return;
    const NSUInteger W = 32, H = 32;
    const NSUInteger rowBytes = W * 4;
    id<MTLBuffer> buffer = [queue.device newBufferWithLength:rowBytes * H
                                                     options:MTLResourceStorageModeShared];
    if (buffer == nil) return;
    id<MTLCommandBuffer> cb = [queue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    if (blit == nil) { [cb commit]; return; }
    [blit copyFromTexture:tex sourceSlice:0 sourceLevel:0
             sourceOrigin:MTLOriginMake(tex.width / 2 - W / 2, tex.height / 2 - H / 2, 0)
               sourceSize:MTLSizeMake(W, H, 1)
                 toBuffer:buffer destinationOffset:0 destinationBytesPerRow:rowBytes
       destinationBytesPerImage:rowBytes * H];
    [blit endEncoding];
    NSString *name = [NSString stringWithUTF8String:label];
    int capturedFrame = frameCount;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        if (completed.status != MTLCommandBufferStatusCompleted) {
            compLog("provider tex %s readback failed status=%ld", label, (long)completed.status);
            return;
        }
        const uint8_t *pixels = (const uint8_t *)buffer.contents;
        if (pixels == NULL) return;
        uint64_t sum[3] = {0, 0, 0};
        uint64_t alphaSum = 0;
        uint8_t maxValue[3] = {0, 0, 0};
        NSUInteger nonBlack = 0;
        for (NSUInteger i = 0; i < W * H; i++) {
            BOOL any = NO;
            for (int c = 0; c < 3; c++) {
                uint8_t value = pixels[i * 4 + (NSUInteger)c];
                sum[c] += value;
                if (value > maxValue[c]) maxValue[c] = value;
                if (value != 0) any = YES;
            }
            alphaSum += pixels[i * 4 + 3];
            if (any) nonBlack++;
        }
        const double count = (double)(W * H);
        const float meanLuma = (float)((sum[0] + sum[1] + sum[2]) / (3.0 * count));
        if (label[0] == 'L') {
            gTexMeanL.store(meanLuma);
            gTexBlackStreakL.store(meanLuma < 1.0f ? gTexBlackStreakL.load() + 1 : 0);
        } else {
            gTexMeanR.store(meanLuma);
            gTexBlackStreakR.store(meanLuma < 1.0f ? gTexBlackStreakR.load() + 1 : 0);
        }
        compLog("provider tex %s %s: mean=(%.1f,%.1f,%.1f) alpha=%.1f max=(%u,%u,%u) nonBlack=%lu/%lu luma=%.2f frame=%d",
                label, name.UTF8String, sum[0] / count, sum[1] / count, sum[2] / count,
                (double)alphaSum / count,
                (unsigned)maxValue[0], (unsigned)maxValue[1], (unsigned)maxValue[2],
                (unsigned long)nonBlack, (unsigned long)(W * H), (double)meanLuma, capturedFrame);
    }];
    [cb commit];
}


// -------------------------------------------------------------------------------------------
// M3c hardening after EV-0090/EV-0091 (immersive black while frames present).
//
// The old build could not prove WHAT reached the drawable and drew exactly one (deprecated,
// singular) drawable. Everything below either fixes that or logs it as evidence:
//
//  1. cp_frame_query_drawables (visionOS 26+; cp_frame_query_drawable is deprecated) -> render
//     and present EVERY drawable, log its target (built_in / capture), view/texture/rate-map
//     counts. A display that only ever receives an untouched drawable is the leading explanation
//     for "black immersive while command buffers complete and the sampled eye texture is bright".
//  2. Pipelines are built from the ACTUAL drawable attachment formats (lazily rebuilt if they
//     differ from the layer configuration), and a nil colour texture / nil render encoder is
//     logged loudly: with an invalid render pass not even the load-action clear colours reach the
//     drawable, which is the only way to get black instead of the red/green clear.
//  3. DRAWN-DRAWABLE readback: 64 strided full-width rows of each eye's drawable colour texture
//     are blitted into a shared buffer inside the frame command buffer (after the render passes,
//     before encodePresent), decoded to a 64x64 RGBA8 image, logged (mean/max/luma/top-strip/
//     centre) and written to Documents/vrmc-drawable-L.raw / -R.raw (+ .meta). This is ground
//     truth of what was presented, with no operator judgement.
//  4. Optional present-proof overlay / clear-only probe / wait-for-completion, all flag-driven:
//       vrmc-present-proof.flag  bright 8 px checker border + magenta centre cross per view
//       vrmc-clear-probe.flag    clear-only (magenta left / cyan right), NO draws
//       vrmc-drawable-dump.flag  write the raw drawable image on every probe frame
//       vrmc-present-wait.flag   [cb waitUntilCompleted] before cp_frame_end_submission
//       vrmc-immersive-selftest.flag  force test pattern + present proof + raw dumps (shell side
//                                opens the immersive space without the game)
//  5. cp_frame_end_submission is never called for a frame that presented no drawable (the
//     framework aborts on that as a client bug), and the rate-map index is bounded by
//     cp_drawable_get_rasterization_rate_map_count instead of blindly using the texture index.
// -------------------------------------------------------------------------------------------

/// M8 foveated sharpening uniforms (matches the FlatFx struct in kShaderSource).
typedef struct {
    float strength;
    float vignette;
    float texelW;
    float texelH;
    float aa;        /* > 0.5: FXAA-style edge anti-aliasing in the upscale pass */
} VRMCFlatFx;

/// Edge anti-aliasing (on by default; Documents/vrmc-aa.txt = "off" disables it for A/B).
static BOOL readAAEnabled(void) {
    NSString *text = readDocumentText(@"vrmc-aa.txt");
    if (text == nil || text.length == 0) return YES;
    return !([text caseInsensitiveCompare:@"off"] == NSOrderedSame || [text isEqualToString:@"0"]);
}

typedef struct {
    id<MTLRenderPipelineState> reproj;
    id<MTLRenderPipelineState> flat;
    id<MTLRenderPipelineState> test;
    id<MTLRenderPipelineState> proof;
    id<MTLRenderPipelineState> flatVignette;
    id<MTLRenderPipelineState> flatSharp;
    MTLPixelFormat colorFormat;
    MTLPixelFormat depthFormat;
    BOOL valid;
} VRMCPipelines;

static BOOL buildPipelines(id<MTLDevice> device, VRMCPipelines *out, MTLPixelFormat colorFormat,
                           MTLPixelFormat depthFormat) {
    out->reproj = nil;
    out->flat = nil;
    out->test = nil;
    out->proof = nil;
    out->flatVignette = nil;
    out->flatSharp = nil;
    out->valid = NO;
    out->colorFormat = colorFormat;
    out->depthFormat = depthFormat;
    NSError *err = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:shaderSource() options:nil error:&err];
    if (library == nil) {
        compLog("shader library failed: %s", err.description.UTF8String);
        return NO;
    }
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [library newFunctionWithName:@"vmain"];
    pd.colorAttachments[0].pixelFormat = colorFormat;
    pd.depthAttachmentPixelFormat = depthFormat;

    pd.fragmentFunction = [library newFunctionWithName:@"fmain_reproj"];
    out->reproj = [device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (out->reproj == nil) compLog("reproj pipeline failed: %s", err.description.UTF8String);
    err = nil;
    pd.fragmentFunction = [library newFunctionWithName:@"fmain_flat"];
    out->flat = [device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (out->flat == nil) compLog("flat pipeline failed: %s", err.description.UTF8String);
    err = nil;
    pd.fragmentFunction = [library newFunctionWithName:@"fmain_test"];
    out->test = [device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (out->test == nil) compLog("test pipeline failed: %s", err.description.UTF8String);
    err = nil;
    pd.fragmentFunction = [library newFunctionWithName:@"fmain_proof"];
    out->proof = [device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (out->proof == nil) compLog("proof pipeline failed: %s", err.description.UTF8String);
    err = nil;
    pd.fragmentFunction = [library newFunctionWithName:@"fmain_flat_vignette"];
    out->flatVignette = [device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (out->flatVignette == nil) compLog("flat vignette pipeline failed: %s", err.description.UTF8String);
    err = nil;
    pd.fragmentFunction = [library newFunctionWithName:@"fmain_flat_sharp"];
    out->flatSharp = [device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (out->flatSharp == nil) compLog("flat sharpen pipeline failed: %s", err.description.UTF8String);
    out->valid = (out->reproj != nil || out->flat != nil || out->test != nil);
    compLog("pipelines color=%lu depth=%lu reproj=%d flat=%d test=%d proof=%d flatVignette=%d flatSharp=%d",
            (unsigned long)colorFormat, (unsigned long)depthFormat,
            out->reproj != nil, out->flat != nil, out->test != nil, out->proof != nil,
            out->flatVignette != nil, out->flatSharp != nil);
    return out->valid;
}


// -------------------------------------------------------------------------------------------
// M4-W2 gaze: a grid of CompositorServices tracking areas over the presented layer.
//
// The system applies the true-gaze hover effect to the area under the user's eyes and tags indirect
// pinch activations with that area's identifier (SwiftUI onSpatialEvent -> VRMCInput_PublishGazeEvent).
// Everything here is fail-safe: flag-gated (Documents/vrmc-gaze.flag), integer-format only, and any
// missing capability/pipeline disables gaze with one log line while presentation continues unchanged.
//
// The mask is 1 pixel per tile; the fragment shader expands it to the tracking-area texture. The tile
// grid is the same in both eyes (identifiers are stable across frames); the provider maps a tile id
// back to a GUI pixel.
// -------------------------------------------------------------------------------------------
typedef struct {
    BOOL enabled;
    BOOL ready;
    BOOL logged;
    MTLPixelFormat format;
    int gridW;
    int gridH;
    id<MTLTexture> mask;
    id<MTLRenderPipelineState> pipeline;
    id<MTLSamplerState> sampler;
} VRMCGazeRenderer;

static BOOL buildGazeRenderer(id<MTLDevice> device, cp_layer_renderer_t lr, VRMCGazeRenderer *out) {
    memset(out, 0, sizeof(*out));
    out->enabled = YES;
    MTLPixelFormat format = MTLPixelFormatInvalid;
    cp_layer_renderer_configuration_t configuration = cp_layer_renderer_get_configuration(lr);
    if (configuration != NULL) {
        format = cp_layer_renderer_configuration_get_tracking_areas_format(configuration);
    }
    if (format != MTLPixelFormatR32Uint && format != MTLPixelFormatR16Uint) {
        compLog("gaze: tracking areas disabled (tracking format %lu is not r32Uint/r16Uint)",
                (unsigned long)format);
        return NO;
    }
    int gridW = VRMC_GAZE_GRID_W;
    int gridH = VRMC_GAZE_GRID_H;
    uint16_t maxValue = 0;
    cp_layer_renderer_properties_t props = cp_layer_renderer_get_properties(lr);
    if (props != NULL) {
        maxValue = cp_layer_renderer_properties_get_tracking_areas_max_value(props);
    }
    if (maxValue < 2) {
        compLog("gaze: tracking areas disabled (max render value=%u)", (unsigned)maxValue);
        return NO;
    }
    while (gridW > 1 && (long)gridW * gridH > (long)maxValue - 1) gridH--;
    if (gridH < 1) {
        compLog("gaze: tracking areas disabled (grid does not fit max render value=%u)", (unsigned)maxValue);
        return NO;
    }
    NSError *err = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:shaderSource() options:nil error:&err];
    if (library == nil) {
        compLog("gaze: shader library failed: %s", err.description.UTF8String);
        return NO;
    }
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [library newFunctionWithName:@"vmain"];
    pd.fragmentFunction = [library newFunctionWithName:(format == MTLPixelFormatR16Uint)
        ? @"fmain_tracking_u16" : @"fmain_tracking"];
    pd.colorAttachments[0].pixelFormat = format;
    err = nil;
    out->pipeline = [device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (out->pipeline == nil) {
        compLog("gaze: tracking pipeline failed: %s", err.description.UTF8String);
        return NO;
    }
    MTLTextureDescriptor *td = [MTLTextureDescriptor new];
    td.textureType = MTLTextureType2D;
    td.pixelFormat = format;
    td.width = (NSUInteger)gridW;
    td.height = (NSUInteger)gridH;
    td.mipmapLevelCount = 1;
    td.usage = MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModeShared;
    out->mask = [device newTextureWithDescriptor:td];
    if (out->mask == nil) {
        compLog("gaze: mask texture allocation failed");
        return NO;
    }
    MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
    sd.minFilter = MTLSamplerMinMagFilterNearest;
    sd.magFilter = MTLSamplerMinMagFilterNearest;
    sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
    out->sampler = [device newSamplerStateWithDescriptor:sd];
    if (out->sampler == nil) {
        compLog("gaze: mask sampler creation failed");
        return NO;
    }
    out->format = format;
    out->gridW = gridW;
    out->gridH = gridH;
    out->ready = YES;
    compLog("gaze: tracking areas ENABLED format=%lu grid=%dx%d tiles=%d maxValue=%u",
            (unsigned long)format, gridW, gridH, gridW * gridH, (unsigned)maxValue);
    return YES;
}

/// Add the tracking areas for this drawable, write the tile-id mask and encode one mask pass per
/// tracking-area texture. Called in the same command buffer as the colour passes, before present.
static void encodeGazeTrackingAreas(VRMCGazeRenderer *gaze, cp_drawable_t drawable,
                                    id<MTLCommandBuffer> cb) {
    if (!gaze->ready) return;
    const size_t textureCount = cp_drawable_get_tracking_areas_texture_count(drawable);
    if (textureCount == 0) {
        if (!gaze->logged) {
            gaze->logged = YES;
            compLog("gaze: drawable has no tracking-area textures (configuration may be unsupported)");
        }
        return;
    }
    const int gw = gaze->gridW;
    const int gh = gaze->gridH;
    const size_t count = (size_t)gw * (size_t)gh;
    // Preallocated mask staging (one alloc per grid change; not per frame).
    static uint32_t *values32 = NULL;
    static uint16_t *values16 = NULL;
    static size_t valuesCapacity = 0;
    static long lastValuesCount = -1;
    if (valuesCapacity < count) {
        free(values32);
        free(values16);
        values32 = (uint32_t *)malloc(count * sizeof(uint32_t));
        values16 = (uint16_t *)malloc(count * sizeof(uint16_t));
        valuesCapacity = count;
        lastValuesCount = -1;
    }
    uint16_t areaCount = 0;
    for (int y = 0; y < gh; y++) {
        for (int x = 0; x < gw; x++) {
            const size_t index = (size_t)y * gw + x;
            const uint64_t tileId = 1ull + (uint64_t)y * (uint64_t)gw + (uint64_t)x;
            cp_tracking_area_t area = cp_drawable_add_tracking_area(drawable,
                                                                     (cp_tracking_area_identifier)tileId);
            uint16_t renderValue = 0;
            if (area != NULL) {
                cp_hover_effect_t hover = cp_tracking_area_add_automatic_hover_effect(area);
                (void)hover;
                renderValue = cp_tracking_area_get_render_value(area);
                areaCount++;
            }
            if (values32 != NULL) values32[index] = renderValue;
            if (values16 != NULL) values16[index] = renderValue;
        }
    }
    if (lastValuesCount != (long)count) {
        lastValuesCount = (long)count;
        compLog("gaze: registered %u/%zu tracking areas grid=%dx%d", (unsigned)areaCount, count, gw, gh);
    }
    if (gaze->format == MTLPixelFormatR32Uint) {
        [gaze->mask replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)gw, (NSUInteger)gh)
                      mipmapLevel:0 withBytes:values32 bytesPerRow:(NSUInteger)gw * sizeof(uint32_t)];
    } else {
        [gaze->mask replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)gw, (NSUInteger)gh)
                      mipmapLevel:0 withBytes:values16 bytesPerRow:(NSUInteger)gw * sizeof(uint16_t)];
    }
    for (size_t i = 0; i < textureCount; i++) {
        id<MTLTexture> trackingTexture = cp_drawable_get_tracking_areas_texture(drawable, i);
        if (trackingTexture == nil) continue;
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = trackingTexture;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        if (enc == nil) continue;
        MTLViewport vp = {0.0, 0.0, (double)trackingTexture.width, (double)trackingTexture.height, 0.0, 1.0};
        [enc setViewport:vp];
        [enc setRenderPipelineState:gaze->pipeline];
        [enc setFragmentTexture:gaze->mask atIndex:3];
        [enc setFragmentSamplerState:gaze->sampler atIndex:3];
        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [enc endEncoding];
    }
}

static inline float halfToFloat(uint16_t h) {
    uint32_t sign = (uint32_t)(h >> 15) & 1u;
    uint32_t exp = (uint32_t)(h >> 10) & 0x1fu;
    uint32_t mant = (uint32_t)h & 0x3ffu;
    uint32_t bits;
    if (exp == 0) {
        if (mant == 0) {
            bits = sign << 31;
        } else {
            exp = 1;
            while ((mant & 0x400u) == 0) { mant <<= 1; exp--; }
            mant &= 0x3ffu;
            bits = (sign << 31) | ((exp + 112u) << 23) | (mant << 13);
        }
    } else if (exp == 31) {
        bits = (sign << 31) | 0x7f800000u | (mant << 13);
    } else {
        bits = (sign << 31) | ((exp + 112u) << 23) | (mant << 13);
    }
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static NSUInteger drawableBytesPerPixel(MTLPixelFormat fmt) {
    switch (fmt) {
        case MTLPixelFormatRGBA16Float: return 8;
        case MTLPixelFormatRGBA8Unorm:
        case MTLPixelFormatRGBA8Unorm_sRGB:
        case MTLPixelFormatBGRA8Unorm:
        case MTLPixelFormatBGRA8Unorm_sRGB:
            return 4;
        default:
            return 0;
    }
}

static NSString *drawableDumpPath(NSString *name) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.firstObject == nil) return nil;
    return [paths.firstObject stringByAppendingPathComponent:name];
}

static void writeDrawableDump(NSString *rawName, const uint8_t *rgba, NSUInteger width, NSUInteger height,
                              NSString *meta) {
    NSString *rawPath = drawableDumpPath(rawName);
    if (rawPath == nil) return;
    NSData *data = [NSData dataWithBytes:rgba length:width * height * 4];
    if (![data writeToFile:rawPath atomically:YES]) {
        compLog("drawable proof: failed to write %s", rawPath.UTF8String);
        return;
    }
    NSString *metaPath = drawableDumpPath([rawName stringByAppendingPathExtension:@"meta"]);
    [[meta dataUsingEncoding:NSUTF8StringEncoding] writeToFile:metaPath atomically:YES];
}

// Blits 64 strided full-width rows of a drawable colour texture into a shared buffer, inside the
// frame command buffer, after the render passes and before cp_drawable_encode_present. The
// completed handler decodes them to a 64x64 RGBA8 image (a vertical+horizontal stride sample of
// exactly what the drawable holds), logs luminance statistics and writes the image + a .meta file.
static BOOL encodeDrawableProbe(id<MTLCommandBuffer> cb, id<MTLTexture> tex, MTLViewport vp,
                                NSUInteger slice, const char *eye, int frameCount,
                                BOOL dumpRaw, int32_t generation) {
    if (cb == nil || tex == nil) return NO;
    NSUInteger bpp = drawableBytesPerPixel(tex.pixelFormat);
    if (bpp == 0 || vp.width < 32 || vp.height < 32) return NO;
    const NSUInteger rows = 64;
    NSUInteger srcX = (NSUInteger)vp.originX;
    NSUInteger srcWidth = (NSUInteger)vp.width;
    if (srcX >= tex.width) srcX = 0;
    if (srcX + srcWidth > tex.width) srcWidth = tex.width - srcX;
    if (srcWidth < 16) return NO;
    NSUInteger rowBytes = srcWidth * bpp;
    id<MTLBuffer> buffer = [cb.device newBufferWithLength:rows * rowBytes
                                                  options:MTLResourceStorageModeShared];
    if (buffer == nil) return NO;
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    if (blit == nil) return NO;
    for (NSUInteger r = 0; r < rows; r++) {
        NSUInteger srcY = (NSUInteger)((double)r / (double)rows * (double)tex.height);
        if (srcY >= tex.height) srcY = tex.height - 1;
        [blit copyFromTexture:tex sourceSlice:slice sourceLevel:0
                 sourceOrigin:MTLOriginMake(srcX, srcY, 0)
                   sourceSize:MTLSizeMake(srcWidth, 1, 1)
                     toBuffer:buffer destinationOffset:r * rowBytes
            destinationBytesPerRow:rowBytes destinationBytesPerImage:rowBytes];
    }
    [blit endEncoding];

    NSString *eyeString = [NSString stringWithUTF8String:eye];
    NSString *rawName = [NSString stringWithFormat:@"vrmc-drawable-%@.raw", eyeString];
    MTLPixelFormat fmt = tex.pixelFormat;
    NSUInteger texWidth = tex.width;
    NSUInteger texHeight = tex.height;
    NSUInteger capturedWidth = srcWidth;
    int capturedFrame = frameCount;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        if (completed.status != MTLCommandBufferStatusCompleted) {
            compLog("drawable proof %s: command buffer status=%ld error=%s", eye,
                    (long)completed.status,
                    completed.error ? completed.error.description.UTF8String : "none");
            return;
        }
        const uint8_t *src = (const uint8_t *)buffer.contents;
        if (src == NULL) return;
        const NSUInteger outW = 64, outH = 64;
        uint8_t out[64 * 64 * 4];
        double sum[3] = {0.0, 0.0, 0.0};
        uint8_t maxValue[3] = {0, 0, 0};
        NSUInteger nonBlack = 0;
        double topSum = 0.0;
        NSUInteger topCount = 0;
        double centreSum = 0.0;
        NSUInteger centreCount = 0;
        for (NSUInteger oy = 0; oy < outH; oy++) {
            NSUInteger srcRow = (oy * rows) / outH;
            if (srcRow >= rows) srcRow = rows - 1;
            const uint8_t *row = src + srcRow * rowBytes;
            for (NSUInteger ox = 0; ox < outW; ox++) {
                NSUInteger px = (ox * capturedWidth) / outW;
                if (px >= capturedWidth) px = capturedWidth - 1;
                const uint8_t *p = row + px * bpp;
                float r = 0.0f, g = 0.0f, b = 0.0f;
                if (fmt == MTLPixelFormatRGBA16Float) {
                    uint16_t h0 = 0, h1 = 0, h2 = 0;
                    memcpy(&h0, p + 0, 2);
                    memcpy(&h1, p + 2, 2);
                    memcpy(&h2, p + 4, 2);
                    r = halfToFloat(h0);
                    g = halfToFloat(h1);
                    b = halfToFloat(h2);
                } else if (fmt == MTLPixelFormatBGRA8Unorm || fmt == MTLPixelFormatBGRA8Unorm_sRGB) {
                    b = (float)p[0] / 255.0f;
                    g = (float)p[1] / 255.0f;
                    r = (float)p[2] / 255.0f;
                } else {
                    r = (float)p[0] / 255.0f;
                    g = (float)p[1] / 255.0f;
                    b = (float)p[2] / 255.0f;
                }
                uint8_t r8 = (uint8_t)(fminf(fmaxf(r, 0.0f), 1.0f) * 255.0f);
                uint8_t g8 = (uint8_t)(fminf(fmaxf(g, 0.0f), 1.0f) * 255.0f);
                uint8_t b8 = (uint8_t)(fminf(fmaxf(b, 0.0f), 1.0f) * 255.0f);
                NSUInteger o = (oy * outW + ox) * 4;
                out[o + 0] = r8;
                out[o + 1] = g8;
                out[o + 2] = b8;
                out[o + 3] = 255;
                sum[0] += (double)r8;
                sum[1] += (double)g8;
                sum[2] += (double)b8;
                if (r8 > maxValue[0]) maxValue[0] = r8;
                if (g8 > maxValue[1]) maxValue[1] = g8;
                if (b8 > maxValue[2]) maxValue[2] = b8;
                if (r8 != 0 || g8 != 0 || b8 != 0) nonBlack++;
                if (oy < 2) {
                    topSum += (double)(r8 + g8 + b8) / 3.0;
                    topCount++;
                }
                if (ox >= 30 && ox < 34 && oy >= 30 && oy < 34) {
                    centreSum += (double)(r8 + g8 + b8) / 3.0;
                    centreCount++;
                }
            }
        }
        const double count = (double)(outW * outH);
        const double luma = (sum[0] + sum[1] + sum[2]) / (3.0 * count);
        const double topLuma = topCount > 0 ? topSum / (double)topCount : -1.0;
        const double centreLuma = centreCount > 0 ? centreSum / (double)centreCount : -1.0;
        compLog("drawable proof %s frame=%d generation=%d src=%lux%lu fmt=%lu: mean=(%.1f,%.1f,%.1f) "
                "luma=%.1f topStripLuma=%.1f centreLuma=%.1f max=(%u,%u,%u) nonBlack=%lu/%lu",
                eye, capturedFrame, generation, (unsigned long)texWidth, (unsigned long)texHeight,
                (unsigned long)fmt, sum[0] / count, sum[1] / count, sum[2] / count, luma,
                topLuma, centreLuma, (unsigned)maxValue[0], (unsigned)maxValue[1],
                (unsigned)maxValue[2], (unsigned long)nonBlack, (unsigned long)(outW * outH));
        if (dumpRaw) {
            NSString *meta = [NSString stringWithFormat:
                @"w=%lu h=%lu format=RGBA8 eye=%@ frame=%d generation=%d srcWidth=%lu srcHeight=%lu "
                @"pixelFormat=%lu meanLuma=%.2f topStripLuma=%.2f centreLuma=%.2f\n",
                (unsigned long)outW, (unsigned long)outH, eyeString, capturedFrame, generation,
                (unsigned long)texWidth, (unsigned long)texHeight, (unsigned long)fmt, luma,
                topLuma, centreLuma];
            writeDrawableDump(rawName, out, outW, outH, meta);
        }
    }];
    return YES;
}

@interface VRMCCompositorThread : NSThread
@property(nonatomic) cp_layer_renderer_t layerRenderer;
@property(nonatomic) int32_t generation;
@end

@implementation VRMCCompositorThread

- (BOOL)stopRequested {
    return gStopGeneration.load() >= self.generation || gGeneration.load() != self.generation;
}

- (void)main {
    cp_layer_renderer_t lr = self.layerRenderer;
    const int32_t generation = self.generation;
    resolveBridge();

    // M4-W1 synthetic-input diagnostic flag, read BEFORE any ARKit session/authorization work so
    // synthetic mode can skip the hand-tracking authorization request entirely: fabricated hands need
    // no permission, the request would pop a system prompt, and it can block compositor start.
    const char *inputSimName = "none";
    BOOL inputSimUnknownContent = NO;
    const int inputSimScript = readInputSimScript(&inputSimName, &inputSimUnknownContent);
    const BOOL inputSynthetic = (inputSimScript >= 0);
    if (inputSynthetic) {
        compLog("INPUT-SIM SYNTHETIC input enabled script=%s flag=Documents/vrmc-input-sim.flag%s "
                "(fabricated 27-joint hands; ARKit hands are ignored; plumbing evidence only, NOT "
                "hands evidence)", inputSimName,
                inputSimUnknownContent ? " content-unknown-defaulted-to-cycle" : "");
    }

    ar_world_tracking_configuration_t cfg = ar_world_tracking_configuration_create();
    ar_world_tracking_provider_t provider = ar_world_tracking_provider_create(cfg);
    ar_session_t session = ar_session_create();

    // M4-W1: hand tracking lives in the SAME ARKit session as world tracking. Ask for hand-tracking
    // authorization explicitly (ARKit does NOT prompt implicitly from ar_session_run), and only add
    // the hand provider once it is allowed: an unauthorized provider can stop the whole session,
    // which would take head tracking (and therefore presentation) down with it. Denied/undetermined
    // keeps the session world-only; the compositor still publishes untracked snapshots
    // (valid_mask = 0) every frame and keeps presenting.
    const BOOL handTrackingSupported = ar_hand_tracking_provider_is_supported();
    ar_hand_tracking_provider_t handProvider = nil;
    ar_hand_anchor_t handAnchorLeft = nil;
    ar_hand_anchor_t handAnchorRight = nil;
    BOOL handProviderIncluded = NO;
    intptr_t handAuthorization = (intptr_t)ar_authorization_status_not_determined;
    if (inputSynthetic) {
        // Synthetic mode: fabricated hands drive the input channel, so no hand data is needed and no
        // authorization prompt may block compositor start. The session stays world-only for hands.
        compLog("INPUT-SIM SYNTHETIC input mode: hand-tracking authorization not requested "
                "(hand tracking supported=%d); the ARKit session is world-only for hands and synthetic "
                "publications drive the input channel", (int)handTrackingSupported);
    } else if (handTrackingSupported) {
        compLog("hand tracking supported=1; requesting hand-tracking authorization");
        handAuthorization = requestHandAuthorization(session, 20.0);
        if (handAuthorization == (intptr_t)ar_authorization_status_allowed) {
            ar_hand_tracking_configuration_t handConfiguration = ar_hand_tracking_configuration_create();
            handProvider = ar_hand_tracking_provider_create(handConfiguration);
            handAnchorLeft = ar_hand_anchor_create();
            handAnchorRight = ar_hand_anchor_create();
            handProviderIncluded = YES;
        } else if (handAuthorization < 0) {
            compLog("hand tracking authorization NOT GRANTED (status=unknown: request timed out or "
                    "returned no result): real hands are unavailable this session. Allow Hand Tracking "
                    "in Settings > Privacy & Security > Hand Tracking, then RELAUNCH VRMC for real "
                    "hands. The ARKit session stays world-only so presentation is unaffected; "
                    "synthetic input is unaffected.");
        } else {
            compLog("hand tracking authorization NOT GRANTED (status=%s): real hands are unavailable "
                    "this session. Allow Hand Tracking in Settings > Privacy & Security > Hand "
                    "Tracking, then RELAUNCH VRMC for real hands. The ARKit session stays world-only so "
                    "presentation is unaffected; synthetic input is unaffected.",
                    authorizationStatusName(handAuthorization));
        }
    } else {
        compLog("hand tracking supported=0 (no hand tracking in this environment, e.g. the visionOS "
                "simulator); publishing untracked hands. Synthetic input (Documents/vrmc-input-sim.flag) "
                "exercises the input channel instead");
    }
    ar_data_providers_t providers = handProviderIncluded
        ? ar_data_providers_create_with_data_providers(provider, handProvider, nil)
        : ar_data_providers_create_with_data_providers(provider, nil);
    // Log ARKit data-provider failures (e.g. hand tracking not authorized, runtime failure) instead
    // of silently presenting an untracked immersive scene.
    ar_session_set_data_provider_state_change_handler(
        session, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),
        ^(ar_data_providers_t changedProviders, ar_data_provider_state_t newState,
          ar_error_t statusError, ar_data_provider_t failedProvider) {
            (void)changedProviders;
            const long errorCode = (statusError != nil) ? (long)ar_error_get_error_code(statusError) : 0L;
            compLog("ARKit data provider state=%ld errorCode=%ld failedProvider=%d%s",
                    (long)newState, errorCode, failedProvider != nil ? 1 : 0,
                    errorCode == (long)ar_session_error_code_data_provider_not_authorized
                        ? " HAND TRACKING NOT AUTHORIZED: allow Hand Tracking in Settings > Privacy & Security"
                        : "");
        });
    ar_session_run(session, providers);
    compLog("ARKit session started (generation %d) hand tracking supported=%d provider=%s "
            "authorization=%s inputMode=%s", generation, (int)handTrackingSupported,
            handProviderIncluded ? "started" : "not-started",
            authorizationStatusName(handAuthorization),
            inputSynthetic ? "synthetic" : "arkit");

    cp_layer_renderer_wait_until_running(lr);
    id<MTLDevice> device = cp_layer_renderer_get_device(lr);
    id<MTLCommandQueue> queue = [device newCommandQueue];
    compLog("wait_until_running returned (generation %d) device=%s", generation,
            device.name.UTF8String);

    // Diagnostic modes: flag files in Documents/ (see file header). Logged so a device log names them.
    const int reprojMode = readReprojMode();
    const BOOL debugShading = diagFlag(@"vrmc-reproj-debug.flag");
    const BOOL forceTestPattern = diagFlag(@"vrmc-test-pattern.flag");
    // Diagnostic A/B: skip cp_drawable_set_device_anchor entirely (EV-0073 saw passthrough without an
    // anchor; this isolates whether the anchor/reprojection path is what keeps the content off-screen).
    const BOOL noDeviceAnchor = diagFlag(@"vrmc-no-anchor.flag");
    // A/B: use the visionOS-26-deprecated singular cp_frame_query_drawable instead of the array API.
    // The known-good M3A probe (EV-0074, displays on D1) uses the deprecated call; this isolates
    // whether the array-API drawable handling is what keeps our layer off-screen.
    const BOOL legacySingleDrawable = diagFlag(@"vrmc-legacy-single-drawable.flag");
    // ROOT CAUSE (EV-0093): clearing the drawable depth attachment to 0.0 (reverse-Z "infinitely
    // far") makes visionOS 27.2 present the whole layer BLACK even though the colour texture is
    // provably bright and the command buffer completes. The known-good M3A probe (EV-0074) clears to
    // 1.0 (near) and displays. The flat sampled image carries no meaningful per-pixel depth, so 1.0 is
    // both safe and the empirically required value on D1. vrmc-depth-zero.flag restores the old 0.0
    // value for A/B only.
    const BOOL depthZero = diagFlag(@"vrmc-depth-zero.flag");
    const BOOL presentProof = diagFlag(@"vrmc-present-proof.flag");
    const BOOL clearProbe = diagFlag(@"vrmc-clear-probe.flag");
    const BOOL dumpRawAlways = diagFlag(@"vrmc-drawable-dump.flag");
    const BOOL presentWait = diagFlag(@"vrmc-present-wait.flag");
    const BOOL selfTest = diagFlag(@"vrmc-immersive-selftest.flag");
    // Re-read while presenting (see the frame loop) so the in-VR quick menu applies it live.
    float vignetteStrength = readVignetteStrength();
    const BOOL diagnostics = diagnosticsEnabled();
    static int samplingDisabled = -1;
    if (samplingDisabled < 0) {
        samplingDisabled = diagFlag(@"vrmc-no-sampling.flag") ? 1 : 0;
    }
    compLog("diagnostics: reprojMode=%d debugShading=%d samplingDisabled=%d forceTestPattern=%d "
            "presentProof=%d clearProbe=%d dumpRaw=%d presentWait=%d selfTest=%d noDeviceAnchor=%d "
            "legacySingleDrawable=%d depthZero=%d vignette=%.2f diagnosticsEnabled=%d "
            "(release default 0: no test pattern/badge/readbacks; Documents/vrmc-diagnostics.flag enables)",
            reprojMode, (int)debugShading, samplingDisabled, (int)forceTestPattern,
            (int)presentProof, (int)clearProbe, (int)dumpRawAlways, (int)presentWait, (int)selfTest,
            (int)noDeviceAnchor, (int)legacySingleDrawable, (int)depthZero, (double)vignetteStrength,
            (int)diagnostics);

    // Query the layer's real configuration instead of hardcoding the colour format: the pipeline
    // must match what the drawable actually hands out.
    MTLPixelFormat configuredColor = MTLPixelFormatRGBA16Float;
    MTLPixelFormat configuredDepth = MTLPixelFormatInvalid;
    cp_layer_renderer_configuration_t configuration = cp_layer_renderer_get_configuration(lr);
    if (configuration != nullptr) {
        MTLPixelFormat color = cp_layer_renderer_configuration_get_color_format(configuration);
        if (color != MTLPixelFormatInvalid) configuredColor = color;
        configuredDepth = cp_layer_renderer_configuration_get_depth_format(configuration);
        compLog("layer configuration colorFormat=%lu depthFormat=%lu foveation=%d layout=%d "
                "maxRenderQuality=%.2f",
                (unsigned long)configuredColor, (unsigned long)configuredDepth,
                (int)cp_layer_renderer_configuration_get_foveation_enabled(configuration),
                (int)cp_layer_renderer_configuration_get_layout(configuration),
                (double)cp_layer_renderer_configuration_get_max_render_quality(configuration));
    }
    // M8: foveation + dynamic render quality. maxRenderQuality is the configured upper bound
    // (ShellLayerConfiguration sets it); runtime quality starts there unless a Documents override
    // says otherwise.
    const BOOL configuredFoveation = configuration != nullptr
        ? (BOOL)cp_layer_renderer_configuration_get_foveation_enabled(configuration) : NO;
    // Sanitize: a runtime that does not support dynamic render quality may report NaN (observed on
    // the visionOS 27.0 simulator). Never feed NaN into the quality controller / layer API.
    float configuredMaxQuality = configuration != nullptr
        ? (float)cp_layer_renderer_configuration_get_max_render_quality(configuration) : 0.0f;
    if (!isfinite(configuredMaxQuality) || configuredMaxQuality <= 0.0f) configuredMaxQuality = 1.0f;
    const float maxRenderQuality = MAX(0.1f, MIN(1.0f, configuredMaxQuality));
    const BOOL qualityControlSupported = configuration != nullptr &&
        isfinite((float)cp_layer_renderer_configuration_get_max_render_quality(configuration)) &&
        cp_layer_renderer_configuration_get_max_render_quality(configuration) > 0.0f;
    VRMCQualityControl qualityControl = readQualityControl(maxRenderQuality);
    NSString *qualityOverride = readDocumentText(@"vrmc-render-quality.txt");
    if (!qualityControlSupported) {
        compLog("render quality: layer does not support dynamic render quality (system default); the "
                "controller stays at the default and only reports drawable sizes");
        qualityControl.autoMode = NO;
    } else if (qualityControl.autoMode) {
        compLog("render quality: auto mode (max=%.2f start=%.2f; Documents/vrmc-render-quality.txt=auto "
                "or vrmc-quality-auto.flag)", (double)maxRenderQuality,
                (double)qualityControl.fixedQuality);
    } else {
        compLog("render quality: fixed %.2f (max=%.2f; Documents/vrmc-render-quality.txt=%s)",
                (double)qualityControl.fixedQuality, (double)maxRenderQuality,
                qualityOverride != nil ? "override" : "absent");
    }
    if (qualityControlSupported) {
        applyRenderQuality(lr, qualityControl.fixedQuality,
                           qualityControl.autoMode ? "auto-mode start" : "configured");
    } else {
        compLog("render quality: current runtime quality %.2f (system-managed)",
                (double)cp_layer_renderer_get_render_quality(lr));
    }
    // 0 = present every display frame (no frame repetition). The system picks the display cadence;
    // this only forbids the layer from repeating our frames, so a sustained app can present at the
    // display's native rate (e.g. 120 Hz on a Vision Pro whose panel supports it) instead of being
    // held at 90 Hz by a repeat count.
    cp_layer_renderer_set_minimum_frame_repeat_count(lr, 0);
    compLog("frame pacing: minimumFrameRepeatCount=%d (0 = present every display frame; the "
            "system picks the display cadence and the M8 render feedback reports the measured one)",
            cp_layer_renderer_get_minimum_frame_repeat_count(lr));
    if (configuredFoveation) {
        compLog("foveation: ENABLED in the layer configuration; drawables provide rasterization rate "
                "maps and a reduced physical texture, and the high-density centre is presented at the "
                "logical view resolution");
    } else {
        compLog("foveation: disabled (capabilities reported no foveation support, or "
                "Documents/vrmc-foveation-off.flag); uniform rasterization at the drawable resolution");
    }
    VRMCPipelines pipes;
    buildPipelines(device, &pipes, configuredColor, configuredDepth);

    id<MTLSamplerState> sampler = nil;
    {
        MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
        sd.minFilter = MTLSamplerMinMagFilterLinear;
        sd.magFilter = MTLSamplerMinMagFilterLinear;
        sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
        sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
        sampler = [device newSamplerStateWithDescriptor:sd];
    }
    MTLDepthStencilDescriptor *dsd = [MTLDepthStencilDescriptor new];
    dsd.depthCompareFunction = MTLCompareFunctionAlways;
    dsd.depthWriteEnabled = NO;
    id<MTLDepthStencilState> depthState = [device newDepthStencilStateWithDescriptor:dsd];

    // M4-W2 gaze: opt-in via Documents/vrmc-gaze.flag. The renderer is built from the actual
    // tracking-area configuration format; unsupported formats disable gaze without affecting output.
    VRMCGazeRenderer gaze;
    memset(&gaze, 0, sizeof(gaze));
    const BOOL gazeRequested = documentFlag(@"vrmc-gaze.flag");
    if (gazeRequested) {
        if (!buildGazeRenderer(device, lr, &gaze)) {
            compLog("gaze: requested but unavailable; W1 hand-ray input remains the active path");
        }
    } else {
        compLog("gaze: disabled (no Documents/vrmc-gaze.flag)");
    }

    int frameCount = 0;
    int presentedFrameCount = 0;
    int framesWithoutDrawable = 0;
    int framesWithoutEncoder = 0;
    int anchorFails = 0;
    BOOL loggedViewInfo = NO;
    BOOL loggedDrawableTopology = NO;
    BOOL useFlat = (reprojMode == VRMCReprojFlat);
    BOOL autoTestPattern = NO;
    BOOL modeLogged = NO;
    BOOL postedRunning = NO;
    BOOL clearProbeLogged = NO;
    BOOL presentProofLogged = NO;
    BOOL warnedUnsupportedReadback = NO;
    BOOL warnedNilColorTexture = NO;
    BOOL warnedNilEncoder = NO;
    BOOL warnedNoDrawables = NO;
    BOOL lastTestPatternState = NO;
    size_t lastLoggedDrawableCount = 0;
    int nilColorViews = 0;
    float ipd = 0.064f;

    // M8 render feedback: measured display cadence + published display geometry.
    VRMCPresentationStats presentStats;
    presentationStatsReset(&presentStats);
    float currentRenderQuality = qualityControl.fixedQuality;
    int lastQualityAdjustFrame = 0;
    uint64_t publishedRenderSettings = 0;
    uint64_t publishedRenderSettingsErrors = 0;
    BOOL loggedRateMaps = NO;
    BOOL loggedRenderFeedback = NO;
    BOOL loggedLogicalSizes = NO;
    // M8 foveated sharpening state (see readSharpenControl): re-read periodically for live A/B.
    VRMCSharpenControl sharpenControl = readSharpenControl();
    BOOL aaEnabled = readAAEnabled();
    // Native-resolution anti-aliasing targets (one per eye) + the frame they were computed from.
    id<MTLRenderPipelineState> fxaaPipe = nil;
    BOOL fxaaPipeFailed = NO;
    id<MTLTexture> aaTex[2] = {nil, nil};
    uint64_t aaSrcHandle[2] = {0, 0};
    BOOL aaLinearize = YES;
    {
        NSString *lin = readDocumentText(@"vrmc-linearize-color.txt");
        if (lin.length > 0 && ([lin caseInsensitiveCompare:@"off"] == NSOrderedSame || lin.floatValue == 0.0f)) {
            aaLinearize = NO;
        }
    }
    compLog("edge anti-aliasing: %s (Documents/vrmc-aa.txt)", aaEnabled ? "ON" : "OFF");
    {
        NSString *sharpText = readDocumentText(@"vrmc-sharpening.txt");
        compLog("sharpen control: enabled=%d auto=%d strength=%.2f (Documents/vrmc-sharpening.txt=%s)",
                (int)sharpenControl.enabled, (int)sharpenControl.autoMode, (double)sharpenControl.strength,
                sharpText.length > 0 ? sharpText.UTF8String : "default(auto)");
    }
    float lastLoggedSharpenStrength = -1.0f;
    float currentSharpenStrength = 0.0f;
    BOOL loggedSharpen = NO;
    // M8 resize grace: the provider clears the shared eye frame before rebuilding its eye targets
    // (VisionRenderer.maybeResizeEyeTargets). Without a grace window the compositor would drop to the
    // procedural test pattern for the one or two frames of every resize (a visible flash during the
    // auto-ramp). Keep the last sampled MTLTexture pair (retained, like the in-flight retention below)
    // and reuse it for up to 30 frames so a resize presents one stale frame instead of the pattern.
    id<MTLTexture> lastLeftEye = nil;
    id<MTLTexture> lastRightEye = nil;
    uint64_t lastEyesFrame = 0;
    int eyesMissingFrames = 0;
    BOOL loggedEyeCacheReuse = NO;

    // M4-W1 input state. One preallocated snapshot per frame (no per-frame allocation) and one
    // rate-limited log counter per concern; never dump joint arrays every frame. The synthetic-flag
    // values (inputSimScript/inputSimName/inputSynthetic) were read before the ARKit session setup.
    double inputSimStart = -1.0;
    int inputSimLastPhase = -1;
    BOOL inputSimLapLogged = NO;
    uint64_t inputPublishCount = 0;
    uint64_t inputPublishErrors = 0;
    uint64_t inputHandQueryFailures = 0;
    uint64_t inputLastTimestampNs = 0;
    BOOL inputFirstPublishLogged = NO;
    const double inputSimLapSeconds = inputSynthetic ? inputSimScriptDuration(inputSimScript) : 0.0;
    while (true) {
        @autoreleasepool {
            if ([self stopRequested]) { compLog("stop requested before frame; exiting loop"); break; }
            cp_layer_renderer_state state = cp_layer_renderer_get_state(lr);
            if (state == cp_layer_renderer_state_invalidated) { compLog("layer invalidated"); break; }
            if (state == cp_layer_renderer_state_paused) { cp_layer_renderer_wait_until_running(lr); continue; }
            cp_frame_t frame = cp_layer_renderer_query_next_frame(lr);
            if (frame == nullptr) continue;
            cp_frame_timing_t timing = cp_frame_predict_timing(frame);
            if (timing == nullptr) continue;
            // The bridge dylib is loaded by the JVM when the provider initializes, which can be after
            // the immersive space opens (auto-open on game start). Retry symbol resolution.
            if (gEyeFn == NULL && (frameCount % 30) == 0) {
                resolveBridge();
            }
            // M8 sharpening lives in compositing (not the game): re-read its Documents knob
            // periodically so it can be A/B'd on device without a rebuild.
            if ((frameCount % 300) == 0) {
                sharpenControl = readSharpenControl();
                aaEnabled = readAAEnabled();
            }
            cp_frame_start_update(frame);
            cp_frame_end_update(frame);
            cp_time_wait_until(cp_frame_timing_get_optimal_input_time(timing));
            if ([self stopRequested] || cp_layer_renderer_get_state(lr) != cp_layer_renderer_state_running) {
                compLog("stop/invalidation after timing wait; exiting without submission");
                break;
            }
            // API ORDER IS PART OF THE CONTRACT (Apple "Drawing fully immersive content using Metal"):
            // startSubmission() must precede queryDrawables(); the drawables/capture targets belong to
            // the submission phase. Querying before startSubmission returned a built_in drawable and the
            // Metal pass saw bright pixels, but the system presented BLACK - the present event was not
            // associated with a started submission. This was the selftest black-immersive root cause.
            cp_frame_start_submission(frame);

            // visionOS 26 deprecated cp_frame_query_drawable in favour of cp_frame_query_drawables:
            // the array can hold more than one drawable (built_in + capture, and render-quality
            // crossfades). A renderer that draws/presents only one of them can leave the buffer the
            // system actually displays untouched -> black immersive while the command buffer
            // completes. Query the array, and never open a submission that will not present.
            size_t drawableCount = 0;
            cp_drawable_t drawables[4] = {nullptr, nullptr, nullptr, nullptr};
            if (legacySingleDrawable) {
                cp_drawable_t single = cp_frame_query_drawable(frame);
                if (single != nullptr) {
                    drawables[0] = single;
                    drawableCount = 1;
                }
            } else {
                cp_drawable_array_t drawableArray = cp_frame_query_drawables(frame);
                if (drawableArray != nullptr) {
                    size_t arrayCount = cp_drawable_array_get_count(drawableArray);
                    drawableCount = arrayCount < 4 ? arrayCount : 4;
                    for (size_t d = 0; d < drawableCount; d++) {
                        drawables[d] = cp_drawable_array_get_drawable(drawableArray, d);
                    }
                }
            }
            if (drawableCount == 0) {
                framesWithoutDrawable++;
                if (!warnedNoDrawables) {
                    warnedNoDrawables = YES;
                    // cp_frame_start_submission already ran above. The array-API contract marks a
                    // 0-count frame as cancelled and "invalid to access", so it is abandoned without
                    // calling cp_frame_end_submission (the known-good M3A probe only ends submissions
                    // it presented; a mid-submission abandon here is the documented cancellation path).
                    compLog("NO-DRAWABLE: frame %d cancelled (0 drawables after startSubmission); "
                            "abandoning without cp_frame_end_submission per the array-API contract",
                            frameCount);
                }
                continue;
            }

            // Which drawable is the one the user sees? Prefer built_in; capture drawables are still
            // rendered and presented but must never drive tracking or display-view publication.
            cp_drawable_t mainDrawable = drawables[0];
            int mainTarget = (int)cp_drawable_get_target(drawables[0]);
            for (size_t d = 0; d < drawableCount; d++) {
                int target = (int)cp_drawable_get_target(drawables[d]);
                if (target == (int)cp_drawable_target_built_in) {
                    mainDrawable = drawables[d];
                    mainTarget = target;
                    break;
                }
            }
            if (!loggedDrawableTopology || drawableCount != lastLoggedDrawableCount) {
                loggedDrawableTopology = YES;
                lastLoggedDrawableCount = drawableCount;
                compLog("drawable topology: count=%zu mainTarget=%d(%s) views=%zu textures=%zu "
                        "rateMaps=%zu", drawableCount, mainTarget,
                        mainTarget == (int)cp_drawable_target_built_in ? "built_in" : "capture",
                        cp_drawable_get_view_count(mainDrawable),
                        cp_drawable_get_texture_count(mainDrawable),
                        cp_drawable_get_rasterization_rate_map_count(mainDrawable));
                for (size_t d = 0; d < drawableCount; d++) {
                    int target = (int)cp_drawable_get_target(drawables[d]);
                    compLog("  drawable[%zu] target=%d(%s) views=%zu textures=%zu rateMaps=%zu", d, target,
                            target == (int)cp_drawable_target_built_in ? "built_in" : "capture",
                            cp_drawable_get_view_count(drawables[d]),
                            cp_drawable_get_texture_count(drawables[d]),
                            cp_drawable_get_rasterization_rate_map_count(drawables[d]));
                }
            }
            if (drawableCount > 1) {
                compLog("MULTI-DRAWABLE frame=%d count=%zu: the frame hands out more than one drawable; "
                        "all are rendered and presented, built_in drives tracking/display views",
                        frameCount, drawableCount);
            }

            int views = (int)cp_drawable_get_view_count(mainDrawable);
            int leftView = 0;
            float measuredIpd = 0.0f;
            if (views >= 2) {
                simd_float3 p0 = cp_view_get_transform(cp_drawable_get_view(mainDrawable, 0)).columns[3].xyz;
                simd_float3 p1 = cp_view_get_transform(cp_drawable_get_view(mainDrawable, 1)).columns[3].xyz;
                leftView = (p0.x <= p1.x) ? 0 : 1;
                measuredIpd = simd_distance(p0, p1);
                if (measuredIpd > 0.04f && measuredIpd < 0.09f) ipd = measuredIpd;
            }

            // Pipelines are built from the formats the DRAWABLE actually reports. A mismatch between
            // the configured colour format and the presented texture silently drops the draw (and
            // possibly the whole pass, including the load-action clear), which presents as black.
            // M7 (audit): view index != texture index in general. Use the first view's texture-map
            // texture index (clamped to the drawable's texture count) for the attachment-format probe.
            size_t probeTexIndex = 0;
            size_t probeTexCount = cp_drawable_get_texture_count(mainDrawable);
            if (views > 0) {
                cp_view_texture_map_t probeMap =
                    cp_view_get_view_texture_map(cp_drawable_get_view(mainDrawable, 0));
                probeTexIndex = cp_view_texture_map_get_texture_index(probeMap);
                if (probeTexIndex >= probeTexCount) probeTexIndex = 0;
            }
            id<MTLTexture> probeColor = views > 0
                ? cp_drawable_get_color_texture(mainDrawable, probeTexIndex) : nil;
            id<MTLTexture> probeDepth = views > 0
                ? cp_drawable_get_depth_texture(mainDrawable, probeTexIndex) : nil;
            if (probeColor != nil) {
                MTLPixelFormat actualColor = probeColor.pixelFormat;
                MTLPixelFormat actualDepth = probeDepth != nil ? probeDepth.pixelFormat : MTLPixelFormatInvalid;
                if (actualColor != pipes.colorFormat || actualDepth != pipes.depthFormat) {
                    compLog("drawable attachment formats color=%lu depth=%lu (depthTex=%p) differ from "
                            "pipeline formats color=%lu depth=%lu; rebuilding pipelines for the drawable",
                            (unsigned long)actualColor, (unsigned long)actualDepth,
                            (__bridge void *)probeDepth, (unsigned long)pipes.colorFormat,
                            (unsigned long)pipes.depthFormat);
                    buildPipelines(device, &pipes, actualColor, actualDepth);
                }
            } else if (!warnedNilColorTexture) {
                warnedNilColorTexture = YES;
                compLog("DRAWABLE COLOR TEXTURE IS NIL (main drawable target=%d views=%d); every view "
                        "will be skipped and the drawable will be presented unwritten (black)", mainTarget, views);
            }

            // Device anchor at presentation time. Without it the compositor cannot reproject the
            // frame, so count failures (a run with anchorFails == frameCount never anchored).
            cp_frame_timing_t actual = cp_drawable_get_frame_timing(mainDrawable);
            cp_time_t presentation = cp_frame_timing_get_presentation_time(actual);
            CFTimeInterval queryTime = cp_time_to_cf_time_interval(presentation);
            ar_device_anchor_t anchor = ar_device_anchor_create();
            ar_device_anchor_query_status_t st =
                ar_world_tracking_provider_query_device_anchor_at_timestamp(provider, queryTime, anchor);
            simd_float4x4 anchorTransform = matrix_identity_float4x4;
            BOOL anchorOK = (st == ar_device_anchor_query_status_success);
            if (anchorOK) {
                anchorTransform = ar_device_anchor_get_origin_from_anchor_transform(anchor);
            } else {
                anchorFails++;
            }

            // Publish the headset's real per-eye frustum + eye-to-head transforms for the provider
            // (macstream's ViewsConfig equivalent). Only the built_in drawable describes what the
            // viewer sees; a capture drawable's views must not be published.
            BOOL displayViewsPublished = NO;
            if (mainTarget == (int)cp_drawable_target_built_in && views >= 2 && gDisplayViewsFn != NULL) {
                vrmc_display_views dv;
                memset(&dv, 0, sizeof(dv));
                dv.ipd_m = ipd;
                for (int i = 0; i < 2; i++) {
                    cp_view_t view = cp_drawable_get_view(mainDrawable, i);
                    simd_float4 t = cp_view_get_tangents(view); // left, right, top, bottom (positive)
                    simd_float4x4 vt = cp_view_get_transform(view);
                    float *tangents = (i == leftView) ? dv.left_tangents : dv.right_tangents;
                    float *matrix = (i == leftView) ? dv.left_eye_to_head : dv.right_eye_to_head;
                    tangents[0] = -t.x;  // left
                    tangents[1] =  t.y;  // right
                    tangents[2] =  t.z;  // up
                    tangents[3] = -t.w;  // down
                    memcpy(matrix, &vt, sizeof(float) * 16);
                }
                if (gDisplayViewsFn(&dv) == 0) {
                    displayViewsPublished = YES;
                    // Provider now renders the display frustum: flat sampling is the aligned path and
                    // avoids the EV-0086 black reprojection branch entirely.
                    useFlat = YES;
                    static int loggedPublishedViews = 0;
                    if (!loggedPublishedViews) {
                        loggedPublishedViews = 1;
                        simd_float3 pl = cp_view_get_transform(cp_drawable_get_view(mainDrawable, leftView)).columns[3].xyz;
                        int rightView = (leftView == 0) ? 1 : 0;
                        simd_float3 pr = cp_view_get_transform(cp_drawable_get_view(mainDrawable, rightView)).columns[3].xyz;
                        compLog("published display views L tangents=(%.3f,%.3f,%.3f,%.3f) Lpos=(%.4f,%.4f,%.4f) "
                                "R tangents=(%.3f,%.3f,%.3f,%.3f) Rpos=(%.4f,%.4f,%.4f) ipd=%.4f",
                                dv.left_tangents[0], dv.left_tangents[1], dv.left_tangents[2], dv.left_tangents[3],
                                pl.x, pl.y, pl.z,
                                dv.right_tangents[0], dv.right_tangents[1], dv.right_tangents[2], dv.right_tangents[3],
                                pr.x, pr.y, pr.z, dv.ipd_m);
                    }
                }
            }

            // ---------------------- M8: render feedback (display geometry + cadence) ----------------------
            // Publish what the display asks for (per-eye logical size at the current render quality,
            // physical foveated drawable extent, foveation/rate-map state, measured display cadence)
            // through the additive native-shared channel; the provider sizes its stereo eye textures
            // from it. Also logs the foveation rate-map geometry and drives the optional auto quality
            // controller. Runs once per frame on the built_in drawable.
            {
                presentationStatsRecord(&presentStats, cp_time_to_cf_time_interval(presentation));
                uint32_t logicalW[2] = {0, 0};
                uint32_t logicalH[2] = {0, 0};
                uint32_t physicalW = 0;
                uint32_t physicalH = 0;
                const size_t rateMapCount = cp_drawable_get_rasterization_rate_map_count(mainDrawable);
                const size_t textureCount = cp_drawable_get_texture_count(mainDrawable);
                for (int i = 0; i < views && i < 2; i++) {
                    cp_view_t view = cp_drawable_get_view(mainDrawable, (size_t)i);
                    cp_view_texture_map_t map = cp_view_get_view_texture_map(view);
                    MTLViewport viewport = cp_view_texture_map_get_viewport(map);
                    size_t texIndex = cp_view_texture_map_get_texture_index(map);
                    if (texIndex >= textureCount) texIndex = ((size_t)i < textureCount) ? (size_t)i : 0;
                    id<MTLTexture> colorTex = cp_drawable_get_color_texture(mainDrawable, texIndex);
                    if (colorTex != nil && physicalW == 0) {
                        physicalW = (uint32_t)colorTex.width;
                        physicalH = (uint32_t)colorTex.height;
                    }
                    NSUInteger logicalWidth = viewport.width > 0.0 ? (NSUInteger)llround(viewport.width) : 0;
                    NSUInteger logicalHeight = viewport.height > 0.0 ? (NSUInteger)llround(viewport.height) : 0;
                    id<MTLRasterizationRateMap> rateMap = nil;
                    if (rateMapCount > 0) {
                        size_t rateMapIndex = texIndex < rateMapCount ? texIndex
                            : (((size_t)i < rateMapCount) ? (size_t)i : 0);
                        rateMap = cp_drawable_get_rasterization_rate_map(mainDrawable, rateMapIndex);
                        if (rateMap != nil) {
                            MTLSize screen = rateMap.screenSize;
                            logicalWidth = screen.width;
                            logicalHeight = screen.height;
                        }
                    }
                    logicalW[i] = (uint32_t)logicalWidth;
                    logicalH[i] = (uint32_t)logicalHeight;
                    if (i >= 0 && i < 2) {
                        gFrameLogicalW[i] = logicalW[i];
                        gFrameLogicalH[i] = logicalH[i];
                    }
                    if (!loggedRateMaps && rateMap != nil) {
                        loggedRateMaps = YES;
                        MTLSize screen = rateMap.screenSize;
                        MTLSize physical = [rateMap physicalSizeForLayer:0];
                        MTLCoordinate2D fovealCentre = [rateMap
                            mapScreenToPhysicalCoordinates:MTLCoordinate2DMake((double)screen.width * 0.5,
                                                                              (double)screen.height * 0.5)
                                                  forLayer:0];
                        compLog("foveation rate map view %d (%s): screen=%lux%lu physical=%lux%lu "
                                "layerCount=%lu fovealCentrePhysical=(%.2f,%.2f) fovealScale=(%.3f,%.3f) "
                                "drawable=%lux%lu viewport=(%.0f,%.0f,%.0f,%.0f) rateMaps=%zu",
                                i, i == leftView ? "left" : "right",
                                (unsigned long)screen.width, (unsigned long)screen.height,
                                (unsigned long)physical.width, (unsigned long)physical.height,
                                (unsigned long)rateMap.layerCount,
                                (double)fovealCentre.x, (double)fovealCentre.y,
                                screen.width > 0 ? (double)fovealCentre.x / ((double)screen.width * 0.5) : 0.0,
                                screen.height > 0 ? (double)fovealCentre.y / ((double)screen.height * 0.5) : 0.0,
                                (unsigned long)physicalW, (unsigned long)physicalH,
                                viewport.originX, viewport.originY, viewport.width, viewport.height,
                                rateMapCount);
                    }
                }
                // A mono drawable (visionOS simulator) has one view; mirror its logical size into the
                // right-eye slot so the native-shared render feedback can still be exercised and
                // verified off-device. Device drawables always have two views.
                if (views == 1 && logicalW[0] > 0 && logicalW[1] == 0) {
                    logicalW[1] = logicalW[0];
                    logicalH[1] = logicalH[0];
                    static int loggedMonoFeedback = 0;
                    if (!loggedMonoFeedback) {
                        loggedMonoFeedback = 1;
                        compLog("render feedback: mono drawable (1 view, simulator); right logical size "
                                "mirrored from left (%ux%u) for channel verification - device builds "
                                "publish both eyes", logicalW[0], logicalH[0]);
                    }
                }
                if (!loggedLogicalSizes && views >= 1 && logicalW[0] > 0) {
                    loggedLogicalSizes = YES;
                    compLog("display geometry: logical L=%ux%u R=%ux%u physical drawable=%ux%u "
                            "foveation=%d rateMaps=%zu renderQuality=%.2f (provider eye targets should "
                            "track the logical size; foveation reduces physical memory/compositor cost, "
                            "not the provider's own render cost)",
                            logicalW[leftView], logicalH[leftView],
                            logicalW[leftView == 0 ? 1 : 0], logicalH[leftView == 0 ? 1 : 0],
                            physicalW, physicalH, (int)configuredFoveation, rateMapCount,
                            (double)cp_layer_renderer_get_render_quality(lr));
                }
                if (gPublishRenderSettingsFn != NULL && views >= 1 && logicalW[0] > 0) {
                    static uint32_t lastPubLW = 0, lastPubLH = 0, lastPubRW = 0, lastPubRH = 0;
                    static float lastPubQuality = -1.0f;
                    const uint32_t leftIndex = (uint32_t)leftView;
                    const uint32_t rightIndex = (leftView == 0) ? 1u : 0u;
                    const BOOL geometryChanged = logicalW[leftIndex] != lastPubLW ||
                        logicalH[leftIndex] != lastPubLH || logicalW[rightIndex] != lastPubRW ||
                        logicalH[rightIndex] != lastPubRH;
                    // The runtime quality is NaN on runtimes without dynamic render quality support;
                    // publish a well-defined value (the configured maximum) instead of failing the
                    // bridge-side validation.
                    float reportedQuality = (float)cp_layer_renderer_get_render_quality(lr);
                    if (!isfinite(reportedQuality) || reportedQuality < 0.0f || reportedQuality > 1.0f) {
                        reportedQuality = maxRenderQuality;
                    }
                    if (frameCount < 3 || geometryChanged || (frameCount % 10) == 0 ||
                        fabsf(reportedQuality - lastPubQuality) > 0.001f) {
                        presentationStatsSummarize(&presentStats);
                        vrmc_render_settings rs;
                        memset(&rs, 0, sizeof(rs));
                        rs.version = VRMC_RENDER_SETTINGS_VERSION;
                        rs.valid = 1;
                        rs.frame_index = (uint32_t)frameCount;
                        rs.foveation_enabled = configuredFoveation ? 1u : 0u;
                        rs.rate_map_count = (uint32_t)rateMapCount;
                        rs.left_logical_width = logicalW[leftIndex];
                        rs.left_logical_height = logicalH[leftIndex];
                        rs.right_logical_width = logicalW[rightIndex];
                        rs.right_logical_height = logicalH[rightIndex];
                        rs.drawable_width = physicalW;
                        rs.drawable_height = physicalH;
                        rs.render_quality = reportedQuality;
                        rs.max_render_quality = maxRenderQuality;
                        rs.display_hz = (float)presentStats.displayHz;
                        rs.frame_time_ms = (float)presentStats.meanMs;
                        rs.provider_eye_width = 0;
                        rs.provider_eye_height = 0;
                        const int32_t publishResult = gPublishRenderSettingsFn(&rs);
                        if (publishResult == 0) {
                            publishedRenderSettings++;
                            lastPubLW = logicalW[leftIndex];
                            lastPubLH = logicalH[leftIndex];
                            lastPubRW = logicalW[rightIndex];
                            lastPubRH = logicalH[rightIndex];
                            lastPubQuality = reportedQuality;
                            if (!loggedRenderFeedback) {
                                loggedRenderFeedback = YES;
                                compLog("render feedback published: logical L=%ux%u R=%ux%u "
                                        "physical=%ux%u foveation=%d rateMaps=%zu quality=%.2f "
                                        "displayHz=%.1f frame=%.2fms",
                                        lastPubLW, lastPubLH, lastPubRW, lastPubRH,
                                        physicalW, physicalH, (int)configuredFoveation,
                                        rateMapCount, (double)reportedQuality,
                                        (double)presentStats.displayHz, (double)presentStats.meanMs);
                            }
                        } else {
                            publishedRenderSettingsErrors++;
                            if (publishedRenderSettingsErrors == 1) {
                                compLog("render feedback publish FAILED rc=%d; the provider keeps its "
                                        "own eye-target sizing (bridge-side validation error)", publishResult);
                            }
                        }
                    }
                }
                // Rate-limited cadence/quality summary + optional auto quality adjustment.
                if (frameCount > 0 && (frameCount % 120) == 0) {
                    presentationStatsSummarize(&presentStats);
                    const double presentHz = presentStats.meanMs > 0.0 ? 1000.0 / presentStats.meanMs : 0.0;
                    float reportedQuality = (float)cp_layer_renderer_get_render_quality(lr);
                    if (!isfinite(reportedQuality) || reportedQuality < 0.0f || reportedQuality > 1.0f) {
                        reportedQuality = maxRenderQuality;
                    }
                    compLog("render feedback: displayHz=%.1f presentHz=%.1f p50=%.2fms p95=%.2fms "
                            "repeats=%d/%d quality=%.2f sharpen=%.2f logical L=%ux%u R=%ux%u "
                            "physical=%lux%lu foveation=%d rateMaps=%zu published=%llu errors=%llu",
                            (double)presentStats.displayHz, presentHz,
                            (double)presentStats.p50Ms, (double)presentStats.p95Ms,
                            presentStats.repeats, presentStats.count,
                            (double)reportedQuality, (double)currentSharpenStrength,
                            logicalW[leftView], logicalH[leftView],
                            logicalW[leftView == 0 ? 1 : 0], logicalH[leftView == 0 ? 1 : 0],
                            (unsigned long)physicalW, (unsigned long)physicalH,
                            (int)configuredFoveation, rateMapCount,
                            (unsigned long long)publishedRenderSettings,
                            (unsigned long long)publishedRenderSettingsErrors);
                    if (qualityControl.autoMode && (frameCount - lastQualityAdjustFrame) >= 120) {
                        lastQualityAdjustFrame = frameCount;
                        const BOOL struggling = presentStats.count > 0 &&
                            (presentStats.repeats > presentStats.count / 8 ||
                             (presentStats.baseMs > 0.0 &&
                              presentStats.p95Ms > presentStats.baseMs * 1.6));
                        const BOOL headroom = presentStats.count > 0 && presentStats.repeats == 0 &&
                            presentStats.baseMs > 0.0 &&
                            presentStats.p95Ms <= presentStats.baseMs * 1.25;
                        float next = currentRenderQuality;
                        if (struggling && currentRenderQuality > 0.2f) {
                            next = MAX(0.2f, currentRenderQuality - 0.10f);
                        } else if (headroom && currentRenderQuality < maxRenderQuality) {
                            next = MIN(maxRenderQuality, currentRenderQuality + 0.05f);
                        }
                        if (fabsf(next - currentRenderQuality) > 0.001f) {
                            const float previous = currentRenderQuality;
                            currentRenderQuality = next;
                            applyRenderQuality(lr, next, "auto adjust");
                            compLog("render quality auto: %.2f -> %.2f (displayHz=%.1f p95=%.2fms "
                                    "repeats=%d/%d)", (double)previous, (double)next,
                                    (double)presentStats.displayHz, (double)presentStats.p95Ms,
                                    presentStats.repeats, presentStats.count);
                        }
                    }
                }
            }

            if (!loggedViewInfo && views > 0) {
                loggedViewInfo = YES;
                compLog("drawable: colorFormat=%lu views=%d textures=%zu rateMaps=%zu target=%d(%s)",
                        (unsigned long)pipes.colorFormat, views,
                        cp_drawable_get_texture_count(mainDrawable),
                        cp_drawable_get_rasterization_rate_map_count(mainDrawable), mainTarget,
                        mainTarget == (int)cp_drawable_target_built_in ? "built_in" : "capture");
                for (int i = 0; i < views; i++) {
                    cp_view_t view = cp_drawable_get_view(mainDrawable, i);
                    cp_view_texture_map_t map = cp_view_get_view_texture_map(view);
                    MTLViewport viewport = cp_view_texture_map_get_viewport(map);
                    size_t texIndex = cp_view_texture_map_get_texture_index(map);
                    size_t sliceIndex = cp_view_texture_map_get_slice_index(map);
                    id<MTLTexture> colorTex = cp_drawable_get_color_texture(mainDrawable, texIndex);
                    id<MTLTexture> depthTex = cp_drawable_get_depth_texture(mainDrawable, texIndex);
                    simd_float4x4 vt = cp_view_get_transform(view);
                    simd_float4x4 proj = cp_drawable_compute_projection(
                        mainDrawable, cp_axis_direction_convention_right_up_back, i);
                    simd_float4x4 invProj = simd_inverse(proj);
                    simd_float4 derived = viewTangents(invProj);
                    logMatrix("viewToDevice", vt);
                    logMatrix("projection", proj);
                    compLog("view %d (%s) texIndex=%zu slice=%zu viewport=(%.0f,%.0f,%.0f,%.0f) "
                            "tangents l/r/d/u=(%.3f,%.3f,%.3f,%.3f) pos=(%.4f,%.4f,%.4f) fwd=(%.3f,%.3f,%.3f)",
                            i, i == leftView ? "left" : "right", texIndex, sliceIndex,
                            viewport.originX, viewport.originY, viewport.width, viewport.height,
                            derived.x, derived.y, derived.z, derived.w,
                            vt.columns[3].x, vt.columns[3].y, vt.columns[3].z,
                            -vt.columns[2].x, -vt.columns[2].y, -vt.columns[2].z);
                    compLog("view %d attachments: color=%p %lux%lu fmt=%lu type=%lu arrayLength=%lu "
                            "slice=%zu | depth=%p %lux%lu fmt=%lu type=%lu | rateMapCount=%zu",
                            i, (__bridge void *)colorTex,
                            (unsigned long)colorTex.width, (unsigned long)colorTex.height,
                            (unsigned long)colorTex.pixelFormat, (unsigned long)colorTex.textureType,
                            (unsigned long)colorTex.arrayLength, sliceIndex,
                            (__bridge void *)depthTex,
                            (unsigned long)(depthTex != nil ? depthTex.width : 0),
                            (unsigned long)(depthTex != nil ? depthTex.height : 0),
                            (unsigned long)(depthTex != nil ? depthTex.pixelFormat : 0),
                            (unsigned long)(depthTex != nil ? depthTex.textureType : 0),
                            cp_drawable_get_rasterization_rate_map_count(mainDrawable));
                }
                vrmc_eye_targets eyesProbe;
                memset(&eyesProbe, 0, sizeof(eyesProbe));
                BOOL haveEyesProbe = (gEyeFn != NULL && gEyeFn(&eyesProbe) == 0 &&
                                      eyesProbe.left_texture != 0 && eyesProbe.right_texture != 0);
                simd_float4 ls = sourceTangentsFromFov(eyesProbe.left_fov);
                simd_float4 rs = sourceTangentsFromFov(eyesProbe.right_fov);
                compLog("provider eye tangents L=(%.3f,%.3f,%.3f,%.3f) R=(%.3f,%.3f,%.3f,%.3f) ipd=%.4f "
                        "haveEyes=%d displayViewsPublished=%d",
                        ls.x, ls.y, ls.z, ls.w, rs.x, rs.y, rs.z, rs.w, ipd, (int)haveEyesProbe,
                        (int)displayViewsPublished);

                // CPU-side ray->UV diagnostics: exactly the shader math, so a device log proves
                // whether the drawable rays land inside the provider frustum (EV-0086 hypothesis).
                // Do NOT reset useFlat here: when display views are published the provider renders
                // the display frustum and flat mapping is the aligned path.
                for (int i = 0; i < views; i++) {
                    cp_view_t view = cp_drawable_get_view(mainDrawable, i);
                    simd_float4x4 vt = cp_view_get_transform(view);
                    simd_float4x4 proj = cp_drawable_compute_projection(
                        mainDrawable, cp_axis_direction_convention_right_up_back, i);
                    simd_float4x4 invProj = simd_inverse(proj);
                    simd_float4 st4 = (i == leftView) ? ls : rs;
                    BOOL isLeft = (i == leftView);
                    VRMCRayDiag center = evaluateRay(invProj, vt, st4, 0.0f, 0.0f);
                    compLog("diag view %d (%s): center d=(%.3f,%.3f,%.3f) finite=%d behind=%d "
                            "t=(%.3f,%.3f) uv=(%.3f,%.3f) inside=%d",
                            i, isLeft ? "left" : "right", center.dir.x, center.dir.y, center.dir.z,
                            (int)center.finite, (int)center.behind, center.t.x, center.t.y,
                            center.uv.x, center.uv.y, (int)center.inside);
                    float corners[4][2] = {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}};
                    for (int c = 0; c < 4; c++) {
                        VRMCRayDiag corner = evaluateRay(invProj, vt, st4, corners[c][0], corners[c][1]);
                        compLog("diag view %d corner %d ndc=(%.0f,%.0f) finite=%d behind=%d uv=(%.3f,%.3f) inside=%d",
                                i, c, corners[c][0], corners[c][1], (int)corner.finite,
                                (int)corner.behind, corner.uv.x, corner.uv.y, (int)corner.inside);
                    }
                    int samples = 9 * 9;
                    int insideCount = 0, behindCount = 0, nonFiniteCount = 0;
                    float maxAbsUV = 0.0f;
                    for (int gy = 0; gy < 9; gy++) {
                        for (int gx = 0; gx < 9; gx++) {
                            float ndcX = -1.0f + 2.0f * (float)gx / 8.0f;
                            float ndcY = -1.0f + 2.0f * (float)gy / 8.0f;
                            VRMCRayDiag sample = evaluateRay(invProj, vt, st4, ndcX, ndcY);
                            if (!sample.finite) { nonFiniteCount++; continue; }
                            if (sample.behind) { behindCount++; continue; }
                            if (sample.inside) insideCount++;
                            float excess = fmaxf(fmaxf(-sample.uv.x, sample.uv.x - 1.0f),
                                                 fmaxf(-sample.uv.y, sample.uv.y - 1.0f));
                            if (excess > maxAbsUV) maxAbsUV = excess;
                        }
                    }
                    compLog("diag view %d coverage 9x9: inside=%d/%d behind=%d/%d nonFinite=%d/%d maxUvExcess=%.3f",
                            i, insideCount, samples, behindCount, samples, nonFiniteCount, samples, maxAbsUV);
                    if (reprojMode == VRMCReprojAuto) {
                        BOOL usable = (center.finite && !center.behind && center.inside) &&
                                      (nonFiniteCount == 0);
                        if (!usable) {
                            useFlat = YES;
                            compLog("diag AUTO-FLAT: view %d centre ray unusable (finite=%d behind=%d inside=%d)",
                                    i, (int)center.finite, (int)center.behind, (int)center.inside);
                        }
                    }
                }
                if (!modeLogged) {
                    modeLogged = YES;
                    compLog("shading mode=%s (%s)%s", useFlat ? "flat" : "reprojection",
                            reprojMode == VRMCReprojFlat ? "forced by flag" :
                            (reprojMode == VRMCReprojForced ? "forced by flag" : "auto"),
                            debugShading ? " debugShading=on" : "");
                }
            } else if (views == 1) {
                static int loggedSingleView = 0;
                if (!loggedSingleView) {
                    loggedSingleView = 1;
                    compLog("drawable has 1 view (simulator or mono target); the compositor expects 2 on device");
                }
            }

            if (gTrackFn != NULL && anchorOK) {
                vrmc_tracking_state ts;
                memset(&ts, 0, sizeof(ts));
                simd_quatf q = simd_quaternion(anchorTransform);
                ts.presentation_time_ns = (uint64_t)(queryTime * 1e9);
                rememberAnchor(ts.presentation_time_ns, anchor);
                ts.head.position.x = anchorTransform.columns[3].x;
                ts.head.position.y = anchorTransform.columns[3].y;
                ts.head.position.z = anchorTransform.columns[3].z;
                ts.head.orientation.x = q.vector.x;
                ts.head.orientation.y = q.vector.y;
                ts.head.orientation.z = q.vector.z;
                ts.head.orientation.w = q.vector.w;
                ts.ipd_m = ipd;
                ts.controllers[0].orientation.w = 1.0f;
                ts.controllers[1].orientation.w = 1.0f;
                gTrackFn(&ts);
            }

            // ---------------------- M4-W1: publish the immersive input snapshot ----------------------
            // One snapshot per frame, after the device-anchor query and before presenting. Hand anchors
            // are queried at the frame's trackable-anchor prediction time in the SAME ARKit session as
            // world tracking and copied in device/anchor space (same space as the head pose above), so
            // the provider needs no extra transform. Synthetic mode (vrmc-input-sim.flag) publishes
            // fabricated hands instead of ARKit data and is independent of authorization.
            {
                vrmc_input_state inputState;
                memset(&inputState, 0, sizeof(inputState));
                inputState.frame_index = (uint32_t)frameCount;
                CFTimeInterval handQueryTime =
                    cp_time_to_cf_time_interval(cp_frame_timing_get_trackable_anchor_time(actual));
                if (!isfinite(handQueryTime)) handQueryTime = queryTime;
                inputState.timestamp_ns = (uint64_t)llround(handQueryTime * 1e9);
                uint32_t validMask = 0;
                if (inputSynthetic) {
                    if (inputSimStart < 0.0) inputSimStart = handQueryTime;
                    int phaseIndex = 0;
                    inputSimPhaseAt(inputSimScript, handQueryTime - inputSimStart, &phaseIndex);
                    const VRMCInputSimScript *script = &kInputSimScripts[inputSimScript];
                    if (phaseIndex >= 0 && phaseIndex < script->count) {
                        const VRMCInputSimPhase *phase = &script->phases[phaseIndex];
                        if (phaseIndex != inputSimLastPhase) {
                            inputSimLastPhase = phaseIndex;
                            inputLog(YES, "input script=%s phase=%d/%d L=(pinch=%d fist=%d) "
                                          "R=(pinch=%d fist=%d) (fabricated hands)",
                                     script->name, phaseIndex + 1, script->count,
                                     (int)phase->pinch_left, (int)phase->fist_left,
                                     (int)phase->pinch_right, (int)phase->fist_right);
                        }
                        buildSyntheticHand(&inputState.hands[VRMC_INPUT_LEFT_HAND], anchorTransform, -1,
                                           phase->pinch_left != 0, phase->fist_left != 0,
                                           inputState.timestamp_ns);
                        buildSyntheticHand(&inputState.hands[VRMC_INPUT_RIGHT_HAND], anchorTransform, +1,
                                           phase->pinch_right != 0, phase->fist_right != 0,
                                           inputState.timestamp_ns);
                        validMask = 3u;
                        if (!inputSimLapLogged && (handQueryTime - inputSimStart) >= inputSimLapSeconds) {
                            inputSimLapLogged = YES;
                            inputLog(YES, "input script=%s lap complete frame=%d (one full fabricated "
                                          "gesture cycle published)", script->name, frameCount);
                        }
                    }
                } else if (handProvider != nil && handAnchorLeft != nil && handAnchorRight != nil) {
                    ar_hand_anchor_query_status_t handQueryStatus =
                        ar_hand_tracking_provider_query_anchors_at_timestamp(
                            handProvider, handQueryTime, handAnchorLeft, handAnchorRight);
                    if (handQueryStatus == ar_hand_anchor_query_status_success) {
                        // Query fills LEFT into hand slot 0 and RIGHT into slot 1 by argument order,
                        // independent of the (normalized) chirality field.
                        if (fillHandFromAnchor(&inputState.hands[VRMC_INPUT_LEFT_HAND], handAnchorLeft,
                                               inputState.timestamp_ns)) {
                            validMask |= 1u;
                        }
                        if (fillHandFromAnchor(&inputState.hands[VRMC_INPUT_RIGHT_HAND], handAnchorRight,
                                               inputState.timestamp_ns)) {
                            validMask |= 2u;
                        }
                    } else {
                        inputHandQueryFailures++;
                        if (inputHandQueryFailures == 1 || (frameCount % 300) == 0) {
                            inputLog(inputSynthetic, "input hand query failed status=%ld frame=%d "
                                     "failures=%llu (publishing untracked hands this frame)",
                                     (long)handQueryStatus, frameCount,
                                     (unsigned long long)inputHandQueryFailures);
                        }
                    }
                }
                inputState.valid_mask = validMask;
                inputLastTimestampNs = inputState.timestamp_ns;
                if (gInputPublishFn != NULL) {
                    const int32_t publishResult = gInputPublishFn(&inputState);
                    if (publishResult == 0) {
                        inputPublishCount++;
                        if (!inputFirstPublishLogged || (frameCount % 300) == 0) {
                            inputFirstPublishLogged = YES;
                            const unsigned long long publishedSeq = (gInputSequenceFn != NULL)
                                ? (unsigned long long)gInputSequenceFn()
                                : (unsigned long long)inputPublishCount;
                            inputLog(inputSynthetic,
                                     "input publish seq=%llu frame=%d valid_mask=%u timestamp_ns=%llu "
                                     "source=%s hands=L%dR%d", publishedSeq, frameCount, validMask,
                                     (unsigned long long)inputState.timestamp_ns,
                                     inputSynthetic ? "synthetic" : "arkit",
                                     (validMask & 1u) ? 1 : 0, (validMask & 2u) ? 1 : 0);
                        }
                    } else {
                        inputPublishErrors++;
                        if (inputPublishErrors == 1 || (frameCount % 300) == 0) {
                            inputLog(inputSynthetic, "input publish error rc=%d frame=%d errors=%llu "
                                     "(provider sees no fresh snapshot and releases; presentation "
                                     "unaffected)", publishResult, frameCount,
                                     (unsigned long long)inputPublishErrors);
                        }
                    }
                }
                // Rate-limited hand/pose telemetry (~every 60 frames). Never dump the 27-joint arrays.
                if ((frameCount % 60) == 0) {
                    const unsigned long long telemetrySeq = (gInputSequenceFn != NULL)
                        ? (unsigned long long)gInputSequenceFn()
                        : (unsigned long long)inputPublishCount;
                    inputLog(inputSynthetic,
                             "input hands L=%d R=%d wristL=(%.3f,%.3f,%.3f) wristR=(%.3f,%.3f,%.3f) "
                             "seq=%llu", (validMask & 1u) ? 1 : 0, (validMask & 2u) ? 1 : 0,
                             inputState.hands[VRMC_INPUT_LEFT_HAND].wrist_position.x,
                             inputState.hands[VRMC_INPUT_LEFT_HAND].wrist_position.y,
                             inputState.hands[VRMC_INPUT_LEFT_HAND].wrist_position.z,
                             inputState.hands[VRMC_INPUT_RIGHT_HAND].wrist_position.x,
                             inputState.hands[VRMC_INPUT_RIGHT_HAND].wrist_position.y,
                             inputState.hands[VRMC_INPUT_RIGHT_HAND].wrist_position.z, telemetrySeq);
                }
            }

            // Acquire the latest eye frame atomically (textures + GPU timeline + change detection).
            // Re-acquire every frame and never cache the handles: the provider may destroy them on a
            // render-target reinit, which bumps texture_generation.
            vrmc_shared_eye_frame eyeFrame;
            memset(&eyeFrame, 0, sizeof(eyeFrame));
            BOOL haveEyes = NO;
            if (gAcquireFn != NULL) {
                haveEyes = (gAcquireFn(&eyeFrame) == 0) && eyeFrame.eyes.left_texture != 0 &&
                           eyeFrame.eyes.right_texture != 0;
            } else if (gEyeFn != NULL) {
                // Legacy accessor: no sync/generation info (older bridge builds).
                haveEyes = (gEyeFn(&eyeFrame.eyes) == 0) && eyeFrame.eyes.left_texture != 0 &&
                           eyeFrame.eyes.right_texture != 0;
            }
            // Game-stop handling: the provider signals teardown from VisionVR.destroy() (and clears
            // the eye textures). Without this, the immersive space would keep presenting the fallback
            // test pattern after the game exits. A 5 s no-eye timeout is the crash/no-destroy fallback.
            {
                static BOOL hadEyesOnce = NO;
                static uint64_t lastEyesNs = 0;
                uint64_t nowNs = clock_gettime_nsec_np(CLOCK_MONOTONIC);
                if (haveEyes) {
                    hadEyesOnce = YES;
                    lastEyesNs = nowNs;
                }
                BOOL gameStopping = (gGameStoppingFn != NULL) && (gGameStoppingFn() != 0);
                BOOL eyesLostTimeout = hadEyesOnce && !haveEyes && lastEyesNs != 0 &&
                    (nowNs - lastEyesNs) > 5ull * 1000000000ull;
                if (gGameStoppedPosted.load() == 0 && (gameStopping || eyesLostTimeout)) {
                    if (gGameStoppedPosted.exchange(1) == 0) {
                        if (gClearGameStoppingFn != NULL) gClearGameStoppingFn();
                        const char *reason = gameStopping ? "provider-signal" : "eyes-lost-timeout";
                        compLog("game stopping detected (%s); posting VRMCGameStopped", reason);
                        // The game is gone; do not keep the (possibly large) eye textures cached.
                        lastLeftEye = nil;
                        lastRightEye = nil;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[NSNotificationCenter defaultCenter]
                                postNotificationName:@"VRMCGameStopped"
                                              object:nil
                                            userInfo:@{@"reason" : @(reason)}];
                        });
                    }
                }
            }
            // Settled-frame selection (tearing / unrendered-frame fix). The provider publishes a texture
            // pair right after recording the GPU copy into it, so the newest publish may still be in
            // flight on the game's GPU queue. Show a publish only once it is settled: a newer one has
            // been published (the game's next frame started after it was submitted), its GPU sync
            // event has signalled, or it has been the newest for 2 compositor frames (game paused or
            // slower than 45 fps). Together with the provider's 3-texture export ring the compositor
            // never samples a texture that is still being written or was never written.
            static __strong id<MTLTexture> pendingL = nil, pendingR = nil, settledL = nil, settledR = nil;
            static vrmc_eye_targets pendingEyes, settledEyes;
            static vrmc_shared_frame_sync pendingSync, settledSync;
            static uint64_t pendingSeq = 0;
            static int pendingSinceFrame = 0;
            static uint64_t settledCount = 0;
            static uint64_t lastShownPoseNs = 0;
            if (frameCount == 0) {
                // New immersive session: nothing from the previous session may be shown or matched.
                pendingL = nil; pendingR = nil; settledL = nil; settledR = nil;
                pendingSeq = 0; settledCount = 0; lastShownPoseNs = 0;
                clearAnchorRing();
            }
            const BOOL rawHaveEyes = haveEyes;
            if (rawHaveEyes) {
                const BOOL newPublish = (pendingL == nil) || eyeFrame.publish_sequence != pendingSeq ||
                    (uint64_t)(uintptr_t)(__bridge void *)pendingL != eyeFrame.eyes.left_texture ||
                    (uint64_t)(uintptr_t)(__bridge void *)pendingR != eyeFrame.eyes.right_texture;
                if (newPublish) {
                    if (pendingL != nil && pendingR != nil) {
                        settledL = pendingL; settledR = pendingR; settledEyes = pendingEyes;
                        settledSync = pendingSync; settledCount++;
                    }
                    pendingL = (__bridge id<MTLTexture>)(void *)(uintptr_t)eyeFrame.eyes.left_texture;
                    pendingR = (__bridge id<MTLTexture>)(void *)(uintptr_t)eyeFrame.eyes.right_texture;
                    pendingEyes = eyeFrame.eyes;
                    pendingSync = eyeFrame.sync;
                    pendingSeq = eyeFrame.publish_sequence;
                    pendingSinceFrame = frameCount;
                } else if (pendingL != nil && settledL != pendingL) {
                    BOOL syncDone = NO;
                    if (eyeFrame.sync.valid != 0 && eyeFrame.sync.shared_event != 0) {
                        id<MTLSharedEvent> ev = (__bridge id<MTLSharedEvent>)(void *)(uintptr_t)eyeFrame.sync.shared_event;
                        syncDone = ev.signaledValue >= eyeFrame.sync.signal_value;
                    }
                    if (syncDone || frameCount - pendingSinceFrame >= 2) {
                        settledL = pendingL; settledR = pendingR; settledEyes = pendingEyes;
                        settledSync = pendingSync; settledCount++;
                    }
                }
                if (settledCount == 1 && settledL != nil) {
                    static BOOL loggedSettle = NO;
                    if (!loggedSettle) {
                        loggedSettle = YES;
                        compLog("eye frames: showing settled frames only (newest publish shown once a newer "
                                "one exists, its GPU event signalled, or it aged 2 frames); pose-matched "
                                "anchors %s", pendingEyes.presentation_deadline_ns != 0 ? "ON" : "OFF (no pose stamp)");
                    }
                }
                haveEyes = (settledL != nil && settledR != nil);
                if (haveEyes) {
                    eyeFrame.eyes = settledEyes;
                    eyeFrame.eyes.left_texture = (uint64_t)(uintptr_t)(__bridge void *)settledL;
                    eyeFrame.eyes.right_texture = (uint64_t)(uintptr_t)(__bridge void *)settledR;
                    // GPU wait (when the provider publishes a timeline) must target the frame shown.
                    eyeFrame.sync = settledSync;
                }
            } else if (pendingL != nil) {
                // The provider cleared the shared frame (resize / teardown): forget the in-flight
                // publish; the last settled pair stays available to the hold-last-frame grace below.
                pendingL = nil; pendingR = nil; pendingSeq = 0;
            }
            if (gGameStoppedPosted.load() != 0) {
                pendingL = nil; pendingR = nil; settledL = nil; settledR = nil; settledCount = 0;
            }
            if (haveEyes) lastShownPoseNs = (uint64_t)eyeFrame.eyes.presentation_deadline_ns;

            // M8 resize grace (see the state comment above): when the provider has just cleared the
            // shared eye frame for a render-target rebuild, keep sampling the last good pair for a few
            // frames. Only for the flat path (the reprojection path needs the provider FOV per frame),
            // and never when the operator explicitly forced the pattern/probe or sampling is disabled.
            BOOL usingCachedEyes = NO;
            if (!haveEyes) {
                eyesMissingFrames++;
                // Release: hold the last picture for up to ~3 s (pause/menu transitions make the
                // provider rebuild its eye targets, which used to flash the test pattern for a
                // fraction of a second), then go to black. Diagnostics keep the short 30-frame grace.
                const int eyeGraceFrames = diagnostics ? 30 : 270;
                if (!forceTestPattern && !samplingDisabled && !selfTest && useFlat &&
                    lastLeftEye != nil && lastRightEye != nil && eyesMissingFrames <= eyeGraceFrames) {
                    usingCachedEyes = YES;
                    if (!loggedEyeCacheReuse) {
                        loggedEyeCacheReuse = YES;
                        compLog("eyes absent: reusing the last sampled eye frame for up to %d frames "
                                "(age=%llu frames; provider render-target rebuild; retained MTLTextures "
                                "stay alive)", eyeGraceFrames,
                                (unsigned long long)(lastEyesFrame != 0 ? frameCount - lastEyesFrame : 0));
                    }
                } else if (loggedEyeCacheReuse) {
                    loggedEyeCacheReuse = NO;
                    // Do not keep the (large) cached pair once the grace is over.
                    lastLeftEye = nil;
                    lastRightEye = nil;
                    compLog("eyes absent for %d frames: last-frame grace expired; %s until eyes return",
                            eyesMissingFrames, diagnostics ? "falling back to the test pattern" : "presenting black");
                }
            } else {
                if (eyesMissingFrames > 0) {
                    compLog("eye frame resumed after %d frame(s) without provider eyes",
                            eyesMissingFrames);
                }
                eyesMissingFrames = 0;
                loggedEyeCacheReuse = NO;
                lastLeftEye = (__bridge id<MTLTexture>)(void *)(uintptr_t)eyeFrame.eyes.left_texture;
                lastRightEye = (__bridge id<MTLTexture>)(void *)(uintptr_t)eyeFrame.eyes.right_texture;
                lastEyesFrame = frameCount;
            }
            // Textures/sizes used to draw this frame: the provider's, or the cached pair.
            uint64_t drawLeftHandle = haveEyes ? eyeFrame.eyes.left_texture
                : (usingCachedEyes ? (uint64_t)(uintptr_t)(__bridge void *)lastLeftEye : 0);
            uint64_t drawRightHandle = haveEyes ? eyeFrame.eyes.right_texture
                : (usingCachedEyes ? (uint64_t)(uintptr_t)(__bridge void *)lastRightEye : 0);
            uint32_t drawLeftWidth = haveEyes ? eyeFrame.eyes.left_width
                : (usingCachedEyes ? (uint32_t)lastLeftEye.width : 0);
            uint32_t drawLeftHeight = haveEyes ? eyeFrame.eyes.left_height
                : (usingCachedEyes ? (uint32_t)lastLeftEye.height : 0);
            uint32_t drawRightWidth = haveEyes ? eyeFrame.eyes.right_width
                : (usingCachedEyes ? (uint32_t)lastRightEye.width : 0);
            uint32_t drawRightHeight = haveEyes ? eyeFrame.eyes.right_height
                : (usingCachedEyes ? (uint32_t)lastRightEye.height : 0);
            const vrmc_eye_targets *eyesPtr = &eyeFrame.eyes;
            // Log every provider eye-texture swap by comparing the per-eye handles.
            //
            // NOT the bridge texture generation: vrmc_shared_clear_eye_textures() zeroes
            // texture_generation before each provider eye-target rebuild and the next publish sets it
            // back to 1, so a "generation != lastGeneration" test only fires on the first frame and
            // hides every later swap (the 2026-11-07 M8 device run rebuilt 15 times but logged one
            // generation line). The handle is what actually changes on a rebuild, and it is also the
            // key of the cached sRGB texture view, so this line gives the purple-menu-flash
            // investigation an exact "which texture was sampled after which swap" timeline.
            static uint64_t loggedEyeHandleL = 0;
            static uint64_t loggedEyeHandleR = 0;
            static int loggedEyeTextureUsage = 0;
            // Frame of the most recent swap; the diagnostics Probe below reads the drawn drawable for
            // the first frames after it (the suspected flash window) without waiting for the 300-frame
            // cadence.
            static uint64_t eyeTextureChangeFrame = 0;
            if (haveEyes && (eyeFrame.eyes.left_texture != loggedEyeHandleL ||
                             eyeFrame.eyes.right_texture != loggedEyeHandleR)) {
                compLog("provider eye textures changed: generation=%u publish=%llu "
                        "L=0x%llx->0x%llx R=0x%llx->0x%llx size=%ux%u "
                        "(handles are re-acquired every frame, never cached; "
                        "generation is reset to 1 by the bridge clear)",
                        eyeFrame.texture_generation, (unsigned long long)eyeFrame.publish_sequence,
                        (unsigned long long)loggedEyeHandleL,
                        (unsigned long long)eyeFrame.eyes.left_texture,
                        (unsigned long long)loggedEyeHandleR,
                        (unsigned long long)eyeFrame.eyes.right_texture,
                        eyeFrame.eyes.left_width, eyeFrame.eyes.left_height);
                loggedEyeHandleL = eyeFrame.eyes.left_texture;
                loggedEyeHandleR = eyeFrame.eyes.right_texture;
                eyeTextureChangeFrame = frameCount;
            }
            if (haveEyes && !loggedEyeTextureUsage) {
                loggedEyeTextureUsage = 1;
                id<MTLTexture> usageLeft = (__bridge id<MTLTexture>)(void *)(uintptr_t)eyeFrame.eyes.left_texture;
                id<MTLTexture> usageRight = (__bridge id<MTLTexture>)(void *)(uintptr_t)eyeFrame.eyes.right_texture;
                compLog("provider eye texture usage L=0x%lx (shaderRead=%d) R=0x%lx (shaderRead=%d) "
                        "syncValid=%d signalValue=%llu providerFrame=%u",
                        (unsigned long)usageLeft.usage, !!(usageLeft.usage & MTLTextureUsageShaderRead),
                        (unsigned long)usageRight.usage, !!(usageRight.usage & MTLTextureUsageShaderRead),
                        (int)(eyeFrame.sync.valid != 0),
                        (unsigned long long)eyeFrame.sync.signal_value,
                        eyeFrame.sync.frame_index);
            }

            if (haveEyes && (frameCount == 1 || frameCount % 300 == 0)) {
                id<MTLTexture> leftTex = (__bridge id<MTLTexture>)(void *)(uintptr_t)eyesPtr->left_texture;
                id<MTLTexture> rightTex = (__bridge id<MTLTexture>)(void *)(uintptr_t)eyesPtr->right_texture;
                if (frameCount == 1) {
                    compLog("provider eye textures L=%p fmt=%lu %lux%lu R=%p fmt=%lu %lux%lu",
                            (__bridge void *)leftTex, (unsigned long)leftTex.pixelFormat,
                            (unsigned long)leftTex.width, (unsigned long)leftTex.height,
                            (__bridge void *)rightTex, (unsigned long)rightTex.pixelFormat,
                            (unsigned long)rightTex.width, (unsigned long)rightTex.height);
                }
                // GPU->CPU readback: once at the start for the log, periodically only in diagnostics
                // (a blit + completion handler every 300 frames is a needless hitch in normal play).
                if (frameCount == 1 || diagnostics) {
                    scheduleProviderTextureStats(queue, leftTex, "L", frameCount);
                    scheduleProviderTextureStats(queue, rightTex, "R", frameCount);
                }
            }
            // If the provider image is measurably black, show the test pattern instead of sampling so a
            // black screen is never ambiguous: pattern visible => presentation alive, provider image black.
            // Diagnostics only: in normal play a dark cave or a black loading screen measures "black"
            // too, and this latch never resets - the pattern would replace the game for the session.
            if (diagnostics && haveEyes && !autoTestPattern &&
                gTexBlackStreakL.load() >= 2 && gTexBlackStreakR.load() >= 2) {
                autoTestPattern = YES;
                compLog("AUTO TEST-PATTERN: provider eye textures measured black twice in a row "
                        "(luma L=%.2f R=%.2f); drawing the procedural pattern instead of sampling",
                        (double)gTexMeanL.load(), (double)gTexMeanR.load());
            }

            // Release: never a test pattern. Without eyes (and past the hold-last-frame grace) the
            // views are cleared to black and nothing is drawn until the game publishes a frame.
            BOOL testPatternNow = diagnostics &&
                                  ((!haveEyes && !usingCachedEyes) || samplingDisabled ||
                                   forceTestPattern || autoTestPattern || selfTest);
            if ((frameCount % 90) == 0) {
                vignetteStrength = readVignetteStrength();
            }
            if (testPatternNow != lastTestPatternState) {
                lastTestPatternState = testPatternNow;
                compLog("TEST PATTERN state changed: active=%d haveEyes=%d samplingDisabled=%d "
                        "forceTestPattern=%d autoTestPattern=%d selfTest=%d (blue mode badge on the pattern)",
                        (int)testPatternNow, (int)haveEyes, samplingDisabled, (int)forceTestPattern,
                        (int)autoTestPattern, (int)selfTest);
            }
            if (clearProbe && !clearProbeLogged) {
                clearProbeLogged = YES;
                compLog("CLEAR-PROBE active: clearing only (viewport 0 magenta, viewport 1 cyan), NO draws. "
                        "If the operator still reports black, no drawable reaches the display.");
            }
            if (presentProof && !presentProofLogged) {
                presentProofLogged = YES;
                compLog("PRESENT-PROOF active: bright checker border + magenta centre cross are drawn per view");
            }

            id<MTLCommandBuffer> cb = [queue commandBuffer];
            // M4 shutdown-safety: keep the provider's MTLTextures alive until this command buffer
            // completes. The provider clears the shared handles on VR teardown, but a frame already in
            // flight must not sample (or release) a freed texture (EV-0096 shutdown SIGSEGV, objc_retain
            // on an eye-texture handle). Retain before encoding, release in the completion handler.
            uint64_t retainedLeft = drawLeftHandle;
            uint64_t retainedRight = drawRightHandle;
            if (retainedLeft != 0) CFRetain((CFTypeRef)(uintptr_t)retainedLeft);
            if (retainedRight != 0) CFRetain((CFTypeRef)(uintptr_t)retainedRight);
            [cb addCompletedHandler:^(id<MTLCommandBuffer> completed) {
                if (retainedLeft != 0) CFRelease((CFTypeRef)(uintptr_t)retainedLeft);
                if (retainedRight != 0) CFRelease((CFTypeRef)(uintptr_t)retainedRight);
            }];
            // Order this frame's sampling after the provider's Vulkan submission: one wait per command
            // buffer, before the first render pass that samples an eye texture. No-op until the
            // provider publishes an exportable timeline (sync.valid == 0).
            if (haveEyes && eyeFrame.sync.valid != 0) {
                id<MTLSharedEvent> sharedEvent =
                    (__bridge id<MTLSharedEvent>)(void *)(uintptr_t)eyeFrame.sync.shared_event;
                if (sharedEvent != nil && [sharedEvent conformsToProtocol:@protocol(MTLSharedEvent)]) {
                    [cb encodeWaitForEvent:sharedEvent value:eyeFrame.sync.signal_value];
                    static int loggedEventWait = 0;
                    if (!loggedEventWait) {
                        loggedEventWait = 1;
                        compLog("eye frame sync: waiting on shared event %p value=%llu providerFrame=%u "
                                "publishSequence=%llu",
                                (__bridge void *)sharedEvent,
                                (unsigned long long)eyeFrame.sync.signal_value,
                                eyeFrame.sync.frame_index,
                                (unsigned long long)eyeFrame.publish_sequence);
                    }
                }
            }
            // Edge anti-aliasing pre-pass at the game's resolution, once per new game frame and eye
            // (the result is reused for every display frame that shows the same game frame).
            BOOL aaReady[2] = {NO, NO};
            if (aaEnabled && useFlat && !testPatternNow && (haveEyes || usingCachedEyes) && !fxaaPipeFailed) {
                if (fxaaPipe == nil) {
                    NSError *aaErr = nil;
                    id<MTLLibrary> aaLib = [device newLibraryWithSource:shaderSource() options:nil error:&aaErr];
                    MTLRenderPipelineDescriptor *apd = [MTLRenderPipelineDescriptor new];
                    apd.vertexFunction = [aaLib newFunctionWithName:@"vmain"];
                    apd.fragmentFunction = [aaLib newFunctionWithName:@"fmain_fxaa"];
                    apd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
                    fxaaPipe = (aaLib != nil && apd.fragmentFunction != nil)
                        ? [device newRenderPipelineStateWithDescriptor:apd error:&aaErr] : nil;
                    if (fxaaPipe == nil) {
                        fxaaPipeFailed = YES;
                        compLog("edge anti-aliasing pipeline FAILED (%s); upscaling without AA",
                                aaErr.description.UTF8String ?: "unknown");
                    }
                }
                for (int eye = 0; eye < 2 && fxaaPipe != nil; eye++) {
                    const uint64_t srcHandle = eye == 0 ? drawLeftHandle : drawRightHandle;
                    if (srcHandle == 0) continue;
                    id<MTLTexture> src = (__bridge id<MTLTexture>)(void *)(uintptr_t)srcHandle;
                    if (src.device != device) continue;
                    if (aaTex[eye] != nil && aaSrcHandle[eye] == srcHandle &&
                        aaTex[eye].width == src.width && aaTex[eye].height == src.height) {
                        aaReady[eye] = YES; // same game frame as last time: reuse
                        continue;
                    }
                    if (aaTex[eye] == nil || aaTex[eye].width != src.width || aaTex[eye].height != src.height) {
                        MTLTextureDescriptor *ad = [MTLTextureDescriptor
                            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                         width:src.width height:src.height mipmapped:NO];
                        ad.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
                        ad.storageMode = MTLStorageModePrivate;
                        aaTex[eye] = [device newTextureWithDescriptor:ad];
                        compLog("edge anti-aliasing: %s target %lux%lu", eye == 0 ? "L" : "R",
                                (unsigned long)src.width, (unsigned long)src.height);
                    }
                    if (aaTex[eye] == nil) continue;
                    id<MTLTexture> srcView = src;
                    MTLPixelFormat sf = src.pixelFormat == MTLPixelFormatRGBA8Unorm ? MTLPixelFormatRGBA8Unorm_sRGB
                        : (src.pixelFormat == MTLPixelFormatBGRA8Unorm ? MTLPixelFormatBGRA8Unorm_sRGB
                                                                       : MTLPixelFormatInvalid);
                    if (aaLinearize && sf != MTLPixelFormatInvalid) {
                        id<MTLTexture> v = [src newTextureViewWithPixelFormat:sf];
                        if (v != nil) srcView = v;
                    }
                    MTLRenderPassDescriptor *arp = [MTLRenderPassDescriptor renderPassDescriptor];
                    arp.colorAttachments[0].texture = aaTex[eye];
                    arp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
                    arp.colorAttachments[0].storeAction = MTLStoreActionStore;
                    id<MTLRenderCommandEncoder> ae = [cb renderCommandEncoderWithDescriptor:arp];
                    if (ae == nil) continue;
                    [ae setRenderPipelineState:fxaaPipe];
                    [ae setFragmentTexture:srcView atIndex:0];
                    [ae setFragmentSamplerState:sampler atIndex:0];
                    float aaPx[2] = {1.0f / (float)src.width, 1.0f / (float)src.height};
                    [ae setFragmentBytes:aaPx length:sizeof(aaPx) atIndex:4];
                    [ae drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
                    [ae endEncoding];
                    aaSrcHandle[eye] = srcHandle;
                    aaReady[eye] = YES;
                }
            }

            size_t presented = 0;
            size_t encodedViews = 0;
            for (size_t d = 0; d < drawableCount; d++) {
                cp_drawable_t drawable = drawables[d];
                int target = (int)cp_drawable_get_target(drawable);
                size_t drawableViews = cp_drawable_get_view_count(drawable);
                int drawableLeftView = 0;
                if (drawableViews >= 2) {
                    simd_float3 p0 = cp_view_get_transform(cp_drawable_get_view(drawable, 0)).columns[3].xyz;
                    simd_float3 p1 = cp_view_get_transform(cp_drawable_get_view(drawable, 1)).columns[3].xyz;
                    drawableLeftView = (p0.x <= p1.x) ? 0 : 1;
                }
                if (anchorOK && !noDeviceAnchor) {
                    // The anchor the shown picture was rendered from (see anchorForPose); the newest
                    // anchor only when no stamped pose is available (no game frame yet, old bridge).
                    ar_device_anchor_t renderAnchor = (haveEyes || usingCachedEyes)
                        ? anchorForPose(lastShownPoseNs) : nil;
                    static uint64_t poseMatched = 0, poseUnmatched = 0;
                    if (renderAnchor != nil) poseMatched++; else if (haveEyes) poseUnmatched++;
                    if (d == 0 && (frameCount % 900) == 0 && (poseMatched + poseUnmatched) > 0) {
                        compLog("pose-matched anchors: matched=%llu unmatched=%llu (unmatched = frame pose "
                                "older than %d display frames or not stamped)",
                                (unsigned long long)poseMatched, (unsigned long long)poseUnmatched,
                                kAnchorRingSize);
                    }
                    cp_drawable_set_device_anchor(drawable, renderAnchor != nil ? renderAnchor : anchor);
                }
                size_t textureCount = cp_drawable_get_texture_count(drawable);
                size_t rateMapCount = cp_drawable_get_rasterization_rate_map_count(drawable);
                for (size_t i = 0; i < drawableViews; i++) {
                    cp_view_t view = cp_drawable_get_view(drawable, i);
                    cp_view_texture_map_t map = cp_view_get_view_texture_map(view);
                    size_t texIndex = cp_view_texture_map_get_texture_index(map);
                    size_t sliceIndex = cp_view_texture_map_get_slice_index(map);
                    MTLViewport viewport = cp_view_texture_map_get_viewport(map);
                    if (texIndex >= textureCount) {
                        static int loggedBadTextureIndex = 0;
                        if (!loggedBadTextureIndex) {
                            loggedBadTextureIndex = 1;
                            compLog("view %d textureIndex=%zu out of range (textureCount=%zu); using view index",
                                    (int)i, texIndex, textureCount);
                        }
                        texIndex = (i < textureCount) ? i : 0;
                        sliceIndex = 0;
                    }
                    id<MTLTexture> colorTexture = cp_drawable_get_color_texture(drawable, texIndex);
                    id<MTLTexture> depthTexture = cp_drawable_get_depth_texture(drawable, texIndex);
                    if (colorTexture == nil) {
                        nilColorViews++;
                        if (!warnedNilColorTexture) {
                            warnedNilColorTexture = YES;
                            compLog("DRAWABLE COLOR TEXTURE IS NIL (drawable=%zu target=%d view=%zu "
                                    "texIndex=%zu textureCount=%zu) - the render pass cannot be encoded, "
                                    "nothing (not even the clear) reaches the drawable",
                                    d, target, i, texIndex, textureCount);
                        }
                        continue;
                    }

                    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
                    rp.colorAttachments[0].texture = colorTexture;
                    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
                    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
                    BOOL isLeftEye = ((int)i == drawableLeftView);
                    if (clearProbe) {
                        rp.colorAttachments[0].clearColor = isLeftEye
                            ? MTLClearColorMake(1.0, 0.0, 1.0, 1.0)
                            : MTLClearColorMake(0.0, 1.0, 1.0, 1.0);
                    } else if (diagnostics) {
                        // Bright per-eye clears prove an invalid pass in diagnostics (red left, green right).
                        rp.colorAttachments[0].clearColor = isLeftEye
                            ? MTLClearColorMake(0.8, 0.05, 0.05, 1.0)
                            : MTLClearColorMake(0.05, 0.7, 0.1, 1.0);
                    } else {
                        rp.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
                    }
                    if (colorTexture.textureType == MTLTextureType2DArray) {
                        rp.colorAttachments[0].slice = sliceIndex;
                    }
                    if (depthTexture != nil) {
                        rp.depthAttachment.texture = depthTexture;
                        rp.depthAttachment.loadAction = MTLLoadActionClear;
                        rp.depthAttachment.storeAction = MTLStoreActionStore;
                        // CompositorServices uses reverse-Z: 0 = infinitely far. The reprojected game
                        // image has no per-pixel depth, so report it at infinity rather than near.
                        // EV-0093: 1.0 (near) is required on D1; 0.0 blacks the presented layer out
                        // (vrmc-depth-zero.flag restores the old behaviour for A/B only).
                        rp.depthAttachment.clearDepth = depthZero ? 0.0 : 1.0;
                        if (depthTexture.textureType == MTLTextureType2DArray) {
                            rp.depthAttachment.slice = sliceIndex;
                        }
                    }
                    // Bound the rate-map index by the drawable's own count: the texture index is not
                    // guaranteed to index the rate-map array, and an out-of-range map on the pass can
                    // blank or distort the render.
                    if (rateMapCount > 0) {
                        size_t rateMapIndex = (texIndex < rateMapCount) ? texIndex : 0;
                        id<MTLRasterizationRateMap> rrm = cp_drawable_get_rasterization_rate_map(drawable, rateMapIndex);
                        if (rrm != nil) rp.rasterizationRateMap = rrm;
                    }

                    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
                    if (enc == nil) {
                        framesWithoutEncoder++;
                        if (!warnedNilEncoder) {
                            warnedNilEncoder = YES;
                            compLog("RENDER ENCODER IS NIL (drawable=%zu target=%d view=%zu color=%lux%lu "
                                    "fmt=%lu type=%lu depth=%p viewport=(%.0f,%.0f,%.0f,%.0f)) - no clear and "
                                    "no draw reaches this drawable",
                                    d, target, i, (unsigned long)colorTexture.width,
                                    (unsigned long)colorTexture.height,
                                    (unsigned long)colorTexture.pixelFormat,
                                    (unsigned long)colorTexture.textureType,
                                    (__bridge void *)depthTexture, viewport.originX, viewport.originY,
                                    viewport.width, viewport.height);
                        }
                        continue;
                    }
                    if (viewport.width > 0 && viewport.height > 0) [enc setViewport:viewport];
                    if (depthState != nil) [enc setDepthStencilState:depthState];
                    if (!clearProbe) {
                        // M8 foveated sharpening: when the provider eye texture is smaller than the
                        // drawable's logical view (the normal case when the game is held below the
                        // display's 4K-class resolution for 120 Hz), the flat bilinear upscale is
                        // sharpened with a fovea-weighted CAS-lite pass instead of plain bilinear.
                        float sharpenStrength = 0.0f;
                        float sharpenTexelW = 0.0f;
                        float sharpenTexelH = 0.0f;
                        if (haveEyes && !testPatternNow && isLeftEye && (frameCount % 300) == 0) {
                            const int gateIndex = (leftView == 1) ? 1 : 0;
                            compLog("sharpen gate: useFlat=%d test=%d enabled=%d auto=%d pipe=%d haveEyes=%d "
                                    "eye=%ux%u ref=%ux%u viewport=%.0fx%.0f mode=%s",
                                    (int)useFlat, (int)testPatternNow, (int)sharpenControl.enabled,
                                    (int)sharpenControl.autoMode, (int)(pipes.flatSharp != nil),
                                    (int)haveEyes, drawLeftWidth, drawLeftHeight,
                                    gFrameLogicalW[gateIndex], gFrameLogicalH[gateIndex],
                                    viewport.width, viewport.height,
                                    sharpenControl.autoMode ? "auto" : "fixed");
                        }
                        if (useFlat && !testPatternNow && pipes.flatSharp != nil &&
                            (haveEyes || usingCachedEyes)) {
                            const uint32_t aaW = isLeftEye ? drawLeftWidth : drawRightWidth;
                            const uint32_t aaH = isLeftEye ? drawLeftHeight : drawRightHeight;
                            if (aaW > 0 && aaH > 0) {
                                sharpenTexelW = (float)(1.0 / (double)aaW);
                                sharpenTexelH = (float)(1.0 / (double)aaH);
                            }
                        }
                        if (useFlat && !testPatternNow && sharpenControl.enabled &&
                            pipes.flatSharp != nil && haveEyes && eyesPtr != NULL) {
                            const uint32_t eyeW = isLeftEye ? drawLeftWidth : drawRightWidth;
                            const uint32_t eyeH = isLeftEye ? drawLeftHeight : drawRightHeight;
                            // The sharpening decision must use the LOGICAL per-eye size, not the
                            // foveated drawable extent: with rate maps the physical drawable is much
                            // smaller than the logical view (device: 2432x2368 vs 6261x5023), so
                            // viewport/eye would never exceed 1.02 and the pass stayed off exactly
                            // when the provider renders below display resolution (the blur case).
                            // The system upscales the foveated drawable to the panel, and the fovea
                            // maps logical pixels 1:1, so provider-eye -> logical is the visible
                            // upscale to compensate.
                            const int logicalIndex = (leftView == 1) ? 1 : 0;
                            const uint32_t logicalRefW = gFrameLogicalW[logicalIndex];
                            const uint32_t logicalRefH = gFrameLogicalH[logicalIndex];
                            const uint32_t refWFinal = logicalRefW > 0 ? logicalRefW : (uint32_t)viewport.width;
                            const uint32_t refHFinal = logicalRefH > 0 ? logicalRefH : (uint32_t)viewport.height;
                            if (eyeW > 0 && eyeH > 0 && refWFinal > 0 && refHFinal > 0) {
                                const double upscale = MAX(refWFinal / (double)eyeW,
                                                           refHFinal / (double)eyeH);
                                if (upscale > 1.02) {
                                    sharpenStrength = sharpenControl.autoMode
                                        ? (float)MIN(0.45, (upscale - 1.0) * 0.35)
                                        : MIN(1.0f, sharpenControl.strength);
                                    sharpenTexelW = (float)(1.0 / (double)eyeW);
                                    sharpenTexelH = (float)(1.0 / (double)eyeH);
                                    if (!loggedSharpen ||
                                        fabsf(sharpenStrength - lastLoggedSharpenStrength) > 0.02f) {
                                        loggedSharpen = YES;
                                        lastLoggedSharpenStrength = sharpenStrength;
                                        compLog("foveated sharpening: %s strength=%.2f provider=%ux%u "
                                                "logicalRef=%ux%u drawableViewport=%.0fx%.0f upscale=%.2f "
                                                "vignette=%.2f (fovea-weighted CAS-lite; "
                                                "Documents/vrmc-sharpening.txt=%s)",
                                                sharpenControl.autoMode ? "auto" : "fixed",
                                                (double)sharpenStrength, eyeW, eyeH, refWFinal, refHFinal,
                                                viewport.width, viewport.height, upscale,
                                                (double)vignetteStrength,
                                                sharpenControl.autoMode ? "auto" : "fixed");
                                    }
                                }
                            }
                        }
                        id<MTLRenderPipelineState> chosen = nil;
                        if (testPatternNow) chosen = pipes.test;
                        else if (useFlat) {
                            if (sharpenStrength > 0.001f ||
                                (aaEnabled && sharpenTexelW > 0.0f && sharpenTexelH > 0.0f)) {
                                chosen = pipes.flatSharp;
                            }
                            else chosen = (vignetteStrength > 0.0f && pipes.flatVignette != nil)
                                ? pipes.flatVignette : pipes.flat;
                        } else chosen = pipes.reproj;
                        currentSharpenStrength = (chosen == pipes.flatSharp) ? sharpenStrength : 0.0f;
                        if (chosen != nil) {
                            [enc setRenderPipelineState:chosen];
                            if (!testPatternNow) {
                                uint64_t handle = isLeftEye ? drawLeftHandle : drawRightHandle;
                                // Reuse the opaque MTLTexture pointer exported by the provider (same GPU/process).
                                id<MTLTexture> tex = (__bridge id<MTLTexture>)(void *)(uintptr_t)handle;
                                // Hardware sRGB decode: the provider texture values are sRGB-encoded, the drawable
                                // is linear float. Bind an sRGB view (cached per handle) so the immersive image gets
                                // the same gamma handling as the window path; Documents/vrmc-linearize-color.txt=off A/Bs it.
                                static BOOL linearizeColorEnabled = YES;
                                static BOOL linearizeColorInit = NO;
                                if (!linearizeColorInit) {
                                    linearizeColorInit = YES;
                                    NSString *linearizeText = readDocumentText(@"vrmc-linearize-color.txt");
                                    if (linearizeText.length > 0 &&
                                        ([linearizeText caseInsensitiveCompare:@"off"] == NSOrderedSame ||
                                         linearizeText.floatValue == 0.0f)) {
                                        linearizeColorEnabled = NO;
                                    }
                                    compLog("color: sRGB->linear %s (%s; Documents/vrmc-linearize-color.txt=%s)",
                                            linearizeColorEnabled ? "ON" : "OFF",
                                            linearizeColorEnabled ? "hardware sRGB texture view, immersive matches window"
                                                                  : "raw linear passthrough (A/B)",
                                            linearizeText.length > 0 ? linearizeText.UTF8String : "default");
                                }
                                MTLPixelFormat srgbViewFormat = MTLPixelFormatInvalid;
                                if (tex.pixelFormat == MTLPixelFormatRGBA8Unorm) {
                                    srgbViewFormat = MTLPixelFormatRGBA8Unorm_sRGB;
                                } else if (tex.pixelFormat == MTLPixelFormatBGRA8Unorm) {
                                    srgbViewFormat = MTLPixelFormatBGRA8Unorm_sRGB;
                                }
                                // Per-eye generation: with one shared counter the left eye's refresh marked
                                // the generation as current, so the right eye kept a stale view of the old
                                // texture whenever a rebuilt texture reused the same address.
                                static uint32_t gSrgbColorGenerationL = 0;
                                static uint32_t gSrgbColorGenerationR = 0;
                                uint32_t *generationCache = isLeftEye ? &gSrgbColorGenerationL : &gSrgbColorGenerationR;
                                const uint32_t viewGeneration = haveEyes ? eyeFrame.texture_generation : *generationCache;
                                if (linearizeColorEnabled && srgbViewFormat != MTLPixelFormatInvalid) {
                                    __strong id<MTLTexture> *viewCache = isLeftEye ? &gSrgbColorViewL : &gSrgbColorViewR;
                                    uint64_t *handleCache = isLeftEye ? &gSrgbColorHandleL : &gSrgbColorHandleR;
                                    // A cached view is only valid for the exact texture it was created from:
                                    // same provider handle, same pixel format, same extent. The bridge
                                    // generation cannot be relied on for this - vrmc_shared_clear_eye_textures()
                                    // resets texture_generation to 0 and the next publish makes it 1 again,
                                    // so it usually looks unchanged across an eye-target rebuild. Requiring
                                    // format+extent as well as the handle means a stale view can never be
                                    // sampled even if a provider texture address were reused.
                                    const BOOL cachedViewStale =
                                        (*viewCache != nil) &&
                                        (*handleCache != handle ||
                                         (*viewCache).pixelFormat != srgbViewFormat ||
                                         (*viewCache).width != tex.width ||
                                         (*viewCache).height != tex.height);
                                    if (*handleCache != handle || *viewCache == nil ||
                                        *generationCache != viewGeneration || cachedViewStale) {
                                        id<MTLTexture> srgbView = [tex newTextureViewWithPixelFormat:srgbViewFormat];
                                        if (srgbView != nil) {
                                            static int loggedSrgbView = 0;
                                            static int loggedSrgbRebuilds = 0;
                                            const uint64_t previousHandle = *handleCache;
                                            const BOOL previousViewWasOtherTexture =
                                                (previousHandle != handle && *viewCache != nil);
                                            *viewCache = srgbView;
                                            *handleCache = handle;
                                            *generationCache = viewGeneration;
                                            if (!loggedSrgbView) {
                                                loggedSrgbView = 1;
                                                compLog("color: sRGB->linear applied via texture view (provider fmt=%lu -> view fmt=%lu %lux%lu)",
                                                        (unsigned long)tex.pixelFormat, (unsigned long)srgbView.pixelFormat,
                                                        (unsigned long)srgbView.width, (unsigned long)srgbView.height);
                                            }
                                            // Per-swap line (bounded to 64): a device log can now prove which
                                            // texture/view the compositor sampled after each eye-target
                                            // rebuild, and whether the previous view belonged to a different
                                            // texture. This is the confirmation hook for the "purple flash
                                            // appeared after the colour correction" report.
                                            if (loggedSrgbRebuilds < 64) {
                                                loggedSrgbRebuilds++;
                                                compLog("color: sRGB view rebuilt %s handle=0x%llx fmt=%lu %lux%lu gen=%u previousHandle=0x%llx previousViewOtherTexture=%d",
                                                        isLeftEye ? "L" : "R",
                                                        (unsigned long long)handle,
                                                        (unsigned long)tex.pixelFormat,
                                                        (unsigned long)srgbView.width, (unsigned long)srgbView.height,
                                                        viewGeneration, (unsigned long long)previousHandle,
                                                        (int)previousViewWasOtherTexture);
                                            }
                                        } else {
                                            static int loggedSrgbViewFailure = 0;
                                            if (!loggedSrgbViewFailure) {
                                                loggedSrgbViewFailure = 1;
                                                compLog("color: sRGB view creation FAILED (handle=0x%llx fmt=%lu); sampling the raw provider texture (no gamma decode)",
                                                        (unsigned long long)handle, (unsigned long)tex.pixelFormat);
                                            }
                                        }
                                    }
                                    // Never sample a cached view that belongs to another texture.
                                    if (*viewCache != nil && *handleCache == handle) tex = *viewCache;
                                }
                                if (tex != nil && tex.device != device) {
                                    static int loggedDeviceMismatch = 0;
                                    if (!loggedDeviceMismatch) {
                                        loggedDeviceMismatch = 1;
                                        compLog("eye texture device mismatch (%p vs compositor %p); skipping sampling",
                                                (__bridge void *)tex.device, (__bridge void *)device);
                                    }
                                    tex = nil;
                                }
                                const int aaEye = isLeftEye ? 0 : 1;
                                const BOOL aaApplied = tex != nil && chosen == pipes.flatSharp &&
                                    aaReady[aaEye] && aaTex[aaEye] != nil && aaSrcHandle[aaEye] == handle;
                                if (aaApplied) tex = aaTex[aaEye]; // already linear (decoded in the pre-pass)
                                if (tex != nil) {
                                    [enc setFragmentTexture:tex atIndex:0];
                                    [enc setFragmentSamplerState:sampler atIndex:0];
                                    if (chosen == pipes.flatVignette) {
                                        // fmain_flat_vignette reads buffer(1); it was never bound, so the
                                        // vignette path sampled an unbound buffer whenever sharpening was off.
                                        float vig = vignetteStrength;
                                        [enc setFragmentBytes:&vig length:sizeof(vig) atIndex:1];
                                    }
                                    if (chosen == pipes.flatSharp) {
                                        // Fovea-weighted CAS-lite parameters (buffer 3 matches the
                                        // FlatFx struct in kShaderSource).
                                        VRMCFlatFx fx;
                                        fx.strength = sharpenStrength;
                                        fx.vignette = vignetteStrength;
                                        fx.texelW = sharpenTexelW;
                                        fx.texelH = sharpenTexelH;
                                        fx.aa = aaApplied ? 1.0f : 0.0f;
                                        [enc setFragmentBytes:&fx length:sizeof(fx) atIndex:3];
                                    }
                                    if (!useFlat) {
                                        VRMCViewParams params;
                                        params.invProjection = simd_inverse(
                                            cp_drawable_compute_projection(drawable,
                                                cp_axis_direction_convention_right_up_back, i));
                                        params.viewToDevice = cp_view_get_transform(view);
                                        params.sourceTangents =
                                            sourceTangentsFromFov(isLeftEye ? eyesPtr->left_fov : eyesPtr->right_fov);
                                        params.misc = simd_make_float4(debugShading ? 1.0f : 0.0f, 0, 0, 0);
                                        [enc setFragmentBytes:&params length:sizeof(params) atIndex:0];
                                    }
                                    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
                                }
                            } else {
                                // Test pattern: eye index + viewport size for the stereo/alignment markers.
                                float viewInfo[4] = { isLeftEye ? 0.0f : 1.0f,
                                                      (float)viewport.width, (float)viewport.height, 0.0f };
                                [enc setFragmentBytes:viewInfo length:sizeof(viewInfo) atIndex:2];
                                [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
                            }
                        }
                        // H1 (audit): the manual Enter-VR path has no provider eyes and shows the test
                        // pattern; draw the proof border then too, so the runbook's expected border is real.
                        if ((presentProof || selfTest || (!haveEyes && testPatternNow)) && pipes.proof != nil) {
                            [enc setRenderPipelineState:pipes.proof];
                            float viewportSize[2] = { (float)viewport.width, (float)viewport.height };
                            [enc setFragmentBytes:viewportSize length:sizeof(viewportSize) atIndex:2];
                            [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
                        }
                    }
                    [enc endEncoding];
                    encodedViews++;

                    // Ground truth of what is being presented: read back the DRAWN drawable texture.
                    // In diagnostics, also probe the first 3 drawn frames after an eye-texture swap:
                    // that is exactly where a texture-view/format switch would flash (the 2026-11-07 M8
                    // purple menu/pause flash was reported after the sRGB texture-view colour fix).
                    // Release is unchanged: diagnostics is false, so the periodic cadence still governs.
                    const BOOL afterEyeTextureSwap = (eyeTextureChangeFrame > 0) &&
                        frameCount >= eyeTextureChangeFrame &&
                        (frameCount - eyeTextureChangeFrame) <= 2;
                    BOOL shouldProbe = diagnostics && !clearProbe &&
                                       (frameCount < 3 || (frameCount % 300) == 0 ||
                                        afterEyeTextureSwap);
                    if (shouldProbe && target == (int)cp_drawable_target_built_in) {
                        BOOL dumpRaw = dumpRawAlways || selfTest || (frameCount < 3);
                        NSUInteger probeSlice = (colorTexture.textureType == MTLTextureType2DArray)
                            ? sliceIndex : 0;
                        BOOL probed = encodeDrawableProbe(cb, colorTexture, viewport, probeSlice,
                                                          isLeftEye ? "L" : "R", frameCount, dumpRaw,
                                                          generation);
                        if (!probed && !warnedUnsupportedReadback) {
                            warnedUnsupportedReadback = YES;
                            compLog("drawable proof skipped: color fmt=%lu type=%lu viewport=(%.0f,%.0f) "
                                    "unsupported (only RGBA16Float and 8-bit RGBA/BGRA are decoded)",
                                    (unsigned long)colorTexture.pixelFormat,
                                    (unsigned long)colorTexture.textureType,
                                    viewport.width, viewport.height);
                        }
                    }
                }
                encodeGazeTrackingAreas(&gaze, drawable, cb);
                cp_drawable_encode_present(drawable, cb);
                presented++;
            }
            // Asynchronous command-buffer health check: a failing present path (invalid render pass,
            // bad attachment format, ...) shows up here instead of only as a black screen on device.
            {
                static int loggedFirstSuccess = 0;
                int capturedFrame = frameCount;
                [cb addCompletedHandler:^(id<MTLCommandBuffer> completed) {
                    if (completed.status != MTLCommandBufferStatusCompleted) {
                        compLog("frame %d command buffer FAILED status=%ld error=%s",
                                capturedFrame, (long)completed.status,
                                completed.error ? completed.error.description.UTF8String : "none");
                    } else if (loggedFirstSuccess == 0) {
                        loggedFirstSuccess = 1;
                        compLog("frame %d command buffer completed (first)", capturedFrame);
                    }
                }];
            }
            [cb commit];
            if (presentWait) {
                // Replicates the EV-0074 probe, which waited for GPU completion before ending the
                // submission. Off by default (blocks the shared GPU while Minecraft renders).
                [cb waitUntilCompleted];
                static int loggedWait = 0;
                if (!loggedWait) {
                    loggedWait = 1;
                    compLog("present-wait: waited for command buffer completion status=%ld error=%s",
                            (long)cb.status,
                            cb.error ? cb.error.description.UTF8String : "none");
                }
            }
            if (presented > 0) {
                cp_frame_end_submission(frame);
                presentedFrameCount++;
                if (!postedRunning) {
                    postedRunning = YES;
                    compLog("first presented frame: drawables=%zu presented=%zu views=%zu frame=%d "
                            "generation=%d -> posting VRMCCompositorRunning",
                            drawableCount, presented, encodedViews, frameCount,
                            generation);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"VRMCCompositorRunning"
                                                                            object:nil
                                                                          userInfo:@{@"generation": @(generation)}];
                    });
                }
            } else {
                compLog("frame %d: NO DRAWABLE PRESENTED (drawableCount=%zu); abandoning the submission "
                        "(cp_frame_end_submission without a presented drawable is a client bug)",
                        frameCount, drawableCount);
            }
            frameCount++;
            writeCompositorHeartbeat(generation, frameCount, presented, drawableCount, (long)cp_layer_renderer_get_state(lr));
            if (frameCount == 1 || frameCount % 120 == 0) {
                char targets[32] = "";
                size_t targetsUsed = 0;
                for (size_t d = 0; d < drawableCount && targetsUsed + 4 < sizeof(targets); d++) {
                    int target = (int)cp_drawable_get_target(drawables[d]);
                    const char *tag = (target == (int)cp_drawable_target_built_in) ? "b" : "c";
                    if (d > 0) targets[targetsUsed++] = ',';
                    targets[targetsUsed++] = tag[0];
                }
                targets[targetsUsed] = 0;
                compLog("frame %d eyes=%d anchor=%d anchorFails=%d leftView=%d ipd=%.4f mode=%s "
                        "arrayCount=%zu targets=[%s] presented=%zu encNil=%d nilColor=%d layerState=%d "
                        "head=(%.2f,%.2f,%.2f) p0=0x%llx p1=0x%llx",
                        frameCount, (int)haveEyes, (int)anchorOK, anchorFails, leftView, ipd,
                        testPatternNow ? "test" : (useFlat ? "flat" : "reproj"),
                        drawableCount, targets, presented, framesWithoutEncoder, nilColorViews,
                        (int)cp_layer_renderer_get_state(lr),
                        anchorTransform.columns[3].x, anchorTransform.columns[3].y, anchorTransform.columns[3].z,
                        (unsigned long long)eyesPtr->left_texture, (unsigned long long)eyesPtr->right_texture);
            }
        }
    }
    // M4-W1 release contract: publish one zeroed snapshot (valid_mask = 0) BEFORE ar_session_stop so
    // the provider sees tracking loss and releases every held action. Without this, closing the
    // immersive space mid-press could leave an attack/teleport latched. Runs on every loop exit path
    // (stop requested, layer invalidated, stale generation); presentation cannot be affected.
    if (gInputPublishFn != NULL) {
        vrmc_input_state releaseState;
        memset(&releaseState, 0, sizeof(releaseState));
        releaseState.frame_index = (uint32_t)frameCount;
        releaseState.valid_mask = 0;
        releaseState.timestamp_ns = inputLastTimestampNs;
        const int32_t releaseResult = gInputPublishFn(&releaseState);
        const unsigned long long releaseSeq = (gInputSequenceFn != NULL)
            ? (unsigned long long)gInputSequenceFn()
            : 0ULL;
        inputLog(inputSynthetic, "input release valid_mask=0 frame=%d seq=%llu rc=%d "
                 "(zeroed snapshot before ar_session_stop so any held action is released)",
                 frameCount, releaseSeq, releaseResult);
    }
    ar_session_stop(session);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"VRMCImmersiveEnded"
                                                            object:nil
                                                          userInfo:@{@"generation": @(generation)}];
    });
    compLog("posted VRMCImmersiveEnded (generation %d); presentedFrames=%d framesWithoutDrawable=%d "
            "framesWithoutEncoder=%d anchorFails=%d",
            generation, presentedFrameCount, framesWithoutDrawable, framesWithoutEncoder, anchorFails);
}

@end

extern "C" void VRMCCompositor_InitAndRun(cp_layer_renderer_t layerRenderer) {
    gGameStoppedPosted.store(0);
    openLog();
    int32_t generation = gGeneration.fetch_add(1) + 1;
    compLog("starting compositor thread (generation %d)", generation);
    VRMCCompositorThread *thread = [[VRMCCompositorThread alloc] init];
    thread.layerRenderer = layerRenderer;
    thread.generation = generation;
    thread.name = @"VRMC Immersive Compositor";
    [thread start];
}
