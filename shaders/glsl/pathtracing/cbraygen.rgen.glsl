#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_shader_image_load_formatted : enable

#include "cbcommon.glsl"
layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;
layout(binding = 1, set = 0) uniform image2D image;
layout(binding = 2, set = 0) uniform CameraProperties{
    mat4 viewInverse;
    mat4 projInverse;
    uint frame;
} cam;

layout(binding = 3, set = 0) buffer GeometryNodes {GeometryNode nodes[];}geometryNodes;

layout(binding = 4, set = 0) buffer Materials {Material mats[];} materials;

layout(binding = 5, set = 0) buffer LightData{
    mat4 objectToWorld;
    int lightGeometryIndex;
} lightData;

layout(location = 0) rayPayloadEXT RayPayload hitValue;

struct LightSampleRes{
    vec3 pos;
    vec3 normal;
    vec3 emit;
};


void uniformSampleLight(vec3 tri0WorldPositions[3], vec3 tri1WorldPositions[3], inout uint seed, out LightSampleRes sampleRes, out float pdf)
{
    float area0 = cacTriangleArea(tri0WorldPositions);
    float area1 = cacTriangleArea(tri1WorldPositions);
    
    float p = rnd(seed);
    float ratio = area0 / (area0 + area1);
    if(p <= ratio){
        sampleRes.pos = uniformSampleTriangle(tri0WorldPositions, seed);
        sampleRes.normal = getTriNormalFromTriPositions(tri0WorldPositions);
    }else{
        sampleRes.pos = uniformSampleTriangle(tri1WorldPositions, seed);
        sampleRes.normal = getTriNormalFromTriPositions(tri1WorldPositions);
    }
    Material lightMat = materials.mats[lightData.lightGeometryIndex];
    sampleRes.emit = lightMat.emission;
    
    pdf = 1.0f / (area0 + area1);
}

void unpackLightWorldPositions(out vec3 tri0WorldPositions[3], out vec3 tri1WorldPositions[3])
{
    GeometryNode node = geometryNodes.nodes[lightData.lightGeometryIndex];
    
    Vertices vertices = Vertices(node.vertexBufferDeviceAddress);
    Indices indices = Indices(node.indexBufferDeviceAddress);
    
    for(int k = 0; k < 3; ++k){
        tri0WorldPositions[k] = vec3(lightData.objectToWorld * vec4(vertices.v[indices.i[k] * 3].xyz, 1.0));
        tri1WorldPositions[k] = vec3(lightData.objectToWorld * vec4(vertices.v[indices.i[k + 3] * 3].xyz, 1.0));
    }
}

void sampleLight(inout uint seed, out LightSampleRes sampleRes, out float pdf)
{
    vec3 tri0Positions[3];
    vec3 tri1Positions[3];
    unpackLightWorldPositions(tri0Positions, tri1Positions);
    uniformSampleLight(tri0Positions, tri1Positions, seed, sampleRes, pdf);
}

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

vec3 cacDirectLight(vec3 pos, vec3 normal, vec3 wo, inout uint seed, Material mat)
{
    // 计算pos处，沿着wo方向的直接光照
    vec3 L_dir = vec3(0.0);
    float pdf_light = 0;
    LightSampleRes lightSampleRes;
    sampleLight(seed, lightSampleRes, pdf_light);
    vec3 p = pos;
    vec3 x = lightSampleRes.pos;
    vec3 ws = normalize(x - p);
    float lightDist = length(x - p);
    
    uint rayFlags = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsSkipClosestHitShaderEXT;
    traceRayEXT(topLevelAS, rayFlags, 0xff, 0, 0, 0, p, 0.01, ws, lightDist - 0.0001f, 0);
    if(hitValue.dis < 0.0f){
        // p对光源x可见
        vec3 f_r = evalDiffuseBRDF(ws, wo, normal, mat);
        float distance2 = dot(x - p, x - p);
        float cosThetaLight = max(0.0, dot(-ws, lightSampleRes.normal));
        float cosThetaObj = max(0.0, dot(ws, normal));
        L_dir = lightSampleRes.emit * f_r * cosThetaObj * cosThetaLight / distance2 / pdf_light;
    }
    return L_dir;
}

vec3 pathTracing(int maxBounce, inout uint seed)
{
    Ray ray = getRayFromCamera(0.001, 10000.0, seed);
    uint rayFlags = gl_RayFlagsOpaqueEXT;
    vec3 totalRadiance = vec3(0.0);
    vec3 throughput = vec3(1.0);
    
    for(int i = 0; i < maxBounce; ++i){
        traceRayEXT(topLevelAS, rayFlags, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);
        if(hitValue.dis > 0.0f) {
            if(hasEmission(hitValue.mat)){
                totalRadiance += hitValue.mat.emission * throughput;
                break;
            }
            vec3 radiance = cacDirectLight(hitValue.worldPos, hitValue.worldNormal, -ray.direction, seed, hitValue.mat);
            
            totalRadiance += radiance * throughput;
            
            ray.origin = hitValue.worldPos;
            // sampling
            float pdf;
            vec3 sampleDir;
            vec3 sampleNormal = hitValue.worldNormal;
            sampleNormal.x = -sampleNormal.x; // hack
            if(nearEqual(hitValue.mat.metallic, 1.0, 0.00001f)){
                sampleSpecular(sampleNormal, ray.direction, sampleDir, pdf);
            }else{
                cosineSampleHemisphere(sampleNormal, seed, sampleDir, pdf);
            }
            vec3 f_r = evalDiffuseBRDF(-ray.direction, sampleDir, sampleNormal, hitValue.mat);
            throughput *= f_r * dot(sampleDir, sampleNormal) / RUSSIAN_ROULETTE / pdf;
            ray.direction = sampleDir;
        }else{
            break;
        }
        
        float x = rnd(seed);
        if(x > RUSSIAN_ROULETTE) break;
    }
    return totalRadiance;
}

void main()
{
    uint seed = getSeed();

    vec3 accumulatedColor = vec3(0.0);
    const int SPP = 1;
    const int BOUNCE = 128;

    for(int i = 0; i < SPP; ++i)
    {
        accumulatedColor += pathTracing(BOUNCE, seed);
    }
    
    vec3 finalColor = accumulatedColor / float(SPP);

    
    /*
    if(cam.frame > 0)
    {
        float a         = 1.0f / float(cam.frame + 1);
        vec3  old_color = imageLoad(image, ivec2(gl_LaunchIDEXT.xy)).xyz;
        imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(mix(old_color, finalColor, a), 1.f));
    }
    else
    {
        // First frame, replace the value in the buffer
        imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(finalColor, 1.f));
    }
    */
    imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(finalColor, 1.0f));
}