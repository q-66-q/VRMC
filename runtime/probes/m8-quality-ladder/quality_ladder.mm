/*
 * M8 quality ladder probe (macOS host Metal; no device, no CompositorServices).
 *
 * The compositor receives the game's eye texture at the provider's dynamic eye-target size and
 * upscales it into the display's logical (4K-class) drawable, optionally with the fovea-weighted
 * CAS-lite sharpening pass. This probe quantifies that trade on real Metal: a 1920x1080 procedural
 * reference is box-downsampled to several eye-target sizes ("game renders at scale S"), then upscaled
 * back to 1920x1080 with the compositor's flat shader and with its sharp shader at the auto strength
 * the compositor would choose. PSNR and edge acutance are measured against the reference so the
 * settings ladder (and the sharpening default) has an objective, reproducible baseline.
 *
 * Metrics exclude the top 1.5% of rows (the compositor's green mode-badge strip is drawn there by
 * both shader variants and is not part of the image).
 *
 * Exit: 0 PASS, 1 FAIL, 2 SKIP (no Metal device).
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int gChecks = 0;
static int gFailures = 0;

static void check(const char *name, BOOL ok, const char *detail) {
    gChecks++;
    if (!ok) { gFailures++; printf("  FAIL %s %s\n", name, detail ? detail : ""); }
}

static NSString *const kShaderSource =
    @"#include <metal_stdlib>\n"
     "using namespace metal;\n"
     "struct VOut { float4 pos [[position]]; float2 ndc; };\n"
     "vertex VOut vmain(uint vid [[vertex_id]]) {\n"
     "  float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };\n"
     "  VOut o; o.pos = float4(p[vid], 0, 1); o.ndc = p[vid]; return o;\n"
     "}\n"
     "fragment float4 fmain_flat(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],\n"
     "                           sampler s [[sampler(0)]]) {\n"
     "  if (in.ndc.y > 0.985) return float4(float3(0.1,0.8,0.1), 1.0);\n"
     "  float2 uv = float2((in.ndc.x + 1.0) * 0.5, (1.0 - in.ndc.y) * 0.5);\n"
     "  return float4(tex.sample(s, uv).rgb, 1.0);\n"
     "}\n"
     "struct FlatFx { float strength; float vignette; float texelW; float texelH; };\n"
     "fragment float4 fmain_flat_sharp(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],\n"
     "                                 sampler s [[sampler(0)]], constant FlatFx &fx [[buffer(3)]]) {\n"
     "  if (in.ndc.y > 0.985) return float4(float3(0.1,0.8,0.1), 1.0);\n"
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
     "  return float4(clamp(sharp, 0.0, 1.0), 1.0);\n"
     "}\n";

typedef struct {
    float strength;
    float vignette;
    float texelW;
    float texelH;
} ProbeFlatFx;

static double lumaAt(const uint8_t *px, NSUInteger index) {
    return (0.2126 * px[index * 4 + 0] + 0.7152 * px[index * 4 + 1] +
            0.0722 * px[index * 4 + 2]) / 255.0;
}

static NSUInteger skipTopRows(NSUInteger height) {
    return (NSUInteger)(0.015 * (double)height) + 1;
}

static double psnrLuma(const uint8_t *ref, const uint8_t *out, NSUInteger w, NSUInteger h) {
    const NSUInteger skip = skipTopRows(h);
    double mse = 0.0;
    NSUInteger count = 0;
    for (NSUInteger y = skip; y < h; y++) {
        for (NSUInteger x = 0; x < w; x++) {
            const double a = lumaAt(ref, y * w + x);
            const double b = lumaAt(out, y * w + x);
            mse += (a - b) * (a - b);
            count++;
        }
    }
    mse /= (double)(count > 0 ? count : 1);
    return mse <= 1e-12 ? 99.0 : 10.0 * log10(1.0 / mse);
}

static double maxAbsDiffLuma(const uint8_t *ref, const uint8_t *out, NSUInteger w, NSUInteger h) {
    const NSUInteger skip = skipTopRows(h);
    double maxDiff = 0.0;
    for (NSUInteger y = skip; y < h; y++) {
        for (NSUInteger x = 0; x < w; x++) {
            maxDiff = fmax(maxDiff, fabs(lumaAt(ref, y * w + x) - lumaAt(out, y * w + x)));
        }
    }
    return maxDiff;
}

static double gradientEnergy(const uint8_t *px, NSUInteger w, NSUInteger h) {
    const NSUInteger skip = skipTopRows(h);
    double sum = 0.0;
    NSUInteger count = 0;
    for (NSUInteger y = skip + 1; y + 1 < h; y++) {
        for (NSUInteger x = 1; x + 1 < w; x++) {
            const double l = lumaAt(px, y * w + x);
            const double lx1 = lumaAt(px, y * w + x + 1);
            const double lx0 = lumaAt(px, y * w + x - 1);
            const double ly1 = lumaAt(px, (y + 1) * w + x);
            const double ly0 = lumaAt(px, (y - 1) * w + x);
            sum += fabs(lx1 - lx0) + fabs(ly1 - ly0);
            count++;
        }
    }
    return count > 0 ? sum / (double)count : 0.0;
}

// All probe textures are MTLStorageModeShared, so a direct getBytes readback is enough.
static uint8_t *readTexture(id<MTLTexture> tex) {
    const NSUInteger w = tex.width, h = tex.height;
    uint8_t *px = (uint8_t *)calloc(1, w * h * 4);
    if (px == NULL) return NULL;
    [tex getBytes:px bytesPerRow:w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
    return px;
}

static id<MTLTexture> makeTexture(id<MTLDevice> device, NSUInteger w, NSUInteger h, const uint8_t *px) {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                 width:w height:h mipmapped:NO];
    d.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    d.storageMode = MTLStorageModeShared;
    id<MTLTexture> tex = [device newTextureWithDescriptor:d];
    if (tex == nil) return nil;
    if (px != NULL) {
        [tex replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0 withBytes:px bytesPerRow:w * 4];
    }
    return tex;
}

static id<MTLTexture> makeReference(id<MTLDevice> device, NSUInteger w, NSUInteger h) {
    uint8_t *px = (uint8_t *)calloc(1, w * h * 4);
    for (NSUInteger y = 0; y < h; y++) {
        for (NSUInteger x = 0; x < w; x++) {
            // Detail sized so the lowest ladder scale (0.4x = 768x432) still represents it: a 16 px
            // checker and a 6 px diagonal stripe are ~6.4 px / ~2.4 px at that scale (no aliasing).
            const BOOL checker = (((x / 16) + (y / 16)) & 1) != 0;
            int v = checker ? 230 : 24;
            if (((x + y) % 48) < 6) v = 250;                 // diagonal stripe (edge proxy)
            if ((x % 240) < 3) v = (v + 130) / 2;            // sparse vertical lines
            uint8_t *p = px + (y * w + x) * 4;
            p[0] = (uint8_t)(x < w / 2 ? (v + 24 > 255 ? 255 : v + 24) : v);
            p[1] = (uint8_t)v;
            p[2] = (uint8_t)(y < h / 2 ? (v + 16 > 255 ? 255 : v + 16) : v);
            p[3] = 255;
        }
    }
    id<MTLTexture> tex = makeTexture(device, w, h, px);
    free(px);
    return tex;
}

/// Box-downsample the reference to an eye-target size (proxy for the game rendering at that scale).
static id<MTLTexture> downscale(id<MTLDevice> device, id<MTLTexture> src, NSUInteger w, NSUInteger h) {
    const NSUInteger sw = src.width, sh = src.height;
    uint8_t *srcPx = readTexture(src);
    uint8_t *dst = (uint8_t *)calloc(1, w * h * 4);
    for (NSUInteger y = 0; y < h; y++) {
        const NSUInteger y0 = y * sh / h;
        const NSUInteger y1 = ((y + 1) * sh + h - 1) / h;
        for (NSUInteger x = 0; x < w; x++) {
            const NSUInteger x0 = x * sw / w;
            const NSUInteger x1 = ((x + 1) * sw + w - 1) / w;
            double r = 0, g = 0, b = 0;
            NSUInteger n = 0;
            for (NSUInteger sy = y0; sy < y1 && sy < sh; sy++) {
                for (NSUInteger sx = x0; sx < x1 && sx < sw; sx++) {
                    const uint8_t *p = srcPx + (sy * sw + sx) * 4;
                    r += p[0]; g += p[1]; b += p[2]; n++;
                }
            }
            uint8_t *p = dst + (y * w + x) * 4;
            p[0] = (uint8_t)(n ? r / n : 0);
            p[1] = (uint8_t)(n ? g / n : 0);
            p[2] = (uint8_t)(n ? b / n : 0);
            p[3] = 255;
        }
    }
    id<MTLTexture> tex = makeTexture(device, w, h, dst);
    free(srcPx);
    free(dst);
    return tex;
}

static id<MTLTexture> renderFlat(id<MTLDevice> device, id<MTLCommandQueue> queue,
                                 id<MTLRenderPipelineState> pipeline, id<MTLTexture> source,
                                 NSUInteger w, NSUInteger h, const ProbeFlatFx *fx) {
    id<MTLTexture> target = makeTexture(device, w, h, NULL);
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = target;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLCommandBuffer> cb = [queue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
    [enc setViewport:(MTLViewport){0.0, 0.0, (double)w, (double)h, 0.0, 1.0}];
    [enc setRenderPipelineState:pipeline];
    [enc setFragmentTexture:source atIndex:0];
    [enc setFragmentBytes:fx length:sizeof(*fx) atIndex:3];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    return target;
}

int main(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) {
            printf("[m8-quality-ladder] SKIP: no Metal device\n");
            return 2;
        }
        printf("[m8-quality-ladder] device=%s\n", device.name.UTF8String);
        id<MTLCommandQueue> queue = [device newCommandQueue];
        const NSUInteger W = 1920, H = 1080;
        id<MTLTexture> reference = makeReference(device, W, H);
        if (reference == nil) {
            printf("[m8-quality-ladder] FAIL: reference texture\n");
            return 1;
        }
        NSError *err = nil;
        id<MTLLibrary> library = [device newLibraryWithSource:kShaderSource options:nil error:&err];
        if (library == nil) {
            printf("[m8-quality-ladder] FAIL: shader library: %s\n", err.description.UTF8String);
            return 1;
        }
        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [library newFunctionWithName:@"vmain"];
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
        pd.fragmentFunction = [library newFunctionWithName:@"fmain_flat"];
        id<MTLRenderPipelineState> flatPipeline = [device newRenderPipelineStateWithDescriptor:pd error:&err];
        pd.fragmentFunction = [library newFunctionWithName:@"fmain_flat_sharp"];
        id<MTLRenderPipelineState> sharpPipeline = [device newRenderPipelineStateWithDescriptor:pd error:&err];
        if (flatPipeline == nil || sharpPipeline == nil) {
            printf("[m8-quality-ladder] FAIL: pipelines\n");
            return 1;
        }

        uint8_t *refPx = readTexture(reference);
        const double scales[] = {0.4, 0.5, 0.625, 0.75, 1.0};
        const int scaleCount = (int)(sizeof(scales) / sizeof(scales[0]));
        double bilinearPsnr[5];
        double sharpPsnr[5];
        double acutRatio[5];
        double strengthUsed[5];
        printf("[m8-quality-ladder] %-6s %-11s %-8s %-8s %-9s %-9s %-7s %s\n",
               "scale", "eyeTarget", "upscale", "strength", "psnrFlat", "psnrSharp", "dPsnr", "acutRatio");
        for (int i = 0; i < scaleCount; i++) {
            const double scale = scales[i];
            const NSUInteger ew = (NSUInteger)llround((double)W * scale);
            const NSUInteger eh = (NSUInteger)llround((double)H * scale);
            const double upscale = (double)W / (double)ew;
            const double strength = upscale > 1.02 ? fmin(0.45, (upscale - 1.0) * 0.35) : 0.0;
            id<MTLTexture> eye = (ew == W && eh == H) ? reference : downscale(device, reference, ew, eh);
            ProbeFlatFx fx = {(float)strength, 0.0f, (float)(1.0 / (double)ew), (float)(1.0 / (double)eh)};
            id<MTLTexture> flatOut = renderFlat(device, queue, flatPipeline, eye, W, H, &fx);
            id<MTLTexture> sharpOut = renderFlat(device, queue, sharpPipeline, eye, W, H, &fx);
            uint8_t *flatPx = readTexture(flatOut);
            uint8_t *sharpPx = readTexture(sharpOut);
            bilinearPsnr[i] = psnrLuma(refPx, flatPx, W, H);
            sharpPsnr[i] = psnrLuma(refPx, sharpPx, W, H);
            const double flatAcut = gradientEnergy(flatPx, W, H);
            const double sharpAcut = gradientEnergy(sharpPx, W, H);
            acutRatio[i] = flatAcut > 0.0 ? sharpAcut / flatAcut : 0.0;
            strengthUsed[i] = strength;
            printf("[m8-quality-ladder] %-6.3f %4lux%-6lu %-8.2f %-8.3f %-9.2f %-9.2f %+7.2f %.2f\n",
                   scale, (unsigned long)ew, (unsigned long)eh, upscale, strength,
                   bilinearPsnr[i], sharpPsnr[i], sharpPsnr[i] - bilinearPsnr[i], acutRatio[i]);
            free(flatPx);
            free(sharpPx);
        }

        // ---- checks ---------------------------------------------------------------------
        // The ladder is a proxy (box-downsample then bilinear upscale), so per-step PSNR can wobble a
        // little from resampling phase; the meaningful, stable assertions are the endpoints.
        check("the smallest eye target is clearly the worst case",
              bilinearPsnr[0] + 3.0 < bilinearPsnr[1],
              "0.4x must lose clearly more detail than 0.5x");
        check("a milder upscale is clearly better than the worst case",
              bilinearPsnr[scaleCount - 2] > bilinearPsnr[0] + 3.0,
              "0.75x must be clearly better than 0.4x");
        const int identityIndex = scaleCount - 1;
        check("identity scale renders the reference losslessly",
              bilinearPsnr[identityIndex] >= 55.0, "expected >= 55 dB at scale 1.0");
        check("no sharpening at identity scale (auto strength 0)",
              strengthUsed[identityIndex] <= 1e-6 && fabs(acutRatio[identityIndex] - 1.0) < 1e-3,
              "strength must be 0 and the image unchanged at scale 1.0");
        BOOL acutanceOK = YES;
        BOOL fidelityOK = YES;
        for (int i = 0; i < identityIndex; i++) {
            // Weak auto strength at a mild upscale (0.75x -> 0.117) still gives a measurable gain.
            if (acutRatio[i] < 1.02) acutanceOK = NO;
            // Sharpening is an intentional fidelity-vs-acutance trade on an upscale; keep it bounded.
            if (sharpPsnr[i] < bilinearPsnr[i] - 1.5) fidelityOK = NO;
        }
        check("sharpening raises edge acutance at every upscaled scale", acutanceOK,
              "expected >= 1.02x the bilinear edge energy");
        check("foveal sharpening gain shrinks as the upscale shrinks",
              acutRatio[0] > acutRatio[identityIndex - 1],
              "aggressive upscales must gain more acutance than mild ones");
        check("sharpening stays within a bounded fidelity trade", fidelityOK,
              "sharp PSNR must stay within 1.5 dB of bilinear");
        printf("[m8-quality-ladder] %d checks, %d failed\n", gChecks, gFailures);
        printf(gFailures == 0 ? "[m8-quality-ladder] RESULT: PASS\n"
                              : "[m8-quality-ladder] RESULT: FAIL\n");
        return gFailures == 0 ? 0 : 1;
    }
}
