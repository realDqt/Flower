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

float DDGILoadProbeRayDistance(uvec3 coords, DDGIVolumeDescGPU volume)
{
    return imageLoad(RayData, ivec3(coords)).a;
}

void main()
{
    uint volumeIndex = GetDDGIVolumeIndex();
    DDGIVolumeDescGPU volume = UnpackDDGIVolumeDescGPU(GetDDGIVolumeConstants(volumeIndex));

    uvec3 DispatchID = gl_GlobalInvocationID;
    uint probeIndex = DispatchID.x;

    int numProbes = (volume.probeCounts.x * volume.probeCounts.y * volume.probeCounts.z);
    if (probeIndex >= numProbes) return;

    int rayIndex;
    int backfaceCount = 0;
    float hitDistances[DDGI_NUM_FIXED_RAYS];

    // Load the hit distances and count the number of backface hits
    for (rayIndex = 0; rayIndex < DDGI_NUM_FIXED_RAYS; rayIndex++)
    {
        // Get the coordinates for the probe ray in the RayData texture array
        uvec3 rayDataTexCoords = DDGIGetRayDataTexelCoords(rayIndex, int(probeIndex), volume);

        // Load the hit distance for the ray
        hitDistances[rayIndex] = DDGILoadProbeRayDistance(rayDataTexCoords, volume);

        // Increment the count if a backface is hit
        backfaceCount += (hitDistances[rayIndex] < 0.f ? 1 : 0) ;
    }

    uvec3 outputCoords = DDGIGetProbeTexelCoords(int(probeIndex), volume);

    vec3 normalizedOffset = imageLoad(ProbeData, ivec3(outputCoords)).xyz;
    // Early out: number of backface hits has been exceeded. The probe is probably inside geometry.
    if((float(backfaceCount) / float(DDGI_NUM_FIXED_RAYS)) > volume.probeFixedRayBackfaceThreshold)
    {
        imageStore(ProbeData, ivec3(outputCoords), vec4(normalizedOffset, DDGI_PROBE_STATE_INACTIVE));
        return;
    }

    // Get the world space position of the probe
    ivec3 probeCoords = DDGIGetProbeCoords(int(probeIndex), volume);
    vec3 probeWorldPosition = DDGIGetProbeWorldPosition(probeCoords, volume);

    // Determine if there is nearby geometry in the probe's voxel.
    // Iterate over the probe rays and compare ray hit distances with
    // the distance(s) to the probe's voxel planes.
    for (rayIndex = 0; rayIndex < DDGI_NUM_FIXED_RAYS; rayIndex++)
    {
        // Skip backface hits
        if(hitDistances[rayIndex] < 0) continue;

        // Get the direction of the "fixed" ray
        vec3 direction = DDGIGetProbeRayDirection(rayIndex, volume);

        // Get the plane normals
        vec3 xNormal = vec3(direction.x / max(abs(direction.x), 0.000001f), 0.f, 0.f);
        vec3 yNormal = vec3(0.f, direction.y / max(abs(direction.y), 0.000001f), 0.f);
        vec3 zNormal = vec3(0.f, 0.f, direction.z / max(abs(direction.z), 0.000001f));

        // Get the relevant planes to intersect
        vec3 p0x = probeWorldPosition + (volume.probeSpacing.x * xNormal);
        vec3 p0y = probeWorldPosition + (volume.probeSpacing.y * yNormal);
        vec3 p0z = probeWorldPosition + (volume.probeSpacing.z * zNormal);

        // Get the ray's intersection distance with each plane
        vec3 distances =
        {
            dot((p0x - probeWorldPosition), xNormal) / max(dot(direction, xNormal), 0.000001f),
            dot((p0y - probeWorldPosition), yNormal) / max(dot(direction, yNormal), 0.000001f),
            dot((p0z - probeWorldPosition), zNormal) / max(dot(direction, zNormal), 0.000001f)
        };

        // If the ray is parallel to the plane, it will never intersect
        // Set the distance to a very large number for those planes
        if (distances.x == 0.f) distances.x = 1e27f;
        if (distances.y == 0.f) distances.y = 1e27f;
        if (distances.z == 0.f) distances.z = 1e27f;

        // Get the distance to the closest plane intersection
        float maxDistance = min(distances.x, min(distances.y, distances.z));

        // If the hit distance is less than the closest plane intersection, the probe should be active
        if(hitDistances[rayIndex] <= maxDistance)
        {
            imageStore(ProbeData, ivec3(outputCoords), vec4(normalizedOffset, DDGI_PROBE_STATE_ACTIVE));
            return;
        }
    }

    imageStore(ProbeData, ivec3(outputCoords), vec4(normalizedOffset, DDGI_PROBE_STATE_INACTIVE));
}