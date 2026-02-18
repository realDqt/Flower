#ifndef PROBE_COMMON_GLSL
#define PROBE_COMMON_GLSL
#include "Common.glsl"
#include "ProbeIndexing.glsl"
#include "utils.glsl"
#include "ProbeOctahedral.glsl"



//------------------------------------------------------------------------
// Probe World Position
//------------------------------------------------------------------------

/**
 * Computes the world-space position of a probe from the probe's 3D grid-space coordinates.
 * Probe relocation is not considered.
 */
vec3 DDGIGetProbeWorldPosition(ivec3 probeCoords, DDGIVolumeDescGPU volume)
{
    // Multiply the grid coordinates by the probe spacing
    vec3 probeGridWorldPosition = vec3(probeCoords * volume.probeSpacing);

    // Shift the grid of probes by half of each axis extent to center the volume about its origin
    vec3 probeGridShift = (volume.probeSpacing * (volume.probeCounts - 1)) * 0.5f;

    // Center the probe grid about the origin
    vec3 probeWorldPosition = (probeGridWorldPosition - probeGridShift);

    // Rotate the probe grid if infinite scrolling is not enabled
    if (!IsVolumeMovementScrolling(volume)) probeWorldPosition = QuaternionRotate(probeWorldPosition, volume.rotation);

    // Translate the grid to the volume's center
    probeWorldPosition += volume.origin + (volume.probeScrollOffsets * volume.probeSpacing);

    return probeWorldPosition;
}

/**
 * Computes a spherically distributed, normalized ray direction for the given ray index in a set of ray samples.
 * Applies the volume's random probe ray rotation transformation to "non-fixed" ray direction samples.
 */
vec3 DDGIGetProbeRayDirection(int rayIndex, DDGIVolumeDescGPU volume)
{
    bool isFixedRay = false;
    int sampleIndex = rayIndex;
    int numRays = volume.probeNumRays;

    if (volume.probeRelocationEnabled || volume.probeClassificationEnabled)
    {
        // TODO
    }

    // Get a ray direction on the sphere
    vec3 direction = SphericalFibonacci(sampleIndex, numRays);

    // Don't rotate fixed rays so relocation/classification are temporally stable
    if (isFixedRay) return normalize(direction);

    // Apply a random rotation and normalize the direction
    return normalize(QuaternionRotate(direction, QuaternionConjugate(volume.probeRayRotation)));
}

/**
 * Computes the surfaceBias parameter used by DDGIGetVolumeIrradiance().
 * The surfaceNormal and cameraDirection arguments are expected to be normalized.
 */
vec3 DDGIGetSurfaceBias(vec3 surfaceNormal, vec3 cameraDirection, DDGIVolumeDescGPU volume)
{
    return (surfaceNormal * volume.probeNormalBias) + (-cameraDirection * volume.probeViewBias);
}

/**
 * Computes a weight value in the range [0, 1] for a world position and volume pair.
 * All positions inside the given volume recieve a weight of 1.
 * Positions outside the volume receive a weight in [0, 1] that
 * decreases as the position moves away from the volume.
 */
float DDGIGetVolumeBlendWeight(vec3 worldPosition, DDGIVolumeDescGPU volume)
{
    // Get the volume's origin and extent
    vec3 origin = volume.origin + (volume.probeScrollOffsets * volume.probeSpacing);
    vec3 extent = (volume.probeSpacing * (volume.probeCounts - 1)) * 0.5f;

    // Get the delta between the (rotated volume) and the world-space position
    vec3 position = (worldPosition - origin);
    position = abs(QuaternionRotate(position, QuaternionConjugate(volume.rotation)));

    vec3 delta = position - extent;
    if(delta.x < 0.f && delta.y < 0.f && delta.z < 0.f) return 1.f;

    // Adjust the blend weight for each axis
    float volumeBlendWeight = 1.f;
    volumeBlendWeight *= (1.f - saturate(delta.x / volume.probeSpacing.x));
    volumeBlendWeight *= (1.f - saturate(delta.y / volume.probeSpacing.y));
    volumeBlendWeight *= (1.f - saturate(delta.z / volume.probeSpacing.z));

    return volumeBlendWeight;
}
#endif