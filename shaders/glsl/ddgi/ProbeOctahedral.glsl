#ifndef PROBE_OCTAHEDRAL_GLSL
#define PROBE_OCTAHEDRAL_GLSL
#include "Utils.glsl"

vec2 DDGIGetNormalizedOctahedralCoordinates(ivec2 texCoords, int numTexels)
{
    vec2 octahedralTexelCoord = vec2(texCoords.x % numTexels, texCoords.y % numTexels);
    
    octahedralTexelCoord.xy += 0.5f;
    
    octahedralTexelCoord.xy /= float(numTexels);
    
    octahedralTexelCoord *= 2.f;
    octahedralTexelCoord -= vec2(1.f, 1.f);

    return octahedralTexelCoord;
}

vec3 DDGIGetOctahedralDirection(vec2 coords)
{
    vec3 direction = vec3(coords.x, coords.y, 1.f - abs(coords.x) - abs(coords.y));
    if (direction.z < 0.f)
    {
        direction.xy = (1.f - abs(direction.yx)) * SignNotZero(direction.xy);
    }
    return normalize(direction);
}

vec2 DDGIGetOctahedralCoordinates(vec3 direction)
{
    float l1norm = abs(direction.x) + abs(direction.y) + abs(direction.z);
    vec2 uv = direction.xy * (1.f / l1norm);
    if (direction.z < 0.f)
    {
        uv = (1.f - abs(uv.yx)) * SignNotZero(uv.xy);
    }
    return uv;
}
#endif