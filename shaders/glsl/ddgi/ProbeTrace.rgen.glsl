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

DDGIVolumeDescGPUPacked GetDDGIVolumeConstants(uint index) { return DDGIVolumes.d[index]; }

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
    imageStore(RayData, ivec3(coords), vec4(radiance, 1e27f));
}

bool IsVisible(vec3 posW, vec3 normW, DirectionalLight light)
{
    Ray ray;
    ray.origin = posW + normW * 0.001f;
    ray.direction = -light.lightDir;
    ray.tmin = 0.001f;
    ray.tmax = 10000.0f;
    hitValue.dis = 1.f;
    traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT | gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsSkipClosestHitShaderEXT, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);
    return hitValue.dis < 0.f;
}

vec3 EvalDiffuseLighting(vec3 posW, vec3 normW, vec3 baseColor, vec3 wo, DirectionalLight light)
{
    if(IsVisible(posW, normW, light)){
        vec3 brdf = evalDiffuseBRDF(-light.lightDir, wo, normW, baseColor);
        return light.lightIntensity * brdf * max(dot(-light.lightDir, normW), 0.f);
    }
    return vec3(0.f);
}

/**
 * Computes the world-space position of a probe from the probe's 3D grid-space coordinates.
 * When probe relocation is enabled, offsets are loaded from the probe data
 * Texture2D and used to adjust the final world position.
 */
vec3 DDGIGetProbeWorldPositionRelocation(ivec3 probeCoords, DDGIVolumeDescGPU volume)
{
    // Get the probe's world-space position
    vec3 probeWorldPosition = DDGIGetProbeWorldPosition(probeCoords, volume);

    // If the volume has probe relocation enabled, account for the probe offsets
    if (volume.probeRelocationEnabled)
    {
        // TODO
    }

    return probeWorldPosition;
}

/**
 * Computes irradiance for the given world-position using the given volume, surface bias,
 * sampling direction, and volume resources.
 */
vec3 DDGIGetVolumeIrradiance(
    vec3 worldPosition,
    vec3 surfaceBias,
    vec3 direction,
    DDGIVolumeDescGPU volume)
{
    vec3 irradiance = vec3(0.f, 0.f, 0.f);
    float  accumulatedWeights = 0.f;

    // Bias the world space position
    vec3 biasedWorldPosition = (worldPosition + surfaceBias);

    // Get the 3D grid coordinates of the probe nearest the biased world position (i.e. the "base" probe)
    ivec3   baseProbeCoords = DDGIGetBaseProbeGridCoords(biasedWorldPosition, volume);

    // Get the world-space position of the base probe (ignore relocation)
    vec3 baseProbeWorldPosition = DDGIGetProbeWorldPosition(baseProbeCoords, volume);

    // Clamp the distance (in grid space) between the given point and the base probe's world position (on each axis) to [0, 1]
    vec3 gridSpaceDistance = (biasedWorldPosition - baseProbeWorldPosition);
    if(!IsVolumeMovementScrolling(volume)) gridSpaceDistance = QuaternionRotate(gridSpaceDistance, QuaternionConjugate(volume.rotation));
    vec3 alpha = clamp((gridSpaceDistance / volume.probeSpacing), vec3(0.f, 0.f, 0.f), vec3(1.f, 1.f, 1.f));

    // Iterate over the 8 closest probes and accumulate their contributions
    for(int probeIndex = 0; probeIndex < 8; probeIndex++)
    {
        // Compute the offset to the adjacent probe in grid coordinates by
        // sourcing the offsets from the bits of the loop index: x = bit 0, y = bit 1, z = bit 2
        ivec3 adjacentProbeOffset = ivec3(probeIndex, probeIndex >> 1, probeIndex >> 2) & ivec3(1, 1, 1);

        // Get the 3D grid coordinates of the adjacent probe by adding the offset to
        // the base probe and clamping to the grid boundaries
        ivec3 adjacentProbeCoords = clamp(baseProbeCoords + adjacentProbeOffset, ivec3(0, 0, 0), volume.probeCounts - ivec3(1, 1, 1));

        // Get the adjacent probe's index, adjusting the adjacent probe index for scrolling offsets (if present)
        int adjacentProbeIndex = DDGIGetScrollingProbeIndex(adjacentProbeCoords, volume);

        // Early Out: don't allow inactive probes to contribute to irradiance
        float probeState = DDGILoadProbeState(adjacentProbeIndex, volume);
        if (probeState == DDGI_PROBE_STATE_INACTIVE) continue;

        // Get the adjacent probe's world position
        vec3 adjacentProbeWorldPosition = DDGIGetProbeWorldPositionRelocation(adjacentProbeCoords, volume); // TODO relocation

        // Compute the distance and direction from the (biased and non-biased) shading point and the adjacent probe
        vec3 worldPosToAdjProbe = normalize(adjacentProbeWorldPosition - worldPosition);
        vec3 biasedPosToAdjProbe = normalize(adjacentProbeWorldPosition - biasedWorldPosition);
        float  biasedPosToAdjProbeDist = length(adjacentProbeWorldPosition - biasedWorldPosition);

        // Compute trilinear weights based on the distance to each adjacent probe
        // to smoothly transition between probes. adjacentProbeOffset is binary, so we're
        // using a 1-alpha when adjacentProbeOffset = 0 and alpha when adjacentProbeOffset = 1.
        vec3 trilinear = max(vec3(0.001f), mix(1.f - alpha, alpha, adjacentProbeOffset));
        float  trilinearWeight = (trilinear.x * trilinear.y * trilinear.z);
        float  weight = 1.f;

        // A naive soft backface weight would ignore a probe when
        // it is behind the surface. That's good for walls, but for
        // small details inside of a room, the normals on the details
        // might rule out all of the probes that have mutual visibility
        // to the point. We instead use a "wrap shading" test. The small
        // offset at the end reduces the "going to zero" impact.
        float wrapShading = (dot(worldPosToAdjProbe, direction) + 1.f) * 0.5f;
        weight *= (wrapShading * wrapShading) + 0.2f;

        // Compute the octahedral coordinates of the adjacent probe
        vec2 octantCoords = DDGIGetOctahedralCoordinates(-biasedPosToAdjProbe);

        // Get the texture array coordinates for the octant of the probe
        vec3 probeTextureUV = DDGIGetProbeUV(adjacentProbeIndex, octantCoords, volume.probeNumDistanceInteriorTexels, volume);

        // Sample the probe's distance texture to get the mean distance to nearby surfaces
        vec2 filteredDistance = 2.f * textureLod(ProbeDistance, probeTextureUV, 0).rg; // bilinear

        // Find the variance of the mean distance
        float variance = abs((filteredDistance.x * filteredDistance.x) - filteredDistance.y);

        // Occlusion test
        float chebyshevWeight = 1.f;
        if(biasedPosToAdjProbeDist > filteredDistance.x) // occluded
        {
            // v must be greater than 0, which is guaranteed by the if condition above.
            float v = biasedPosToAdjProbeDist - filteredDistance.x;
            chebyshevWeight = variance / (variance + (v * v));

            // Increase the contrast in the weight
            chebyshevWeight = max((chebyshevWeight * chebyshevWeight * chebyshevWeight), 0.f);
        }

        // Avoid visibility weights ever going all the way to zero because
        // when *no* probe has visibility we need a fallback value
        weight *= max(0.05f, chebyshevWeight);

        // Avoid a weight of zero
        weight = max(0.000001f, weight);

        // A small amount of light is visible due to logarithmic perception, so
        // crush tiny weights but keep the curve continuous
        const float crushThreshold = 0.2f;
        if (weight < crushThreshold)
        {
            weight *= (weight * weight) * (1.f / (crushThreshold * crushThreshold));
        }

        // Apply the trilinear weights
        weight *= trilinearWeight;

        // Get the octahedral coordinates for the sample direction
        octantCoords = DDGIGetOctahedralCoordinates(direction);

        // Get the probe's texture coordinates
        probeTextureUV = DDGIGetProbeUV(adjacentProbeIndex, octantCoords, volume.probeNumIrradianceInteriorTexels, volume);

        // Sample the probe's irradiance
        vec3 probeIrradiance = textureLod(ProbeIrradiance, probeTextureUV, 0).rgb; // bilinear

        // Decode the tone curve, but leave a gamma = 2 curve to approximate sRGB blending
        vec3 exponent = vec3(volume.probeIrradianceEncodingGamma * 0.5f);
        probeIrradiance = pow(probeIrradiance, exponent);

        // Accumulate the weighted irradiance
        irradiance += (weight * probeIrradiance);
        accumulatedWeights += weight;
    }

    if(accumulatedWeights == 0.f) return vec3(0.f, 0.f, 0.f);

    irradiance *= (1.f / accumulatedWeights);   // Normalize by the accumulated weights
    irradiance *= irradiance;                   // Go back to linear irradiance
    irradiance *= M_2PI;                    // Multiply by the area of the integration domain (hemisphere) to complete the Monte Carlo Estimator equation

    // Adjust for energy loss due to reduced precision in the R10G10B10A2 irradiance texture format
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

    vec3 probeWorldPosition = DDGIGetProbeWorldPosition(probeCoords, volume);

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
        // TODO
    }

    DirectionalLight light;
    initDirectionalLight(light);
    vec3 diffuse = EvalDiffuseLighting(hitValue.worldPos, hitValue.worldNormal, hitValue.mat.baseColor.rgb, -ray.direction, light);

    vec3 irradiance = vec3(0.f);
    vec3 surfaceBias = DDGIGetSurfaceBias(hitValue.worldNormal, ray.direction, volume);

    float volumeBlendWeight = DDGIGetVolumeBlendWeight(hitValue.worldPos, volume);

    // Don't evaluate irradiance when the surface is outside the volume
    if (volumeBlendWeight > 0)
    {
        // Get irradiance from the DDGIVolume
        irradiance = DDGIGetVolumeIrradiance(
            hitValue.worldPos,
            surfaceBias,
            hitValue.worldNormal,
            volume);

        // Attenuate irradiance by the blend weight
        irradiance *= volumeBlendWeight;
    }

    // Perfectly diffuse reflectors don't exist in the real world.
    // Limit the BRDF albedo to a maximum value to account for the energy loss at each bounce.
    float maxAlbedo = 0.9f;

    // Store the final ray radiance and hit distance
    vec3 radiance = diffuse + ((min(hitValue.mat.baseColor.rgb, vec3(maxAlbedo, maxAlbedo, maxAlbedo)) / M_PI) * irradiance);
    DDGIStoreProbeRayFrontfaceHit(outputCoords, volume, saturate(radiance), hitValue.dis);
}