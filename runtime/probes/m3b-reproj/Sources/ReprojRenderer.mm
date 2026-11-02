// M3b — standalone visionOS CompositorServices reprojection validation probe.
//
// Question under test (EV-0086: immersive is completely black on device although the compositor samples
// both provider eye textures): is the black caused by (a) the compositor's reprojection math
// (projection/view conventions or ray->UV mapping) or (b) bad/black provider eye textures / alpha?
//
// This probe reproduces the exact VRMCCompositor.mm pipeline on the visionOS simulator:
//   * dedicated CompositorLayer, rgba16Float, foveation off, dedicated render NSThread (Apple sample pattern)
//   * logs view count, cp_view_get_transform, cp_drawable_compute_projection, derived tangents,
//     and the exact CPU ray->UV math of VRMCCompositor.mm (center, corners, grid; z-sign/coverage/NaN)
//   * builds a synthetic 1024x1024 provider eye texture, samples it through the EXACT fragment shader
//     copied from VRMCCompositor.mm, renders the old flat sampler as a control, and a debug branch-color
//     variant (magenta = uv outside provider frustum, blue = ray behind camera, black = other)
//   * blit-reads back the drawable color texture, validates pixels against a CPU reference of the same
//     math, and writes small PNGs + a log to Documents/ (pulled back to runtime/probes/m3b-reproj/results/)
//   * additionally reconstructs the EV-0086 device views from the device log (tangents + pos + fwd) and
//     runs the same CPU math + shader on them, so the device case is testable without the device.
//
// Simulator output is code/convention evidence only; it is NOT product/device evidence (AGENT.md section 9).
#include "Bridging.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include <simd/simd.h>
#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------------------------
static FILE *gLog = NULL;
static NSString *gDocsDir = nil;
static NSString *gResultsDir = nil;
static NSMutableArray<NSString *> *gSummary = nil;

static void mLog(const char *fmt, ...) {
    char line[4096];
    va_list args;
    va_start(args, fmt);
    vsnprintf(line, sizeof(line), fmt, args);
    va_end(args);
    NSLog(@"[m3b] %s", line);
    if (gLog) {
        fprintf(gLog, "[m3b] %s\n", line);
        fflush(gLog);
    }
}

static void sumLog(NSString *line) {
    if (gSummary) [gSummary addObject:line];
}

static void openLog(void) {
    if (gLog) return;
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    gDocsDir = paths.firstObject;
    gResultsDir = [gDocsDir stringByAppendingPathComponent:@"results"];
    [[NSFileManager defaultManager] createDirectoryAtPath:gResultsDir withIntermediateDirectories:YES attributes:nil error:nil];
    gLog = fopen([[gDocsDir stringByAppendingPathComponent:@"m3b.log"] UTF8String], "a");
    if (!gSummary) gSummary = [NSMutableArray array];
}

// ---------------------------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------------------------
static const int kPatternSize = 1024;
static const float kDeg2Rad = 0.017453292519943295f;

// Provider reports half-angles 55 deg (110 deg full) for each eye (EV-0086: L=R=(-1.428,1.428,-1.428,1.428)).
static const float kProviderTan = 1.4281480f; // tan(55 deg)

static std::vector<uint8_t> gPattern;       // alpha = 255
static std::vector<uint8_t> gPatternAlpha0; // alpha = 0 (used to test whether alpha matters)

// EV-0086 device log, verbatim:
//   view 0 (left)  tangents l/r/d/u=(-1.732,1.000,-1.192,1.000) pos=(-0.0349,-0.0272,0.0045) fwd=(0.001,0.014,-1.000)
//   view 1 (right) tangents l/r/d/u=(-1.000,1.732,-1.192,1.000) pos=( 0.0300,-0.0251,0.0025) fwd=(0.003,0.016,-1.000)
struct DeviceView {
    const char *name;
    simd_float3 pos;
    simd_float3 fwd;
    float l, r, d, u;
};
static const DeviceView kDeviceViews[2] = {
    {"L", simd_make_float3(-0.0349f, -0.0272f, 0.0045f), simd_make_float3(0.001f, 0.014f, -1.0f),
     -1.732f, 1.000f, -1.192f, 1.000f},
    {"R", simd_make_float3(0.0300f, -0.0251f, 0.0025f), simd_make_float3(0.003f, 0.016f, -1.0f),
     -1.000f, 1.732f, -1.192f, 1.000f},
};

// ---------------------------------------------------------------------------------------------
// Shaders — f_reproj / f_reproj_alpha1 are copied VERBATIM from runtime/native-shell/Sources/
// VRMCCompositor.mm (kShaderSource). Debug/flat variants share the same math.
// ---------------------------------------------------------------------------------------------
static const char *kShaderSource = R"MSL(
#include <metal_stdlib>
using namespace metal;

struct ViewParams { float4x4 invProjection; float4x4 viewToDevice; float4 sourceTangents; };
struct VOut { float4 pos [[position]]; float2 ndc; };

vertex VOut vmain(uint vid [[vertex_id]]) {
    float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
    VOut o;
    o.pos = float4(p[vid], 0, 1);
    o.ndc = p[vid];
    return o;
}

// EXACT copy of VRMCCompositor.mm fmain.
fragment float4 f_reproj(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                         sampler s [[sampler(0)]], constant ViewParams &vp [[buffer(0)]]) {
    float4 v = vp.invProjection * float4(in.ndc, 0.5, 1);
    float3 d = (vp.viewToDevice * float4(v.xyz / v.w, 0)).xyz;
    if (d.z > -1e-4) return float4(0, 0, 0, 1);
    float2 t = d.xy / -d.z;
    float4 st = vp.sourceTangents;
    float2 uv = float2((t.x - st.x) / (st.y - st.x), (st.w - t.y) / (st.w - st.z));
    if (any(uv < 0.0) || any(uv > 1.0)) return float4(0, 0, 0, 1);
    return tex.sample(s, uv);
}

// Same math, but the early-out branches are color coded so branch dominance is visible in the readback:
//   CYAN    = ray is behind the camera (d.z > -1e-4)
//   MAGENTA = ray points outside the provider frustum (uv outside [0,1])
//   sample  = mapped inside the provider image (alpha forced to 1)
fragment float4 f_reproj_debug(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                               sampler s [[sampler(0)]], constant ViewParams &vp [[buffer(0)]]) {
    float4 v = vp.invProjection * float4(in.ndc, 0.5, 1);
    float3 d = (vp.viewToDevice * float4(v.xyz / v.w, 0)).xyz;
    if (d.z > -1e-4) return float4(0, 1, 1, 1);
    float2 t = d.xy / -d.z;
    float4 st = vp.sourceTangents;
    float2 uv = float2((t.x - st.x) / (st.y - st.x), (st.w - t.y) / (st.w - st.z));
    if (any(uv < 0.0) || any(uv > 1.0)) return float4(1, 0, 1, 1);
    float4 c = tex.sample(s, uv);
    return float4(c.rgb, 1.0);
}

// EXACT copy of f_reproj plus forcing alpha=1 on the sampled path.
fragment float4 f_reproj_alpha1(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                sampler s [[sampler(0)]], constant ViewParams &vp [[buffer(0)]]) {
    float4 v = vp.invProjection * float4(in.ndc, 0.5, 1);
    float3 d = (vp.viewToDevice * float4(v.xyz / v.w, 0)).xyz;
    if (d.z > -1e-4) return float4(0, 0, 0, 1);
    float2 t = d.xy / -d.z;
    float4 st = vp.sourceTangents;
    float2 uv = float2((t.x - st.x) / (st.y - st.x), (st.w - t.y) / (st.w - st.z));
    if (any(uv < 0.0) || any(uv > 1.0)) return float4(0, 0, 0, 1);
    float4 c = tex.sample(s, uv);
    return float4(c.rgb, 1.0);
}

// Control: the old "flat" fullscreen sampler (stretch the eye image over the drawable).
fragment float4 f_flat(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                       sampler s [[sampler(0)]], constant ViewParams &vp [[buffer(0)]]) {
    float2 uv = float2(in.ndc.x * 0.5 + 0.5, 0.5 - in.ndc.y * 0.5) + vp.sourceTangents.xy * 0.0;
    return tex.sample(s, uv);
}
)MSL";

// ---------------------------------------------------------------------------------------------
// CPU math helpers (mirror of the shader + reconstruction of the device views)
// ---------------------------------------------------------------------------------------------
namespace m3b {

struct ProbeViewParams {
    simd_float4x4 invProjection;
    simd_float4x4 viewToDevice;
    simd_float4 sourceTangents;
};
static_assert(sizeof(ProbeViewParams) == 144, "MSL ViewParams layout must be 144 bytes");

// Standard asymmetric perspective with reverse-Z (near -> 1, far -> 0), as CompositorServices uses.
static simd_float4x4 makeProjectionFromTangents(float l, float r, float d, float u, float nearZ, float farZ) {
    float A = 2.0f / (r - l);
    float B = (r + l) / (r - l);
    float C = 2.0f / (u - d);
    float D = (u + d) / (u - d);
    float E = nearZ / (farZ - nearZ);
    float F = nearZ * farZ / (farZ - nearZ);
    simd_float4x4 m;
    m.columns[0] = simd_make_float4(A, 0.0f, 0.0f, 0.0f);
    m.columns[1] = simd_make_float4(0.0f, C, 0.0f, 0.0f);
    m.columns[2] = simd_make_float4(B, D, E, -1.0f);
    m.columns[3] = simd_make_float4(0.0f, 0.0f, F, 0.0f);
    return m;
}

// View->device transform reconstructed from the logged pos/fwd (rotation roll unknown -> parameterised).
static simd_float4x4 makeViewToDevice(simd_float3 pos, simd_float3 fwd, float rollRad) {
    simd_float3 back = -simd_normalize(fwd);
    simd_float3 upHint = simd_make_float3(0.0f, 1.0f, 0.0f);
    simd_float3 right0 = simd_normalize(simd_cross(upHint, back));
    simd_float3 up0 = simd_cross(back, right0);
    float c = cosf(rollRad);
    float s = sinf(rollRad);
    simd_float3 right = c * right0 + s * up0;
    simd_float3 up = -s * right0 + c * up0;
    simd_float4x4 m;
    m.columns[0] = simd_make_float4(right, 0.0f);
    m.columns[1] = simd_make_float4(up, 0.0f);
    m.columns[2] = simd_make_float4(back, 0.0f);
    m.columns[3] = simd_make_float4(pos, 1.0f);
    return m;
}

// Same derivation as VRMCCompositor.mm viewTangents().
static simd_float4 derivedViewTangents(simd_float4x4 invProjection) {
    simd_float4 tangents = simd_make_float4(0.0f, 0.0f, 0.0f, 0.0f);
    const float ndc[4][2] = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};
    for (int k = 0; k < 4; k++) {
        simd_float4 v = simd_mul(invProjection, simd_make_float4(ndc[k][0], ndc[k][1], 0.5f, 1.0f));
        simd_float3 p = simd_make_float3(v.x, v.y, v.z) / v.w;
        tangents[k] = (k < 2 ? p.x : p.y) / -p.z;
    }
    return tangents;
}

struct RaySample {
    bool valid = true;
    bool nan = false;
    bool behind = false;
    bool uvIn = false;
    float dz = 0.0f;
    float tx = 0.0f, ty = 0.0f;
    float u = 0.0f, v = 0.0f;
};

// EXACT CPU mirror of the fragment shader's ray->UV math.
static RaySample computeRaySample(simd_float4x4 invProjection, simd_float4x4 viewToDevice,
                                  simd_float4 sourceTangents, float nx, float ny) {
    RaySample s;
    simd_float4 v = simd_mul(invProjection, simd_make_float4(nx, ny, 0.5f, 1.0f));
    if (!std::isfinite(v.w) || std::fabs(v.w) < 1e-12f) {
        s.valid = false;
        s.nan = true;
        return s;
    }
    simd_float3 p = simd_make_float3(v.x / v.w, v.y / v.w, v.z / v.w);
    simd_float4 dd = simd_mul(viewToDevice, simd_make_float4(p, 0.0f));
    simd_float3 d = simd_make_float3(dd.x, dd.y, dd.z);
    s.dz = d.z;
    if (!std::isfinite(d.x) || !std::isfinite(d.y) || !std::isfinite(d.z)) {
        s.valid = false;
        s.nan = true;
        return s;
    }
    if (d.z > -1e-4f) {
        s.behind = true;
        return s;
    }
    s.tx = d.x / -d.z;
    s.ty = d.y / -d.z;
    s.u = (s.tx - sourceTangents.x) / (sourceTangents.y - sourceTangents.x);
    s.v = (sourceTangents.w - s.ty) / (sourceTangents.w - sourceTangents.z);
    s.uvIn = std::isfinite(s.u) && std::isfinite(s.v) && s.u >= 0.0f && s.u <= 1.0f && s.v >= 0.0f && s.v <= 1.0f;
    if (!std::isfinite(s.u) || !std::isfinite(s.v)) {
        s.valid = false;
        s.nan = true;
    }
    return s;
}

// Bilinear CPU sample of the synthetic pattern, matching the Metal linear/clamp-to-edge sampler.
static void cpuSamplePattern(const std::vector<uint8_t> &pat, int size, float u, float v, float out[4]) {
    float fx = u * (float)size - 0.5f;
    float fy = v * (float)size - 0.5f;
    int x0 = (int)floorf(fx);
    int y0 = (int)floorf(fy);
    float tx = fx - (float)x0;
    float ty = fy - (float)y0;
    auto at = [&](int x, int y, int c) -> float {
        if (x < 0) x = 0;
        if (x >= size) x = size - 1;
        if (y < 0) y = 0;
        if (y >= size) y = size - 1;
        return (float)pat[((size_t)y * (size_t)size + (size_t)x) * 4 + (size_t)c] / 255.0f;
    };
    for (int c = 0; c < 4; c++) {
        float v00 = at(x0, y0, c);
        float v10 = at(x0 + 1, y0, c);
        float v01 = at(x0, y0 + 1, c);
        float v11 = at(x0 + 1, y0 + 1, c);
        out[c] = (v00 * (1.0f - tx) + v10 * tx) * (1.0f - ty) + (v01 * (1.0f - tx) + v11 * tx) * ty;
    }
}

static NSString *matrixRowsString(simd_float4x4 m) {
    NSMutableString *s = [NSMutableString string];
    for (int r = 0; r < 4; r++) {
        [s appendFormat:@"(%.6f %.6f %.6f %.6f)", m.columns[0][r], m.columns[1][r], m.columns[2][r], m.columns[3][r]];
        if (r < 3) [s appendString:@" "];
    }
    return s;
}

static float maxAbsRotationDiff(simd_float4x4 a, simd_float4x4 b) {
    float m = 0.0f;
    for (int c = 0; c < 3; c++) {
        for (int r = 0; r < 3; r++) {
            m = std::max(m, std::fabs(a.columns[c][r] - b.columns[c][r]));
        }
    }
    return m;
}

// Rotation part of a view->device matrix inverted (transpose for an orthonormal basis), translation zero.
static simd_float4x4 inverseRotation(simd_float4x4 m) {
    simd_float4x4 r;
    for (int c = 0; c < 3; c++) {
        r.columns[c] = simd_make_float4(m.columns[0][c], m.columns[1][c], m.columns[2][c], 0.0f);
    }
    r.columns[3] = simd_make_float4(0.0f, 0.0f, 0.0f, 1.0f);
    return r;
}

static void buildPatterns(void) {
    gPattern.assign((size_t)kPatternSize * kPatternSize * 4, 0);
    gPatternAlpha0.assign((size_t)kPatternSize * kPatternSize * 4, 0);
    const int n = kPatternSize;
    for (int y = 0; y < n; y++) {
        for (int x = 0; x < n; x++) {
            size_t o = ((size_t)y * n + x) * 4;
            int cell = ((x / 128) + (y / 128)) & 1;
            int g = cell ? 80 : 40;
            int r = g, gg = g, b = g;
            // Grid lines every 64 px (2 px wide) to make warping obvious.
            if ((x % 64) < 2 || (y % 64) < 2) {
                r = gg = b = 240;
            }
            // Distinct corner blocks: TL red, TR green, BL blue, BR yellow. Any flip/rotation is visible.
            if (x < 128 && y < 128) {
                r = 220; gg = 30; b = 30;
            } else if (x >= n - 128 && y < 128) {
                r = 30; gg = 200; b = 40;
            } else if (x < 128 && y >= n - 128) {
                r = 30; gg = 60; b = 220;
            } else if (x >= n - 128 && y >= n - 128) {
                r = 230; gg = 200; b = 20;
            }
            // Asymmetric "T" marker in the upper right region (detects mirroring).
            if (y >= 200 && y < 208 && x >= 640 && x < 820) {
                r = gg = b = 255;
            }
            if (x >= 700 && x < 708 && y >= 140 && y < 260) {
                r = gg = b = 255;
            }
            // Centre crosshair (white).
            bool hx = std::abs(x - n / 2) < 3;
            bool hy = std::abs(y - n / 2) < 3;
            if ((hx && std::abs(y - n / 2) < 90) || (hy && std::abs(x - n / 2) < 90)) {
                r = gg = b = 255;
            }
            gPattern[o + 0] = (uint8_t)r;
            gPattern[o + 1] = (uint8_t)gg;
            gPattern[o + 2] = (uint8_t)b;
            gPattern[o + 3] = 255;
            gPatternAlpha0[o + 0] = (uint8_t)r;
            gPatternAlpha0[o + 1] = (uint8_t)gg;
            gPatternAlpha0[o + 2] = (uint8_t)b;
            gPatternAlpha0[o + 3] = 0;
        }
    }
}

struct FramePlan {
    int variant;      // 0=exact reproj, 1=debug branches, 2=flat control, 3=exact+alpha1
    bool useDepth;
    bool useRRM;
    bool alpha0;      // use the alpha=0 synthetic texture
    const char *name;
};
static const FramePlan kFramePlan[] = {
    {0, true, true, false, "drawable-01-reproj-depth"},
    {1, true, true, false, "drawable-02-debug-depth"},
    {2, true, true, false, "drawable-03-flat-depth"},
    {0, false, true, false, "drawable-04-reproj-nodepth"},
    {3, true, true, true, "drawable-05-reproj-alpha1-alpha0tex"},
    {0, true, true, true, "drawable-06-reproj-alpha0tex"},
    {0, true, false, false, "drawable-07-reproj-norrm"},
    {0, true, true, false, "drawable-08-reproj-final"},
};
static const int kFramePlanCount = (int)(sizeof(kFramePlan) / sizeof(kFramePlan[0]));

static const char *variantName(int v) {
    switch (v) {
        case 0: return "reproj";
        case 1: return "debug";
        case 2: return "flat";
        case 3: return "reproj-alpha1";
        default: return "unknown";
    }
}

static const char *fragmentName(int v) {
    switch (v) {
        case 0: return "f_reproj";
        case 1: return "f_reproj_debug";
        case 2: return "f_flat";
        case 3: return "f_reproj_alpha1";
        default: return "f_reproj";
    }
}

}  // namespace m3b

// ---------------------------------------------------------------------------------------------
// Renderer
// ---------------------------------------------------------------------------------------------
@interface M3BRenderer : NSObject
- (instancetype)initWithLayerRenderer:(cp_layer_renderer_t)layerRenderer;
- (void)run;
@end

@implementation M3BRenderer {
    cp_layer_renderer_t _lr;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLLibrary> _library;
    id<MTLSamplerState> _sampler;
    id<MTLTexture> _syntheticTex;
    id<MTLTexture> _syntheticAlpha0Tex;

    MTLPixelFormat _colorFormat;
    MTLPixelFormat _depthFormat;
    id<MTLRenderPipelineState> _pipeDrawDepth[4];
    id<MTLRenderPipelineState> _pipeDrawNoDepth[4];
    id<MTLRenderPipelineState> _pipeOffscreen[4];

    BOOL _didStaticAnalysis;
    int _liveViewCount;
    m3b::ProbeViewParams _liveParams[2];
    m3b::ProbeViewParams _deviceParams[2];
    int _lastPhase;
}

- (instancetype)initWithLayerRenderer:(cp_layer_renderer_t)layerRenderer {
    self = [super init];
    if (self) {
        _lr = layerRenderer;
        _lastPhase = -1;
    }
    return self;
}

- (void)run {
    mLog("render thread started");
    cp_layer_renderer_wait_until_running(_lr);
    mLog("layer renderer running");
    _device = cp_layer_renderer_get_device(_lr);
    _queue = [_device newCommandQueue];
    mLog("device=%s os=%s", _device.name.UTF8String,
         [[[NSProcessInfo processInfo] operatingSystemVersionString] UTF8String]);

    cp_layer_renderer_configuration_t cfg = cp_layer_renderer_get_configuration(_lr);
    _colorFormat = MTLPixelFormatInvalid;
    _depthFormat = MTLPixelFormatInvalid;
    if (cfg != nullptr) {
        _colorFormat = cp_layer_renderer_configuration_get_color_format(cfg);
        _depthFormat = cp_layer_renderer_configuration_get_depth_format(cfg);
        simd_float2 defRange = cp_layer_renderer_configuration_get_default_depth_range(cfg);
        mLog("CONFIG colorFormat=%lu depthFormat=%lu layout=%d foveationEnabled=%d defaultDepthRange far=%.4f near=%.4f",
             (unsigned long)_colorFormat, (unsigned long)_depthFormat,
             (int)cp_layer_renderer_configuration_get_layout(cfg),
             (int)cp_layer_renderer_configuration_get_foveation_enabled(cfg), defRange.x, defRange.y);
    } else {
        mLog("CONFIG: cp_layer_renderer_get_configuration returned null");
    }
    if (_colorFormat == MTLPixelFormatInvalid) _colorFormat = MTLPixelFormatRGBA16Float;
    if (_depthFormat != MTLPixelFormatInvalid) {
        mLog("depth attachment format = %lu", (unsigned long)_depthFormat);
    } else {
        mLog("depth attachment format = invalid (no depth textures expected)");
    }

    m3b::buildPatterns();
    [self buildResources];

    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    int frameIndex = 0;
    while (true) {
        @autoreleasepool {
            cp_layer_renderer_state state = cp_layer_renderer_get_state(_lr);
            if (state == cp_layer_renderer_state_invalidated) {
                mLog("layer invalidated at frame %d", frameIndex);
                break;
            }
            if (state == cp_layer_renderer_state_paused) {
                cp_layer_renderer_wait_until_running(_lr);
                continue;
            }
            if (CFAbsoluteTimeGetCurrent() - startTime > 240.0) {
                mLog("wall-clock limit reached at frame %d", frameIndex);
                break;
            }
            cp_frame_t frame = cp_layer_renderer_query_next_frame(_lr);
            if (frame == nullptr) {
                continue;
            }
            cp_frame_timing_t timing = cp_frame_predict_timing(frame);
            if (timing == nullptr) {
                continue;
            }
            cp_frame_start_update(frame);
            cp_frame_end_update(frame);
            cp_time_wait_until(cp_frame_timing_get_optimal_input_time(timing));
            if (cp_layer_renderer_get_state(_lr) != cp_layer_renderer_state_running) {
                mLog("state not running after timing wait at frame %d; exiting", frameIndex);
                break;
            }
            cp_frame_start_submission(frame);
            cp_drawable_t drawable = cp_frame_query_drawable(frame);
            if (drawable == nullptr) {
                cp_frame_end_submission(frame);
                continue;
            }

            if (frameIndex == 0) {
                [self analyzeStatic:drawable];
                [self renderDrawable:drawable
                             variant:0
                            useDepth:YES
                              useRRM:YES
                             texture:_syntheticTex
                        readbackName:nil
                           saveRaw:NO];
            } else if (frameIndex - 1 < m3b::kFramePlanCount) {
                const m3b::FramePlan &plan = m3b::kFramePlan[frameIndex - 1];
                id<MTLTexture> tex = plan.alpha0 ? _syntheticAlpha0Tex : _syntheticTex;
                mLog("FRAME %d plan=%s variant=%s depth=%d rrm=%d alpha0=%d", frameIndex, plan.name,
                     m3b::variantName(plan.variant), (int)plan.useDepth, (int)plan.useRRM, (int)plan.alpha0);
                [self renderDrawable:drawable
                             variant:plan.variant
                            useDepth:plan.useDepth
                              useRRM:plan.useRRM
                             texture:tex
                        readbackName:[NSString stringWithUTF8String:plan.name]
                           saveRaw:frameIndex <= 2];
            } else {
                // Phase cycling for simulator screenshots (alpha / alpha-forced comparisons).
                int phaseFrame = frameIndex - (m3b::kFramePlanCount + 1);
                int phase = (phaseFrame / 150) % 3;
                if (phase != _lastPhase) {
                    _lastPhase = phase;
                    mLog("PHASE %d name=%s frame=%d t=%.3f", phase,
                         phase == 0 ? "normal-alpha255" : (phase == 1 ? "alpha0-texture" : "alpha1-forced-alpha0-texture"),
                         frameIndex, CFAbsoluteTimeGetCurrent());
                }
                int variant = (phase == 2) ? 3 : 0;
                id<MTLTexture> tex = (phase >= 1) ? _syntheticAlpha0Tex : _syntheticTex;
                [self renderDrawable:drawable
                             variant:variant
                            useDepth:YES
                              useRRM:YES
                             texture:tex
                        readbackName:nil
                           saveRaw:NO];
            }

            cp_frame_end_submission(frame);
            frameIndex++;
            if (frameIndex == 1 || frameIndex % 120 == 0) {
                mLog("frame %d submitted", frameIndex);
            }
            if (frameIndex >= 1200) {
                mLog("frame limit reached");
                break;
            }
        }
    }

    NSString *done = [NSString stringWithFormat:@"done frames=%d ended=%.3f", frameIndex, CFAbsoluteTimeGetCurrent()];
    [done writeToFile:[gDocsDir stringByAppendingPathComponent:@"m3b-done.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    if (gSummary) {
        [[gSummary componentsJoinedByString:@"\n"] writeToFile:[gResultsDir stringByAppendingPathComponent:@"summary.txt"]
                                                  atomically:YES
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
    }
    mLog("DONE frames=%d", frameIndex);
}

// ---------------------------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------------------------
- (id<MTLTexture>)makeSyntheticTextureWithPattern:(const std::vector<uint8_t> *)pattern
                                              name:(NSString *)name {
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                  width:kPatternSize
                                                                                 height:kPatternSize
                                                                              mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModeShared;
    id<MTLTexture> tex = [_device newTextureWithDescriptor:td];
    if (tex == nil) {
        mLog("failed to create synthetic texture %s", name.UTF8String);
        return nil;
    }
    [tex replaceRegion:MTLRegionMake2D(0, 0, kPatternSize, kPatternSize)
           mipmapLevel:0
             withBytes:pattern->data()
           bytesPerRow:(NSUInteger)kPatternSize * 4];
    mLog("created synthetic provider eye texture %s (%dx%d rgba8unorm, alpha=%d)", name.UTF8String,
         kPatternSize, kPatternSize, (*pattern)[3] == 255 ? 255 : (int)(*pattern)[3]);
    return tex;
}

- (id<MTLRenderPipelineState>)makePipeline:(int)variant
                               colorFormat:(MTLPixelFormat)colorFormat
                               depthFormat:(MTLPixelFormat)depthFormat {
    NSError *err = nil;
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [_library newFunctionWithName:@"vmain"];
    pd.fragmentFunction = [_library newFunctionWithName:[NSString stringWithUTF8String:m3b::fragmentName(variant)]];
    pd.colorAttachments[0].pixelFormat = colorFormat;
    if (depthFormat != MTLPixelFormatInvalid) pd.depthAttachmentPixelFormat = depthFormat;
    id<MTLRenderPipelineState> ps = [_device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (ps == nil) {
        mLog("pipeline variant=%s colorFormat=%lu depthFormat=%lu failed: %s", m3b::variantName(variant),
             (unsigned long)colorFormat, (unsigned long)depthFormat, err.description.UTF8String);
    }
    return ps;
}

- (void)buildResources {
    NSError *err = nil;
    NSString *src = [NSString stringWithUTF8String:kShaderSource];
    _library = [_device newLibraryWithSource:src options:nil error:&err];
    if (_library == nil) {
        mLog("SHADER LIBRARY FAILED: %s", err.description.UTF8String);
        return;
    }
    mLog("shader library compiled");

    MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
    sd.minFilter = MTLSamplerMinMagFilterLinear;
    sd.magFilter = MTLSamplerMinMagFilterLinear;
    sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
    _sampler = [_device newSamplerStateWithDescriptor:sd];

    _syntheticTex = [self makeSyntheticTextureWithPattern:&gPattern name:@"alpha255"];
    _syntheticAlpha0Tex = [self makeSyntheticTextureWithPattern:&gPatternAlpha0 name:@"alpha0"];

    for (int v = 0; v < 4; v++) {
        _pipeDrawDepth[v] = [self makePipeline:v colorFormat:_colorFormat depthFormat:_depthFormat];
        _pipeDrawNoDepth[v] = [self makePipeline:v colorFormat:_colorFormat depthFormat:MTLPixelFormatInvalid];
        _pipeOffscreen[v] = [self makePipeline:v colorFormat:MTLPixelFormatRGBA16Float depthFormat:MTLPixelFormatInvalid];
    }
    int made = 0;
    for (int v = 0; v < 4; v++) {
        if (_pipeDrawDepth[v] || _pipeDrawNoDepth[v] || _pipeOffscreen[v]) made++;
    }
    mLog("pipelines: drawableDepth/drawableNoDepth/offscreen created for %d/4 variants (colorFormat=%lu depthFormat=%lu)",
         made, (unsigned long)_colorFormat, (unsigned long)_depthFormat);
}

// ---------------------------------------------------------------------------------------------
// Static analysis (first drawable): matrices, tangents, CPU ray->UV, offscreen shader validation
// ---------------------------------------------------------------------------------------------
- (void)analyzeStatic:(cp_drawable_t)drawable {
    if (_didStaticAnalysis) return;
    _didStaticAnalysis = YES;
    mLog("================= STATIC ANALYSIS (first drawable) =================");

    size_t views = cp_drawable_get_view_count(drawable);
    size_t texCount = cp_drawable_get_texture_count(drawable);
    size_t rrmCount = cp_drawable_get_rasterization_rate_map_count(drawable);
    simd_float2 depthRange = cp_drawable_get_depth_range(drawable);
    mLog("drawable: views=%zu textures=%zu rrmCount=%zu depthRange far=%.4f near=%.4f",
         views, texCount, rrmCount, depthRange.x, depthRange.y);
    sumLog([NSString stringWithFormat:@"sim: views=%zu textures=%zu rrmCount=%zu depthRange=(far %.4f near %.4f)",
            views, texCount, rrmCount, depthRange.x, depthRange.y]);

    _liveViewCount = (int)std::min<size_t>(views, 2);
    simd_float4 providerSt = simd_make_float4(-kProviderTan, kProviderTan, -kProviderTan, kProviderTan);

    for (int i = 0; i < (int)views; i++) {
        cp_view_t view = cp_drawable_get_view(drawable, (size_t)i);
        cp_view_texture_map_t tm = cp_view_get_view_texture_map(view);
        size_t texIndex = cp_view_texture_map_get_texture_index(tm);
        size_t sliceIndex = cp_view_texture_map_get_slice_index(tm);
        MTLViewport vp = cp_view_texture_map_get_viewport(tm);
        id<MTLTexture> colorTex = cp_drawable_get_color_texture(drawable, texIndex);
        id<MTLTexture> depthTex = cp_drawable_get_depth_texture(drawable, texIndex);
        id<MTLRasterizationRateMap> rrm = cp_drawable_get_rasterization_rate_map(drawable, texIndex);
        simd_float4x4 vt = cp_view_get_transform(view);
        simd_float4x4 proj = cp_drawable_compute_projection(drawable, cp_axis_direction_convention_right_up_back, (size_t)i);
        simd_float4x4 invP = simd_inverse(proj);
        simd_float4 derived = m3b::derivedViewTangents(invP);

        simd_float4 legacy = simd_make_float4(0, 0, 0, 0);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        legacy = cp_view_get_tangents(view);
#pragma clang diagnostic pop

        mLog("VIEW %d/%zu textureMap: texIndex=%zu sliceIndex=%zu viewport=(x=%.1f y=%.1f w=%.1f h=%.1f) colorTex=%lux%lu(type=%lu fmt=%lu) depthTex=%p rrm=%p",
             i, views, texIndex, sliceIndex, vp.originX, vp.originY, vp.width, vp.height,
             (unsigned long)colorTex.width, (unsigned long)colorTex.height, (unsigned long)colorTex.textureType,
             (unsigned long)colorTex.pixelFormat, (__bridge void *)depthTex, (__bridge void *)rrm);
        mLog("VIEW %d transform rows [right; up; back; pos]: %s", i, m3b::matrixRowsString(vt).UTF8String);
        mLog("VIEW %d projection rows: %s", i, m3b::matrixRowsString(proj).UTF8String);
        mLog("VIEW %d derived tangents l/r/d/u=(%.4f, %.4f, %.4f, %.4f)", i, derived.x, derived.y, derived.z, derived.w);
        mLog("VIEW %d cp_view_get_tangents (deprecated; l/r/t/b positive)=(%.4f, %.4f, %.4f, %.4f) cross-check -derive.x=%.4f derive.y=%.4f derive.w=%.4f -derive.z=%.4f",
             i, legacy.x, legacy.y, legacy.z, legacy.w, -derived.x, derived.y, derived.w, -derived.z);
        mLog("VIEW %d pos=(%.5f, %.5f, %.5f) fwd=(-z)=(%.4f, %.4f, %.4f)",
             i, vt.columns[3].x, vt.columns[3].y, vt.columns[3].z,
             -vt.columns[2].x, -vt.columns[2].y, -vt.columns[2].z);

        if (i < 2) {
            _liveParams[i].invProjection = invP;
            _liveParams[i].viewToDevice = vt;
            _liveParams[i].sourceTangents = providerSt;
        }

        // Validate the device-case reconstruction method: rebuild view->device from pos/fwd and compare.
        simd_float4x4 reconVt = m3b::makeViewToDevice(
            simd_make_float3(vt.columns[3].x, vt.columns[3].y, vt.columns[3].z),
            simd_make_float3(-vt.columns[2].x, -vt.columns[2].y, -vt.columns[2].z), 0.0f);
        mLog("VIEW %d reconstruction-check max|R_recon-R_real|=%.6f (device views below are reconstructed this way; roll unknown)",
             i, m3b::maxAbsRotationDiff(vt, reconVt));

        if (i < 2) {
            [self cpuDiagnostics:[NSString stringWithFormat:@"live-view%d", i]
                          params:&_liveParams[i]
                              st:providerSt
                      logSamples:YES];
        }
    }

    mLog("================= EV-0086 DEVICE VIEW RECONSTRUCTION =================");
    sumLog(@"EV-0086 device views: L tangents=(-1.732,1.000,-1.192,1.000) pos=(-0.0349,-0.0272,0.0045) fwd=(0.001,0.014,-1.000); R tangents=(-1.000,1.732,-1.192,1.000) pos=(0.0300,-0.0251,0.0025) fwd=(0.003,0.016,-1.000); provider tangents L=R=(-1.428,1.428,-1.428,1.428); ipd=0.065");
    for (int i = 0; i < 2; i++) {
        const DeviceView &dv = kDeviceViews[i];
        simd_float4x4 proj = m3b::makeProjectionFromTangents(dv.l, dv.r, dv.d, dv.u, 0.01f, 1000.0f);
        simd_float4x4 invP = simd_inverse(proj);
        simd_float4x4 vt = m3b::makeViewToDevice(dv.pos, dv.fwd, 0.0f);
        _deviceParams[i].invProjection = invP;
        _deviceParams[i].viewToDevice = vt;
        _deviceParams[i].sourceTangents = providerSt;

        mLog("DEVICE %s reconstructed: pos=(%.4f, %.4f, %.4f) fwd=(%.3f, %.3f, %.3f) tangents l/r/d/u=(%.3f, %.3f, %.3f, %.3f)",
             dv.name, dv.pos.x, dv.pos.y, dv.pos.z, dv.fwd.x, dv.fwd.y, dv.fwd.z, dv.l, dv.r, dv.d, dv.u);
        mLog("DEVICE %s reconstructed projection rows: %s", dv.name, m3b::matrixRowsString(proj).UTF8String);
        mLog("DEVICE %s reconstructed transform rows [right; up; back; pos]: %s", dv.name,
             m3b::matrixRowsString(vt).UTF8String);

        [self cpuDiagnostics:[NSString stringWithFormat:@"device-%s", dv.name]
                      params:&_deviceParams[i]
                          st:providerSt
                  logSamples:YES];

        // Roll sensitivity (the device log gives no roll; the view cannot be reconstructed exactly).
        for (float rolls : {-20.0f, 0.0f, 20.0f}) {
            m3b::ProbeViewParams p = _deviceParams[i];
            p.viewToDevice = m3b::makeViewToDevice(dv.pos, dv.fwd, rolls * kDeg2Rad);
            double pct = [self coveragePct:&p st:providerSt];
            mLog("DEVICE %s roll-sensitivity roll=%+.1f deg -> provider-uv coverage=%.2f%%", dv.name, rolls, pct);
        }
        // Opposite view-transform convention hypothesis (device->view instead of view->device).
        {
            m3b::ProbeViewParams p = _deviceParams[i];
            p.viewToDevice = m3b::inverseRotation(vt);
            double pct = [self coveragePct:&p st:providerSt];
            mLog("DEVICE %s hypothesis: if viewToDevice were the inverse (device->view), coverage=%.2f%%", dv.name, pct);
        }
    }

    // ---------------- Offscreen shader validation (no dependence on simulator presentation) ----------------
    mLog("================= OFFSCREEN SHADER VALIDATION =================");
    const int osSize = 512;
    for (int i = 0; i < _liveViewCount; i++) {
        for (int v = 0; v < 4; v++) {
            id<MTLTexture> out = [self offscreenRenderVariant:v params:&_liveParams[i] texture:_syntheticTex size:osSize];
            NSString *name = [NSString stringWithFormat:@"offscreen-live-view%d-%s", i, m3b::variantName(v)];
            [self analyzeReadback:[self readbackTextureRGBA16F:out]
                            width:osSize
                           height:osSize
                             name:name
                          variant:v
                           params:&_liveParams[i]
                      texAlphaZero:NO
                          saveRaw:(v == 0)];
        }
    }
    for (int i = 0; i < 2; i++) {
        for (int v = 0; v < 4; v++) {
            id<MTLTexture> out = [self offscreenRenderVariant:v params:&_deviceParams[i] texture:_syntheticTex size:osSize];
            NSString *name = [NSString stringWithFormat:@"offscreen-device-%s-%s", kDeviceViews[i].name,
                                                        m3b::variantName(v)];
            [self analyzeReadback:[self readbackTextureRGBA16F:out]
                            width:osSize
                           height:osSize
                             name:name
                          variant:v
                           params:&_deviceParams[i]
                      texAlphaZero:NO
                          saveRaw:NO];
        }
    }
    // Alpha experiment: same math, alpha=0 provider texture, with and without forced alpha=1.
    for (int v : {0, 3}) {
        id<MTLTexture> out = [self offscreenRenderVariant:v params:&_liveParams[0] texture:_syntheticAlpha0Tex size:osSize];
        NSString *name = [NSString stringWithFormat:@"offscreen-live-view0-alpha0tex-%s", m3b::variantName(v)];
        [self analyzeReadback:[self readbackTextureRGBA16F:out]
                        width:osSize
                       height:osSize
                         name:name
                      variant:v
                       params:&_liveParams[0]
                  texAlphaZero:YES
                      saveRaw:NO];
    }
    // Self-consistent mapping: source tangents = the view's own tangents -> the WHOLE pattern must be
    // reproduced (all four corner colors + asymmetric T marker + centre crosshair). Visual proof that the
    // exact shader samples a correctly mapped texture, independent of the provider frustum.
    {
        m3b::ProbeViewParams p = _liveParams[0];
        p.sourceTangents = m3b::derivedViewTangents(p.invProjection);
        id<MTLTexture> out = [self offscreenRenderVariant:0 params:&p texture:_syntheticTex size:osSize];
        [self analyzeReadback:[self readbackTextureRGBA16F:out]
                        width:osSize
                       height:osSize
                         name:@"offscreen-live-view0-fullpattern-reproj"
                      variant:0
                       params:&p
                  texAlphaZero:NO
                      saveRaw:NO];
    }
    // All-black provider texture: what the compositor displays if the exported eye texture contains no
    // rendered content. The exact shader faithfully outputs opaque black - the EV-0086 symptom - which is
    // why a device-side texture readback diagnostic is required to tell (a) from (b).
    {
        std::vector<uint8_t> black((size_t)kPatternSize * kPatternSize * 4, 0);
        for (size_t i = 3; i < black.size(); i += 4) black[i] = 255;
        id<MTLTexture> blackTex = [self makeSyntheticTextureWithPattern:&black name:@"black"];
        id<MTLTexture> out = [self offscreenRenderVariant:3 params:&_liveParams[0] texture:blackTex size:osSize];
        [self analyzeReadback:[self readbackTextureRGBA16F:out]
                        width:osSize
                       height:osSize
                         name:@"offscreen-live-view0-black-texture-reproj-alpha1"
                      variant:3
                       params:nullptr
                  texAlphaZero:NO
                      saveRaw:NO];
    }
}

- (double)coveragePct:(const m3b::ProbeViewParams *)p st:(simd_float4)st {
    const int dim = 33;
    int n = 0, nIn = 0;
    for (int gy = 0; gy < dim; gy++) {
        for (int gx = 0; gx < dim; gx++) {
            float nx = -1.0f + 2.0f * (float)gx / (float)(dim - 1);
            float ny = -1.0f + 2.0f * (float)gy / (float)(dim - 1);
            m3b::RaySample s = m3b::computeRaySample(p->invProjection, p->viewToDevice, st, nx, ny);
            n++;
            if (s.valid && !s.nan && !s.behind && s.uvIn) nIn++;
        }
    }
    return 100.0 * (double)nIn / (double)std::max(n, 1);
}

- (void)cpuDiagnostics:(NSString *)label
                params:(const m3b::ProbeViewParams *)p
                    st:(simd_float4)st
            logSamples:(BOOL)logSamples {
    simd_float4 derived = m3b::derivedViewTangents(p->invProjection);
    mLog("CPU[%s] tangents from invProjection l/r/d/u=(%.4f, %.4f, %.4f, %.4f) | provider st l/r/d/u=(%.4f, %.4f, %.4f, %.4f)",
         label.UTF8String, derived.x, derived.y, derived.z, derived.w, st.x, st.y, st.z, st.w);

    if (logSamples) {
        const float probes[5][2] = {{0.0f, 0.0f}, {-1.0f, -1.0f}, {1.0f, -1.0f}, {-1.0f, 1.0f}, {1.0f, 1.0f}};
        for (int k = 0; k < 5; k++) {
            m3b::RaySample s = m3b::computeRaySample(p->invProjection, p->viewToDevice, st, probes[k][0], probes[k][1]);
            mLog("CPU[%s] ndc=(%+.2f, %+.2f) dz=%+.6f behind=%d t=(%+.4f, %+.4f) uv=(%+.4f, %+.4f) uvIn=%d nan=%d",
                 label.UTF8String, probes[k][0], probes[k][1], s.dz, (int)s.behind,
                 s.tx, s.ty, s.u, s.v, (int)s.uvIn, (int)s.nan);
        }
    }

    const int dim = 33;
    int n = 0, nNan = 0, nBehind = 0, nOOB = 0, nIn = 0;
    float minTX = 1e9f, maxTX = -1e9f, minTY = 1e9f, maxTY = -1e9f;
    float minU = 1e9f, maxU = -1e9f, minV = 1e9f, maxV = -1e9f;
    float minDZ = 1e9f, maxDZ = -1e9f;
    int hz[8] = {0};
    for (int gy = 0; gy < dim; gy++) {
        for (int gx = 0; gx < dim; gx++) {
            float nx = -1.0f + 2.0f * (float)gx / (float)(dim - 1);
            float ny = -1.0f + 2.0f * (float)gy / (float)(dim - 1);
            m3b::RaySample s = m3b::computeRaySample(p->invProjection, p->viewToDevice, st, nx, ny);
            n++;
            if (s.nan || !s.valid) {
                nNan++;
                continue;
            }
            if (s.behind) {
                nBehind++;
                hz[0]++;
                continue;
            }
            minTX = std::min(minTX, s.tx);
            maxTX = std::max(maxTX, s.tx);
            minTY = std::min(minTY, s.ty);
            maxTY = std::max(maxTY, s.ty);
            minU = std::min(minU, s.u);
            maxU = std::max(maxU, s.u);
            minV = std::min(minV, s.v);
            maxV = std::max(maxV, s.v);
            minDZ = std::min(minDZ, s.dz);
            maxDZ = std::max(maxDZ, s.dz);
            if (s.uvIn) nIn++; else nOOB++;
            int b;
            if (s.dz > -0.05f) b = 1;
            else if (s.dz > -0.25f) b = 2;
            else if (s.dz > -0.5f) b = 3;
            else if (s.dz > -0.75f) b = 4;
            else if (s.dz > -0.95f) b = 5;
            else if (s.dz > -1.05f) b = 6;
            else b = 7;
            hz[b]++;
        }
    }
    double pctInside = 100.0 * (double)nIn / (double)std::max(n, 1);
    double pctBehind = 100.0 * (double)nBehind / (double)std::max(n, 1);
    double pctOOB = 100.0 * (double)nOOB / (double)std::max(n, 1);
    double pctNan = 100.0 * (double)nNan / (double)std::max(n, 1);
    mLog("CPU[%s] grid=%dx%d n=%d behind=%d oob=%d inside=%d nan=%d -> pctInside=%.2f%% pctBehind=%.2f%% pctOOB=%.2f%% pctNaN=%.2f%% pctBlackBranch(=behind+oob+nan)=%.2f%%",
         label.UTF8String, dim, dim, n, nBehind, nOOB, nIn, nNan, pctInside, pctBehind, pctOOB, pctNan,
         100.0 - pctInside);
    mLog("CPU[%s] t.x=[%+.4f, %+.4f] t.y=[%+.4f, %+.4f] uv.x=[%+.4f, %+.4f] uv.y=[%+.4f, %+.4f]",
         label.UTF8String, minTX, maxTX, minTY, maxTY, minU, maxU, minV, maxV);
    mLog("CPU[%s] dz min=%+.6f max=%+.6f hist dz>=-0.05:%d [-0.05,-0.25):%d [-0.25,-0.5):%d [-0.5,-0.75):%d [-0.75,-0.95):%d [-0.95,-1.05):%d <-1.05:%d behind:%d",
         label.UTF8String, minDZ, maxDZ, hz[1], hz[2], hz[3], hz[4], hz[5], hz[6], hz[7], hz[0]);

    // Control: if the provider frustum were the view's own frustum, coverage must be ~100%.
    double ownPct = [self coveragePct:p st:derived];
    mLog("CPU[%s] control(source tangents = view's own tangents) coverage=%.2f%% (formula sanity; expect 100 unless rays behind)",
         label.UTF8String, ownPct);

    sumLog([NSString stringWithFormat:@"CPU[%@] pctInside=%.2f%% pctBehind=%.2f%% pctOOB=%.2f%% pctNaN=%.2f%% t.x=[%.3f,%.3f] t.y=[%.3f,%.3f] uv.x=[%.3f,%.3f] uv.y=[%.3f,%.3f] own-source-sanity=%.2f%%",
            label, pctInside, pctBehind, pctOOB, pctNan, minTX, maxTX, minTY, maxTY, minU, maxU, minV, maxV, ownPct]);
}

// ---------------------------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------------------------
- (id<MTLRenderPipelineState>)pipelineForVariant:(int)variant useDepth:(BOOL)useDepth offscreen:(BOOL)offscreen {
    if (variant < 0 || variant > 3) return nil;
    if (offscreen) return _pipeOffscreen[variant];
    return useDepth ? _pipeDrawDepth[variant] : _pipeDrawNoDepth[variant];
}

- (void)encodeQuad:(id<MTLRenderCommandEncoder>)enc
              pipe:(id<MTLRenderPipelineState>)pipe
           texture:(id<MTLTexture>)tex
            params:(const m3b::ProbeViewParams *)p {
    if (pipe == nil) {
        mLog("encodeQuad: nil pipeline, skipping draw");
        return;
    }
    [enc setRenderPipelineState:pipe];
    [enc setFragmentTexture:tex atIndex:0];
    [enc setFragmentSamplerState:_sampler atIndex:0];
    if (p != nullptr) [enc setFragmentBytes:p length:sizeof(*p) atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

- (id<MTLTexture>)offscreenRenderVariant:(int)variant
                                  params:(const m3b::ProbeViewParams *)p
                                 texture:(id<MTLTexture>)tex
                                    size:(int)size {
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                  width:(NSUInteger)size
                                                                                 height:(NSUInteger)size
                                                                              mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModePrivate;
    id<MTLTexture> out = [_device newTextureWithDescriptor:td];
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = out;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
    [self encodeQuad:enc pipe:[self pipelineForVariant:variant useDepth:NO offscreen:YES] texture:tex params:p];
    [enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    if (cb.error) {
        mLog("offscreen render error variant=%s: %s", m3b::variantName(variant), cb.error.description.UTF8String);
    }
    return out;
}

- (const m3b::ProbeViewParams *)paramsForView:(int)i drawable:(cp_drawable_t)drawable {
    if (i < _liveViewCount && i < 2) return &_liveParams[i];
    if (i < 2) return &_deviceParams[i];
    return &_liveParams[0];
}

- (void)renderDrawable:(cp_drawable_t)drawable
               variant:(int)variant
              useDepth:(BOOL)useDepth
                useRRM:(BOOL)useRRM
               texture:(id<MTLTexture>)tex
          readbackName:(NSString *)name
               saveRaw:(BOOL)saveRaw {
    int views = (int)cp_drawable_get_view_count(drawable);
    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    for (int i = 0; i < views && i < 2; i++) {
        cp_view_t view = cp_drawable_get_view(drawable, (size_t)i);
        cp_view_texture_map_t tm = cp_view_get_view_texture_map(view);
        size_t texIndex = cp_view_texture_map_get_texture_index(tm);
        MTLViewport vp = cp_view_texture_map_get_viewport(tm);
        id<MTLTexture> colorTex = cp_drawable_get_color_texture(drawable, texIndex);

        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = colorTex;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = (i == 0) ? MTLClearColorMake(0.8, 0.05, 0.05, 1.0)
                                                     : MTLClearColorMake(0.05, 0.7, 0.1, 1.0);

        BOOL depthOK = useDepth && _depthFormat != MTLPixelFormatInvalid;
        if (depthOK) {
            id<MTLTexture> depthTex = cp_drawable_get_depth_texture(drawable, texIndex);
            if (depthTex != nil) {
                rp.depthAttachment.texture = depthTex;
                rp.depthAttachment.loadAction = MTLLoadActionClear;
                rp.depthAttachment.storeAction = MTLStoreActionStore;
                // CompositorServices reverse-Z: 0 = infinitely far, same as VRMCCompositor.mm.
                rp.depthAttachment.clearDepth = 0.0;
            } else {
                depthOK = NO;
            }
        }
        id<MTLRasterizationRateMap> rrm = useRRM ? cp_drawable_get_rasterization_rate_map(drawable, texIndex) : nil;
        if (rrm != nil) rp.rasterizationRateMap = rrm;

        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        if (enc != nil) {
            if (vp.width > 0.0 && vp.height > 0.0 &&
                (vp.width != (double)colorTex.width || vp.height != (double)colorTex.height)) {
                [enc setViewport:vp];
            }
            const m3b::ProbeViewParams *p = [self paramsForView:i drawable:drawable];
            [self encodeQuad:enc
                        pipe:[self pipelineForVariant:variant useDepth:depthOK offscreen:NO]
                     texture:tex
                      params:p];
            [enc endEncoding];
        }
    }
    cp_drawable_encode_present(drawable, cb);
    [cb commit];

    if (name == nil) return;
    [cb waitUntilCompleted];
    if (cb.error) mLog("drawable command buffer error: %s", cb.error.description.UTF8String);

    for (int i = 0; i < views && i < 2; i++) {
        cp_view_t view = cp_drawable_get_view(drawable, (size_t)i);
        cp_view_texture_map_t tm = cp_view_get_view_texture_map(view);
        size_t texIndex = cp_view_texture_map_get_texture_index(tm);
        id<MTLTexture> colorTex = cp_drawable_get_color_texture(drawable, texIndex);
        NSString *n = (views > 1) ? [NSString stringWithFormat:@"%@-view%d", name, i] : name;
        NSData *data = [self readbackTextureRGBA16F:colorTex];
        const m3b::ProbeViewParams *p = [self paramsForView:i drawable:drawable];
        [self analyzeReadback:data
                        width:(int)colorTex.width
                       height:(int)colorTex.height
                         name:n
                      variant:variant
                       params:p
                  texAlphaZero:(tex == _syntheticAlpha0Tex)
                      saveRaw:saveRaw];
    }
}

- (NSData *)readbackTextureRGBA16F:(id<MTLTexture>)tex {
    if (tex == nil) return nil;
    if (tex.textureType != MTLTextureType2D) {
        mLog("readback skipped: textureType=%lu is not 2D", (unsigned long)tex.textureType);
        return nil;
    }
    if (tex.pixelFormat != MTLPixelFormatRGBA16Float) {
        mLog("readback skipped: pixelFormat=%lu is not rgba16Float", (unsigned long)tex.pixelFormat);
        return nil;
    }
    NSUInteger w = tex.width;
    NSUInteger h = tex.height;
    NSUInteger bpr = ((w * 8 + 255) / 256) * 256;
    id<MTLBuffer> buf = [_device newBufferWithLength:bpr * h options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    if (blit == nil) return nil;
    [blit copyFromTexture:tex
              sourceSlice:0
              sourceLevel:0
             sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:MTLSizeMake(w, h, 1)
                 toBuffer:buf
        destinationOffset:0
   destinationBytesPerRow:bpr
 destinationBytesPerImage:bpr * h];
    [blit endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    if (cb.error) {
        mLog("readback blit error: %s", cb.error.description.UTF8String);
        return nil;
    }
    NSMutableData *out = [NSMutableData dataWithLength:w * h * 8];
    const uint8_t *src = (const uint8_t *)buf.contents;
    uint8_t *dst = (uint8_t *)out.mutableBytes;
    for (NSUInteger y = 0; y < h; y++) {
        memcpy(dst + y * w * 8, src + y * bpr, w * 8);
    }
    return out;
}

// ---------------------------------------------------------------------------------------------
// Image analysis, CPU-reference validation, PNG output
// ---------------------------------------------------------------------------------------------
static BOOL writePNG(NSString *path, const uint8_t *rgba, int w, int h) {
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (cs == NULL) return NO;
    CGContextRef ctx = CGBitmapContextCreate((void *)rgba, (size_t)w, (size_t)h, 8, (size_t)w * 4, cs,
                                             kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (ctx == NULL) return NO;
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (img == NULL) return NO;
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.png"), 1, NULL);
    BOOL ok = NO;
    if (dest != NULL) {
        CGImageDestinationAddImage(dest, img, NULL);
        ok = (BOOL)CGImageDestinationFinalize(dest);
        CFRelease(dest);
    }
    CGImageRelease(img);
    return ok;
}

- (void)analyzeReadback:(NSData *)data
                  width:(int)w
                 height:(int)h
                   name:(NSString *)name
                variant:(int)variant
                 params:(const m3b::ProbeViewParams *)params
            texAlphaZero:(BOOL)texAlphaZero
                saveRaw:(BOOL)saveRaw {
    if (data == nil || w <= 0 || h <= 0) {
        mLog("READBACK %s: no data", name.UTF8String);
        return;
    }
    const _Float16 *px = (const _Float16 *)data.bytes;
    const NSUInteger count = (NSUInteger)w * (NSUInteger)h;

    double sumR = 0, sumG = 0, sumB = 0, sumA = 0;
    long nBlackOpaque = 0, nMagenta = 0, nBlue = 0, nCyan = 0, nAlphaLow = 0, nNonBlack = 0;
    float maxR = 0, maxG = 0, maxB = 0;
    for (NSUInteger i = 0; i < count; i++) {
        float r = (float)px[i * 4 + 0];
        float g = (float)px[i * 4 + 1];
        float b = (float)px[i * 4 + 2];
        float a = (float)px[i * 4 + 3];
        sumR += r;
        sumG += g;
        sumB += b;
        sumA += a;
        maxR = std::max(maxR, r);
        maxG = std::max(maxG, g);
        maxB = std::max(maxB, b);
        if (r < 0.02f && g < 0.02f && b < 0.02f && a > 0.9f) nBlackOpaque++;
        if (r > 0.5f && b > 0.5f && g < 0.3f) nMagenta++;
        if (b > 0.5f && r < 0.3f && g < 0.3f) nBlue++;
        if (g > 0.5f && b > 0.5f && r < 0.3f) nCyan++;
        if (a < 0.5f) nAlphaLow++;
        if ((r + g + b) / 3.0f > 0.05f) nNonBlack++;
    }
    double inv = 1.0 / (double)std::max<NSUInteger>(count, 1);
    const _Float16 *center = px + (((NSUInteger)(h / 2) * (NSUInteger)w) + (NSUInteger)(w / 2)) * 4;
    mLog("READBACK %s %dx%d mean=(%.4f, %.4f, %.4f, %.4f) max=(%.3f, %.3f, %.3f) blackOpaque=%.2f%% nonBlack=%.2f%% magenta=%.2f%% blue=%.2f%% cyan=%.2f%% alpha<0.5=%.2f%% center=(%.3f, %.3f, %.3f, %.3f)",
         name.UTF8String, w, h, sumR * inv, sumG * inv, sumB * inv, sumA * inv, maxR, maxG, maxB,
         100.0 * (double)nBlackOpaque * inv, 100.0 * (double)nNonBlack * inv,
         100.0 * (double)nMagenta * inv, 100.0 * (double)nBlue * inv, 100.0 * (double)nCyan * inv,
         100.0 * (double)nAlphaLow * inv,
         (float)center[0], (float)center[1], (float)center[2], (float)center[3]);
    sumLog([NSString stringWithFormat:@"READBACK %@ %dx%d mean=(%.3f %.3f %.3f %.3f) blackOpaque=%.1f%% nonBlack=%.1f%% magenta=%.1f%% blue=%.1f%% cyan=%.1f%% alphaLow=%.1f%%",
            name, w, h, sumR * inv, sumG * inv, sumB * inv, sumA * inv,
            100.0 * (double)nBlackOpaque * inv, 100.0 * (double)nNonBlack * inv,
            100.0 * (double)nMagenta * inv, 100.0 * (double)nBlue * inv, 100.0 * (double)nCyan * inv,
            100.0 * (double)nAlphaLow * inv]);

    if (params != nullptr && (variant == 0 || variant == 2 || variant == 3)) {
        [self validateReadback:data width:w height:h name:name variant:variant params:params texAlphaZero:texAlphaZero];
    }

    if (!gResultsDir) return;
    // Downsample to at most 512 px on the long edge; debug images use nearest so branch colors stay pure.
    int ds = (int)ceilf((float)std::max(w, h) / 512.0f);
    if (ds < 1) ds = 1;
    int ow = w / ds;
    int oh = h / ds;
    if (ow < 1) ow = 1;
    if (oh < 1) oh = 1;
    std::vector<uint8_t> img((size_t)ow * (size_t)oh * 4, 0);
    for (int y = 0; y < oh; y++) {
        for (int x = 0; x < ow; x++) {
            float acc[4] = {0, 0, 0, 0};
            int n = 0;
            if (variant == 1) {
                int sx = std::min(x * ds + ds / 2, w - 1);
                int sy = std::min(y * ds + ds / 2, h - 1);
                const _Float16 *q = px + ((size_t)sy * (size_t)w + (size_t)sx) * 4;
                for (int c = 0; c < 4; c++) acc[c] = (float)q[c];
                n = 1;
            } else {
                for (int yy = 0; yy < ds; yy++) {
                    for (int xx = 0; xx < ds; xx++) {
                        int sx = x * ds + xx;
                        int sy = y * ds + yy;
                        if (sx >= w || sy >= h) continue;
                        const _Float16 *q = px + ((size_t)sy * (size_t)w + (size_t)sx) * 4;
                        for (int c = 0; c < 4; c++) acc[c] += (float)q[c];
                        n++;
                    }
                }
            }
            if (n < 1) n = 1;
            for (int c = 0; c < 4; c++) {
                float v = acc[c] / (float)n;
                if (v < 0.0f) v = 0.0f;
                if (v > 1.0f) v = 1.0f;
                img[((size_t)y * (size_t)ow + (size_t)x) * 4 + (size_t)c] = (uint8_t)lroundf(v * 255.0f);
            }
        }
    }
    NSString *pngPath = [gResultsDir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
    BOOL ok = writePNG(pngPath, img.data(), ow, oh);
    mLog("SAVED %s (%dx%d from %dx%d) ok=%d", pngPath.lastPathComponent.UTF8String, ow, oh, w, h, (int)ok);
    if (saveRaw) {
        NSString *rawPath = [gResultsDir stringByAppendingPathComponent:[name stringByAppendingString:@".raw"]];
        NSData *rawData = [NSData dataWithBytes:img.data() length:img.size()];
        BOOL rawOK = [rawData writeToFile:rawPath atomically:YES];
        mLog("SAVED %s (%d bytes) ok=%d", rawPath.lastPathComponent.UTF8String, (int)img.size(), (int)rawOK);
    }
}

- (void)validateReadback:(NSData *)data
                   width:(int)w
                  height:(int)h
                    name:(NSString *)name
                 variant:(int)variant
                  params:(const m3b::ProbeViewParams *)params
             texAlphaZero:(BOOL)texAlphaZero {
    const _Float16 *px = (const _Float16 *)data.bytes;
    const int probes = 5;
    int matched = 0;
    int mismatched = 0;
    float maxErr = 0.0f;
    NSMutableString *firstErrors = [NSMutableString string];
    for (int gy = 0; gy < probes; gy++) {
        for (int gx = 0; gx < probes; gx++) {
            int x = (int)((0.1f + 0.2f * (float)gx) * (float)w);
            int y = (int)((0.1f + 0.2f * (float)gy) * (float)h);
            if (x >= w) x = w - 1;
            if (y >= h) y = h - 1;
            float ndcx = 2.0f * ((float)x + 0.5f) / (float)w - 1.0f;
            float ndcy = 1.0f - 2.0f * ((float)y + 0.5f) / (float)h;
            float exp[4] = {0, 0, 0, 1};
            if (variant == 2) {
                float u = ndcx * 0.5f + 0.5f;
                float v = 0.5f - ndcy * 0.5f;
                m3b::cpuSamplePattern(gPattern, kPatternSize, u, v, exp);
                exp[3] = 1.0f;
            } else {
                m3b::RaySample s = m3b::computeRaySample(params->invProjection, params->viewToDevice,
                                                        params->sourceTangents, ndcx, ndcy);
                if (s.nan || !s.valid || s.behind || !s.uvIn) {
                    exp[0] = exp[1] = exp[2] = 0.0f;
                    exp[3] = 1.0f;
                } else {
                    m3b::cpuSamplePattern(gPattern, kPatternSize, s.u, s.v, exp);
                    exp[3] = (variant == 3) ? 1.0f : (texAlphaZero ? 0.0f : 1.0f);
                }
            }
            const _Float16 *q = px + ((size_t)y * (size_t)w + (size_t)x) * 4;
            float act[4] = {(float)q[0], (float)q[1], (float)q[2], (float)q[3]};
            float err = 0.0f;
            for (int c = 0; c < 4; c++) err = std::max(err, std::fabs(exp[c] - act[c]));
            maxErr = std::max(maxErr, err);
            if (err <= 0.03f) {
                matched++;
            } else {
                mismatched++;
                if (firstErrors.length < 300) {
                    [firstErrors appendFormat:@" [x=%d y=%d exp=(%.3f %.3f %.3f %.3f) act=(%.3f %.3f %.3f %.3f) err=%.3f]",
                                              x, y, exp[0], exp[1], exp[2], exp[3], act[0], act[1], act[2], act[3], err];
                }
            }
        }
    }
    const char *status = (mismatched == 0) ? "PASS" : (mismatched <= 3 ? "PARTIAL" : "FAIL");
    mLog("VALIDATE %s probes=%d matched=%d maxAbsErr=%.4f status=%s%s", name.UTF8String, probes * probes,
         matched, maxErr, status, mismatched > 0 ? firstErrors.UTF8String : "");
    sumLog([NSString stringWithFormat:@"VALIDATE %@ probes=%d matched=%d maxAbsErr=%.4f status=%s",
            name, probes * probes, matched, maxErr, status]);
}

@end

// ---------------------------------------------------------------------------------------------
// Thread + entry point
// ---------------------------------------------------------------------------------------------
@interface M3BThread : NSThread
@property (nonatomic) cp_layer_renderer_t layerRenderer;
@end

@implementation M3BThread

- (void)main {
    M3BRenderer *renderer = [[M3BRenderer alloc] initWithLayerRenderer:self.layerRenderer];
    if (renderer == nil) {
        mLog("failed to create renderer");
        return;
    }
    [renderer run];
}

@end

namespace {
static M3BThread *gThread = nil;
static BOOL gStarted = NO;
}  // namespace

extern "C" void VRMCProbe_InitAndRun(cp_layer_renderer_t layerRenderer) {
    openLog();
    if (gStarted) {
        mLog("VRMCProbe_InitAndRun called again; ignoring (probe is one-shot)");
        return;
    }
    gStarted = YES;
    mLog("CompositorLayer closure entered; starting M3B render thread");
    gThread = [[M3BThread alloc] init];
    gThread.layerRenderer = layerRenderer;
    gThread.name = @"M3B Render Thread";
    [gThread start];
}
