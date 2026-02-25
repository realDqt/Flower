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

    // Get the probe's texel coordinates in the Probe Data texture array
    uvec3 outputCoords = DDGIGetProbeTexelCoords(int(probeIndex), volume);

    // Read the current world position offset
    vec3 offset = DDGILoadProbeDataOffset(outputCoords, volume);

    // Initialize variables
    int   closestBackfaceIndex = -1;
    int   closestFrontfaceIndex = -1;
    int   farthestFrontfaceIndex = -1;
    float closestBackfaceDistance = 1e27f;
    float closestFrontfaceDistance = 1e27f;
    float farthestFrontfaceDistance = 0.f;
    float backfaceCount = 0.f;

    // Get the number of rays to inspect
    int numRays = min(volume.probeNumRays, DDGI_NUM_FIXED_RAYS);

    // Iterate over the rays cast for this probe to find the number of backfaces and closest/farthest distances to the probe
    for (int rayIndex = 0; rayIndex < numRays; rayIndex++)
    {
        // Get the coordinates for the probe ray in the RayData texture array
        uvec3 rayDataTexCoords = DDGIGetRayDataTexelCoords(rayIndex, int(probeIndex), volume);

        // Load the hit distance for the ray
        float hitDistance = DDGILoadProbeRayDistance(rayDataTexCoords, volume);

        if (hitDistance < 0.f)
        {
            // Found a backface
            backfaceCount++;

            // Negate the hit distance on a backface hit and scale back to the full distance
            hitDistance = hitDistance * -5.f;
            if (hitDistance < closestBackfaceDistance)
            {
                // Store the closest backface distance and ray index
                closestBackfaceDistance = hitDistance;
                closestBackfaceIndex = rayIndex;
            }
        }
        else
        {
            // Found a frontface
            if (hitDistance < closestFrontfaceDistance)
            {
                // Store the closest frontface distance and ray index
                closestFrontfaceDistance = hitDistance;
                closestFrontfaceIndex = rayIndex;
            }
            else if (hitDistance > farthestFrontfaceDistance)
            {
                // Store the farthest frontface distance and ray index
                farthestFrontfaceDistance = hitDistance;
                farthestFrontfaceIndex = rayIndex;
            }
        }
    }

    vec3 fullOffset = vec3(1e27f, 1e27f, 1e27f);

    if (closestBackfaceIndex != -1 && float(backfaceCount) / float(numRays) > volume.probeFixedRayBackfaceThreshold)
    {
        // If at least one backface triangle is hit AND backfaces are hit by enough probe rays,
        // assume the probe is inside geometry and move it outside of the geometry.
        vec3 closestBackfaceDirection = DDGIGetProbeRayDirection(closestBackfaceIndex, volume);
        fullOffset = offset + (closestBackfaceDirection * (closestBackfaceDistance + volume.probeMinFrontfaceDistance * 0.5f));
    }
    else if (closestFrontfaceDistance < volume.probeMinFrontfaceDistance)
    {
        // Don't move the probe if moving towards the farthest frontface will also bring us closer to the nearest frontface
        vec3 closestFrontfaceDirection = DDGIGetProbeRayDirection(closestFrontfaceIndex, volume);
        vec3 farthestFrontfaceDirection = DDGIGetProbeRayDirection(farthestFrontfaceIndex, volume);

        if (dot(closestFrontfaceDirection, farthestFrontfaceDirection) <= 0.f)
        {
            // Ensures the probe never moves through the farthest frontface
            farthestFrontfaceDirection *= min(farthestFrontfaceDistance, 1.f);
            fullOffset = offset + farthestFrontfaceDirection;
        }
    }
    else if (closestFrontfaceDistance > volume.probeMinFrontfaceDistance)
    {
        // Probe isn't near anything, try to move it back towards zero offset
        float moveBackMargin = min(closestFrontfaceDistance - volume.probeMinFrontfaceDistance, length(offset));
        vec3 moveBackDirection = normalize(-offset);
        fullOffset = offset + (moveBackMargin * moveBackDirection);
    }


    // Absolute maximum distance that probe could be moved should satisfy ellipsoid equation:
    // x^2 / probeGridSpacing.x^2 + y^2 / probeGridSpacing.y^2 + z^2 / probeGridSpacing.y^2 < (0.5)^2
    // Clamp to less than maximum distance to avoid degenerate cases
    vec3 normalizedOffset = fullOffset / volume.probeSpacing;
    if (dot(normalizedOffset, normalizedOffset) < 0.2025f) // 0.45 * 0.45 == 0.2025
    {
        offset = fullOffset;
    }

    // Write the probe offsets
    DDGIStoreProbeDataOffset(outputCoords, offset, volume);
}
