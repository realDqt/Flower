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
	ivec4 probeDebugFlags;
	vec4 probeDebugParams;
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
		uvec3 probeDataCoords = DDGIGetProbeTexelCoords(probeIndex, volume);
		
		state = texelFetch(ProbeData, ivec3(probeDataCoords), 0).w;
	}

	return state;
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

float DDGIGetProbeDebugRadius(DDGIVolumeDescGPU volume)
{
	float minSpacing = min(volume.probeSpacing.x, min(volume.probeSpacing.y, volume.probeSpacing.z));
	return max(0.001f, minSpacing * cam.probeDebugParams.x);
}

float DDGIIntersectSphere(Ray ray, vec3 center, float radius)
{
	vec3 oc = ray.origin - center;
	float halfB = dot(oc, ray.direction);
	float c = dot(oc, oc) - (radius * radius);
	float discriminant = halfB * halfB - c;
	if (discriminant < 0.0f) return -1.0f;

	float sqrtDiscriminant = sqrt(discriminant);
	float t = -halfB - sqrtDiscriminant;
	if (t < ray.tmin) t = -halfB + sqrtDiscriminant;
	if (t < ray.tmin || t > ray.tmax) return -1.0f;
	return t;
}

vec3 DDGISampleProbeDebugIrradiance(int probeIndex, vec3 direction, DDGIVolumeDescGPU volume)
{
	vec2 octantCoords = DDGIGetOctahedralCoordinates(normalize(direction));
	vec3 probeTextureUV = DDGIGetProbeUV(probeIndex, octantCoords, volume.probeNumIrradianceInteriorTexels, volume);
	vec3 irradiance = textureLod(ProbeIrradiance, probeTextureUV, 0).rgb;
	vec3 exponent = vec3(volume.probeIrradianceEncodingGamma * 0.5f);
	irradiance = pow(irradiance, exponent);
	return irradiance * irradiance;
}

vec2 DDGISampleProbeDebugDistance(int probeIndex, vec3 direction, DDGIVolumeDescGPU volume)
{
	vec2 octantCoords = DDGIGetOctahedralCoordinates(normalize(direction));
	vec3 probeTextureUV = DDGIGetProbeUV(probeIndex, octantCoords, volume.probeNumDistanceInteriorTexels, volume);
	return 2.0f * textureLod(ProbeDistance, probeTextureUV, 0).rg;
}

vec3 DDGIGetProbeDebugColor(int probeIndex, ivec3 probeCoords, vec3 probeWorldPosition, vec3 rayOrigin, DDGIVolumeDescGPU volume, int mode)
{
	float probeState = DDGILoadProbeState(probeIndex, volume);
	vec3 color = vec3(1.0f);

	if (mode == 1)
	{
		color = (probeState == DDGI_PROBE_STATE_INACTIVE) ? vec3(0.95f, 0.20f, 0.15f) : vec3(0.15f, 0.85f, 0.25f);
		vec3 relocation = probeWorldPosition - DDGIGetProbeWorldPosition(probeCoords, volume);
		float relocationRatio = clamp(length(relocation) / max(DDGIGetProbeDebugRadius(volume), 0.001f), 0.0f, 1.0f);
		color = mix(color, vec3(0.20f, 0.55f, 1.00f), relocationRatio);
	}
	else if (mode == 2)
	{
		vec3 viewDirection = normalize(rayOrigin - probeWorldPosition);
		color = DDGISampleProbeDebugIrradiance(probeIndex, viewDirection, volume);
		color = color / (vec3(1.0f) + color);
		if (probeState == DDGI_PROBE_STATE_INACTIVE) color = mix(color, vec3(0.85f, 0.15f, 0.10f), 0.70f);
	}
	else if (mode == 3)
	{
		vec3 viewDirection = normalize(rayOrigin - probeWorldPosition);
		vec2 filteredDistance = DDGISampleProbeDebugDistance(probeIndex, viewDirection, volume);
		float distanceRatio = saturate(filteredDistance.x / max(volume.probeMaxRayDistance, 0.001f));
		color = mix(vec3(0.10f, 0.25f, 0.95f), vec3(0.95f, 0.85f, 0.15f), distanceRatio);
		if (probeState == DDGI_PROBE_STATE_INACTIVE) color = mix(color, vec3(0.85f, 0.15f, 0.10f), 0.60f);
	}

	return color;
}

vec3 DDGIShadeProbeDebugSphere(vec3 baseColor, Ray ray, float t, vec3 center)
{
	vec3 hitPosition = ray.origin + ray.direction * t;
	vec3 normal = normalize(hitPosition - center);
	vec3 lightDirection = normalize(vec3(0.35f, 0.85f, 0.25f));
	float diffuse = 0.25f + 0.75f * max(dot(normal, lightDirection), 0.0f);
	float rim = pow(1.0f - max(dot(normal, -ray.direction), 0.0f), 4.0f);
	return baseColor * diffuse + (vec3(1.0f) * rim * 0.20f);
}

bool DDGIFindProbeDebugHit(
	Ray ray,
	float sceneT,
	DDGIVolumeDescGPU volume,
	out float closestT,
	out vec3 probeCenter,
	out ivec3 probeCoords,
	out int probeIndex,
	out int probeBehindSurface)
{
	bool found = false;
	float radius = DDGIGetProbeDebugRadius(volume);
	int probeCount = volume.probeCounts.x * volume.probeCounts.y * volume.probeCounts.z;
	closestT = ray.tmax;
	probeBehindSurface = 0;

	for (int linearProbeIndex = 0; linearProbeIndex < probeCount; ++linearProbeIndex)
	{
		ivec3 coords = DDGIGetProbeCoords(linearProbeIndex, volume);
		int scrollingProbeIndex = DDGIGetScrollingProbeIndex(coords, volume);
		vec3 worldPosition = DDGIGetProbeWorldPositionWithRelocation(coords, volume);
		float t = DDGIIntersectSphere(ray, worldPosition, radius);
		if (t < 0.0f) continue;

		if (t < closestT)
		{
			found = true;
			closestT = t;
			probeCenter = worldPosition;
			probeCoords = coords;
			probeIndex = scrollingProbeIndex;
			probeBehindSurface = int(t > sceneT);
		}
	}

	return found;
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

	int probeDebugMode = cam.probeDebugFlags.x;
	if (probeDebugMode > 0)
	{
		uint volumeIndex = GetDDGIVolumeIndex();
		DDGIVolumeDescGPU volume = UnpackDDGIVolumeDescGPU(GetDDGIVolumeConstants(volumeIndex));
		float sceneT = (hitValue.dis < 0.0f) ? ray.tmax : hitValue.dis;
		float probeT;
		vec3 probeCenter;
		ivec3 probeCoords;
		int probeIndex;
		int probeBehindSurface;
		if (DDGIFindProbeDebugHit(ray, sceneT, volume, probeT, probeCenter, probeCoords, probeIndex, probeBehindSurface))
		{
			if ((probeBehindSurface == 0) || (cam.probeDebugFlags.y != 0))
			{
				vec3 probeBaseColor = DDGIGetProbeDebugColor(probeIndex, probeCoords, probeCenter, ray.origin, volume, probeDebugMode);
				vec3 probeColor = DDGIShadeProbeDebugSphere(probeBaseColor, ray, probeT, probeCenter);
				float alpha = saturate(cam.probeDebugParams.y);
				if (probeBehindSurface != 0) alpha *= 0.45f;
				finalColor = mix(finalColor, probeColor, alpha);
			}
		}
	}

	imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(finalColor, 1.0f));
}
