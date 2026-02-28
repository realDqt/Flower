#ifndef PROBE_COMMON_GLSL
#define PROBE_COMMON_GLSL
#include "Common.glsl"
#include "ProbeIndexing.glsl"
#include "utils.glsl"
#include "ProbeOctahedral.glsl"



vec3 DDGIGetProbeWorldPosition(ivec3 probeCoords, DDGIVolumeDescGPU volume)
{

    vec3 probeGridWorldPosition = vec3(probeCoords * volume.probeSpacing);
    
    vec3 probeGridShift = (volume.probeSpacing * (volume.probeCounts - 1)) * 0.5f;
    
    vec3 probeWorldPosition = (probeGridWorldPosition - probeGridShift);
    
    if (!IsVolumeMovementScrolling(volume)) probeWorldPosition = QuaternionRotate(probeWorldPosition, volume.rotation);
    
    probeWorldPosition += volume.origin + (volume.probeScrollOffsets * volume.probeSpacing);

    return probeWorldPosition;
}

vec3 DDGIGetProbeRayDirection(int rayIndex, DDGIVolumeDescGPU volume)
{
    bool isFixedRay = false;
    int sampleIndex = rayIndex;
    int numRays = volume.probeNumRays;

    if (volume.probeRelocationEnabled || volume.probeClassificationEnabled)
    {
        isFixedRay = (rayIndex < DDGI_NUM_FIXED_RAYS);
        sampleIndex = isFixedRay ? rayIndex : (rayIndex - DDGI_NUM_FIXED_RAYS);
        numRays = isFixedRay ? DDGI_NUM_FIXED_RAYS : (numRays - DDGI_NUM_FIXED_RAYS);
    }
    
    vec3 direction = SphericalFibonacci(sampleIndex, numRays);
    
    if (isFixedRay) return normalize(direction);
    
    return normalize(QuaternionRotate(direction, QuaternionConjugate(volume.probeRayRotation)));
}


vec3 DDGIGetSurfaceBias(vec3 surfaceNormal, vec3 cameraDirection, DDGIVolumeDescGPU volume)
{
    return (surfaceNormal * volume.probeNormalBias) + (-cameraDirection * volume.probeViewBias);
}


float DDGIGetVolumeBlendWeight(vec3 worldPosition, DDGIVolumeDescGPU volume)
{
    vec3 origin = volume.origin + (volume.probeScrollOffsets * volume.probeSpacing);
    vec3 extent = (volume.probeSpacing * (volume.probeCounts - 1)) * 0.5f;
    
    vec3 position = (worldPosition - origin);
    position = abs(QuaternionRotate(position, QuaternionConjugate(volume.rotation)));

    vec3 delta = position - extent;
    if(delta.x < 0.f && delta.y < 0.f && delta.z < 0.f) return 1.f;
    
    float volumeBlendWeight = 1.f;
    volumeBlendWeight *= (1.f - saturate(delta.x / volume.probeSpacing.x));
    volumeBlendWeight *= (1.f - saturate(delta.y / volume.probeSpacing.y));
    volumeBlendWeight *= (1.f - saturate(delta.z / volume.probeSpacing.z));

    return volumeBlendWeight;
}
#endif