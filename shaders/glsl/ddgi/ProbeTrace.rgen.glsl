#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_shader_image_load_formatted : enable

#include "Utils.glsl"
#include "DDGIPushConstants.glsl"
#include "ProbeIndexing.glsl"
#include "DDGIVolumeDescGPU.glsl"
#include "ProbeCommon.glsl"

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;
layout(binding = 1, set = 0) readonly buffer DDGIVolumeDescGPUPackedBlock {DDGIVolumeDescGPUPacked d[];} DDGIVolumes;
layout(binding = 2, set = 0) uniform sampler2DArray ProbeData;
layout(binding = 3, set = 0) uniform sampler2DArray ProbeIrradiance;
layout(binding = 4, set = 0) uniform sampler2DArray ProbeDistance;
layout(binding = 5, set = 0, rgba32f) uniform image2DArray RayData;

layout(location = 0) rayPayloadEXT RayPayload hitValue;
layout(location = 1) rayPayloadEXT bool shadowed;

DDGIVolumeDescGPUPacked GetDDGIVolumeConstants(uint index) { return DDGIVolumes.d[index]; }

float DDGILoadProbeState(int probeIndex, DDGIVolumeDescGPU volume)
{
    float state = DDGI_PROBE_STATE_ACTIVE;
    if (volume.probeClassificationEnabled)
    {
        uvec3 probeDataCoords = DDGIGetProbeTexelCoords(probeIndex, volume);
        
        state = texelFetch(ProbeData, ivec3(probeDataCoords), 0).w;
    }

    return state;
}

void DDGIStoreProbeRayMiss(uvec3 coords, DDGIVolumeDescGPU volume, vec3 radiance)
{
    imageStore(RayData, ivec3(coords), vec4(radiance, 1e27f));
}

void DDGIStoreProbeRayBackfaceHit(uvec3 coords, DDGIVolumeDescGPU volume, float hitT)
{
    imageStore(RayData, ivec3(coords), vec4(vec3(0.f), -hitT * 0.2f));
}

void DDGIStoreProbeRayFrontfaceHit(uvec3 coords, DDGIVolumeDescGPU volume, vec3 radiance, float hitT)
{
    imageStore(RayData, ivec3(coords), vec4(radiance, hitT));
}

bool IsVisible(vec3 posW, vec3 normW, DirectionalLight light)
{
    Ray ray;
    ray.origin = posW + normW * 0.001f;
    ray.direction = -light.lightDir;
    ray.tmin = 0.001f;
    ray.tmax = 10000.0f;
    shadowed = true;
    traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT | gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsSkipClosestHitShaderEXT, 0xff, 0, 0, 1, ray.origin, ray.tmin, ray.direction, ray.tmax, 1);
    return !shadowed;
}

vec3 EvalDiffuseLighting(vec3 posW, vec3 normW, vec3 baseColor, vec3 wo, DirectionalLight light)
{
    if(IsVisible(posW, normW, light)){
        vec3 brdf = evalDiffuseBRDF(-light.lightDir, wo, normW, baseColor);
        return light.lightIntensity * brdf * max(dot(-light.lightDir, normW), 0.f);
    }
    return vec3(0.f);
}

vec3 DDGILoadProbeDataOffset(uvec3 coords, DDGIVolumeDescGPU volume)
{
    return texelFetch(ProbeData, ivec3(coords), 0).xyz * volume.probeSpacing;
}

vec3 DDGIGetProbeWorldPositionWithRelocation(ivec3 probeCoords, DDGIVolumeDescGPU volume)
{
    vec3 probeWorldPosition = DDGIGetProbeWorldPosition(probeCoords, volume);
    
    if (volume.probeRelocationEnabled)
    {
        int probeIndex = DDGIGetScrollingProbeIndex(probeCoords, volume);
        
        uvec3 coords = DDGIGetProbeTexelCoords(probeIndex, volume);
        
        probeWorldPosition += DDGILoadProbeDataOffset(coords, volume);

    }

    return probeWorldPosition;
}

void DDGIStoreProbeRayFrontfaceHit(uvec3 coords, DDGIVolumeDescGPU volume, float hitT)
{
    imageStore(RayData, ivec3(coords), vec4(vec3(0.0), hitT));
}


vec3 DDGIGetVolumeIrradiance(
    vec3 worldPosition,
    vec3 surfaceBias,
    vec3 direction,
    DDGIVolumeDescGPU volume)
{
    vec3 irradiance = vec3(0.f, 0.f, 0.f);
    float  accumulatedWeights = 0.f;
    
    vec3 biasedWorldPosition = (worldPosition + surfaceBias);
    
    ivec3   baseProbeCoords = DDGIGetBaseProbeGridCoords(biasedWorldPosition, volume);
    
    vec3 baseProbeWorldPosition = DDGIGetProbeWorldPosition(baseProbeCoords, volume);
    
    vec3 gridSpaceDistance = (biasedWorldPosition - baseProbeWorldPosition);
    if(!IsVolumeMovementScrolling(volume)) gridSpaceDistance = QuaternionRotate(gridSpaceDistance, QuaternionConjugate(volume.rotation));
    vec3 alpha = clamp((gridSpaceDistance / volume.probeSpacing), vec3(0.f, 0.f, 0.f), vec3(1.f, 1.f, 1.f));
    
    for(int probeIndex = 0; probeIndex < 8; probeIndex++)
    {
        // Compute the offset to the adjacent probe in grid coordinates by
        // sourcing the offsets from the bits of the loop index: x = bit 0, y = bit 1, z = bit 2
        ivec3 adjacentProbeOffset = ivec3(probeIndex, probeIndex >> 1, probeIndex >> 2) & ivec3(1, 1, 1);
        ivec3 adjacentProbeCoords = clamp(baseProbeCoords + adjacentProbeOffset, ivec3(0, 0, 0), volume.probeCounts - ivec3(1, 1, 1));
        
        int adjacentProbeIndex = DDGIGetScrollingProbeIndex(adjacentProbeCoords, volume);
        
        float probeState = DDGILoadProbeState(adjacentProbeIndex, volume);
        if (probeState == DDGI_PROBE_STATE_INACTIVE) continue;
        
        vec3 adjacentProbeWorldPosition = DDGIGetProbeWorldPositionWithRelocation(adjacentProbeCoords, volume);
        
        vec3 worldPosToAdjProbe = normalize(adjacentProbeWorldPosition - worldPosition);
        vec3 biasedPosToAdjProbe = normalize(adjacentProbeWorldPosition - biasedWorldPosition);
        float  biasedPosToAdjProbeDist = length(adjacentProbeWorldPosition - biasedWorldPosition);
        
        vec3 trilinear = max(vec3(0.001f), mix(1.f - alpha, alpha, adjacentProbeOffset));
        float  trilinearWeight = (trilinear.x * trilinear.y * trilinear.z);
        float  weight = 1.f;

        
        float wrapShading = (dot(worldPosToAdjProbe, direction) + 1.f) * 0.5f;
        weight *= (wrapShading * wrapShading) + 0.2f;
        
        vec2 octantCoords = DDGIGetOctahedralCoordinates(-biasedPosToAdjProbe);
        
        vec3 probeTextureUV = DDGIGetProbeUV(adjacentProbeIndex, octantCoords, volume.probeNumDistanceInteriorTexels, volume);

        // Sample the probe's distance texture to get the mean distance to nearby surfaces
        vec2 filteredDistance = 2.f * textureLod(ProbeDistance, probeTextureUV, 0).rg; // bilinear
        
        float variance = abs((filteredDistance.x * filteredDistance.x) - filteredDistance.y);
        variance = max(variance, 0.0005f); // make no sense

        // Occlusion test
        float chebyshevWeight = 1.f;
        if(DDGI_ENABLE_CHEBVSHEV_TEST && biasedPosToAdjProbeDist > filteredDistance.x) // occluded
        {
            float v = biasedPosToAdjProbeDist - filteredDistance.x;
            chebyshevWeight = variance / (variance + (v * v));
            
            chebyshevWeight = max((chebyshevWeight * chebyshevWeight * chebyshevWeight), 0.f);
        }
        
        weight *= max(0.05f, chebyshevWeight);
        weight = max(0.000001f, weight);
        
        const float crushThreshold = 0.2f;
        if (weight < crushThreshold)
        {
            weight *= (weight * weight) * (1.f / (crushThreshold * crushThreshold));
        }
        
        weight *= trilinearWeight;
        
        octantCoords = DDGIGetOctahedralCoordinates(direction);
        probeTextureUV = DDGIGetProbeUV(adjacentProbeIndex, octantCoords, volume.probeNumIrradianceInteriorTexels, volume);
        
        vec3 probeIrradiance = textureLod(ProbeIrradiance, probeTextureUV, 0).rgb; // bilinear
        
        vec3 exponent = vec3(volume.probeIrradianceEncodingGamma * 0.5f);
        probeIrradiance = pow(probeIrradiance, exponent);
        
        irradiance += (weight * probeIrradiance);
        accumulatedWeights += weight;
    }

    if(accumulatedWeights == 0.f) return vec3(0.f, 0.f, 0.f);

    irradiance *= (1.f / accumulatedWeights);   
    irradiance *= irradiance;                  
    irradiance *= M_2PI;                    // Multiply by the area of the integration domain (hemisphere) to complete the Monte Carlo Estimator equation
    
    if (volume.probeIrradianceFormat == DDGI_VOLUME_TEXTURE_FORMAT_U32)
    {
        irradiance *= 1.0989f;
    }

    return irradiance;
}


void main() {

    uint volumeIndex = GetDDGIVolumeIndex();
    DDGIVolumeDescGPU volume = UnpackDDGIVolumeDescGPU(GetDDGIVolumeConstants(volumeIndex));

    int rayIndex = int(gl_LaunchIDEXT.x);
    int probePlaneIndex = int(gl_LaunchIDEXT.y);
    int planeIndex = int(gl_LaunchIDEXT.z);

    int probesPerPlane = DDGIGetProbesPerPlane(volume.probeCounts);

    int probeIndex = (planeIndex * probesPerPlane) + probePlaneIndex;

    ivec3 probeCoords = DDGIGetProbeCoords(probeIndex, volume);

    probeIndex = DDGIGetScrollingProbeIndex(probeCoords, volume);

    float probeState = DDGILoadProbeState(probeIndex, volume);

    if (probeState == DDGI_PROBE_STATE_INACTIVE && rayIndex >= DDGI_NUM_FIXED_RAYS) return;

    vec3 probeWorldPosition = DDGIGetProbeWorldPositionWithRelocation(probeCoords, volume);

    vec3 probeRayDirection = DDGIGetProbeRayDirection(rayIndex, volume);

    uvec3 outputCoords = DDGIGetRayDataTexelCoords(rayIndex, probeIndex, volume);

    Ray ray;
    ray.origin = probeWorldPosition;
    ray.direction = probeRayDirection;
    ray.tmin = 0.f;
    ray.tmax = volume.probeMaxRayDistance;

    traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);

    if(hitValue.dis < 0.0f){
        DDGIStoreProbeRayMiss(outputCoords, volume, vec3(0.f));
        return;
    }
    

    if(hitValue.hitKind == gl_HitKindBackFacingTriangleEXT){
        DDGIStoreProbeRayBackfaceHit(outputCoords, volume, hitValue.dis);
        return;
    }


    if((volume.probeRelocationEnabled || volume.probeClassificationEnabled) && rayIndex < DDGI_NUM_FIXED_RAYS)
    {
        DDGIStoreProbeRayFrontfaceHit(outputCoords, volume, hitValue.dis);
        return;
    }


    DirectionalLight light = getGlobalDirectionalLight();

    vec3 diffuse = EvalDiffuseLighting(hitValue.worldPos, hitValue.worldNormal, hitValue.mat.baseColor.rgb, -ray.direction, light);

    vec3 irradiance = vec3(0.f);
    vec3 surfaceBias = DDGIGetSurfaceBias(hitValue.worldNormal, ray.direction, volume);

    float volumeBlendWeight = DDGIGetVolumeBlendWeight(hitValue.worldPos, volume);
    
    if (volumeBlendWeight > 0)
    {
        irradiance = DDGIGetVolumeIrradiance(
            hitValue.worldPos,
            surfaceBias,
            hitValue.worldNormal,
            volume);
        
        irradiance *= volumeBlendWeight;
    }
    
    float maxAlbedo = 0.9f;
    vec3 radiance = diffuse + ((min(hitValue.mat.baseColor.rgb, vec3(maxAlbedo, maxAlbedo, maxAlbedo)) / M_PI) * irradiance);

    DDGIStoreProbeRayFrontfaceHit(outputCoords, volume, saturate(radiance), hitValue.dis);
}