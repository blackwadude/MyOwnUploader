//
//  Shade.metal
//  Runner
//
//  Created by MOJOJOJO on 23/06/2025.
//
#include <metal_stdlib>
using namespace metal;

struct VSOutput {
    float4 position [[position]];
    float2 texCoord;
};

// no more stage_in – we’ll generate a full-screen quad from the vertex_id
vertex VSOutput vertex_main(uint   vid [[vertex_id]],
                            constant float4x4 &M [[buffer(0)]])
{
    // triangle-strip order: 0:(-1,-1), 1:( 1,-1), 2:(-1, 1), 3:( 1, 1)
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    // matching tex-coords (flip Y)
    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    VSOutput out;
    float2 pos      = positions[vid];
    out.position    = M * float4(pos, 0.0, 1.0);
    out.texCoord    = texCoords[vid];
    return out;
}

fragment half4 fragment_main(VSOutput            in   [[stage_in]],
                             texture2d<half>     videoTex [[texture(0)]],
                             texture2d<half>     overTex  [[texture(1)]],
                             sampler             samp     [[sampler(0)]])
{
    half4 bg = videoTex.sample(samp, in.texCoord);
    half4 fg = overTex.sample(samp, in.texCoord);
    // simple alpha blend
    return mix(bg, fg, fg.a);
}
