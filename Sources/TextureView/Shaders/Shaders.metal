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

vertex TextureViewFragmentIn textureViewVertex(
    constant float3x3& transform [[ buffer(0) ]],
    uint vertexID [[ vertex_id ]]
) {
    float2 texCoord = vertices[vertexID];
    texCoord.y *= -1.0f;

    float3 position = transform * float3(vertices[vertexID], 1.0f);
    position /= position.z;

    return {
        float4(position, 1.0f),
        fma(texCoord, 0.5f, 0.5f)
    };
}

fragment float4 textureViewFragment(
    TextureViewFragmentIn in [[stage_in]],
    texture2d<float, access::sample> source [[ texture(0) ]]
) {
    constexpr sampler s(
        coord::normalized,
        address::clamp_to_zero,
        filter::linear
    );
    return source.sample(s, in.textureCoordinate);
}
