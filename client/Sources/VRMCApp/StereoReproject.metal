#include <metal_stdlib>
using namespace metal;

struct ReprojectUniforms {
    float4 presentTangents; // left, right, bottom, top
    float4 captureTangents;
    float4 qCaptureToPresent; // x,y,z,w
    float4 uvRect;            // u0, v0, uWidth, vHeight
    float4 misc;              // x = flipV, y = unused, z = unused, w = unused
};

struct VertexOut {
    float4 position [[position]];
    float2 ndc;
};

vertex VertexOut vrmc_fullscreen_vertex(uint vertexID [[vertex_id]]) {
    // Full-screen triangle. NDC y is up; the fragment shader receives the interpolated NDC.
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.ndc = positions[vertexID];
    return out;
}

static float3 rotate_vector(float4 q, float3 v) {
    float3 u = q.xyz;
    float s = q.w;
    float3 uv = cross(u, v);
    float3 uuv = cross(u, uv);
    return v + (uv * (2.0 * s)) + (uuv * 2.0);
}

fragment float4 vrmc_reproject_fragment(
    VertexOut in [[stage_in]],
    constant ReprojectUniforms &u [[buffer(0)]],
    texture2d<float> eyeTexture [[texture(0)]],
    sampler eyeSampler [[sampler(0)]]
) {
    float2 ndc = clamp(in.ndc, float2(-1.0), float2(1.0));

    // Present eye ray from the drawable's configured tangents.
    float px = mix(u.presentTangents.x, u.presentTangents.y, (ndc.x + 1.0) * 0.5);
    float py = mix(u.presentTangents.z, u.presentTangents.w, (ndc.y + 1.0) * 0.5);
    float3 presentDir = normalize(float3(px, py, -1.0));

    // Inverse of qCaptureToPresent maps the present direction into capture space.
    float4 inverse = float4(-u.qCaptureToPresent.xyz, u.qCaptureToPresent.w);
    float3 captureDir = rotate_vector(inverse, presentDir);
    if (captureDir.z > -0.0001) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float cx = captureDir.x / -captureDir.z;
    float cy = captureDir.y / -captureDir.z;
    float u0 = (cx - u.captureTangents.x) / (u.captureTangents.y - u.captureTangents.x);
    float v0 = (u.captureTangents.w - cy) / (u.captureTangents.w - u.captureTangents.z);
    if (u.misc.x > 0.5) { v0 = 1.0 - v0; }

    float2 uv = u.uvRect.xy + float2(u0, v0) * u.uvRect.zw;
    if (any(uv < float2(0.0)) || any(uv > float2(1.0))) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    return eyeTexture.sample(eyeSampler, uv);
}
