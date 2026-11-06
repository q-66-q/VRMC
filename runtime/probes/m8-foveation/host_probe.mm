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
    "}\n"
    // Mirrors VRMCCompositor.mm's M8 foveated sharpening (FlatFx + fmain_flat_sharp).
    "struct FlatFx { float strength; float vignette; float texelW; float texelH; };\n"
    "fragment float4 fmain_flat_sharp(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],\n"
    "                                 sampler s [[sampler(0)]], constant FlatFx &fx [[buffer(3)]]) {\n"
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
    "  float3 sharp = c + (c - blur) * (fx.strength * foveal);\n"
    "  sharp = clamp(sharp, lo - 0.06, hi + 0.06);\n"
    "  float vig = 1.0 - clamp(fx.vignette, 0.0, 0.95) * smoothstep(0.55, 1.0, r);\n"
    "  return float4(clamp(sharp, 0.0, 1.0) * vig, 1.0);\n"
    "}\n";

typedef struct {
    float strength;
    float vignette;
    float texelW;
    float texelH;
} ProbeFlatFx;

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
                              MTLSize viewportSize, NSString *fragName,
                              const void *fxBytes, size_t fxLength, id<MTLTexture> *outTarget) {
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:[NSString stringWithUTF8String:kShader]
                                                  options:nil error:&error];
    if (library == nil) {
        printf("shader compile failed: %s\n", error.description.UTF8String);
        return NO;
    }
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [library newFunctionWithName:@"vmain"];
    pd.fragmentFunction = [library newFunctionWithName:fragName];
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
    if (fxBytes != NULL && fxLength > 0) {
        [enc setFragmentBytes:fxBytes length:fxLength atIndex:3];
    }
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

/// Checkerboard stand-in for a low-resolution game frame (8 px cells, black/white).
static id<MTLTexture> makeCheckerTexture(id<MTLDevice> device, NSUInteger width, NSUInteger height,
                                         NSUInteger cell) {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                 width:width height:height mipmapped:NO];
    d.usage = MTLTextureUsageShaderRead;
    d.storageMode = MTLStorageModeShared;
    id<MTLTexture> tex = [device newTextureWithDescriptor:d];
    if (tex == nil) return nil;
    const NSUInteger rowBytes = width * 4;
    uint8_t *px = (uint8_t *)malloc(rowBytes * height);
    for (NSUInteger y = 0; y < height; y++) {
        for (NSUInteger x = 0; x < width; x++) {
            uint8_t v = (((x / cell) + (y / cell)) & 1) ? 235 : 20;
            uint8_t *p = px + y * rowBytes + x * 4;
            p[0] = p[1] = p[2] = v;
            p[3] = 255;
        }
    }
    [tex replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:px bytesPerRow:rowBytes];
    free(px);
    return tex;
}

/// Mean luma gradient magnitude over a rectangle (edge acutance proxy; 0..1 scale).
static double gradientEnergy(const uint8_t *px, NSUInteger width, NSUInteger height,
                             double x0, double y0, double x1, double y1) {
    NSUInteger xi0 = (NSUInteger)MAX(2.0, x0 * (double)width);
    NSUInteger yi0 = (NSUInteger)MAX(2.0, y0 * (double)height);
    NSUInteger xi1 = (NSUInteger)MIN((double)width - 2.0, x1 * (double)width);
    NSUInteger yi1 = (NSUInteger)MIN((double)height - 2.0, y1 * (double)height);
    double sum = 0.0;
    NSUInteger count = 0;
    for (NSUInteger y = yi0; y < yi1; y++) {
        for (NSUInteger x = xi0; x < xi1; x++) {
            double l = (double)px[(y * width + x) * 4 + 1];
            double lx1 = (double)px[(y * width + (x + 1)) * 4 + 1];
            double lx0 = (double)px[(y * width + (x - 1)) * 4 + 1];
            double ly1 = (double)px[((y + 1) * width + x) * 4 + 1];
            double ly0 = (double)px[((y - 1) * width + x) * 4 + 1];
            sum += (fabs(lx1 - lx0) + fabs(ly1 - ly0)) / 510.0;
            count++;
        }
    }
    return count > 0 ? sum / (double)count : 0.0;
}

/// Mean absolute luma difference between two same-size RGBA8 images (0..1 scale).
static double meanAbsDiff(const uint8_t *a, const uint8_t *b, NSUInteger pixelCount) {
    double sum = 0.0;
    for (NSUInteger i = 0; i < pixelCount; i++) {
        sum += fabs((double)a[i * 4 + 1] - (double)b[i * 4 + 1]);
    }
    return pixelCount > 0 ? sum / ((double)pixelCount * 255.0) : 0.0;
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
        BOOL rendered = renderSampledPass(device, queue, pattern, target, rateMap, screenSize,
                                         @"fmain_flat", NULL, 0, nil);
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
                                               physicalSize, @"fmain_flat", NULL, 0, nil);
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

        // ---- M8 foveated sharpening: 4x upscale of a low-resolution game frame (no rate map) ----
        // Plain bilinear vs the compositor's fovea-weighted CAS-lite. A checkerboard has measurable
        // edge acutance, so this is an objective check that the feature sharpens the upscale, keeps the
        // correction bounded (anti-halo), and tapers off in the periphery.
        const NSUInteger lowW = 480, lowH = 270, upW = 1920, upH = 1080;
        id<MTLTexture> lowTex = makeCheckerTexture(device, lowW, lowH, 8);
        MTLTextureDescriptor *upDesc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                               width:upW height:upH mipmapped:NO];
        upDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        upDesc.storageMode = MTLStorageModeShared;
        id<MTLTexture> plainTarget = [device newTextureWithDescriptor:upDesc];
        id<MTLTexture> sharpTarget = [device newTextureWithDescriptor:upDesc];
        ProbeFlatFx fx = {0.45f, 0.0f, 1.0f / (float)lowW, 1.0f / (float)lowH};
        BOOL okPlain = renderSampledPass(device, queue, lowTex, plainTarget, nil,
                                         MTLSizeMake(upW, upH, 1), @"fmain_flat", NULL, 0, nil);
        BOOL okSharp = renderSampledPass(device, queue, lowTex, sharpTarget, nil,
                                         MTLSizeMake(upW, upH, 1), @"fmain_flat_sharp",
                                         &fx, sizeof(fx), nil);
        check("4x upscale passes encode (plain + sharp)", okPlain && okSharp, "render encoder/command buffer");
        if (okPlain && okSharp && lowTex != nil) {
            uint8_t *plainPx = readTexture(device, queue, plainTarget);
            uint8_t *sharpPx = readTexture(device, queue, sharpTarget);
            double plainGrad = gradientEnergy(plainPx, upW, upH, 0.02, 0.02, 0.98, 0.98);
            double sharpGrad = gradientEnergy(sharpPx, upW, upH, 0.02, 0.02, 0.98, 0.98);
            const double ratio = plainGrad > 0.0 ? sharpGrad / plainGrad : 0.0;
            printf("[m8-foveation-probe] upscale sharpen: plainEdge=%.4f sharpEdge=%.4f ratio=%.2f\n",
                   plainGrad, sharpGrad, ratio);
            check("sharpening increases edge acutance on a 4x upscale", ratio >= 1.05,
                  "expected >= 1.05x the bilinear edge energy");
            const double mad = meanAbsDiff(plainPx, sharpPx, upW * upH);
            printf("[m8-foveation-probe] upscale sharpen: meanAbsDiff=%.4f (anti-halo bound 0.15)\n", mad);
            check("sharpening correction is bounded (anti-halo clamp)", mad <= 0.15,
                  "mean absolute luma change too large");
            const double centrePlain = gradientEnergy(plainPx, upW, upH, 0.35, 0.35, 0.65, 0.65);
            const double centreSharp = gradientEnergy(sharpPx, upW, upH, 0.35, 0.35, 0.65, 0.65);
            const double boxes[4][4] = {{0.02, 0.02, 0.16, 0.16}, {0.84, 0.02, 0.98, 0.16},
                                        {0.02, 0.84, 0.16, 0.98}, {0.84, 0.84, 0.98, 0.98}};
            double cornerPlain = 0.0, cornerSharp = 0.0;
            for (int b = 0; b < 4; b++) {
                cornerPlain += gradientEnergy(plainPx, upW, upH, boxes[b][0], boxes[b][1], boxes[b][2], boxes[b][3]);
                cornerSharp += gradientEnergy(sharpPx, upW, upH, boxes[b][0], boxes[b][1], boxes[b][2], boxes[b][3]);
            }
            cornerPlain /= 4.0;
            cornerSharp /= 4.0;
            const double centreGain = centrePlain > 0.0 ? centreSharp / centrePlain : 0.0;
            const double cornerGain = cornerPlain > 0.0 ? cornerSharp / cornerPlain : 0.0;
            printf("[m8-foveation-probe] upscale sharpen: centreGain=%.2f cornerGain=%.2f\n",
                   centreGain, cornerGain);
            check("foveal weighting: centre edge gain exceeds corner edge gain",
                  centreGain >= cornerGain + 0.02, "the periphery must be sharpened less than the fovea");
            free(plainPx);
            free(sharpPx);
        }

        // ---- M8 combined pass: fovea-weighted sharpening UNDER a real rasterization rate map ----
        // The exact device combination: the provider frame is sharpened while the drawable is foveated.
        // The rate-mapped target must be the physical extent while the viewport is the logical (screen)
        // size; the sharpening taps stay in provider texels and the foveal taper is in drawable NDC, so
        // the centre gain must survive the rate map and the periphery must stay unsharpened.
        MTLTextureDescriptor *fovDesc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                               width:physicalSize.width
                                                              height:physicalSize.height
                                                            mipmapped:NO];
        fovDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        fovDesc.storageMode = MTLStorageModeShared;
        id<MTLTexture> plainFovTarget = [device newTextureWithDescriptor:fovDesc];
        id<MTLTexture> sharpFovTarget = [device newTextureWithDescriptor:fovDesc];
        BOOL okFovPlain = renderSampledPass(device, queue, lowTex, plainFovTarget, rateMap,
                                            screenSize, @"fmain_flat", NULL, 0, nil);
        BOOL okFovSharp = renderSampledPass(device, queue, lowTex, sharpFovTarget, rateMap,
                                            screenSize, @"fmain_flat_sharp", &fx, sizeof(fx), nil);
        check("foveated + sharpened upscale encodes (plain + sharp)", okFovPlain && okFovSharp,
              "render encoder/command buffer with the rate map");
        if (okFovPlain && okFovSharp) {
            const NSUInteger fovW = physicalSize.width, fovH = physicalSize.height;
            uint8_t *plainFovPx = readTexture(device, queue, plainFovTarget);
            uint8_t *sharpFovPx = readTexture(device, queue, sharpFovTarget);
            const double centrePlain = gradientEnergy(plainFovPx, fovW, fovH, 0.35, 0.35, 0.65, 0.65);
            const double centreSharp = gradientEnergy(sharpFovPx, fovW, fovH, 0.35, 0.35, 0.65, 0.65);
            const double fovBoxes[4][4] = {{0.02, 0.02, 0.16, 0.16}, {0.84, 0.02, 0.98, 0.16},
                                           {0.02, 0.84, 0.16, 0.98}, {0.84, 0.84, 0.98, 0.98}};
            double cornerPlain = 0.0, cornerSharp = 0.0;
            for (int b = 0; b < 4; b++) {
                cornerPlain += gradientEnergy(plainFovPx, fovW, fovH, fovBoxes[b][0], fovBoxes[b][1],
                                              fovBoxes[b][2], fovBoxes[b][3]);
                cornerSharp += gradientEnergy(sharpFovPx, fovW, fovH, fovBoxes[b][0], fovBoxes[b][1],
                                              fovBoxes[b][2], fovBoxes[b][3]);
            }
            cornerPlain /= 4.0;
            cornerSharp /= 4.0;
            const double centreGain = centrePlain > 0.0 ? centreSharp / centrePlain : 0.0;
            const double cornerGain = cornerPlain > 0.0 ? cornerSharp / cornerPlain : 0.0;
            printf("[m8-foveation-probe] foveated sharpen: centreGain=%.2f cornerGain=%.2f\n",
                   centreGain, cornerGain);
            check("foveated sharpening keeps the centre acutance gain", centreGain >= 1.05,
                  "expected >= 1.05x the bilinear centre edge energy under the rate map");
            check("foveated sharpening taper survives the rate map", centreGain >= cornerGain + 0.02,
                  "the periphery must be sharpened less than the fovea");
            const double fovMad = meanAbsDiff(plainFovPx, sharpFovPx, fovW * fovH);
            printf("[m8-foveation-probe] foveated sharpen: meanAbsDiff=%.4f (anti-halo bound 0.15)\n", fovMad);
            check("foveated sharpening correction is bounded", fovMad <= 0.15,
                  "mean absolute luma change too large");
            free(plainFovPx);
            free(sharpFovPx);
        }

        printf("[m8-foveation-probe] %d checks, %d failed\n", gChecks, gFailures);
        printf(gFailures == 0 ? "[m8-foveation-probe] RESULT: PASS\n"
                              : "[m8-foveation-probe] RESULT: FAIL\n");
        return gFailures == 0 ? 0 : 1;
    }
}
