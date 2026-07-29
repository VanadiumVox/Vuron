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
    float3 localPos;
    float3 worldPos;
};

// The math program (runs on GPU cores)
vertex VertexOut vertexMain(uint VertexID [[vertex_id]],
            constant VertexIn* vertices [[buffer(0)]],
            constant float4x4& mvpMatrix [[buffer(1)]], // The mvp matrix bridge
            constant float4x4& modelMatrix [[buffer(3)]]) // The model matrix bridge
{
    VertexOut out;
    VertexIn in = vertices[VertexID];

    // NEVER FORGET THIS FIX WHICH SOLVED INTER-DIMENSIONAL CUBES
    // R.I.P INTER_DIMENSIONAL_CUBE.exe 4th June 2026
    out.position = mvpMatrix * float4(in.position, 1.0);

    out.color = in.color;
    out.localPos = float3(in.position[0], in.position[1], in.position[2]);

    // Calculating 3D position for Lighting math
    out.worldPos = (modelMatrix * float4(in.position, 1.0)).xyz;

    return out;
}

// The pixel Colorizer
// [[stade_in]] tells the hardware to take the Vertex Shader otuput
// and put it directly in this function
// P.S, I'm leaving that as 'otuput' to prove that this was written by a human.
fragment float4 fragmentMain(VertexOut in [[stage_in]],
                             constant float& alphaFlag [[buffer(2)]])
{

    // --- The Crosshair Pass ---
    if (alphaFlag > 1.5)
    {
        float thickness = 0.15; // Width of the bars
        float size = 0.8; // Length of the bars

        // Carving out a '+' sign
        if ((abs(in.localPos.x) > thickness && abs(in.localPos.y) > thickness) ||
            abs(in.localPos.x) > size || abs(in.localPos.y) > size)
            {
                discard_fragment();
            }
            // Output pure white. The Metal Pipeline will convert to color inversion
            return float4(1.0, 1.0, 1.0, 1.0);
    }

    // --- The Shadow Pass ---
    // If the C++ engine sends an alpha lower than 1, it's the shadow.
    else if (alphaFlag < 1.0)
    {
        // Measure distance from the center. if outside 0.5 radius, destroy pixel
        if (length(in.localPos.xz) > 0.5)
        {
            discard_fragment();
        }
        // Return pure black, blended by alpha value to darken the floor
        return float4(0.0, 0.0, 0.0, alphaFlag);
    }

    // --- The Lighting Pass ---

    // 1. The trick: Calculate Flat-shaded normal
    // Metal compares this exact pixel's3D position with the pixel next to it
    float3 dx = dfdx(in.worldPos);
    float3 dy = dfdy(in.worldPos);

    // Cross product gives us the perfect perpendicular vector
    // (if lighting looks inside-out, swap this to cross(dx, dy)
    float3 normal = normalize(cross(dx, dy));

    // 2. The Sun (directional light)
    // Pointing down and slightly forward
    float3 sunDir = normalize(float3(-0.5, -1.0, 0.5));
    float3 lightDir = -sunDir; // Reverse to point TOWARD the sun for the math

    // Ambient light
    float ambient = 0.35;

    // The Valve "Half-Lambertian" light trick
    // Wraps light around geometry so faces pointing away from the sun get soft bounced light
    float diffuse = (dot(normal, lightDir) * 0.5) + 0.5;

    // 3. Dynamic point light (the glowing pick-up item / rocket / whatnot)
    // Hardcoded near the staircase for testing! =======================================================]
    float3 pointLightPos = float3(0.0, -1.0, 4.0);
    float3 pointLightColor = float3(1.0, 0.4, 0.0); // Bright ORANGE
    float lightRadius = 6.0;

    // Calculate total distance and angle to the point light
    float3 dirToLight = pointLightPos - in.worldPos;
    float distToLight = length(dirToLight);
    dirToLight = normalize(dirToLight);

    // Fade out over a distance (attenuation)
    float attenuation = max(0.0, 1.0 - (distToLight / lightRadius));
    float pointDiffuse = max(0.0, dot(normal, dirToLight)) * attenuation;

    // 4. Combine all light sources
    // Ambient + Sunlight + (Point light * point light color)
    float3 finalLight = ambient + (diffuse * 0.6) + (pointDiffuse * pointLightColor * 1.5);

    // Multiply the raw color by the lighting data
    float3 finalColor = in.color * finalLight;

    return float4(finalColor, 1.0);
}