// VRMC immersive compositor for the SwiftUI shell (M3-W2/W3/W4).
// CompositorServices loop + Metal per-eye reprojection of the provider's exported eye MTLTextures,
// plus ARKit device tracking pushed into the bridge for the provider (vrmc_shared_*).
#include "Bridging.h"
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <ARKit/ARKit.h>
#include <atomic>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>

static FILE *gLog;
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
    NSLog(@"[vrmc-comp] %s", line);
    if (gLog) { fprintf(gLog, "[vrmc-comp] %s\n", line); fflush(gLog); }
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

// Per-view reprojection parameters (must match `ViewParams` in kShaderSource).
typedef struct {
    simd_float4x4 invProjection; // drawable view NDC -> view space (cp_drawable_compute_projection, right_up_back)
    simd_float4x4 viewToDevice;  // cp_view_get_transform: eye relative to the device anchor
    simd_float4 sourceTangents;  // provider eye frustum: left, right, down, up (signed tangents, -Z forward)
} VRMCViewParams;

// The provider renders each eye with its own frustum relative to the head (device anchor) orientation.
// CompositorServices views have their own asymmetric frustum and may be rotated relative to the device,
// so stretching the eye image over the drawable puts the provider's "straight ahead" at the drawable
// centre, which on Vision Pro lies temporally of the optical axis -> both eyes diverge (exotropia).
// Instead, every drawable pixel is turned into a device-space ray and looked up in the provider's frustum.
static NSString *const kShaderSource =
    @"#include <metal_stdlib>\n"
     "using namespace metal;\n"
     "struct ViewParams { float4x4 invProjection; float4x4 viewToDevice; float4 sourceTangents; };\n"
     "struct VOut { float4 pos [[position]]; float2 ndc; };\n"
     "vertex VOut vmain(uint vid [[vertex_id]]) {\n"
     "  float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };\n"
     "  VOut o; o.pos = float4(p[vid], 0, 1); o.ndc = p[vid]; return o;\n"
     "}\n"
     "fragment float4 fmain(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],\n"
     "                      sampler s [[sampler(0)]], constant ViewParams &vp [[buffer(0)]]) {\n"
     "  float4 v = vp.invProjection * float4(in.ndc, 0.5, 1);\n"
     "  float3 d = (vp.viewToDevice * float4(v.xyz / v.w, 0)).xyz;\n"
     "  if (d.z > -1e-4) return float4(0, 0, 0, 1);\n"
     "  float2 t = d.xy / -d.z;\n"
     "  float4 st = vp.sourceTangents;\n"
     "  float2 uv = float2((t.x - st.x) / (st.y - st.x), (st.w - t.y) / (st.w - st.z));\n"
     "  if (any(uv < 0.0) || any(uv > 1.0)) return float4(0, 0, 0, 1);\n"
     "  return tex.sample(s, uv);\n"
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

    NSError *err = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:kShaderSource options:nil error:&err];
    id<MTLRenderPipelineState> pipeline = nil;
    if (library != nil) {
        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [library newFunctionWithName:@"vmain"];
        pd.fragmentFunction = [library newFunctionWithName:@"fmain"];
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
        pd.depthAttachmentPixelFormat = cp_layer_renderer_configuration_get_depth_format(
            cp_layer_renderer_get_configuration(lr));
        pipeline = [device newRenderPipelineStateWithDescriptor:pd error:&err];
        if (pipeline == nil) compLog("pipeline failed: %s", err.description.UTF8String);
    } else {
        compLog("shader library failed: %s", err.description.UTF8String);
    }
    id<MTLSamplerState> sampler = nil;
    if (pipeline != nil) {
        MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
        sd.minFilter = MTLSamplerMinMagFilterLinear;
        sd.magFilter = MTLSamplerMinMagFilterLinear;
        sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
        sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
        sampler = [device newSamplerStateWithDescriptor:sd];
        compLog("pipeline ready");
    }

    int frameCount = 0;
    BOOL loggedViews = NO;
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

            static int samplingDisabled = -1;
            if (samplingDisabled < 0) {
                NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *flag = [docs.firstObject stringByAppendingPathComponent:@"vrmc-no-sampling.flag"];
                samplingDisabled = [[NSFileManager defaultManager] fileExistsAtPath:flag] ? 1 : 0;
                compLog("samplingDisabled=%d", samplingDisabled);
            }
            vrmc_eye_targets eyes;
            memset(&eyes, 0, sizeof(eyes));
            BOOL haveEyes = (gEyeFn != NULL && gEyeFn(&eyes) == 0 &&
                             eyes.left_texture != 0 && eyes.right_texture != 0);

            if (!loggedViews && haveEyes) {
                loggedViews = YES;
                for (int i = 0; i < views; i++) {
                    cp_view_t view = cp_drawable_get_view(drawable, i);
                    simd_float4x4 vt = cp_view_get_transform(view);
                    simd_float4 derived = viewTangents(simd_inverse(
                        cp_drawable_compute_projection(drawable, cp_axis_direction_convention_right_up_back, i)));
                    compLog("view %d (%s) tangents l/r/d/u=(%.3f,%.3f,%.3f,%.3f)"
                            " pos=(%.4f,%.4f,%.4f) fwd=(%.3f,%.3f,%.3f)",
                            i, i == leftView ? "left" : "right", derived.x, derived.y, derived.z, derived.w,
                            vt.columns[3].x, vt.columns[3].y, vt.columns[3].z,
                            -vt.columns[2].x, -vt.columns[2].y, -vt.columns[2].z);
                }
                simd_float4 ls = sourceTangentsFromFov(eyes.left_fov), rs = sourceTangentsFromFov(eyes.right_fov);
                compLog("provider eye tangents L=(%.3f,%.3f,%.3f,%.3f) R=(%.3f,%.3f,%.3f,%.3f) ipd=%.4f",
                        ls.x, ls.y, ls.z, ls.w, rs.x, rs.y, rs.z, rs.w, ipd);
            }

            id<MTLCommandBuffer> cb = [queue commandBuffer];
            for (int i = 0; i < views; i++) {
                MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
                rp.colorAttachments[0].texture = cp_drawable_get_color_texture(drawable, i);
                rp.colorAttachments[0].loadAction = MTLLoadActionClear;
                rp.colorAttachments[0].storeAction = MTLStoreActionStore;
                rp.colorAttachments[0].clearColor = (i == leftView)
                    ? MTLClearColorMake(0.8, 0.05, 0.05, 1.0)
                    : MTLClearColorMake(0.05, 0.7, 0.1, 1.0);
                rp.depthAttachment.texture = cp_drawable_get_depth_texture(drawable, i);
                rp.depthAttachment.loadAction = MTLLoadActionClear;
                rp.depthAttachment.storeAction = MTLStoreActionStore;
                // CompositorServices uses reverse-Z: 0 = infinitely far. The reprojected game image has no
                // per-pixel depth, so report it at infinity rather than at the near plane (1.0).
                rp.depthAttachment.clearDepth = 0.0;
                id<MTLRasterizationRateMap> rrm = cp_drawable_get_rasterization_rate_map(drawable, i);
                if (rrm) rp.rasterizationRateMap = rrm;

                id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
                if (pipeline != nil && haveEyes && i < 2 && !samplingDisabled) {
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
                        VRMCViewParams params;
                        params.invProjection = simd_inverse(
                            cp_drawable_compute_projection(drawable, cp_axis_direction_convention_right_up_back, i));
                        params.viewToDevice = cp_view_get_transform(cp_drawable_get_view(drawable, i));
                        params.sourceTangents = sourceTangentsFromFov(isLeft ? eyes.left_fov : eyes.right_fov);
                        [enc setRenderPipelineState:pipeline];
                        [enc setFragmentTexture:tex atIndex:0];
                        [enc setFragmentSamplerState:sampler atIndex:0];
                        [enc setFragmentBytes:&params length:sizeof(params) atIndex:0];
                        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
                    }
                }
                [enc endEncoding];
            }
            cp_drawable_encode_present(drawable, cb);
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
                compLog("frame %d eyes=%d anchor=%d leftView=%d ipd=%.4f head=(%.2f,%.2f,%.2f) p0=0x%llx p1=0x%llx",
                        frameCount, (int)haveEyes, (int)(st == ar_device_anchor_query_status_success),
                        leftView, ipd,
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
