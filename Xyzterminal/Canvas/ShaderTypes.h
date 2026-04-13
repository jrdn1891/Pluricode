#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

struct NodeInstance {
    simd_float2 position;
    simd_float2 size;
    simd_float4 color;
    float cornerRadius;
    float selected;
};

struct Uniforms {
    simd_float4x4 viewProjection;
    simd_float2 viewportSize;
    float zoom;
    float contentsScale;
};

struct EdgeVertexData {
    simd_float2 position;
    simd_float4 color;
};

#endif
