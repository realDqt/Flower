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

layout(binding = 3, set = 0) buffer DirectionalLight{
    vec3 direction; // 平行光方向 (从光源指向场景)
    vec3 emission;  // 强度/颜色
} directionalLight;

layout(location = 0) rayPayloadEXT RayPayload hitValue;

uint getSeed()
{
    return tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, cam.frame);
}

// 相机射线生成 (含抗锯齿抖动)
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

// 计算平行光的直接光照贡献
vec3 cacDirectionalLight(vec3 pos, vec3 wo, vec3 normal, vec4 baseColor)
{
    vec3 L_dir = vec3(0.0);
    vec3 wi = normalize(directionalLight.direction.xyz); // 指向光源的方向
    
    uint rayFlags = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsSkipClosestHitShaderEXT | gl_RayFlagsOpaqueEXT;
    
    // 逻辑：向着平行光方向追踪 10000 距离，看是否有遮挡
    traceRayEXT(topLevelAS, rayFlags, 0xff, 0, 0, 0, pos, 0.001, wi, 10000.0, 0);

    // hitValue.dis < 0 表示未击中任何物体（路径畅通）
    if(hitValue.dis < 0.0f) {
        vec3 brdf = evalDiffuseBRDF(wi, wo, normal, baseColor); // wi并不影响简单diffuse
        L_dir = directionalLight.emission.xyz * brdf * max(dot(wi, normal), 0.0f);
    }
    return L_dir;
}

vec3 pathTracing(int maxBounce, inout uint seed)
{
    Ray ray = getRayFromCamera(0.001, 10000.0, seed);
    vec3 throughput = vec3(1.0);
    vec3 totalRadiance = vec3(0.0);

    for(int i = 0; i < maxBounce; ++i) {
        traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);
        
        if(hitValue.dis < 0.0f) {
            break;
        }

        // --- Next Event Estimation for Directional Light ---
        vec3 directL = cacDirectionalLight(hitValue.worldPos, -ray.direction, hitValue.worldNormal, hitValue.baseColor);
        totalRadiance += directL * throughput;

        // --- BSDF Sampling ---
        vec3 sampleDir;
        float pdf;
        cosineSampleHemisphere(hitValue.worldNormal, seed, sampleDir, pdf);

        vec3 brdf = evalDiffuseBRDF(sampleDir, -ray.direction, hitValue.worldNormal, hitValue.baseColor);
        
        throughput *= (brdf * dot(sampleDir, hitValue.worldNormal)) / pdf;
        
        if(rnd(seed) > RUSSIAN_ROULETTE) break;
        throughput /= RUSSIAN_ROULETTE;

        // 更新射线状态进行下一次弹射
        ray.origin = hitValue.worldPos;
        ray.direction = sampleDir;
    }

    return totalRadiance;
}

vec3 getSceneBaseColor(inout uint seed)
{
    Ray ray = getRayFromCamera(0.001, 10000.0, seed);
    traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);
    if(hitValue.dis > 0.0f){
        traceRayEXT(topLevelAS, gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsSkipClosestHitShaderEXT | gl_RayFlagsOpaqueEXT, 0xff, 0, 0, 0, hitValue.worldPos, ray.tmin, directionalLight.direction.xyz, ray.tmax, 0);
        if(hitValue.dis > 0.0f)hitValue.baseColor.rgb *= 0.7f;
        return hitValue.baseColor.rgb;
    }else{
        return vec3(0.0f);
    }
}

void temporalAccumalation(vec3 finalColor)
{
    // 时间累积逻辑
    if(cam.frame > 0) {
        float a = 1.0f / float(cam.frame + 1);
        vec3 old_color = imageLoad(image, ivec2(gl_LaunchIDEXT.xy)).xyz;
        imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(mix(old_color, finalColor, a), 1.f));
    } else {
        imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(finalColor, 1.f));
    }
}

void main()
{
    uint seed = getSeed();
    
    const int SPP = 4;
    const int BOUNCE = 128; 
    vec3 accumaltedColor = vec3(0.0);
    for(int spp = 0; spp < SPP; ++spp){
        accumaltedColor += pathTracing(BOUNCE, seed);
    }
    vec3 finalColor = accumaltedColor / SPP;
    imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(finalColor, 1.f));
}