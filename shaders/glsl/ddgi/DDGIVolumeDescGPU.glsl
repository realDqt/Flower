#ifndef DDGI_VOLUME_DESC_GPU_GLSL
#define DDGI_VOLUME_DESC_GPU_GLSL

/**
 * Describes the properties of a DDGIVolume, with values packed to compact formats.
 * This version of the struct uses 128B to store some values at full precision.
 */
struct DDGIVolumeDescGPUPacked
{
    vec3     origin;
    float    probeHysteresis;
    //------------------------------------------------- 16B
    vec4     rotation;
    //------------------------------------------------- 32B
    vec4     probeRayRotation;
    //------------------------------------------------- 48B
    float    probeMaxRayDistance;
    float    probeNormalBias;
    float    probeViewBias;
    float    probeDistanceExponent;
    //------------------------------------------------- 64B
    float    probeIrradianceEncodingGamma;
    float    probeIrradianceThreshold;
    float    probeBrightnessThreshold;
    float    probeMinFrontfaceDistance;
    //------------------------------------------------- 80B
    vec3     probeSpacing;
    uint     packed0;       // probeCounts.x (10), probeCounts.y (10), probeCounts.z (10), unused (2)
    //------------------------------------------------- 96B
    uint     packed1;       // probeRandomRayBackfaceThreshold (16), probeFixedRayBackfaceThreshold (16)
    uint     packed2;       // probeNumRays (16), probeNumIrradianceInteriorTexels (8), probeNumDistanceInteriorTexels (8)
    uint     packed3;       // probeScrollOffsets.x (15) sign bit (1), probeScrollOffsets.y (15) sign bit (1)
    uint     packed4;       // probeScrollOffsets.z (15) sign bit (1)
    // movementType (1), probeRayDataFormat (3), probeIrradianceFormat (3), probeRelocationEnabled (1)
    // probeClassificationEnabled (1), probeVariabilityEnabled (1)
    // probeScrollClear Y-Z plane (1), probeScrollClear X-Z plane (1), probeScrollClear X-Y plane (1)
    // probeScrollDirection Y-Z plane (1), probeScrollDirection X-Z plane (1), probeScrollDirection X-Y plane (1)
    //------------------------------------------------- 112B
    uvec4    reserved;      // 16B reserved for future use
    //------------------------------------------------- 128B
};


/**
 * Describes the properties of a DDGIVolume.
 */
struct DDGIVolumeDescGPU
{
    vec3     origin;                             // world-space location of the volume center

    vec4     rotation;                           // rotation quaternion for the volume
    vec4     probeRayRotation;                   // rotation quaternion for probe rays

    uint     movementType;                       // type of movement the volume allows. 0: default, 1: infinite scrolling

    vec3     probeSpacing;                       // world-space distance between probes
    ivec3    probeCounts;                        // number of probes on each axis of the volume

    int      probeNumRays;                       // number of rays traced per probe
    int      probeNumIrradianceInteriorTexels;   // number of texels in one dimension of a probe's irradiance texture (does not include 1-texel border)
    int      probeNumDistanceInteriorTexels;     // number of texels in one dimension of a probe's distance texture (does not include 1-texel border)

    float    probeHysteresis;                    // weight of the previous irradiance and distance data store in probes
    float    probeMaxRayDistance;                // maximum world-space distance a probe ray can travel
    float    probeNormalBias;                    // offset along the surface normal, applied during lighting to avoid numerical instabilities when determining visibility
    float    probeViewBias;                      // offset along the camera view ray, applied during lighting to avoid numerical instabilities when determining visibility
    float    probeDistanceExponent;              // exponent used during visibility testing. High values react rapidly to depth discontinuities, but may cause banding
    float    probeIrradianceEncodingGamma;       // exponent that perceptually encodes irradiance for faster light-to-dark convergence

    float    probeIrradianceThreshold;           // threshold to identify when large lighting changes occur
    float    probeBrightnessThreshold;           // threshold that specifies the maximum allowed difference in brightness between the previous and current irradiance values
    float    probeRandomRayBackfaceThreshold;    // threshold that specifies the ratio of *random* rays traced for a probe that may hit back facing triangles before the probe is considered inside geometry (used in blending)

    // Probe Relocation, Probe Classification
    float    probeFixedRayBackfaceThreshold;     // threshold that specifies the ratio of *fixed* rays traced for a probe that may hit back facing triangles before the probe is considered inside geometry (used in relocation & classification)
    float    probeMinFrontfaceDistance;          // minimum world-space distance to a front facing triangle allowed before a probe is relocated

    // Infinite Scrolling Volumes
    ivec3    probeScrollOffsets;                 // grid-space offsets used for scrolling movement
    bool     probeScrollClear[3];                // whether probes of a plane need to be cleared due to scrolling movement
    bool     probeScrollDirections[3];           // direction of scrolling movement (0: negative, 1: positive)

    // Feature Options
    uint     probeRayDataFormat;                 // texture format of the ray data texture (EDDGIVolumeTextureFormat)
    uint     probeIrradianceFormat;              // texture format of the irradiance texture (EDDGIVolumeTextureFormat)
    bool     probeRelocationEnabled;             // whether probe relocation is enabled for this volume
    bool     probeClassificationEnabled;         // whether probe classification is enabled for this volume
    bool     probeVariabilityEnabled;            // whether probe variability is enabled for this volume
};


DDGIVolumeDescGPU UnpackDDGIVolumeDescGPU(DDGIVolumeDescGPUPacked inputParam)
{
    DDGIVolumeDescGPU outputRes;
    outputRes.origin = inputParam.origin;
    outputRes.probeHysteresis = inputParam.probeHysteresis;
    outputRes.rotation = inputParam.rotation;
    outputRes.probeRayRotation = inputParam.probeRayRotation;
    outputRes.probeMaxRayDistance = inputParam.probeMaxRayDistance;
    outputRes.probeNormalBias = inputParam.probeNormalBias;
    outputRes.probeViewBias = inputParam.probeViewBias;
    outputRes.probeDistanceExponent = inputParam.probeDistanceExponent;
    outputRes.probeIrradianceEncodingGamma = inputParam.probeIrradianceEncodingGamma;
    outputRes.probeIrradianceThreshold = inputParam.probeIrradianceThreshold;
    outputRes.probeBrightnessThreshold = inputParam.probeBrightnessThreshold;
    outputRes.probeMinFrontfaceDistance = inputParam.probeMinFrontfaceDistance;
    outputRes.probeSpacing = inputParam.probeSpacing;

    // Probe Counts
    outputRes.probeCounts.x = int(inputParam.packed0 & 0x000003FF);
    outputRes.probeCounts.y = int((inputParam.packed0 >> 10) & 0x000003FF);
    outputRes.probeCounts.z = int((inputParam.packed0 >> 20) & 0x000003FF);

    // Thresholds
    outputRes.probeRandomRayBackfaceThreshold = float(inputParam.packed1 & 0x0000FFFF) / 65535.f;
    outputRes.probeFixedRayBackfaceThreshold = float((inputParam.packed1 >> 16) & 0x0000FFFF) / 65535.f;

    // Counts
    outputRes.probeNumRays = int(inputParam.packed2 & 0x0000FFFF);
    outputRes.probeNumIrradianceInteriorTexels = int((inputParam.packed2 >> 16) & 0x000000FF);
    outputRes.probeNumDistanceInteriorTexels = int((inputParam.packed2 >> 24) & 0x000000FF);

    // Probe Scroll Offsets
    outputRes.probeScrollOffsets.x = int(inputParam.packed3 & 0x00007FFF);
    if (((inputParam.packed3 >> 15) & 0x00000001) != 0u) outputRes.probeScrollOffsets.x *= -1;
    outputRes.probeScrollOffsets.y = int((inputParam.packed3 >> 16) & 0x00007FFF);
    if (((inputParam.packed3 >> 31) & 0x00000001) != 0u) outputRes.probeScrollOffsets.y *= -1;
    outputRes.probeScrollOffsets.z = int((inputParam.packed4) & 0x00007FFF);
    if (((inputParam.packed4 >> 15) & 0x00000001) != 0u) outputRes.probeScrollOffsets.z *= -1;

    // Feature Bits
    outputRes.movementType = (inputParam.packed4 >> 16) & 0x00000001;
    outputRes.probeRayDataFormat = uint((inputParam.packed4 >> 17) & 0x00000007);
    outputRes.probeIrradianceFormat = uint((inputParam.packed4 >> 20) & 0x00000007);
    outputRes.probeRelocationEnabled = bool((inputParam.packed4 >> 23) & 0x00000001);
    outputRes.probeClassificationEnabled = bool((inputParam.packed4 >> 24) & 0x00000001);
    outputRes.probeVariabilityEnabled = bool((inputParam.packed4 >> 25) & 0x00000001);
    outputRes.probeScrollClear[0] = bool((inputParam.packed4 >> 26) & 0x00000001);
    outputRes.probeScrollClear[1] = bool((inputParam.packed4 >> 27) & 0x00000001);
    outputRes.probeScrollClear[2] = bool((inputParam.packed4 >> 28) & 0x00000001);
    outputRes.probeScrollDirections[0] = bool((inputParam.packed4 >> 29) & 0x00000001);
    outputRes.probeScrollDirections[1] = bool((inputParam.packed4 >> 30) & 0x00000001);
    outputRes.probeScrollDirections[2] = bool((inputParam.packed4 >> 31) & 0x00000001);

    return outputRes;
}
#endif