/*
 * M8 host probe: verify the compositor's flat sampling pass behaves correctly when the render pass
 * carries a variable rasterization rate map (the CompositorServices foveation mechanism).
 *
 * Why: the visionOS simulator reports supportsFoveation=false, so the device foveation path cannot be
 * exercised there, and D1 was unavailable. macOS Apple Silicon supports MTLRasterizationRateMap, which
 * lets us prove the two things this project depends on without a headset:
 *
 *  1. A full-screen full-viewport draw into a rate-mapped target renders the expected content: a
 *     physical target pixel that the rate map expands to a given logical position samples the eye
 *     texture at that logical position (i.e. the shader's NDC->UV mapping stays logical under VRR).
 *  2. The render-pass viewport must be the rate map's SCREEN (logical) size, not the physical texture
 *     size. This mirrors how the compositor uses the CompositorServices view viewport
 *     (cp_view_texture_map_get_viewport; the "never hardcode, use textureMap.viewport" guidance also
 *     used by the public drawing-graphics-on-Apple-Vision article). The negative control with the
 *     physical-size viewport must fail the same center check.
 *
 * The shader below is the same math as VRMCCompositor.mm's vmain + fmain_flat (full-screen triangle
 * strip, NDC -> (u, 1-v) sampling) without the diagnostic badge.
 *
 * Build/run: runtime/probes/m8-foveation/run.sh   (macOS host only; no device, no CompositorServices)
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <math.h>
#include <stdio.h>

static const char *kShader = ""
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct VOut { float4 pos [[position]]; float2 ndc; };\n"
    "vertex VOut vmain(uint vid [[vertex_id]]) {\n"
    "  float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };\n"
    "  VOut o; o.pos = float4(p[vid], 0, 1); o.ndc = p[vid]; return o;\n"
    "}\n"
    "fragment float4 fmain_flat(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],\n"
    "                           sampler s [[sampler(0)]]) {\n"
    "  float2 uv = float2((in.ndc.x + 1.0) * 0.5, (1.0 - in.ndc.y) * 0.5);\n"
    "  return float4(tex.sample(s, uv).rgb, 1.0);\n"
    "}\n";

static int gChecks = 0;
static int gFailures = 0;

static void check(const char *name, BOOL ok, const char *detail) {
    gChecks++;
    if (!ok) {
        gFailures++;
        printf("  FAIL %s %s\n", name, detail ? detail : "");
    } else {
        printf("  PASS %s\n", name);
    }
}

// Eye-texture stand-in: 1024x1024 quadrant pattern (TL red, TR green, BL blue, BR white) with a
// white centre cross, so a UV mapping error is visible as the wrong quadrant/centre colour.
static id<MTLTexture> makePatternTexture(id<MTLDevice> device) {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                 width:1024 height:1024 mipmapped:NO];
    d.usage = MTLTextureUsageShaderRead;
    d.storageMode = MTLStorageModeShared;
    id<MTLTexture> tex = [device newTextureWithDescriptor:d];
    if (tex == nil) return nil;
    const NSUInteger rowBytes = 1024 * 4;
    uint8_t *px = (uint8_t *)calloc(1, rowBytes * 1024);
    for (NSUInteger y = 0; y < 1024; y++) {
        for (NSUInteger x = 0; x < 1024; x++) {
            uint8_t *p = px + y * rowBytes + x * 4;
            if (x >= 482 && x < 542 && y >= 482 && y < 542) { p[0] = p[1] = p[2] = 255; }
            else if (x < 512 && y < 512) { p[0] = 220; }
            else if (x >= 512 && y < 512) { p[1] = 220; }
            else if (x < 512) { p[2] = 220; }
            else { p[0] = p[1] = p[2] = 235; }
            p[3] = 255;
        }
    }
    [tex replaceRegion:MTLRegionMake2D(0, 0, 1024, 1024) mipmapLevel:0 withBytes:px bytesPerRow:rowBytes];
    free(px);
    return tex;
}

static id<MTLRasterizationRateMap> makeRateMap(id<MTLDevice> device, MTLSize screenSize) {
    // Three rate columns/rows: 0.5 in the periphery, 1.0 in the centre = a static foveated map with
    // the same shape as the system's eye-tracked maps (high density centre, half-rate periphery).
    float horizontal[3] = {0.5f, 1.0f, 0.5f};
    float vertical[3] = {0.5f, 1.0f, 0.5f};
    MTLRasterizationRateLayerDescriptor *layer =
        [[MTLRasterizationRateLayerDescriptor alloc] initWithSampleCount:MTLSizeMake(3, 3, 0)
                                                              horizontal:horizontal
                                                                vertical:vertical];
    MTLRasterizationRateMapDescriptor *desc = [MTLRasterizationRateMapDescriptor new];
    desc.screenSize = screenSize;
    [desc setLayer:layer atIndex:0];
    return [device newRasterizationRateMapWithDescriptor:desc];
}

/// Render the full-screen sampling pass into a rate-mapped target and return 1) the target texture and
/// 2) success of the encode. viewportSize is deliberately a parameter (negative-control use).
static BOOL renderSampledPass(id<MTLDevice> device, id<MTLCommandQueue> queue, id<MTLTexture> pattern,
                              id<MTLTexture> target, id<MTLRasterizationRateMap> rateMap,
                              MTLSize viewportSize, id<MTLTexture> *outTarget) {
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:[NSString stringWithUTF8String:kShader]
                                                  options:nil error:&error];
    if (library == nil) {
        printf("shader compile failed: %s\n", error.description.UTF8String);
        return NO;
    }
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [library newFunctionWithName:@"vmain"];
    pd.fragmentFunction = [library newFunctionWithName:@"fmain_flat"];
    pd.colorAttachments[0].pixelFormat = target.pixelFormat;
    id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:pd error:&error];
    if (pipeline == nil) {
        printf("pipeline create failed: %s\n", error.description.UTF8String);
        return NO;
    }
    MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
    sd.minFilter = MTLSamplerMinMagFilterLinear;
    sd.magFilter = MTLSamplerMinMagFilterLinear;
    sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
    id<MTLSamplerState> sampler = [device newSamplerStateWithDescriptor:sd];

    id<MTLCommandBuffer> cb = [queue commandBuffer];
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = target;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    rp.rasterizationRateMap = rateMap;   // CompositorServices' foveation mechanism.
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
    if (enc == nil) {
        printf("render encoder nil\n");
        return NO;
    }
    [enc setViewport:(MTLViewport){0.0, 0.0, (double)viewportSize.width, (double)viewportSize.height, 0.0, 1.0}];
    [enc setRenderPipelineState:pipeline];
    [enc setFragmentTexture:pattern atIndex:0];
    [enc setFragmentSamplerState:sampler atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    if (cb.status != MTLCommandBufferStatusCompleted || cb.error != nil) {
        printf("command buffer failed: %s\n", cb.error ? cb.error.description.UTF8String : "status");
        return NO;
    }
    if (outTarget) *outTarget = target;
    return YES;
}

static uint8_t *readTexture(id<MTLDevice> device, id<MTLCommandQueue> queue, id<MTLTexture> tex) {
    NSUInteger bpr = tex.width * 4;
    id<MTLBuffer> buffer = [device newBufferWithLength:bpr * tex.height options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = [queue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit copyFromTexture:tex sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:MTLSizeMake(tex.width, tex.height, 1)
                 toBuffer:buffer destinationOffset:0 destinationBytesPerRow:bpr
      destinationBytesPerImage:bpr * tex.height];
    [blit endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    uint8_t *copy = (uint8_t *)malloc(bpr * tex.height);
    memcpy(copy, buffer.contents, bpr * tex.height);
    return copy;
}

static BOOL colorIs(const uint8_t *px, NSUInteger width, NSUInteger x, NSUInteger y,
                    int r, int g, int b, int tolerance) {
    const uint8_t *p = px + (y * width + x) * 4;
    return abs((int)p[0] - r) <= tolerance && abs((int)p[1] - g) <= tolerance && abs((int)p[2] - b) <= tolerance;
}

int main(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) {
            printf("[m8-foveation-probe] SKIP: no Metal device\n");
            return 2;
        }
        printf("[m8-foveation-probe] device=%s\n", device.name.UTF8String);
        id<MTLCommandQueue> queue = [device newCommandQueue];
        id<MTLTexture> pattern = makePatternTexture(device);
        if (pattern == nil) { printf("[m8-foveation-probe] FAIL: pattern texture\n"); return 1; }

        const MTLSize screenSize = MTLSizeMake(1920, 1080, 1);
        id<MTLRasterizationRateMap> rateMap = makeRateMap(device, screenSize);
        if (rateMap == nil) {
            printf("[m8-foveation-probe] SKIP: device does not support rasterization rate maps\n");
            return 2;
        }
        const MTLSize physicalSize = [rateMap physicalSizeForLayer:0];
        printf("[m8-foveation-probe] rate map: screen=%zux%zu physical=%zux%zu (%.1f%% of screen pixels)\n",
               (size_t)screenSize.width, (size_t)screenSize.height,
               (size_t)physicalSize.width, (size_t)physicalSize.height,
               100.0 * (double)(physicalSize.width * physicalSize.height) /
                   (double)(screenSize.width * screenSize.height));
        check("rate map reduces physical pixel count",
              physicalSize.width < screenSize.width && physicalSize.height < screenSize.height,
              "expected a smaller physical target for the 0.5 periphery");

        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                       width:physicalSize.width
                                                                                      height:physicalSize.height
                                                                                   mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        td.storageMode = MTLStorageModeShared;
        id<MTLTexture> target = [device newTextureWithDescriptor:td];
        if (target == nil) { printf("[m8-foveation-probe] FAIL: target texture\n"); return 1; }

        // ---- positive: viewport = SCREEN (logical) size, as CompositorServices' view viewport is used
        BOOL rendered = renderSampledPass(device, queue, pattern, target, rateMap, screenSize, nil);
        check("rate-mapped pass encodes and completes", rendered, "render encoder / command buffer");
        if (!rendered) { printf("[m8-foveation-probe] RESULT: FAIL\n"); return 1; }
        uint8_t *px = readTexture(device, queue, target);

        MTLCoordinate2D centrePhysical = [rateMap mapScreenToPhysicalCoordinates:MTLCoordinate2DMake(960.0, 540.0)
                                                                        forLayer:0];
        MTLCoordinate2D quarterPhysical = [rateMap mapScreenToPhysicalCoordinates:MTLCoordinate2DMake(480.0, 270.0)
                                                                         forLayer:0];
        printf("[m8-foveation-probe] logical centre -> physical (%.1f,%.1f); logical (480,270) -> physical (%.1f,%.1f)\n",
               (double)centrePhysical.x, (double)centrePhysical.y,
               (double)quarterPhysical.x, (double)quarterPhysical.y);
        check("logical centre maps to the pattern centre (white cross)",
              colorIs(px, physicalSize.width, (NSUInteger)centrePhysical.x, (NSUInteger)centrePhysical.y,
                      255, 255, 255, 12), "expected white centre cross");
        check("logical upper-left quarter maps to the red quadrant",
              colorIs(px, physicalSize.width, (NSUInteger)quarterPhysical.x, (NSUInteger)quarterPhysical.y,
                      220, 0, 0, 12), "expected red quadrant");

        // ---- negative control: viewport = physical size is the bug this probe guards against
        id<MTLTexture> wrongTarget = [device newTextureWithDescriptor:td];
        BOOL renderedWrong = renderSampledPass(device, queue, pattern, wrongTarget, rateMap,
                                               physicalSize, nil);
        check("negative control still encodes", renderedWrong, "render encoder / command buffer");
        BOOL wrongCentreIsWhite = YES;
        if (renderedWrong) {
            uint8_t *wrongPx = readTexture(device, queue, wrongTarget);
            wrongCentreIsWhite = colorIs(wrongPx, physicalSize.width,
                                         (NSUInteger)centrePhysical.x, (NSUInteger)centrePhysical.y,
                                         255, 255, 255, 12);
            free(wrongPx);
        }
        check("physical-size viewport corrupts the foveal centre (negative control fails as expected)",
              !wrongCentreIsWhite, "if this passes, the probe cannot distinguish the viewport convention");
        free(px);

        printf("[m8-foveation-probe] %d checks, %d failed\n", gChecks, gFailures);
        printf(gFailures == 0 ? "[m8-foveation-probe] RESULT: PASS\n"
                              : "[m8-foveation-probe] RESULT: FAIL\n");
        return gFailures == 0 ? 0 : 1;
    }
}
