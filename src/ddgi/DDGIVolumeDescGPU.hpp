#pragma once
#include "Common.hpp"

/**
 * Describes the properties of a DDGIVolume, with values packed to compact formats.
 * This version of the struct uses 128B to store some values at full precision.
 */
struct DDGIVolumeDescGPUPacked
{
    glm::vec3     origin;
    float    probeHysteresis;
    //------------------------------------------------- 16B
    glm::vec4     rotation;
    //------------------------------------------------- 32B
    glm::vec4     probeRayRotation;
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
    glm::vec3     probeSpacing;
    glm::uint     packed0;       // probeCounts.x (10), probeCounts.y (10), probeCounts.z (10), unused (2)
    //------------------------------------------------- 96B
    glm::uint     packed1;       // probeRandomRayBackfaceThreshold (16), probeFixedRayBackfaceThreshold (16)
    glm::uint     packed2;       // probeNumRays (16), probeNumIrradianceInteriorTexels (8), probeNumDistanceInteriorTexels (8)
    glm::uint     packed3;       // probeScrollOffsets.x (15) sign bit (1), probeScrollOffsets.y (15) sign bit (1)
    glm::uint     packed4;       // probeScrollOffsets.z (15) sign bit (1)
    // movementType (1), probeRayDataFormat (3), probeIrradianceFormat (3), probeRelocationEnabled (1)
    // probeClassificationEnabled (1), probeVariabilityEnabled (1)
    // probeScrollClear Y-Z plane (1), probeScrollClear X-Z plane (1), probeScrollClear X-Y plane (1)
    // probeScrollDirection Y-Z plane (1), probeScrollDirection X-Z plane (1), probeScrollDirection X-Y plane (1)
    //------------------------------------------------- 112B
    glm::uvec4    reserved;      // 16B reserved for future use
    //------------------------------------------------- 128B
};


/**
 * Describes the properties of a DDGIVolume.
 */
struct DDGIVolumeDescGPU
{
    glm::vec3     origin;                             // world-space location of the volume center

    glm::vec4     rotation;                           // rotation quaternion for the volume
    glm::vec4     probeRayRotation;                   // rotation quaternion for probe rays

    glm::uint     movementType;                       // type of movement the volume allows. 0: default, 1: infinite scrolling

    glm::vec3     probeSpacing;                       // world-space distance between probes
    glm::ivec3    probeCounts;                        // number of probes on each axis of the volume

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
    glm::ivec3    probeScrollOffsets;                 // grid-space offsets used for scrolling movement
    bool     probeScrollClear[3];                // whether probes of a plane need to be cleared due to scrolling movement
    bool     probeScrollDirections[3];           // direction of scrolling movement (0: negative, 1: positive)

    // Feature Options
    glm::uint     probeRayDataFormat;                 // texture format of the ray data texture (EDDGIVolumeTextureFormat)
    glm::uint     probeIrradianceFormat;              // texture format of the irradiance texture (EDDGIVolumeTextureFormat)
    bool     probeRelocationEnabled;             // whether probe relocation is enabled for this volume
    bool     probeClassificationEnabled;         // whether probe classification is enabled for this volume
    bool     probeVariabilityEnabled;            // whether probe variability is enabled for this volume
};


inline DDGIVolumeDescGPUPacked packDDGIVolumeDescGPU(const DDGIVolumeDescGPU input)
{
    DDGIVolumeDescGPUPacked output = {};

    output.origin = input.origin;
    output.probeHysteresis = input.probeHysteresis;
    output.rotation = input.rotation;
    output.probeRayRotation = input.probeRayRotation;
    output.probeMaxRayDistance = input.probeMaxRayDistance;
    output.probeNormalBias = input.probeNormalBias;
    output.probeViewBias = input.probeViewBias;
    output.probeDistanceExponent = input.probeDistanceExponent;
    output.probeIrradianceEncodingGamma = input.probeIrradianceEncodingGamma;
    output.probeIrradianceThreshold = input.probeIrradianceThreshold;
    output.probeBrightnessThreshold = input.probeBrightnessThreshold;
    output.probeMinFrontfaceDistance = input.probeMinFrontfaceDistance;
    output.probeSpacing = input.probeSpacing;

    output.packed0  = (uint32_t)input.probeCounts.x;
    output.packed0 |= (uint32_t)input.probeCounts.y << 10;
    output.packed0 |= (uint32_t)input.probeCounts.z << 20;

    output.packed1  = (uint32_t)(input.probeRandomRayBackfaceThreshold * 65535);
    output.packed1 |= (uint32_t)(input.probeFixedRayBackfaceThreshold * 65535) << 16;

    output.packed2  = (uint32_t)input.probeNumRays;
    output.packed2 |= (uint32_t)input.probeNumIrradianceInteriorTexels << 16;
    output.packed2 |= (uint32_t)input.probeNumDistanceInteriorTexels << 24;

    // Probe Scroll Offsets
    output.packed3 = (output.packed3 & ~0x7FFF)     | abs(input.probeScrollOffsets.x);
    output.packed3 = (output.packed3 & ~0x8000)     | ((input.probeScrollOffsets.x < 0) << 15);
    output.packed3 = (output.packed3 & ~0x10000)    | abs(input.probeScrollOffsets.y) << 16;
    output.packed3 = (output.packed3 & ~0x80000000) | ((input.probeScrollOffsets.y < 0) << 31);
    output.packed4 = (output.packed4 & ~0x7FFF)     | abs(input.probeScrollOffsets.z);
    output.packed4 = (output.packed4 & ~0x8000)     | ((input.probeScrollOffsets.z < 0) << 15);

    // Feature Bits
    output.packed4 = (output.packed4 & ~0x10000)    | (input.movementType << 16);
    output.packed4 = (output.packed4 & ~0xE0000)    | (input.probeRayDataFormat << 17);
    output.packed4 = (output.packed4 & ~0x700000)   | (input.probeIrradianceFormat << 20);
    output.packed4 = (output.packed4 & ~0x800000)   | (input.probeRelocationEnabled << 23);
    output.packed4 = (output.packed4 & ~0x1000000)  | (input.probeClassificationEnabled << 24);
    output.packed4 = (output.packed4 & ~0x2000000)  | (input.probeVariabilityEnabled << 25);
    output.packed4 = (output.packed4 & ~0x4000000)  | (input.probeScrollClear[0] << 26);
    output.packed4 = (output.packed4 & ~0x8000000)  | (input.probeScrollClear[1] << 27);
    output.packed4 = (output.packed4 & ~0x10000000) | (input.probeScrollClear[2] << 28);
    output.packed4 = (output.packed4 & ~0x20000000) | (input.probeScrollDirections[0] << 29);
    output.packed4 = (output.packed4 & ~0x40000000) | (input.probeScrollDirections[1] << 30);
    output.packed4 = (output.packed4 & ~0x80000000) | (input.probeScrollDirections[2] << 31);

    return output;
}


