#ifndef PROBE_INDEXING_GLSL
#define PROBE_INDEXING_GLSL
#include "Common.glsl"
#include "Utils.glsl"

int DDGIGetProbesPerPlane(ivec3 probeCounts)
{
    return (probeCounts.x * probeCounts.z);
}


int DDGIGetPlaneIndex(ivec3 probeCoords)
{
    return probeCoords.y;
}


int DDGIGetProbeIndexInPlane(ivec3 probeCoords, ivec3 probeCounts)
{
    return probeCoords.x + (probeCounts.x * probeCoords.z);
}


int DDGIGetProbeIndexInPlane(uvec3 texCoords, ivec3 probeCounts, int probeNumTexels)
{
    return int(texCoords.x / probeNumTexels) + (probeCounts.x * int(texCoords.y / probeNumTexels));
}


int DDGIGetProbeIndex(ivec3 probeCoords, DDGIVolumeDescGPU volume)
{
    int probesPerPlane = DDGIGetProbesPerPlane(volume.probeCounts);
    int planeIndex = DDGIGetPlaneIndex(probeCoords);
    int probeIndexInPlane = DDGIGetProbeIndexInPlane(probeCoords, volume.probeCounts);

    return (planeIndex * probesPerPlane) + probeIndexInPlane;
}


int DDGIGetProbeIndex(uvec3 texCoords, int probeNumTexels, DDGIVolumeDescGPU volume)
{
    int probesPerPlane = DDGIGetProbesPerPlane(volume.probeCounts);
    int probeIndexInPlane = DDGIGetProbeIndexInPlane(texCoords, volume.probeCounts, probeNumTexels);

    return (int(texCoords.z) * probesPerPlane) + probeIndexInPlane;
}


ivec3 DDGIGetProbeCoords(int probeIndex, DDGIVolumeDescGPU volume)
{
    ivec3 probeCoords;

    probeCoords.x = probeIndex % volume.probeCounts.x;
    probeCoords.y = probeIndex / (volume.probeCounts.x * volume.probeCounts.z);
    probeCoords.z = (probeIndex / volume.probeCounts.x) % volume.probeCounts.z;

    return probeCoords;
}


int DDGIGetScrollingProbeIndex(ivec3 probeCoords, DDGIVolumeDescGPU volume)
{
    return DDGIGetProbeIndex(((probeCoords + volume.probeScrollOffsets + volume.probeCounts) % volume.probeCounts), volume);
}


uvec3 DDGIGetProbeTexelCoords(int probeIndex, DDGIVolumeDescGPU volume)
{
    // Find the probe's plane index
    int probesPerPlane = DDGIGetProbesPerPlane(volume.probeCounts);
    int planeIndex = int(probeIndex / probesPerPlane);

    int x = (probeIndex % volume.probeCounts.x);
    int y = (probeIndex / volume.probeCounts.x) % volume.probeCounts.z;

    return uvec3(x, y, planeIndex);
}

uvec3 DDGIGetRayDataTexelCoords(int rayIndex, int probeIndex, DDGIVolumeDescGPU volume)
{
    int probesPerPlane = DDGIGetProbesPerPlane(volume.probeCounts);

    uvec3 coords;
    coords.x = rayIndex;
    coords.z = probeIndex / probesPerPlane;
    coords.y = probeIndex - (coords.z * probesPerPlane);

    return coords;
}

ivec3 DDGIGetBaseProbeGridCoords(vec3 worldPosition, DDGIVolumeDescGPU volume)
{
    vec3 position = worldPosition - (volume.origin + (volume.probeScrollOffsets * volume.probeSpacing));
    
    if(!IsVolumeMovementScrolling(volume)) position = QuaternionRotate(position, QuaternionConjugate(volume.rotation));
    
    position += (volume.probeSpacing * (volume.probeCounts - 1)) * 0.5f;
    
    ivec3 probeCoords = ivec3(position / volume.probeSpacing);

    probeCoords = clamp(probeCoords, ivec3(0, 0, 0), (volume.probeCounts - ivec3(1, 1, 1)));

    return probeCoords;
}

vec3 DDGIGetProbeUV(int probeIndex, vec2 octantCoordinates, int numProbeInteriorTexels, DDGIVolumeDescGPU volume)
{
    uvec3 coords = DDGIGetProbeTexelCoords(probeIndex, volume);
    
    float numProbeTexels = (numProbeInteriorTexels + 2.f);

    float textureWidth = numProbeTexels * volume.probeCounts.x;
    float textureHeight = numProbeTexels * volume.probeCounts.z;
    
    vec2 uv = vec2(coords.x * numProbeTexels, coords.y * numProbeTexels) + (numProbeTexels * 0.5f);
    uv += octantCoordinates.xy * float(numProbeInteriorTexels * 0.5f);
    uv /= vec2(textureWidth, textureHeight);
    return vec3(uv, coords.z);
}
#endif