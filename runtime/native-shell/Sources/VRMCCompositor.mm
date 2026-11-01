// VRMC immersive compositor for the SwiftUI shell (M3-W2/W3/W4).
// CompositorServices loop + Metal fullscreen sampling of the provider's exported eye MTLTextures,
// plus ARKit device tracking pushed into the bridge for the provider (vrmc_shared_*).
#include "Bridging.h"
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <ARKit/ARKit.h>
#include <dlfcn.h>
#include <stdio.h>

static FILE *gLog;
static void *gBridge;
typedef int32_t (*eye_targets_fn)(vrmc_eye_targets *);
typedef int32_t (*set_tracking_fn)(const vrmc_tracking_state *);
static eye_targets_fn gEyeFn;
static set_tracking_fn gTrackFn;

static void compLog(const char *fmt, ...) {
    char line[1024];
    va_list args; va_start(args, fmt);
    vsnprintf(line, sizeof(line), fmt, args);
    va_end(args);
    NSLog(@"[vrmc-comp] %s", line);
    if (gLog) { fprintf(gLog, "[vrmc-comp] %s\n", line); fflush(gLog); }
}

static void openLog(void) {
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

static NSString *const kShaderSource =
    @"#include <metal_stdlib>\n"
     "using namespace metal;\n"
     "struct VOut { float4 pos [[position]]; float2 uv; };\n"
     "vertex VOut vmain(uint vid [[vertex_id]]) {\n"
     "  float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };\n"
     "  float2 t[4] = { float2(0,1), float2(1,1), float2(0,0), float2(1,0) };\n"
     "  VOut o; o.pos = float4(p[vid], 0, 1); o.uv = t[vid]; return o;\n"
     "}\n"
     "fragment float4 fmain(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {\n"
     "  constexpr sampler s(filter::linear, address::clamp_to_edge);\n"
     "  return tex.sample(s, in.uv);\n"
     "}\n";

@interface VRMCCompositorThread : NSThread
@property(nonatomic) cp_layer_renderer_t layerRenderer;
@end

@implementation VRMCCompositorThread

- (void)main {
    cp_layer_renderer_t lr = self.layerRenderer;
    resolveBridge();

    ar_world_tracking_configuration_t cfg = ar_world_tracking_configuration_create();
    ar_world_tracking_provider_t provider = ar_world_tracking_provider_create(cfg);
    ar_data_providers_t providers = ar_data_providers_create_with_data_providers(provider, nil);
    ar_session_t session = ar_session_create();
    ar_session_run(session, providers);
    compLog("ARKit session started");

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
        pipeline = [device newRenderPipelineStateWithDescriptor:pd error:&err];
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
    while (true) {
        @autoreleasepool {
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
                ts.ipd_m = 0.064f;
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

            id<MTLCommandBuffer> cb = [queue commandBuffer];
            int views = (int)cp_drawable_get_view_count(drawable);
            for (int i = 0; i < views; i++) {
                MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
                rp.colorAttachments[0].texture = cp_drawable_get_color_texture(drawable, i);
                rp.colorAttachments[0].loadAction = MTLLoadActionClear;
                rp.colorAttachments[0].storeAction = MTLStoreActionStore;
                rp.colorAttachments[0].clearColor = (i == 0)
                    ? MTLClearColorMake(0.8, 0.05, 0.05, 1.0)
                    : MTLClearColorMake(0.05, 0.7, 0.1, 1.0);
                rp.depthAttachment.texture = cp_drawable_get_depth_texture(drawable, i);
                rp.depthAttachment.loadAction = MTLLoadActionClear;
                rp.depthAttachment.storeAction = MTLStoreActionStore;
                rp.depthAttachment.clearDepth = 1.0;
                id<MTLRasterizationRateMap> rrm = cp_drawable_get_rasterization_rate_map(drawable, i);
                if (rrm) rp.rasterizationRateMap = rrm;

                id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
                if (pipeline != nil && haveEyes && i < 2 && !samplingDisabled) {
                    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                                 width:(NSUInteger)MAX(eyes.left_width, 1)
                                                                                                height:(NSUInteger)MAX(eyes.left_height, 1)
                                                                                             mipmapped:NO];
                    td.usage = MTLTextureUsageShaderRead;
                    id<MTLTexture> tex = nil;
                    uint64_t handle = (i == 0) ? eyes.left_texture : eyes.right_texture;
                    if (handle != 0) {
                        // Reuse the opaque MTLTexture pointer exported by the provider (same GPU/process).
                        tex = (__bridge id<MTLTexture>)(void *)(uintptr_t)handle;
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
                    if (tex != nil) {
                        [enc setRenderPipelineState:pipeline];
                        [enc setFragmentTexture:tex atIndex:0];
                        [enc setFragmentSamplerState:sampler atIndex:0];
                        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
                    }
                }
                [enc endEncoding];
            }
            cp_drawable_encode_present(drawable, cb);
            [cb commit];
            // Do not block the compositor on GPU completion (the sample doesn't); blocking here can
            // stall the shared GPU while Minecraft is rendering.
            if (cp_layer_renderer_get_state(lr) == cp_layer_renderer_state_running) {
                cp_frame_end_submission(frame);
            } else {
                compLog("layer left running state before endSubmission; exiting loop");
                break;
            }

            frameCount++;
            if (frameCount == 1 || frameCount % 120 == 0) {
                compLog("frame %d eyes=%d anchor=%d head=(%.2f,%.2f,%.2f) p0=0x%llx p1=0x%llx",
                        frameCount, (int)haveEyes, (int)(st == ar_device_anchor_query_status_success),
                        anchorTransform.columns[3].x, anchorTransform.columns[3].y, anchorTransform.columns[3].z,
                        (unsigned long long)eyes.left_texture, (unsigned long long)eyes.right_texture);
            }
        }
    }
    ar_session_stop(session);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"VRMCImmersiveEnded" object:nil];
    });
    compLog("posted VRMCImmersiveEnded");
}
@end

extern "C" void VRMCCompositor_InitAndRun(cp_layer_renderer_t layerRenderer) {
    openLog();
    compLog("starting compositor thread");
    VRMCCompositorThread *thread = [[VRMCCompositorThread alloc] init];
    thread.layerRenderer = layerRenderer;
    thread.name = @"VRMC Immersive Compositor";
    [thread start];
}
