#include <metal_stdlib>

using namespace metal;

// The input structure, matching the C++ vertex
struct VertexIn {
    packed_float3 position;
    packed_float3 color;
};

// The output structure to hand to the next bit of code
struct VertexOut {
//[[position]] tells the mac hardware that "This is the final coordinate on screen"
    float4 position [[position]];
    float3 color;
};

// The math program (runs on GPU cores)
vertex VertexOut vertexMain(uint VertexID [[vertex_id]],
                constant VertexIn* vertices [[buffer(0)]])
{
    VertexOut out;

    //Grab the specific vertex for this specific GPU thread
    VertexIn in = vertices[VertexID];

    // Convert (x,y,z) into 4D screen space (x,y,z,w)
    // The 'w' bit is important for Matrix multiplication (yeah, I learned this in colleg)
    out.position = float4(in.position, 1.0);

    // Pass the color
    out.color = in.color;

    return out;
}

// The pixel Colorizer
// [[stade_in]] tells the hardware to take the Vertex Shader otuput
// and put it directly in this function
// P.S, I'm leaving that as 'otuput' to prove that this was written by a human.
fragment float4 fragmentMain(VertexOut in [[stage_in]]) {
    // We take the 3 dimensional color (r,g,b) from the Vertex Shader
    // and add an opacity(alpha) value of 1 to make it solid
    return float4(in.color, 1.0);
}