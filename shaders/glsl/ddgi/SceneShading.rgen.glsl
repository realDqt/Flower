#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_shader_image_load_formatted : enable

#include "Utils.glsl"
#include "DDGIVolumeDescGPU.glsl"
#include "DDGIPushConstants.glsl"
#include "ProbeCommon.glsl"

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;
layout(binding = 1, set = 0) uniform image2D image;
layout(binding = 2, set = 0) uniform CameraProperties{
	mat4 viewInverse;
	mat4 projInverse;
	vec3 position;
	uint frame;
} cam;

layout(binding = 5, set = 0) readonly buffer DDGIVolumeDescGPUPackedBlock {DDGIVolumeDescGPUPacked d[];} DDGIVolumes;
DDGIVolumeDescGPUPacked GetDDGIVolumeConstants(uint index) { return DDGIVolumes.d[index]; }

layout(binding = 6, set = 0) uniform sampler2DArray ProbeIrradiance;
layout(binding = 7, set = 0) uniform sampler2DArray ProbeDistance;
layout(binding = 8, set = 0) uniform sampler2DArray ProbeData;


layout(location = 0) rayPayloadEXT RayPayload hitValue;
layout(location = 1) rayPayloadEXT bool shadowed;

uint getSeed()
{
	uint seed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, cam.frame);
	return seed;
}

Ray getRayFromCamera(float tmin, float tmax, inout uint seed)
{

	float r1 = rnd(seed);
	float r2 = rnd(seed);

	vec2 subpixel_jitter = cam.frame == 0 ? vec2(0.5f, 0.5f) : vec2(r1, r2);
	const vec2 pixelCenter = vec2(gl_LaunchIDEXT.xy) + subpixel_jitter;
	const vec2 inUV = pixelCenter / vec2(gl_LaunchSizeEXT.xy);
	vec2 d = inUV * 2.0 - 1.0;

	vec4 origin = cam.viewInverse * vec4(0, 0, 0, 1);
	vec4 target = cam.projInverse * vec4(d.x, d.y, 1, 1);
	vec4 direction = cam.viewInverse * vec4(normalize(target.xyz), 0.0);

	Ray ray;
	ray.origin = origin.xyz;
	ray.direction = direction.xyz;
	ray.tmin = tmin;
	ray.tmax = tmax;
	return ray;
}

bool isVisible(vec3 posW, vec3 normW, DirectionalLight light)
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

vec3 evalDiffuseLighting(vec3 posW, vec3 normW, vec3 baseColor, vec3 wo, DirectionalLight light)
{
	if(isVisible(posW, normW, light)){
		vec3 brdf = evalDiffuseBRDF(-light.lightDir, wo, normW, baseColor);
		return light.lightIntensity * brdf * max(dot(-light.lightDir, normW), 0.f);
	}
	return vec3(0.f);
}

vec3 evalDirectLighting(vec3 posW, vec3 normW, vec3 baseColor, vec3 wo)
{
	DirectionalLight light = getGlobalDirectionalLight();
	return evalDiffuseLighting(posW, normW, baseColor, wo, light);
}

float DDGILoadProbeState(int probeIndex, DDGIVolumeDescGPU volume)
{
	float state = DDGI_PROBE_STATE_ACTIVE;
	if (volume.probeClassificationEnabled)
	{
		// Get the probe's texel coordinates in the Probe Data texture
		uvec3 probeDataCoords = DDGIGetProbeTexelCoords(probeIndex, volume);

		// Get the probe's classification state
		state = texelFetch(ProbeData, ivec3(probeDataCoords), 0).w;
	}

	return state;
}

vec3 DDGILoadProbeDataOffset(uvec3 coords, DDGIVolumeDescGPU volume)
{
	return texelFetch(ProbeData, ivec3(coords), 0).xyz * volume.probeSpacing;
}


/**
 * Computes the world-space position of a probe from the probe's 3D grid-space coordinates.
 * When probe relocation is enabled, offsets are loaded from the probe data
 * Texture2D and used to adjust the final world position.
 */
vec3 DDGIGetProbeWorldPositionWithRelocation(ivec3 probeCoords, DDGIVolumeDescGPU volume)
{
	// Get the probe's world-space position
	vec3 probeWorldPosition = DDGIGetProbeWorldPosition(probeCoords, volume);

	// If the volume has probe relocation enabled, account for the probe offsets
	if (volume.probeRelocationEnabled)
	{
		// Get the scroll adjusted probe index
		int probeIndex = DDGIGetScrollingProbeIndex(probeCoords, volume);

		// Find the texture coordinates of the probe in the Probe Data texture
		uvec3 coords = DDGIGetProbeTexelCoords(probeIndex, volume);

		// Load the probe's world-space position offset and add it to the current world position
		probeWorldPosition += DDGILoadProbeDataOffset(coords, volume);

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
		vec3 adjacentProbeWorldPosition = DDGIGetProbeWorldPositionWithRelocation(adjacentProbeCoords, volume);

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
		variance = max(variance, 0.0005f); // make no sense


		// Occlusion test
		float chebyshevWeight = 1.f;
		if(biasedPosToAdjProbeDist > filteredDistance.x + DDGI_CHEBVSHEV_BIAS) // occluded
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

vec3 evalIndirectLighting(vec3 posW, vec3 normW, vec3 baseColor, vec3 wo)
{
	uint volumeIndex = GetDDGIVolumeIndex();
	DDGIVolumeDescGPU volume = UnpackDDGIVolumeDescGPU(GetDDGIVolumeConstants(volumeIndex));

	vec3 cameraDirection = normalize(posW - cam.position);
	vec3 surfaceBias = DDGIGetSurfaceBias(normW, cameraDirection, volume);

	float blendWeight = DDGIGetVolumeBlendWeight(posW, volume);
	vec3 irradiance = vec3(0.f);
	if(blendWeight > 0)
	{
		// Get irradiance for the world-space position in the volume
		irradiance += DDGIGetVolumeIrradiance(
			posW,
			surfaceBias,
			normW,
			volume);

		irradiance *= blendWeight;

	};

	vec3 brdf = baseColor / M_PI;
	return irradiance * brdf;
}



void main()
{
	uint seed = getSeed();

	Ray ray = getRayFromCamera(0.001, 10000.0, seed);
	hitValue.dis = 1.0;
	traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);
	vec3 finalColor = hitValue.mat.baseColor.rgb;
	if(hitValue.dis < 0.0){
		finalColor = vec3(0.0);
	}else{
		vec3 directLighting = evalDirectLighting(hitValue.worldPos, hitValue.worldNormal, hitValue.mat.baseColor.rgb, -ray.direction);
		vec3 indirectLighting = evalIndirectLighting(hitValue.worldPos, hitValue.worldNormal, hitValue.mat.baseColor.rgb, -ray.direction);
		finalColor = directLighting + indirectLighting;
	}

	imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(finalColor, 1.0f));
}