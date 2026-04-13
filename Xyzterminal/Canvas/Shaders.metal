#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float2 pixelSize;
    float cornerRadius;
    float selected;
};

constant float2 quadVertices[] = {
    {0, 0}, {1, 0}, {1, 1},
    {0, 0}, {1, 1}, {0, 1}
};

vertex VertexOut vertex_node(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant NodeInstance *instances [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    NodeInstance inst = instances[iid];
    float2 uv = quadVertices[vid];
    float2 canvasPos = uv * inst.size + inst.position;

    VertexOut out;
    out.position = uniforms.viewProjection * float4(canvasPos, 0, 1);
    out.uv = uv;
    out.color = inst.color;
    out.pixelSize = inst.size * uniforms.zoom * uniforms.contentsScale;
    out.cornerRadius = inst.cornerRadius * uniforms.contentsScale;
    out.selected = inst.selected;
    return out;
}

fragment float4 fragment_node(VertexOut in [[stage_in]]) {
    float2 p = (in.uv - 0.5) * in.pixelSize;
    float2 halfSize = in.pixelSize * 0.5;
    float r = min(in.cornerRadius, min(halfSize.x, halfSize.y));

    float2 d = abs(p) - (halfSize - r);
    float dist = length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0) - r;

    if (dist > 0.5) discard_fragment();

    float4 color = in.color;

    if (in.selected > 0.5 && dist > -3.0) {
        float t = smoothstep(-3.0, -1.0, dist);
        color = mix(color, float4(0.35, 0.55, 1.0, 1.0), t);
    }

    color.a *= 1.0 - smoothstep(-0.5, 0.5, dist);
    return color;
}

struct EdgeVertexIn {
    float2 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct EdgeVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex EdgeVertexOut vertex_edge(
    EdgeVertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    EdgeVertexOut out;
    out.position = uniforms.viewProjection * float4(in.position, 0, 1);
    out.color = in.color;
    return out;
}

fragment float4 fragment_edge(EdgeVertexOut in [[stage_in]]) {
    return in.color;
}
