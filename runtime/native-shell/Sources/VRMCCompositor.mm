// VRMC immersive compositor for the SwiftUI shell (M3-W2/W3/W4).
// CompositorServices loop + Metal per-eye reprojection of the provider's exported eye MTLTextures,
// plus ARKit device tracking pushed into the bridge for the provider (vrmc_shared_*).
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

static FILE *gLog;
static std::mutex gLogMutex;
static void *gBridge;
typedef int32_t (*eye_targets_fn)(vrmc_eye_targets *);
typedef int32_t (*set_tracking_fn)(const vrmc_tracking_state *);
static eye_targets_fn gEyeFn;
static set_tracking_fn gTrackFn;
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
        compLog("bridge resolved handle=%p eye=%p tracking=%p", h, gEyeFn, gTrackFn);
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

    // Diagnostic modes: flag files in Documents/ (see file header). Logged so a device log names them.
    const int reprojMode = readReprojMode();
    const BOOL debugShading = documentFlag(@"vrmc-reproj-debug.flag");
    const BOOL forceTestPattern = documentFlag(@"vrmc-test-pattern.flag");
    static int samplingDisabled = -1;
    if (samplingDisabled < 0) {
        samplingDisabled = documentFlag(@"vrmc-no-sampling.flag") ? 1 : 0;
        compLog("samplingDisabled=%d", samplingDisabled);
    }
    compLog("diagnostics: reprojMode=%d (0=auto 1=forced 2=flat) debugShading=%d samplingDisabled=%d",
            reprojMode, (int)debugShading, samplingDisabled);

    MTLPixelFormat colorFormat = MTLPixelFormatRGBA16Float;
    MTLPixelFormat depthFormat = MTLPixelFormatInvalid;
    if (lr != nullptr) {
        cp_layer_renderer_configuration_t configuration = cp_layer_renderer_get_configuration(lr);
        if (configuration != nullptr) {
            depthFormat = cp_layer_renderer_configuration_get_depth_format(configuration);
        }
        compLog("layer configuration colorFormat=%lu depthFormat=%lu", (unsigned long)colorFormat,
                (unsigned long)depthFormat);
    }

    NSError *err = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:kShaderSource options:nil error:&err];
    id<MTLRenderPipelineState> pipelineReproj = nil;
    id<MTLRenderPipelineState> pipelineFlat = nil;
    id<MTLRenderPipelineState> pipelineTest = nil;
    id<MTLDepthStencilState> depthState = nil;
    if (library != nil) {
        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [library newFunctionWithName:@"vmain"];
        pd.colorAttachments[0].pixelFormat = colorFormat;
        pd.depthAttachmentPixelFormat = depthFormat;

        pd.fragmentFunction = [library newFunctionWithName:@"fmain_reproj"];
        pipelineReproj = [device newRenderPipelineStateWithDescriptor:pd error:&err];
        if (pipelineReproj == nil) compLog("reproj pipeline failed: %s", err.description.UTF8String);

        pd.fragmentFunction = [library newFunctionWithName:@"fmain_flat"];
        pipelineFlat = [device newRenderPipelineStateWithDescriptor:pd error:&err];
        if (pipelineFlat == nil) compLog("flat pipeline failed: %s", err.description.UTF8String);

        pd.fragmentFunction = [library newFunctionWithName:@"fmain_test"];
        pipelineTest = [device newRenderPipelineStateWithDescriptor:pd error:&err];
        if (pipelineTest == nil) compLog("test pipeline failed: %s", err.description.UTF8String);

        MTLDepthStencilDescriptor *dsd = [MTLDepthStencilDescriptor new];
        dsd.depthCompareFunction = MTLCompareFunctionAlways;
        dsd.depthWriteEnabled = NO;
        depthState = [device newDepthStencilStateWithDescriptor:dsd];
        compLog("pipeline ready reproj=%d flat=%d test=%d", pipelineReproj != nil, pipelineFlat != nil,
                pipelineTest != nil);
    } else {
        compLog("shader library failed: %s", err.description.UTF8String);
    }

    id<MTLSamplerState> sampler = nil;
    if (pipelineReproj != nil || pipelineFlat != nil) {
        MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
        sd.minFilter = MTLSamplerMinMagFilterLinear;
        sd.magFilter = MTLSamplerMinMagFilterLinear;
        sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
        sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
        sampler = [device newSamplerStateWithDescriptor:sd];
    }

    int frameCount = 0;
    BOOL loggedViewInfo = NO;
    BOOL useFlat = (reprojMode == VRMCReprojFlat);
    BOOL autoTestPattern = NO;
    BOOL modeLogged = NO;
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
            cp_frame_start_submission(frame);
            cp_drawable_t drawable = cp_frame_query_drawable(frame);
            if (drawable == nullptr) { cp_frame_end_submission(frame); continue; }

            cp_frame_timing_t actual = cp_drawable_get_frame_timing(drawable);
            cp_time_t presentation = cp_frame_timing_get_presentation_time(actual);
            CFTimeInterval queryTime = cp_time_to_cf_time_interval(presentation);
            ar_device_anchor_t anchor = ar_device_anchor_create();
            ar_device_anchor_query_status_t st =
                ar_world_tracking_provider_query_device_anchor_at_timestamp(provider, queryTime, anchor);
            simd_float4x4 anchorTransform = matrix_identity_float4x4;
            if (st == ar_device_anchor_query_status_success) {
                anchorTransform = ar_device_anchor_get_origin_from_anchor_transform(anchor);
                cp_drawable_set_device_anchor(drawable, anchor);
            }

            // Eye selection and IPD come from the views themselves: the left eye is the view whose
            // origin is at negative X relative to the device anchor.
            int views = (int)cp_drawable_get_view_count(drawable);
            int leftView = 0;
            if (views >= 2) {
                simd_float3 p0 = cp_view_get_transform(cp_drawable_get_view(drawable, 0)).columns[3].xyz;
                simd_float3 p1 = cp_view_get_transform(cp_drawable_get_view(drawable, 1)).columns[3].xyz;
                leftView = (p0.x <= p1.x) ? 0 : 1;
                float measured = simd_distance(p0, p1);
                if (measured > 0.04f && measured < 0.09f) ipd = measured;
            }

            if (!loggedViewInfo && views > 0) {
                loggedViewInfo = YES;
                if (views >= 2) {
                    compLog("drawable: colorFormat=%lu views=%d", (unsigned long)colorFormat, views);
                    for (int i = 0; i < views; i++) {
                        cp_view_t view = cp_drawable_get_view(drawable, i);
                        cp_view_texture_map_t map = cp_view_get_view_texture_map(view);
                        MTLViewport viewport = cp_view_texture_map_get_viewport(map);
                        size_t texIndex = cp_view_texture_map_get_texture_index(map);
                        simd_float4x4 vt = cp_view_get_transform(view);
                        simd_float4x4 proj = cp_drawable_compute_projection(
                            drawable, cp_axis_direction_convention_right_up_back, i);
                        simd_float4x4 invProj = simd_inverse(proj);
                        simd_float4 derived = viewTangents(invProj);
                        logMatrix("viewToDevice", vt);
                        logMatrix("projection", proj);
                        compLog("view %d (%s) texIndex=%zu viewport=(%.0f,%.0f,%.0f,%.0f) "
                                "tangents l/r/d/u=(%.3f,%.3f,%.3f,%.3f) pos=(%.4f,%.4f,%.4f) fwd=(%.3f,%.3f,%.3f)",
                                i, i == leftView ? "left" : "right", texIndex,
                                viewport.originX, viewport.originY, viewport.width, viewport.height,
                                derived.x, derived.y, derived.z, derived.w,
                                vt.columns[3].x, vt.columns[3].y, vt.columns[3].z,
                                -vt.columns[2].x, -vt.columns[2].y, -vt.columns[2].z);
                    }
                    vrmc_eye_targets eyesProbe;
                    memset(&eyesProbe, 0, sizeof(eyesProbe));
                    BOOL haveEyesProbe = (gEyeFn != NULL && gEyeFn(&eyesProbe) == 0 &&
                                          eyesProbe.left_texture != 0 && eyesProbe.right_texture != 0);
                    simd_float4 ls = sourceTangentsFromFov(eyesProbe.left_fov);
                    simd_float4 rs = sourceTangentsFromFov(eyesProbe.right_fov);
                    compLog("provider eye tangents L=(%.3f,%.3f,%.3f,%.3f) R=(%.3f,%.3f,%.3f,%.3f) ipd=%.4f haveEyes=%d",
                            ls.x, ls.y, ls.z, ls.w, rs.x, rs.y, rs.z, rs.w, ipd, (int)haveEyesProbe);

                    // CPU-side ray->UV diagnostics: exactly the shader math, so a device log proves
                    // whether the drawable rays land inside the provider frustum (EV-0086 hypothesis).
                    useFlat = (reprojMode == VRMCReprojFlat);
                    for (int i = 0; i < views; i++) {
                        cp_view_t view = cp_drawable_get_view(drawable, i);
                        simd_float4x4 vt = cp_view_get_transform(view);
                        simd_float4x4 proj = cp_drawable_compute_projection(
                            drawable, cp_axis_direction_convention_right_up_back, i);
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
                } else {
                    compLog("drawable has %d view(s); compositor expects 2 (device)", views);
                }
            }

            if (gTrackFn != NULL) {
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

            vrmc_eye_targets eyes;
            memset(&eyes, 0, sizeof(eyes));
            BOOL haveEyes = (gEyeFn != NULL && gEyeFn(&eyes) == 0 &&
                             eyes.left_texture != 0 && eyes.right_texture != 0);

            if (!modeLogged && frameCount > 0) {
                modeLogged = YES;
                compLog("shading mode=%s (%s)%s", useFlat ? "flat" : "reprojection",
                        reprojMode == VRMCReprojFlat ? "forced by flag" :
                        (reprojMode == VRMCReprojForced ? "forced by flag" : "auto"),
                        debugShading ? " debugShading=on" : "");
            }

            if (haveEyes && (frameCount == 1 || frameCount % 300 == 0)) {
                id<MTLTexture> leftTex = (__bridge id<MTLTexture>)(void *)(uintptr_t)eyes.left_texture;
                id<MTLTexture> rightTex = (__bridge id<MTLTexture>)(void *)(uintptr_t)eyes.right_texture;
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

            id<MTLCommandBuffer> cb = [queue commandBuffer];
            size_t textureCount = cp_drawable_get_texture_count(drawable);
            for (int i = 0; i < views; i++) {
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
                                i, texIndex, textureCount);
                    }
                    texIndex = (size_t)i;
                    sliceIndex = 0;
                }

                MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
                id<MTLTexture> colorTexture = cp_drawable_get_color_texture(drawable, texIndex);
                id<MTLTexture> depthTexture = cp_drawable_get_depth_texture(drawable, texIndex);
                rp.colorAttachments[0].texture = colorTexture;
                rp.colorAttachments[0].loadAction = MTLLoadActionClear;
                rp.colorAttachments[0].storeAction = MTLStoreActionStore;
                rp.colorAttachments[0].clearColor = (i == leftView)
                    ? MTLClearColorMake(0.8, 0.05, 0.05, 1.0)
                    : MTLClearColorMake(0.05, 0.7, 0.1, 1.0);
                if (colorTexture.textureType == MTLTextureType2DArray) {
                    rp.colorAttachments[0].slice = sliceIndex;
                }
                rp.depthAttachment.texture = depthTexture;
                rp.depthAttachment.loadAction = MTLLoadActionClear;
                rp.depthAttachment.storeAction = MTLStoreActionStore;
                if (depthTexture.textureType == MTLTextureType2DArray) {
                    rp.depthAttachment.slice = sliceIndex;
                }
                // CompositorServices uses reverse-Z: 0 = infinitely far. The reprojected game image has no
                // per-pixel depth, so report it at infinity rather than at the near plane (1.0).
                rp.depthAttachment.clearDepth = 0.0;
                id<MTLRasterizationRateMap> rrm = cp_drawable_get_rasterization_rate_map(drawable, texIndex);
                if (rrm) rp.rasterizationRateMap = rrm;

                id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
                if (enc != nil) {
                    if (viewport.width > 0 && viewport.height > 0) [enc setViewport:viewport];
                    if (depthState != nil) [enc setDepthStencilState:depthState];
                    BOOL testPattern = (!haveEyes || samplingDisabled || forceTestPattern || autoTestPattern);
                    id<MTLRenderPipelineState> chosen = nil;
                    if (testPattern) chosen = pipelineTest;
                    else if (useFlat) chosen = pipelineFlat;
                    else chosen = pipelineReproj;
                    if (chosen != nil && sampler != nil) {
                        [enc setRenderPipelineState:chosen];
                        if (!testPattern) {
                            BOOL isLeft = (i == leftView);
                            uint64_t handle = isLeft ? eyes.left_texture : eyes.right_texture;
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
                                        sourceTangentsFromFov(isLeft ? eyes.left_fov : eyes.right_fov);
                                    params.misc = simd_make_float4(debugShading ? 1.0f : 0.0f, 0, 0, 0);
                                    [enc setFragmentBytes:&params length:sizeof(params) atIndex:0];
                                }
                                [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
                            }
                        } else {
                            [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
                        }
                    }
                    [enc endEncoding];
                }
            }
            cp_drawable_encode_present(drawable, cb);
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
                    } else if (!loggedFirstSuccess) {
                        loggedFirstSuccess = 1;
                        compLog("frame %d command buffer completed (first)", capturedFrame);
                    }
                }];
            }
            [cb commit];
            // Do not block the compositor on GPU completion (the sample doesn't); blocking here can
            // stall the shared GPU while Minecraft is rendering.
            if ([self stopRequested] || cp_layer_renderer_get_state(lr) != cp_layer_renderer_state_running) {
                compLog("stop/invalidation before endSubmission; exiting without endSubmission");
                break;
            }
            cp_frame_end_submission(frame);

            frameCount++;
            if (frameCount == 1 || frameCount % 120 == 0) {
                compLog("frame %d eyes=%d anchor=%d leftView=%d ipd=%.4f mode=%s head=(%.2f,%.2f,%.2f) p0=0x%llx p1=0x%llx",
                        frameCount, (int)haveEyes, (int)(st == ar_device_anchor_query_status_success),
                        leftView, ipd, useFlat ? "flat" : "reproj",
                        anchorTransform.columns[3].x, anchorTransform.columns[3].y, anchorTransform.columns[3].z,
                        (unsigned long long)eyes.left_texture, (unsigned long long)eyes.right_texture);
            }
        }
    }
    ar_session_stop(session);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"VRMCImmersiveEnded"
                                                            object:nil
                                                          userInfo:@{@"generation": @(generation)}];
    });
    compLog("posted VRMCImmersiveEnded (generation %d)", generation);
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
