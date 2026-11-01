// M3a gate-2 probe renderer, modeled on Apple's CompositorServices C sample:
//  - dedicated NSThread
//  - cp_frame_predict_timing -> start_update/end_update -> wait(optimal_input_time)
//  - start_submission -> query_drawable -> cp_drawable_set_device_anchor -> render ->
//    cp_drawable_encode_present -> commit -> end_submission
//  - ARKit world tracking C API with cp_time_to_cf_time_interval for the query timestamp
#include "Bridging.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <ARKit/ARKit.h>
#import <Spatial/Spatial.h>
#include <stdio.h>

static FILE *gLog;

static void probeLog(const char *fmt, ...) {
    char line[1024];
    va_list args; va_start(args, fmt);
    vsnprintf(line, sizeof(line), fmt, args);
    va_end(args);
    NSLog(@"[m3a-c] %s", line);
    if (gLog) { fprintf(gLog, "[m3a-c] %s\n", line); fflush(gLog); }
}

static void openLog(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [paths.firstObject stringByAppendingPathComponent:@"m3a-probe.log"];
    gLog = fopen(path.UTF8String, "a");
}

@interface ProbeThread : NSThread
@property(nonatomic) cp_layer_renderer_t layerRenderer;
@end

@implementation ProbeThread
- (void)main {
    cp_layer_renderer_t lr = self.layerRenderer;

    ar_world_tracking_configuration_t cfg = ar_world_tracking_configuration_create();
    ar_world_tracking_provider_t provider = ar_world_tracking_provider_create(cfg);
    ar_data_providers_t providers = ar_data_providers_create_with_data_providers(provider, nil);
    ar_session_t session = ar_session_create();
    ar_session_run(session, providers);
    probeLog("ARKit session started");

    cp_layer_renderer_wait_until_running(lr);
    id<MTLDevice> device = cp_layer_renderer_get_device(lr);
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLBuffer> readback = [device newBufferWithLength:16 options:MTLResourceStorageModeShared];
    probeLog("render thread running; device=%s", device.name.UTF8String);

    while (true) {
        @autoreleasepool {
            cp_layer_renderer_state state = cp_layer_renderer_get_state(lr);
            if (state == cp_layer_renderer_state_invalidated) {
                probeLog("layer invalidated; exiting");
                break;
            }
            if (state == cp_layer_renderer_state_paused) {
                cp_layer_renderer_wait_until_running(lr);
                continue;
            }
            cp_frame_t frame = cp_layer_renderer_query_next_frame(lr);
            if (frame == nullptr) continue;
            cp_frame_timing_t timing = cp_frame_predict_timing(frame);
            if (timing == nullptr) continue;
            cp_frame_start_update(frame);
            cp_frame_end_update(frame);
            cp_time_wait_until(cp_frame_timing_get_optimal_input_time(timing));
            cp_frame_start_submission(frame);
            cp_drawable_t drawable = cp_frame_query_drawable(frame);
            if (drawable == nullptr) {
                cp_frame_end_submission(frame);
                continue;
            }
            // ARKit anchor at presentation time.
            cp_frame_timing_t actual = cp_drawable_get_frame_timing(drawable);
            cp_time_t presentation = cp_frame_timing_get_presentation_time(actual);
            CFTimeInterval queryTime = cp_time_to_cf_time_interval(presentation);
            ar_device_anchor_t anchor = ar_device_anchor_create();
            ar_device_anchor_query_status_t st =
                ar_world_tracking_provider_query_device_anchor_at_timestamp(provider, queryTime, anchor);
            if (st == ar_device_anchor_query_status_success) {
                // TEST: log anchor translation, then do NOT set it (variant to check whether a bad anchor
                // is moving the layer out of view).
                simd_float4x4 t = ar_device_anchor_get_origin_from_anchor_transform(anchor);
                static int loggedAnchor = 0;
                if (!loggedAnchor) {
                    loggedAnchor = 1;
                    probeLog("anchor pos=(%.2f, %.2f, %.2f)", t.columns[3].x, t.columns[3].y, t.columns[3].z);
                }
                cp_drawable_set_device_anchor(drawable, anchor);
            }

            id<MTLCommandBuffer> cb = [queue commandBuffer];
            int views = (int)cp_drawable_get_view_count(drawable);
            static int loggedLayout = 0;
            if (!loggedLayout) {
                loggedLayout = 1;
                for (int i = 0; i < views; i++) {
                    id<MTLTexture> tex = cp_drawable_get_color_texture(drawable, i);
                    probeLog("view %d colorTex=%p size=%lux%lu fmt=%lu arrayLen=%lu", i,
                             (__bridge void *)tex,
                             (unsigned long)tex.width, (unsigned long)tex.height,
                             (unsigned long)tex.pixelFormat, (unsigned long)tex.arrayLength);
                }
            }
            for (int i = 0; i < views; i++) {
                MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
                rp.colorAttachments[0].texture = cp_drawable_get_color_texture(drawable, i);
                rp.colorAttachments[0].loadAction = MTLLoadActionClear;
                rp.colorAttachments[0].storeAction = MTLStoreActionStore;
                rp.colorAttachments[0].clearColor = (i == 0)
                    ? MTLClearColorMake(0.8, 0.05, 0.05, 1.0)
                    : MTLClearColorMake(0.05, 0.7, 0.1, 1.0);
                // Sample parity: dedicated layout expects the drawable depth texture + rate map.
                rp.depthAttachment.texture = cp_drawable_get_depth_texture(drawable, i);
                rp.depthAttachment.loadAction = MTLLoadActionClear;
                rp.depthAttachment.storeAction = MTLStoreActionStore;
                rp.depthAttachment.clearDepth = 1.0;
                id<MTLRasterizationRateMap> rrm = cp_drawable_get_rasterization_rate_map(drawable, i);
                if (rrm) rp.rasterizationRateMap = rrm;
                static int loggedDepth = 0;
                if (!loggedDepth) {
                    loggedDepth = 1;
                    probeLog("view %d depthTex=%p rrm=%p", i,
                             (__bridge void *)rp.depthAttachment.texture, (__bridge void *)rrm);
                }
                id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
                [enc endEncoding];
            }
            id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
            if (blit) {
                [blit copyFromTexture:cp_drawable_get_color_texture(drawable, 0)
                          sourceSlice:0 sourceLevel:0
                         sourceOrigin:MTLOriginMake(0, 0, 0)
                           sourceSize:MTLSizeMake(1, 1, 1)
                             toBuffer:readback destinationOffset:0
                destinationBytesPerRow:8 destinationBytesPerImage:8];
                [blit endEncoding];
            }
            cp_drawable_encode_present(drawable, cb);
            [cb commit];
            [cb waitUntilCompleted];
            static int loggedCompletion = 0;
            if (!loggedCompletion) {
                loggedCompletion = 1;
                probeLog("completed cb status=%ld error=%s", (long)cb.status,
                         cb.error ? cb.error.description.UTF8String : "none");
                if (readback) {
                    _Float16 *px = (_Float16 *)readback.contents;
                    probeLog("readback tex0 pixel0 r=%.3f g=%.3f b=%.3f a=%.3f",
                             (float)px[0], (float)px[1], (float)px[2], (float)px[3]);
                }
            }
            static int loggedCommit = 0;
            if (!loggedCommit) {
                loggedCommit = 1;
                probeLog("committed cb status=%ld error=%s", (long)cb.status,
                         cb.error ? cb.error.description.UTF8String : "none");
            }
            cp_frame_end_submission(frame);

            static int frameCount = 0;
            frameCount++;
            if (frameCount == 1 || frameCount % 60 == 0) {
                probeLog("frame %d anchorStatus=%d queryTime=%.3f", frameCount, (int)st, queryTime);
            }
        }
    }
    ar_session_stop(session);
}
@end

extern "C" void VRMCProbe_InitAndRun(cp_layer_renderer_t layerRenderer) {
    openLog();
    probeLog("closure entered; starting ProbeThread");
    ProbeThread *thread = [[ProbeThread alloc] init];
    thread.layerRenderer = layerRenderer;
    thread.name = @"M3A C Render Thread";
    [thread start];
}
