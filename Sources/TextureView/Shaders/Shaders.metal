#include <metal_stdlib>
using namespace metal;

typedef struct {
    float4 position [[ position ]];
    float2 textureCoordinate;
} TextureViewFragmentIn;

constant float2 vertices[] = {
    { -1.0f,  1.0f },
    { -1.0f, -1.0f },
    {  1.0f,  1.0f },
    {  1.0f, -1.0f }
};

vertex TextureViewFragmentIn textureViewVertex(constant float4x4& projectionMatrix [[ buffer(0) ]],
                                               uint vertexID [[ vertex_id ]]) {
    float2 texCoord = vertices[vertexID];
    texCoord.y *= -1.0f;
    return {
        projectionMatrix * float4(vertices[vertexID], 0.0f, 1.0f),
        fma(texCoord, 0.5f, 0.5f)
    };
}

fragment float4 textureViewFragment(TextureViewFragmentIn in [[stage_in]],
                                    texture2d<float, access::sample> source [[ texture(0) ]]) {
    constexpr sampler s(coord::normalized,
                        address::clamp_to_zero,
                        filter::linear);
    const auto position = float3(in.textureCoordinate, 1.0f).xy;
    return source.sample(s, position);
}
