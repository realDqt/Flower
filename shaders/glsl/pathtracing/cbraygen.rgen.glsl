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


void sampleLight(vec3 tri0WorldPositions[3], vec3 tri1WorldPositions[3], inout uint seed, out LightSampleRes sampleRes, out float pdf)
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
    sampleLight(tri0Positions, tri1Positions, seed, sampleRes, pdf);
}

uint getSeed()
{
    uint seed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, cam.frame);
    return seed;
}

Ray getRayFromCamera(float tmin, float tmax)
{
    uint seed = getSeed();

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

vec3 cacDirectLight(vec3 pos, vec3 wo)
{
    // TODO: 计算pos处，沿着wo方向的直接光照
    vec3 L_dir = vec3(0.0);
    float pdf_light = 0;
    LightSampleRes lightSampleRes;
    return vec3(0.0);
}

vec3 pathTracing(int maxBounce)
{
    Ray ray = getRayFromCamera(0.001, 10000.0);
    uint rayFlags = gl_RayFlagsOpaqueEXT;
    vec3 totalRadiance = vec3(0.0);
    uint seed = getSeed();
    for(int i = 0; i < maxBounce; ++i){
        traceRayEXT(topLevelAS, rayFlags, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);
        if(hitValue.dis > 0) {
            totalRadiance += cacDirectLight(hitValue.worldPos, -ray.direction);
            ray.origin = hitValue.worldPos;
            ray.direction = uniformSample(-ray.direction, hitValue.worldNormal, seed);
        }else{
            break;
        }
    }
    return totalRadiance;
}

void main()
{
    Ray ray = getRayFromCamera(0.001, 10000.0);
    hitValue.mat.baseColor = vec4(0.0, 0.0, 0.0, 1.0);
    traceRayEXT(topLevelAS, gl_RayFlagsNoneEXT, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);

    // de-noising
    vec3 normal01 = getNormal01(hitValue.worldNormal);
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