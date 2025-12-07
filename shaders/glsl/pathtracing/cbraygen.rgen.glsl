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

layout(binding = 5, set = 0) buffer LightData{
    mat4 objectToWorld;
    int lightGeometryIndex;
} lightData;

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

// 计算三角形面积
// 原理：三角形面积等于两边叉积模长的一半
float cacTriangleArea(vec3 worldPositions[3])
{
    vec3 edge1 = vec3(worldPositions[1] - worldPositions[0]);
    vec3 edge2 = vec3(worldPositions[2] - worldPositions[0]);

    // cross(edge1, edge2) 得到法向量（长度为平行四边形面积）
    // length 取模长，然后除以 2 得到三角形面积
    float area = 0.5 * length(cross(edge1, edge2));

    return area;
}

// 均匀采样三角形表面的点
// 注意：必须传入 seed 用于生成随机数，且必须使用 sqrt 校正分布
vec3 uniformSampleTriangle(vec3 worldPositions[3], inout uint seed)
{
    // 1. 获取两个 [0, 1) 的随机数
    // 假设你有之前定义的 rnd() 函数
    float r1 = rnd(seed);
    float r2 = rnd(seed);

    // 2. 计算重心坐标 (Barycentric Coordinates)
    // 关键：必须对 r1 开根号，否则采样点会聚集在 worldPositions[0] 附近
    float sqrtR1 = sqrt(r1);

    float u = 1.0 - sqrtR1;
    float v = sqrtR1 * (1.0 - r2);
    float w = sqrtR1 * r2; // 或者 w = 1.0 - u - v;

    // 3. 混合顶点位置得到采样点
    vec3 samplePoint = vec3(worldPositions[0] * u +
    worldPositions[1] * v +
    worldPositions[2] * w);

    return samplePoint;
}

void sampleLight(vec3 tri0WorldPositions[3], vec3 tri1WorldPositions[3], inout uint seed, out vec3 samplePos, out float pdf)
{
    float area0 = cacTriangleArea(tri0WorldPositions);
    float area1 = cacTriangleArea(tri1WorldPositions);
    
    float p = rnd(seed);
    float ratio = area0 / (area0 + area1);
    if(p <= ratio){
        samplePos = uniformSampleTriangle(tri0WorldPositions, seed);
    }else{
        samplePos = uniformSampleTriangle(tri1WorldPositions, seed);
    }
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