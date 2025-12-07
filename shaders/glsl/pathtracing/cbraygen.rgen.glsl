#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_shader_image_load_formatted : enable

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;
layout(binding = 1, set = 0) uniform image2D image;
layout(binding = 2, set = 0) uniform CameraProperties{
    mat4 viewInverse;
    mat4 projInverse;
    uint frame;
} cam;

#include "cbcommon.glsl"
layout(location = 0) rayPayloadEXT RayPayload hitValue;

// Tiny Encryption Algorithm
// By Fahad Zafar, Marc Olano and Aaron Curtis, see https://www.highperformancegraphics.org/previous/www_2010/media/GPUAlgorithms/HPG2010_GPUAlgorithms_Zafar.pdf
uint tea(uint val0, uint val1)
{
    uint sum = 0;
    uint v0 = val0;
    uint v1 = val1;
    for (uint n = 0; n < 16; n++)
    {
        sum += 0x9E3779B9;
        v0 += ((v1 << 4) + 0xA341316C) ^ (v1 + sum) ^ ((v1 >> 5) + 0xC8013EA4);
        v1 += ((v0 << 4) + 0xAD90777D) ^ (v0 + sum) ^ ((v0 >> 5) + 0x7E95761E);
    }
    return v0;
}

// Linear congruential generator based on the previous RNG state
// See https://en.wikipedia.org/wiki/Linear_congruential_generator
uint lcg(inout uint previous)
{
    const uint multiplier = 1664525u;
    const uint increment = 1013904223u;
    previous   = (multiplier * previous + increment);
    return previous & 0x00FFFFFFu;
}

// Generate a random float in [0, 1) given the previous RNG state
float rnd(inout uint previous)
{
    return (float(lcg(previous)) / float(0x01000000));
}

void main()
{
    uint seed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, cam.frame);

    float r1 = rnd(seed);
    float r2 = rnd(seed);

    vec2 subpixel_jitter = cam.frame == 0 ? vec2(0.5f, 0.5f) : vec2(r1, r2);
    const vec2 pixelCenter = vec2(gl_LaunchIDEXT.xy) + subpixel_jitter;
    const vec2 inUV = pixelCenter / vec2(gl_LaunchSizeEXT.xy);
    vec2 d = inUV * 2.0 - 1.0;

    vec4 origin = cam.viewInverse * vec4(0, 0, 0, 1);
    vec4 target = cam.projInverse * vec4(d.x, d.y, 1, 1);
    vec4 direction = cam.viewInverse * vec4(normalize(target.xyz), 0.0);

    float tmin = 0.001;
    float tmax = 10000.0;
    hitValue.mat.baseColor = vec4(0.0, 0.0, 0.0, 1.0);
    traceRayEXT(topLevelAS, gl_RayFlagsNoneEXT, 0xff, 0, 0, 0, origin.xyz, tmin, direction.xyz, tmax, 0);

    // de-noising
    vec3 normal01 = getNormal01(hitValue.normal);
    vec3 hitColor = hitValue.mat.baseColor.rgb;
    if(hitColor == vec3(0.0)) normal01 = vec3(0.0);
    
    if(cam.frame > 0){
        float a = 1.0f / float(cam.frame + 1);
        vec3 oldColor = imageLoad(image, ivec2(gl_LaunchIDEXT.xy)).xyz;
        imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(mix(oldColor, hitColor, a), 1.0f));
    }else{
        imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(hitColor, 1.0f));
    }
}