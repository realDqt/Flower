#version 460
#extension GL_GOOGLE_include_directive : require
#include "Utils.glsl"
#include "DDGIPushConstants.glsl"
#include "ProbeIndexing.glsl"
#include "DDGIVolumeDescGPU.glsl"
#include "ProbeCommon.glsl"

layout(binding = 0, set = 0) readonly buffer DDGIVolumeDescGPUPackedBlock {DDGIVolumeDescGPUPacked d[];} DDGIVolumes;
layout(binding = 1, set = 0, rgba32f) uniform image2DArray ProbeIrradiance;
layout(binding = 2, set = 0, rgba32f) uniform readonly image2DArray RayData;
layout(binding = 3, set = 0, rgba32f) uniform readonly image2DArray ProbeData;


DDGIVolumeDescGPUPacked GetDDGIVolumeConstants(uint index) { return DDGIVolumes.d[index]; }
layout(local_size_x = DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE, local_size_y = DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE, local_size_z  = 1) in;


float DDGILoadProbeState(int probeIndex, DDGIVolumeDescGPU volume)
{
    float state = DDGI_PROBE_STATE_ACTIVE;
    if (volume.probeClassificationEnabled)
    {
        uvec3 probeDataCoords = DDGIGetProbeTexelCoords(probeIndex, volume);
        state = imageLoad(ProbeData, ivec3(probeDataCoords)).w;
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


    vec4 src = imageLoad(ProbeIrradiance, ivec3(copyCoordinates));
    imageStore(ProbeIrradiance, ivec3(DispatchThreadID), src);
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
            // TODO: Scrolling
        }
        
        float probeState = DDGILoadProbeState(probeIndex, volume);
        if (probeState == DDGI_PROBE_STATE_INACTIVE)
        {
            // TODO: Variability
            return;
        }
        
        vec2 probeOctantUV = DDGIGetNormalizedOctahedralCoordinates(ivec2(threadCoords.xy), int(DDGI_PROBE_IRRADIANCE_SIDE));
        vec3 probeRayDirection = DDGIGetOctahedralDirection(probeOctantUV);

        int rayIndex = 0;
        
        if(volume.probeRelocationEnabled || volume.probeClassificationEnabled)
        {
            rayIndex = DDGI_NUM_FIXED_RAYS;
        }

        uint backfaces = 0;
        uint maxBackfaces = uint((volume.probeNumRays - rayIndex) * volume.probeRandomRayBackfaceThreshold);

        vec4 result = vec4(0.f, 0.f, 0.f, 0.f);
        for ( ; rayIndex < volume.probeNumRays; rayIndex++){
            vec3 rayDirection = DDGIGetProbeRayDirection(rayIndex, volume);
            float weight = max(0.f, dot(probeRayDirection, rayDirection));
            uvec3 rayDataTexCoords = DDGIGetRayDataTexelCoords(rayIndex, probeIndex, volume);
            vec3 probeRayRadiance = DDGILoadProbeRayRadiance(rayDataTexCoords, volume);
            float  probeRayDistance = DDGILoadProbeRayDistance(rayDataTexCoords, volume);
            // Backface hit
            if (probeRayDistance < 0.f)
            {
                backfaces++;
                
                if (backfaces >= maxBackfaces) return;

                continue;
            }
            
            result += vec4(probeRayRadiance * weight, weight);
        }

        float epsilon = float(volume.probeNumRays);
        if (volume.probeRelocationEnabled || volume.probeClassificationEnabled)
        {
            epsilon -= DDGI_NUM_FIXED_RAYS;
        }
        epsilon *= 1e-9f;

        result.rgb *= 1.f / (2.f * max(result.a, epsilon));
        result.a = 1.f;


        vec3 probeIrradianceMean = imageLoad(ProbeIrradiance, ivec3(DispatchThreadID)).rgb;
        
        float  hysteresis = volume.probeHysteresis;
        if (dot(probeIrradianceMean, probeIrradianceMean) == 0) hysteresis = 0.f;
        
        result.rgb = pow(result.rgb, vec3(1.f / volume.probeIrradianceEncodingGamma));
        
        vec3 delta = (result.rgb - probeIrradianceMean.rgb);
        
        vec3 irradianceSample = result.rgb;

        if (MaxComponent(probeIrradianceMean.rgb - result.rgb) > volume.probeIrradianceThreshold)
        {
            // Lower the hysteresis when a large lighting change is detected
            hysteresis = max(0.f, hysteresis - 0.75f);
        }

        if (LinearRGBToLuminance(delta) > volume.probeBrightnessThreshold)
        {
            // Clamp the maximum per-update change in irradiance when a large brightness change is detected
            delta *= 0.25f;
        }

        const float c_threshold = 1.f / 1024.f;
        vec3 lerpDelta = (1.f - hysteresis) * delta;
        if (MaxComponent(result.rgb) < MaxComponent(probeIrradianceMean.rgb))
        {
            lerpDelta = min(max(vec3(c_threshold), abs(lerpDelta)), abs(delta)) * sign(lerpDelta);
        }
        result = vec4(probeIrradianceMean.rgb + lerpDelta, 1.f);

        if (volume.probeVariabilityEnabled)
        {
            // TODO: Variability
        }
        
        imageStore(ProbeIrradiance, ivec3(DispatchThreadID), result);
        return;
    }

    memoryBarrier(); // 确保所有内存写入对所有线程可见
    barrier();       // 确保组内所有线程都到达此点（执行同步）

    UpdateBorderTexel(DispatchThreadID, GroupThreadID, GroupID, volume);

}