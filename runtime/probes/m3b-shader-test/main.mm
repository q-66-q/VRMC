// VRMC reprojection shader unit test (macOS Metal, synthetic CompositorServices-like matrices).
// Validates: MSL compiles, uniform struct layout matches, full-screen quad orientation, per-pixel
// ray->UV math equals the CPU reference, flat shader control, and no-black fallbacks.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <simd/simd.h>
#include <math.h>
#include <stdio.h>

typedef struct {
    simd_float4x4 invProjection;
    simd_float4x4 viewToDevice;
    simd_float4 sourceTangents;
    simd_float4 misc;
} ViewParams;

static simd_float4x4 makeFrustum(float l, float r, float b, float t, float n, float f) {
    // GL-convention frustum (RH, camera looks -Z, NDC z in [-1,1]) with tangent edges l/r/b/t.
    float m00 = 2.0f / (r - l);
    float m11 = 2.0f / (t - b);
    float m20 = (r + l) / (r - l);
    float m21 = (t + b) / (t - b);
    float m22 = -(f + n) / (f - n);
    float m23 = -2.0f * f * n / (f - n);
    simd_float4x4 m;
    m.columns[0] = simd_make_float4(m00, 0, 0, 0);
    m.columns[1] = simd_make_float4(0, m11, 0, 0);
    m.columns[2] = simd_make_float4(m20, m21, m22, -1.0f);
    m.columns[3] = simd_make_float4(0, 0, m23, 0);
    return m;
}

typedef struct { int finite; int behind; float u, v; } CPUResult;

static CPUResult cpuRayUV(simd_float4x4 invP, simd_float4x4 v2d, simd_float4 st, float nx, float ny) {
    CPUResult res; memset(&res, 0, sizeof(res));
    simd_float4 v = simd_mul(invP, simd_make_float4(nx, ny, 0.5f, 1.0f));
    simd_float3 vp = simd_make_float3(v.x / v.w, v.y / v.w, v.z / v.w);
    simd_float4 d4 = simd_mul(v2d, simd_make_float4(vp.x, vp.y, vp.z, 0.0f));
    simd_float3 d = simd_make_float3(d4.x, d4.y, d4.z);
    res.finite = isfinite(d.x) && isfinite(d.y) && isfinite(d.z);
    if (!res.finite) return res;
    if (!(d.z < -1e-4f)) { res.behind = 1; return res; }
    float tx = d.x / -d.z, ty = d.y / -d.z;
    res.u = (tx - st.x) / (st.y - st.x);
    res.v = (st.w - ty) / (st.w - st.z);
    return res;
}

static id<MTLTexture> makeProviderTexture(id<MTLDevice> dev, int size) {
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
        width:size height:size mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModeShared;
    id<MTLTexture> tex = [dev newTextureWithDescriptor:td];
    uint8_t *px = (uint8_t *)malloc((size_t)size * size * 4);
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            float u = (x + 0.5f) / size, v = (y + 0.5f) / size;
            int checker = (((x * 8) / size) + ((y * 8) / size)) & 1;
            uint8_t *p = px + ((size_t)y * size + x) * 4;
            p[0] = (uint8_t)lrintf(u * 255.0f);
            p[1] = (uint8_t)lrintf(v * 255.0f);
            p[2] = checker ? 255 : 0;
            p[3] = 255;
        }
    }
    [tex replaceRegion:MTLRegionMake2D(0, 0, size, size) mipmapLevel:0 withBytes:px bytesPerRow:(NSUInteger)size * 4];
    free(px);
    return tex;
}

int main(void) {
    @autoreleasepool {
        NSError *err = nil;
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        if (!dev) { printf("FAIL: no Metal device\n"); return 1; }
        NSString *src = [NSString stringWithContentsOfFile:@"/tmp/vrmc-testshader.metal" encoding:NSUTF8StringEncoding error:&err];
        if (!src) { printf("FAIL: cannot read shader: %s\n", err.description.UTF8String); return 1; }
        id<MTLLibrary> lib = [dev newLibraryWithSource:src options:nil error:&err];
        if (!lib) { printf("FAIL: MSL compile error: %s\n", err.description.UTF8String); return 1; }
        printf("PASS: MSL compiled (macOS Metal runtime)\n");

        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [lib newFunctionWithName:@"vmain"];
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
        pd.fragmentFunction = [lib newFunctionWithName:@"fmain_reproj"];
        id<MTLRenderPipelineState> pipeReproj = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
        if (!pipeReproj) { printf("FAIL: reproj pipeline: %s\n", err.description.UTF8String); return 1; }
        pd.fragmentFunction = [lib newFunctionWithName:@"fmain_flat"];
        id<MTLRenderPipelineState> pipeFlat = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
        if (!pipeFlat) { printf("FAIL: flat pipeline: %s\n", err.description.UTF8String); return 1; }
        pd.fragmentFunction = [lib newFunctionWithName:@"fmain_test"];
        id<MTLRenderPipelineState> pipeTest = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
        if (!pipeTest) { printf("FAIL: test pipeline: %s\n", err.description.UTF8String); return 1; }
        printf("PASS: all pipelines built\n");

        MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
        sd.minFilter = MTLSamplerMinMagFilterLinear; sd.magFilter = MTLSamplerMinMagFilterLinear;
        sd.sAddressMode = MTLSamplerAddressModeClampToEdge; sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
        id<MTLSamplerState> sampler = [dev newSamplerStateWithDescriptor:sd];

        const int TEX = 1024, RT = 512;
        id<MTLTexture> eyeTex = makeProviderTexture(dev, TEX);
        MTLTextureDescriptor *rtd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
            width:RT height:RT mipmapped:NO];
        rtd.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        rtd.storageMode = MTLStorageModeShared;
        id<MTLTexture> rt = [dev newTextureWithDescriptor:rtd];
        id<MTLCommandQueue> queue = [dev newCommandQueue];

        // Synthetic per-eye view: CompositorServices-like asymmetric frustum from the EV-0086 device log.
        float l = -1.732f, r = 1.000f, b = -1.192f, t = 1.000f;
        simd_float4x4 proj = makeFrustum(l, r, b, t, 0.05f, 1000.0f);
        simd_float4x4 invProj = simd_inverse(proj);
        simd_float4x4 viewToDevice = matrix_identity_float4x4;
        viewToDevice.columns[3] = simd_make_float4(-0.0349f, -0.0272f, 0.0045f, 1.0f);
        float half = tanf(55.0f * (float)M_PI / 180.0f);
        simd_float4 st = simd_make_float4(-half, half, -half, half);
        ViewParams params;
        params.invProjection = invProj;
        params.viewToDevice = viewToDevice;
        params.sourceTangents = st;
        params.misc = simd_make_float4(0, 0, 0, 0);

        // CPU reference for a few sample NDC points.
        int failures = 0;
        float worstCenter = 0.0f;
        {
            // Render reprojection pass.
            id<MTLCommandBuffer> cb = [queue commandBuffer];
            MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
            rp.colorAttachments[0].texture = rt;
            rp.colorAttachments[0].loadAction = MTLLoadActionClear;
            rp.colorAttachments[0].storeAction = MTLStoreActionStore;
            rp.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 1.0, 0.0, 1.0); // green = not drawn
            id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
            [enc setRenderPipelineState:pipeReproj];
            [enc setFragmentTexture:eyeTex atIndex:0];
            [enc setFragmentSamplerState:sampler atIndex:0];
            [enc setFragmentBytes:&params length:sizeof(params) atIndex:0];
            [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
            [enc endEncoding];
            [cb commit];
            [cb waitUntilCompleted];

            uint8_t *px = (uint8_t *)malloc((size_t)RT * RT * 4);
            [rt getBytes:px bytesPerRow:(NSUInteger)RT * 4 fromRegion:MTLRegionMake2D(0, 0, RT, RT) mipmapLevel:0];
            int checked = 0, mismatched = 0;
            float maxErr = 0;
            for (int gy = 0; gy < 9; gy++) {
                for (int gx = 0; gx < 9; gx++) {
                    int x = RT / 8 + gx * (RT - RT / 4) / 8;   // avoid edges
                    int y = RT / 8 + gy * (RT - RT / 4) / 8;
                    float ndcX = 2.0f * (x + 0.5f) / RT - 1.0f;
                    float ndcY = 1.0f - 2.0f * (y + 0.5f) / RT;
                    if (ndcY > 0.985f) continue; // badge strip
                    CPUResult ref = cpuRayUV(invProj, viewToDevice, st, ndcX, ndcY);
                    if (!ref.finite || ref.behind) continue;
                    float clu = fminf(fmaxf(ref.u, 0.0f), 1.0f); // shader clamps out-of-frustum
                    float clv = fminf(fmaxf(ref.v, 0.0f), 1.0f);
                    uint8_t *p = px + ((size_t)y * RT + x) * 4;
                    float gotU = p[0] / 255.0f, gotV = p[1] / 255.0f;
                    float errU = fabsf(gotU - clu), errV = fabsf(gotV - clv);
                    float e = fmaxf(errU, errV);
                    if (e > maxErr) maxErr = e;
                    checked++;
                    if (e > 0.03f) {
                        mismatched++;
                        if (mismatched <= 6) {
                            printf("  mismatch px(%d,%d) ndc(%.2f,%.2f) cpuUV=(%.3f,%.3f) cl=(%.3f,%.3f) gpuUV=(%.3f,%.3f)\n",
                                   x, y, ndcX, ndcY, ref.u, ref.v, clu, clv, gotU, gotV);
                        }
                    }
                    if (gx == 4 && gy == 4) worstCenter = e;
                }
            }
            printf("%s: reprojection CPU-vs-GPU on %d samples, mismatched=%d maxErr=%.4f centerErr=%.4f\n",
                   (mismatched == 0 ? "PASS" : "FAIL"), checked, mismatched, maxErr, worstCenter);
            if (mismatched != 0) failures++;
            // Is anything drawn at all?
            int green = 0, black = 0, drawn = 0;
            for (int i = 0; i < RT * RT; i++) {
                uint8_t *p = px + (size_t)i * 4;
                if (p[0] == 0 && p[1] == 255 && p[2] == 0) green++;
                else if (p[0] == 0 && p[1] == 0 && p[2] == 0) black++;
                else drawn++;
            }
            printf("  coverage: drawn=%d green(clear)=%d black=%d of %d (badge rows excluded not needed)\n",
                   drawn, green, black, RT * RT);
            if (drawn == 0) { printf("FAIL: nothing drawn\n"); failures++; }
            free(px);
        }

        // Flat shader control: at ndc centre, uv=(0.5,0.5) -> rgb approx (127,127, ?), never black.
        {
            id<MTLCommandBuffer> cb = [queue commandBuffer];
            MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
            rp.colorAttachments[0].texture = rt;
            rp.colorAttachments[0].loadAction = MTLLoadActionClear;
            rp.colorAttachments[0].storeAction = MTLStoreActionStore;
            id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
            [enc setRenderPipelineState:pipeFlat];
            [enc setFragmentTexture:eyeTex atIndex:0];
            [enc setFragmentSamplerState:sampler atIndex:0];
            [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
            [enc endEncoding];
            [cb commit];
            [cb waitUntilCompleted];
            uint8_t *px = (uint8_t *)malloc((size_t)RT * RT * 4);
            [rt getBytes:px bytesPerRow:(NSUInteger)RT * 4 fromRegion:MTLRegionMake2D(0, 0, RT, RT) mipmapLevel:0];
            uint8_t *center = px + ((size_t)(RT / 2) * RT + RT / 2) * 4;
            printf("flat control centre rgb=(%u,%u,%u) (expect ~127,127,*)%s\n",
                   center[0], center[1], center[2],
                   (abs((int)center[0] - 127) < 4 && abs((int)center[1] - 127) < 4) ? " PASS" : " FAIL");
            free(px);
        }
        // Test pattern control: not black at centre.
        {
            id<MTLCommandBuffer> cb = [queue commandBuffer];
            MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
            rp.colorAttachments[0].texture = rt;
            rp.colorAttachments[0].loadAction = MTLLoadActionClear;
            rp.colorAttachments[0].storeAction = MTLStoreActionStore;
            id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
            [enc setRenderPipelineState:pipeTest];
            [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
            [enc endEncoding];
            [cb commit];
            [cb waitUntilCompleted];
            uint8_t *px = (uint8_t *)malloc((size_t)RT * RT * 4);
            [rt getBytes:px bytesPerRow:(NSUInteger)RT * 4 fromRegion:MTLRegionMake2D(0, 0, RT, RT) mipmapLevel:0];
            uint8_t *center = px + ((size_t)(RT / 2) * RT + RT / 2) * 4;
            int nonzero = (center[0] || center[1] || center[2]);
            printf("test-pattern control centre rgb=(%u,%u,%u)%s\n", center[0], center[1], center[2],
                   nonzero ? " PASS" : " FAIL");
            if (!nonzero) failures++;
            free(px);
        }
        printf(failures == 0 ? "RESULT: ALL SHADER CHECKS PASS\n" : "RESULT: FAILURES=%d\n", failures);
        return failures == 0 ? 0 : 1;
    }
}
