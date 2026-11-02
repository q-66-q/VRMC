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
static eye_targets_fn gEyeFn;
static acquire_eyes_fn gAcquireFn;
static set_tracking_fn gTrackFn;
static set_display_views_fn gDisplayViewsFn;
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
    NSString *path = [paths.firstObject stringByAppendingPathComponent:@"vrmc-compositor.log"];
    gLog = fopen(path.UTF8String, "a");
}

static void resolveBridge(void) {
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
        compLog("bridge resolved handle=%p eye=%p tracking=%p displayViews=%p acquireEyes=%p", h,
                gEyeFn, gTrackFn, gDisplayViewsFn, gAcquireFn);
    }
}

static BOOL documentFlag(NSString *name) {
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [docs.firstObject stringByAppendingPathComponent:name];
    return [[NSFileManager defaultManager] fileExistsAtPath:path] ? YES : NO;
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
static NSString *const kShaderSource =
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
     "  if (in.ndc.y > 0.985) return float4(float3(0.1,0.8,0.1), 1.0);\n"
     "  float2 uv = float2((in.ndc.x + 1.0) * 0.5, (1.0 - in.ndc.y) * 0.5);\n"
     "  return float4(tex.sample(s, uv).rgb, 1.0);\n"
     "}\n"
     "fragment float4 fmain_reproj(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],\n"
     "                             sampler s [[sampler(0)]], constant ViewParams &vp [[buffer(0)]]) {\n"
     "  if (in.ndc.y > 0.985) return float4(float3(0.9,0.1,0.1), 1.0);\n"
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
     "fragment float4 fmain_test(VOut in [[stage_in]]) {\n"
     "  float2 uv = in.ndc * 0.5 + 0.5;\n"
     "  float3 col = float3(uv.x, uv.y, 0.35) + float3(0.05);\n"
     "  float2 g = fract(uv * 10.0);\n"
     "  if (g.x < 0.02 || g.y < 0.02) col = float3(1.0, 1.0, 0.4);\n"
     "  if (abs(uv.x - 0.5) < 0.003 || abs(uv.y - 0.5) < 0.003) col = float3(1.0, 0.2, 0.2);\n"
     "  if (in.ndc.y > 0.985) return float4(float3(0.1,0.3,1.0), 1.0);\n"
     "  return float4(col, 1.0);\n"
     "}\n"
     // Present-proof overlay (vrmc-present-proof.flag / vrmc-immersive-selftest.flag): an 8 px
     // white/cyan checker border plus a magenta centre cross. Drawn after the main draw, interior
     // fragments discarded, so it cannot change what the sampled path shows.
     "fragment float4 fmain_proof(VOut in [[stage_in]], constant float2 &vpSize [[buffer(2)]]) {\n"
     "  float2 px = (in.ndc * 0.5 + 0.5) * vpSize;\n"
     "  bool inBorder = (px.x < 8.0) || (px.y < 8.0) || (px.x > vpSize.x - 8.0) || (px.y > vpSize.y - 8.0);\n"
     "  bool inCross = (fabs(px.x - vpSize.x * 0.5) < 3.0) || (fabs(px.y - vpSize.y * 0.5) < 3.0);\n"
     "  if (!inBorder && !inCross) discard_fragment();\n"
     "  if (inCross) return float4(1.0, 0.0, 1.0, 1.0);\n"
     "  float checker = fmod(floor(px.x / 8.0) + floor(px.y / 8.0), 2.0);\n"
     "  return checker > 0.5 ? float4(1.0, 1.0, 1.0, 1.0) : float4(0.0, 1.0, 1.0, 1.0);\n"
     "}\n";

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

typedef struct {
    id<MTLRenderPipelineState> reproj;
    id<MTLRenderPipelineState> flat;
    id<MTLRenderPipelineState> test;
    id<MTLRenderPipelineState> proof;
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
    out->valid = NO;
    out->colorFormat = colorFormat;
    out->depthFormat = depthFormat;
    NSError *err = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:kShaderSource options:nil error:&err];
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
    out->valid = (out->reproj != nil || out->flat != nil || out->test != nil);
    compLog("pipelines color=%lu depth=%lu reproj=%d flat=%d test=%d proof=%d",
            (unsigned long)colorFormat, (unsigned long)depthFormat,
            out->reproj != nil, out->flat != nil, out->test != nil, out->proof != nil);
    return out->valid;
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

    ar_world_tracking_configuration_t cfg = ar_world_tracking_configuration_create();
    ar_world_tracking_provider_t provider = ar_world_tracking_provider_create(cfg);
    ar_data_providers_t providers = ar_data_providers_create_with_data_providers(provider, nil);
    ar_session_t session = ar_session_create();
    ar_session_run(session, providers);
    compLog("ARKit session started (generation %d)", generation);

    cp_layer_renderer_wait_until_running(lr);
    id<MTLDevice> device = cp_layer_renderer_get_device(lr);
    id<MTLCommandQueue> queue = [device newCommandQueue];
    compLog("wait_until_running returned (generation %d) device=%s", generation,
            device.name.UTF8String);

    // Diagnostic modes: flag files in Documents/ (see file header). Logged so a device log names them.
    const int reprojMode = readReprojMode();
    const BOOL debugShading = documentFlag(@"vrmc-reproj-debug.flag");
    const BOOL forceTestPattern = documentFlag(@"vrmc-test-pattern.flag");
    const BOOL presentProof = documentFlag(@"vrmc-present-proof.flag");
    const BOOL clearProbe = documentFlag(@"vrmc-clear-probe.flag");
    const BOOL dumpRawAlways = documentFlag(@"vrmc-drawable-dump.flag");
    const BOOL presentWait = documentFlag(@"vrmc-present-wait.flag");
    const BOOL selfTest = documentFlag(@"vrmc-immersive-selftest.flag");
    static int samplingDisabled = -1;
    if (samplingDisabled < 0) {
        samplingDisabled = documentFlag(@"vrmc-no-sampling.flag") ? 1 : 0;
    }
    compLog("diagnostics: reprojMode=%d debugShading=%d samplingDisabled=%d forceTestPattern=%d "
            "presentProof=%d clearProbe=%d dumpRaw=%d presentWait=%d selfTest=%d",
            reprojMode, (int)debugShading, samplingDisabled, (int)forceTestPattern,
            (int)presentProof, (int)clearProbe, (int)dumpRawAlways, (int)presentWait, (int)selfTest);

    // Query the layer's real configuration instead of hardcoding the colour format: the pipeline
    // must match what the drawable actually hands out.
    MTLPixelFormat configuredColor = MTLPixelFormatRGBA16Float;
    MTLPixelFormat configuredDepth = MTLPixelFormatInvalid;
    cp_layer_renderer_configuration_t configuration = cp_layer_renderer_get_configuration(lr);
    if (configuration != nullptr) {
        MTLPixelFormat color = cp_layer_renderer_configuration_get_color_format(configuration);
        if (color != MTLPixelFormatInvalid) configuredColor = color;
        configuredDepth = cp_layer_renderer_configuration_get_depth_format(configuration);
        compLog("layer configuration colorFormat=%lu depthFormat=%lu foveation=%d layout=%d",
                (unsigned long)configuredColor, (unsigned long)configuredDepth,
                (int)cp_layer_renderer_configuration_get_foveation_enabled(configuration),
                (int)cp_layer_renderer_configuration_get_layout(configuration));
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
            cp_drawable_array_t drawableArray = cp_frame_query_drawables(frame);
            if (drawableArray != nullptr) {
                size_t arrayCount = cp_drawable_array_get_count(drawableArray);
                drawableCount = arrayCount < 4 ? arrayCount : 4;
                for (size_t d = 0; d < drawableCount; d++) {
                    drawables[d] = cp_drawable_array_get_drawable(drawableArray, d);
                }
            }
            if (drawableCount == 0) {
                framesWithoutDrawable++;
                if (!warnedNoDrawables) {
                    warnedNoDrawables = YES;
                    compLog("NO-DRAWABLE: frame %d returned 0 drawables; abandoning the frame WITHOUT "
                            "start/endSubmission (CompositorServices aborts on end_submission without a "
                            "presented drawable)", frameCount);
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
            id<MTLTexture> probeColor = views > 0
                ? cp_drawable_get_color_texture(mainDrawable, (size_t)leftView) : nil;
            id<MTLTexture> probeDepth = views > 0
                ? cp_drawable_get_depth_texture(mainDrawable, (size_t)leftView) : nil;
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
            const vrmc_eye_targets *eyesPtr = &eyeFrame.eyes;
            static uint32_t loggedTextureGeneration = 0;
            static int loggedEyeTextureUsage = 0;
            if (haveEyes && eyeFrame.texture_generation != loggedTextureGeneration) {
                id<MTLTexture> generationLeft =
                    (__bridge id<MTLTexture>)(void *)(uintptr_t)eyeFrame.eyes.left_texture;
                id<MTLTexture> generationRight =
                    (__bridge id<MTLTexture>)(void *)(uintptr_t)eyeFrame.eyes.right_texture;
                compLog("provider eye textures changed: generation=%u publish=%llu L=%p R=%p "
                        "(handles are re-acquired every frame, never cached)",
                        eyeFrame.texture_generation, (unsigned long long)eyeFrame.publish_sequence,
                        (__bridge void *)generationLeft, (__bridge void *)generationRight);
                loggedTextureGeneration = eyeFrame.texture_generation;
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
                scheduleProviderTextureStats(queue, leftTex, "L", frameCount);
                scheduleProviderTextureStats(queue, rightTex, "R", frameCount);
            }
            // If the provider image is measurably black, show the test pattern instead of sampling so a
            // black screen is never ambiguous: pattern visible => presentation alive, provider image black.
            if (haveEyes && !autoTestPattern &&
                gTexBlackStreakL.load() >= 2 && gTexBlackStreakR.load() >= 2) {
                autoTestPattern = YES;
                compLog("AUTO TEST-PATTERN: provider eye textures measured black twice in a row "
                        "(luma L=%.2f R=%.2f); drawing the procedural pattern instead of sampling",
                        (double)gTexMeanL.load(), (double)gTexMeanR.load());
            }

            BOOL testPatternNow = (!haveEyes || samplingDisabled || forceTestPattern ||
                                   autoTestPattern || selfTest);
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
                if (anchorOK) {
                    cp_drawable_set_device_anchor(drawable, anchor);
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
                    } else {
                        rp.colorAttachments[0].clearColor = isLeftEye
                            ? MTLClearColorMake(0.8, 0.05, 0.05, 1.0)
                            : MTLClearColorMake(0.05, 0.7, 0.1, 1.0);
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
                        rp.depthAttachment.clearDepth = 0.0;
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
                        id<MTLRenderPipelineState> chosen = nil;
                        if (testPatternNow) chosen = pipes.test;
                        else if (useFlat) chosen = pipes.flat;
                        else chosen = pipes.reproj;
                        if (chosen != nil) {
                            [enc setRenderPipelineState:chosen];
                            if (!testPatternNow) {
                                uint64_t handle = isLeftEye ? eyesPtr->left_texture : eyesPtr->right_texture;
                                // Reuse the opaque MTLTexture pointer exported by the provider (same GPU/process).
                                id<MTLTexture> tex = (__bridge id<MTLTexture>)(void *)(uintptr_t)handle;
                                if (tex != nil && tex.device != device) {
                                    static int loggedDeviceMismatch = 0;
                                    if (!loggedDeviceMismatch) {
                                        loggedDeviceMismatch = 1;
                                        compLog("eye texture device mismatch (%p vs compositor %p); skipping sampling",
                                                (__bridge void *)tex.device, (__bridge void *)device);
                                    }
                                    tex = nil;
                                }
                                if (tex != nil) {
                                    [enc setFragmentTexture:tex atIndex:0];
                                    [enc setFragmentSamplerState:sampler atIndex:0];
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
                                [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
                            }
                        }
                        if ((presentProof || selfTest) && pipes.proof != nil) {
                            [enc setRenderPipelineState:pipes.proof];
                            float viewportSize[2] = { (float)viewport.width, (float)viewport.height };
                            [enc setFragmentBytes:viewportSize length:sizeof(viewportSize) atIndex:2];
                            [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
                        }
                    }
                    [enc endEncoding];
                    encodedViews++;

                    // Ground truth of what is being presented: read back the DRAWN drawable texture.
                    BOOL shouldProbe = !clearProbe && (frameCount < 3 || (frameCount % 300) == 0);
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
    openLog();
    int32_t generation = gGeneration.fetch_add(1) + 1;
    compLog("starting compositor thread (generation %d)", generation);
    VRMCCompositorThread *thread = [[VRMCCompositorThread alloc] init];
    thread.layerRenderer = layerRenderer;
    thread.generation = generation;
    thread.name = @"VRMC Immersive Compositor";
    [thread start];
}
