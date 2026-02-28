#version 460
#extension GL_GOOGLE_include_directive : require
#include "Utils.glsl"
#include "DDGIPushConstants.glsl"
#include "ProbeIndexing.glsl"
#include "DDGIVolumeDescGPU.glsl"
#include "ProbeCommon.glsl"

layout(binding = 0, set = 0) readonly buffer DDGIVolumeDescGPUPackedBlock {DDGIVolumeDescGPUPacked d[];} DDGIVolumes;
layout(binding = 1, set = 0, rgba32f) uniform readonly image2DArray RayData;
layout(binding = 2, set = 0, rgba32f) uniform image2DArray ProbeData;

DDGIVolumeDescGPUPacked GetDDGIVolumeConstants(uint index) { return DDGIVolumes.d[index]; }

layout(local_size_x = 32, local_size_y = 1, local_size_z  = 1) in;

vec3 DDGILoadProbeDataOffset(uvec3 coords, DDGIVolumeDescGPU volume)
{
    return imageLoad(ProbeData, ivec3(coords)).xyz * volume.probeSpacing;
}

float DDGILoadProbeRayDistance(uvec3 coords, DDGIVolumeDescGPU volume)
{
    return imageLoad(RayData, ivec3(coords)).a;
}

void DDGIStoreProbeDataOffset(uvec3 coords, vec3 wsOffset, DDGIVolumeDescGPU volume)
{
    float state = imageLoad(ProbeData, ivec3(coords)).a;
    imageStore(ProbeData, ivec3(coords), vec4(wsOffset / volume.probeSpacing, state));
}


void main()
{
    uint volumeIndex = GetDDGIVolumeIndex();
    DDGIVolumeDescGPU volume = UnpackDDGIVolumeDescGPU(GetDDGIVolumeConstants(volumeIndex));

    uvec3 DispatchID = gl_GlobalInvocationID;
    uint probeIndex = DispatchID.x;

    int numProbes = (volume.probeCounts.x * volume.probeCounts.y * volume.probeCounts.z);
    if (probeIndex >= numProbes) return;
    
    uvec3 outputCoords = DDGIGetProbeTexelCoords(int(probeIndex), volume);
    
    vec3 offset = DDGILoadProbeDataOffset(outputCoords, volume);
    
    int   closestBackfaceIndex = -1;
    int   closestFrontfaceIndex = -1;
    int   farthestFrontfaceIndex = -1;
    float closestBackfaceDistance = 1e27f;
    float closestFrontfaceDistance = 1e27f;
    float farthestFrontfaceDistance = 0.f;
    float backfaceCount = 0.f;
    
    int numRays = min(volume.probeNumRays, DDGI_NUM_FIXED_RAYS);
    
    for (int rayIndex = 0; rayIndex < numRays; rayIndex++)
    {
        uvec3 rayDataTexCoords = DDGIGetRayDataTexelCoords(rayIndex, int(probeIndex), volume);
        
        float hitDistance = DDGILoadProbeRayDistance(rayDataTexCoords, volume);

        if (hitDistance < 0.f)
        {
            // Found a backface
            backfaceCount++;
            
            hitDistance = hitDistance * -5.f;
            if (hitDistance < closestBackfaceDistance)
            {
                closestBackfaceDistance = hitDistance;
                closestBackfaceIndex = rayIndex;
            }
        }
        else
        {
            // Found a frontface
            if (hitDistance < closestFrontfaceDistance)
            {
                closestFrontfaceDistance = hitDistance;
                closestFrontfaceIndex = rayIndex;
            }
            else if (hitDistance > farthestFrontfaceDistance)
            {
                farthestFrontfaceDistance = hitDistance;
                farthestFrontfaceIndex = rayIndex;
            }
        }
    }

    vec3 fullOffset = vec3(1e27f, 1e27f, 1e27f);

    if (closestBackfaceIndex != -1 && float(backfaceCount) / float(numRays) > volume.probeFixedRayBackfaceThreshold)
    {
        vec3 closestBackfaceDirection = DDGIGetProbeRayDirection(closestBackfaceIndex, volume);
        fullOffset = offset + (closestBackfaceDirection * (closestBackfaceDistance + volume.probeMinFrontfaceDistance * 0.5f));
    }
    else if (closestFrontfaceDistance < volume.probeMinFrontfaceDistance)
    {
        vec3 closestFrontfaceDirection = DDGIGetProbeRayDirection(closestFrontfaceIndex, volume);
        vec3 farthestFrontfaceDirection = DDGIGetProbeRayDirection(farthestFrontfaceIndex, volume);

        if (dot(closestFrontfaceDirection, farthestFrontfaceDirection) <= 0.f)
        {
            farthestFrontfaceDirection *= min(farthestFrontfaceDistance, 1.f);
            fullOffset = offset + farthestFrontfaceDirection;
        }
    }
    else if (closestFrontfaceDistance > volume.probeMinFrontfaceDistance)
    {
        float moveBackMargin = min(closestFrontfaceDistance - volume.probeMinFrontfaceDistance, length(offset));
        vec3 moveBackDirection = normalize(-offset);
        fullOffset = offset + (moveBackMargin * moveBackDirection);
    }

    
    vec3 normalizedOffset = fullOffset / volume.probeSpacing;
    if (dot(normalizedOffset, normalizedOffset) < 0.2025f) // 0.45 * 0.45 == 0.2025
    {
        offset = fullOffset;
    }
    
    DDGIStoreProbeDataOffset(outputCoords, offset, volume);
}
