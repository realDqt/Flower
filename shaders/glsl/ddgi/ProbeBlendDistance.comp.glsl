#version 460
#extension GL_GOOGLE_include_directive : require
#include "Utils.glsl"
#include "DDGIPushConstants.glsl"
#include "ProbeIndexing.glsl"
#include "DDGIVolumeDescGPU.glsl"
#include "ProbeCommon.glsl"

layout(binding = 0, set = 0) readonly buffer DDGIVolumeDescGPUPackedBlock {DDGIVolumeDescGPUPacked d[];} DDGIVolumes;
layout(binding = 1, set = 0, rg32f) uniform image2DArray ProbeDistance;
layout(binding = 2, set = 0, rgba32f) uniform readonly image2DArray RayData;


DDGIVolumeDescGPUPacked GetDDGIVolumeConstants(uint index) { return DDGIVolumes.d[index]; }
layout(local_size_x = DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE, local_size_y = DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE, local_size_z  = 1) in;


float DDGILoadProbeState(int probeIndex, DDGIVolumeDescGPU volume)
{
    float state = DDGI_PROBE_STATE_ACTIVE;
    if (volume.probeClassificationEnabled)
    {
        // TODO
        /*
        // Get the probe's texel coordinates in the Probe Data texture
        uvec3 probeDataCoords = DDGIGetProbeTexelCoords(probeIndex, volume);

        // Get the probe's classification state
        state = texelFetch(ProbeData, ivec3(probeDataCoords)).w;
        */
    }

    return state;
}

vec3 DDGILoadProbeRayRadiance(uvec3 coords, DDGIVolumeDescGPU volume)
{
    return imageLoad(RayData, ivec3(coords)).rgb;
}

float DDGILoadProbeRayDistance(uvec3 coords, DDGIVolumeDescGPU volume)
{
    return imageLoad(RayData, ivec3(coords)).a;
}

// When the thread maps to a border texel, update it with the latest blended information for later use in bilinear filtering
void UpdateBorderTexel(uvec3 DispatchThreadID, uvec3 GroupThreadID, uvec3 GroupID, DDGIVolumeDescGPU volume)
{
    bool isCornerTexel = bool((GroupThreadID.x == 0 || GroupThreadID.x == (DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE - 1)) && (GroupThreadID.y == 0 || GroupThreadID.y == (DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE - 1)));
    bool isRowTexel = bool((GroupThreadID.x > 0 && GroupThreadID.x < (DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE - 1)));

    uvec3 copyCoordinates = uvec3(GroupID.x * DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE, GroupID.y * DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE, DispatchThreadID.z);

    if(isCornerTexel)
    {
        copyCoordinates.x += GroupThreadID.x > 0 ? 1 : DDGI_PROBE_IRRADIANCE_SIDE;
        copyCoordinates.y += GroupThreadID.y > 0 ? 1 : DDGI_PROBE_IRRADIANCE_SIDE;
    }
    else if(isRowTexel)
    {
        copyCoordinates.x += (DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE - 1) - GroupThreadID.x;
        copyCoordinates.y += GroupThreadID.y + ((GroupThreadID.y > 0) ? -1 : 1);
    }
    else // Column Texel
    {
        copyCoordinates.x += GroupThreadID.x + ((GroupThreadID.x > 0) ? -1 : 1);
        copyCoordinates.y += (DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE - 1) - GroupThreadID.y;
    }


    vec2 src = imageLoad(ProbeDistance, ivec3(copyCoordinates)).rg;
    imageStore(ProbeDistance, ivec3(DispatchThreadID), vec4(src, 0.f, 1.f));
}

void main()
{
    uvec3 DispatchThreadID = gl_GlobalInvocationID;
    uvec3 GroupThreadID = gl_LocalInvocationID;
    uvec3 GroupID = gl_WorkGroupID;
    uint GroupIndex = gl_LocalInvocationIndex;

    bool isBorderTexel = bool(GroupThreadID.x == 0 || GroupThreadID.x == (DDGI_PROBE_IRRADIANCE_SIDE + 1));
    isBorderTexel = (isBorderTexel || bool(GroupThreadID.y == 0 || GroupThreadID.y == (DDGI_PROBE_IRRADIANCE_SIDE + 1)));

    uint volumeIndex = GetDDGIVolumeIndex();
    DDGIVolumeDescGPU volume = UnpackDDGIVolumeDescGPU(GetDDGIVolumeConstants(volumeIndex));

    int probeIndex = DDGIGetProbeIndex(DispatchThreadID, int(DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE), volume);
    uint numProbes = (volume.probeCounts.x * volume.probeCounts.y * volume.probeCounts.z);
    if (probeIndex >= numProbes || probeIndex < 0) return;

    if(!isBorderTexel){
        ivec3 threadCoords = ivec3(GroupID.x * DDGI_PROBE_IRRADIANCE_SIDE, GroupID.y * DDGI_PROBE_IRRADIANCE_SIDE, DispatchThreadID.z) + ivec3(GroupThreadID) - ivec3(1, 1, 0);

        if (IsVolumeMovementScrolling(volume))
        {
            // TODO
        }

        // Early out: don't blend rays for probes that are inactive
        float probeState = DDGILoadProbeState(probeIndex, volume);
        if (probeState == DDGI_PROBE_STATE_INACTIVE)
        {
            // TODO
        }

        // Get the probe ray direction associated with this thread
        vec2 probeOctantUV = DDGIGetNormalizedOctahedralCoordinates(ivec2(threadCoords.xy), int(DDGI_PROBE_IRRADIANCE_SIDE));
        vec3 probeRayDirection = DDGIGetOctahedralDirection(probeOctantUV);

        int rayIndex = 0;

        if(volume.probeRelocationEnabled || volume.probeClassificationEnabled)
        {
            // TODO
        }


        vec4 result = vec4(0.f, 0.f, 0.f, 0.f);
        for ( ; rayIndex < volume.probeNumRays; rayIndex++){
            vec3 rayDirection = DDGIGetProbeRayDirection(rayIndex, volume);
            float weight = max(0.f, dot(probeRayDirection, rayDirection));
            uvec3 rayDataTexCoords = DDGIGetRayDataTexelCoords(rayIndex, probeIndex, volume);

            // Initialize the max probe hit distance to 50% larger the maximum distance between probe grid cells
            float probeMaxRayDistance = length(volume.probeSpacing) * 1.5f;

            // Increase or decrease the filtered distance value's "sharpness"
            weight = pow(weight, volume.probeDistanceExponent);

            // Load the ray traced distance
            // Hit distance is negative on backface hits (for probe relocation), so take the absolute value of the loaded data
            float probeRayDistance = min(abs(DDGILoadProbeRayDistance(rayDataTexCoords, volume)), probeMaxRayDistance);

            // Filter the ray hit distance
            result += vec4(probeRayDistance * weight, (probeRayDistance * probeRayDistance) * weight, 0.f, weight);
        }

        float epsilon = float(volume.probeNumRays);
        if (volume.probeRelocationEnabled || volume.probeClassificationEnabled)
        {
            // TODO
        }
        epsilon *= 1e-9f;

        result.rgb *= 1.f / (2.f * max(result.a, epsilon));
        result.a = 1.f;


        vec2 probeDistanceMean = imageLoad(ProbeDistance, ivec3(DispatchThreadID)).rg;
        float  hysteresis = volume.probeHysteresis;
        if (dot(probeDistanceMean, probeDistanceMean) == 0) hysteresis = 0.f;

        // Interpolate the new filtered distance with the existing filtered distance in the probe.
        // A high hysteresis value emphasizes the existing probe filtered distance.
        result = vec4(mix(result.rg, probeDistanceMean.rg, hysteresis), 0.f, 1.f);
        imageStore(ProbeDistance, ivec3(DispatchThreadID), result);
        return;
    }

    memoryBarrier(); // 确保所有内存写入对所有线程可见
    barrier();       // 确保组内所有线程都到达此点（执行同步）

    UpdateBorderTexel(DispatchThreadID, GroupThreadID, GroupID, volume);

}