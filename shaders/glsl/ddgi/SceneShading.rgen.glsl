#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_shader_image_load_formatted : enable

#include "Utils.glsl"
layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;
layout(binding = 1, set = 0) uniform image2D image;
layout(binding = 2, set = 0) uniform CameraProperties{
	mat4 viewInverse;
	mat4 projInverse;
	uint frame;
} cam;

layout(binding = 3, set = 0) buffer GeometryNodes {GeometryNode nodes[];}geometryNodes;

layout(binding = 4, set = 0) buffer Materials {Material mats[];} materials;

layout(location = 0) rayPayloadEXT RayPayload hitValue;

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


void main()
{
	uint seed = getSeed();

	Ray ray = getRayFromCamera(0.001, 10000.0, seed);
	hitValue.dis = 1.0;
	traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);
	vec3 finalColor = hitValue.mat.baseColor.rgb;
	//finalColor = encodeNormal(hitValue.worldNormal);
	if(hitValue.dis < 0.0){
		finalColor = vec3(0.0);
	}else{
		DirectionalLight light;
		initDirectionalLight(light);
		vec3 shadowOrigin = hitValue.worldPos + hitValue.worldNormal * 0.001;
		traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT, 0xff, 0, 0, 0, shadowOrigin, ray.tmin, -normalize(light.lightDir), ray.tmax, 0);
		if(hitValue.dis > 0.0f){
			finalColor *= 0.0;
		}

	}

	imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(finalColor, 1.0f));
}