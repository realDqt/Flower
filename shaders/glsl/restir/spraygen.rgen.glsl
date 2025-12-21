#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_shader_image_load_formatted : enable

#include "spcommon.glsl"

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;
layout(binding = 1, set = 0) uniform image2D image;
layout(binding = 2, set = 0) uniform CameraProperties
{
    mat4 viewInverse;
    mat4 projInverse;
    uint frame;
} cam;

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

    const int SPP = 1;
    const int BOUNCE = 1;
    
    for(int spp = 0; spp < SPP; spp++) {
        traceRayEXT(topLevelAS, gl_RayFlagsNoneEXT, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);
    }

    vec3 hitColor = hitValue.baseColor.rgb;

    if(cam.frame > 0)
    {
        float a         = 1.0f / float(cam.frame + 1);
        vec3  old_color = imageLoad(image, ivec2(gl_LaunchIDEXT.xy)).xyz;
        imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(mix(old_color, hitColor, a), 1.f));
    }
    else
    {
        // First frame, replace the value in the buffer
        imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(hitColor, 1.f));
    }
}
