#version 460
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_ray_tracing : require
#include "spcommon.glsl"
#include "restircommon.glsl"

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;

layout(binding = 1, set = 0) buffer TemporalReservoirBufferIn{
    Reservoir data[];
} temporalReservoirBufferIn;

layout(binding = 2, set = 0) buffer SpatialReservoirBufferIn{
    Reservoir data[];
} spatialReservoirBufferIn;

layout(binding = 3, set = 0) buffer SpatialReservoirBufferOut{
    Reservoir data[];
} spatialReservoirBufferOut;


layout(binding = 4, set = 0, r32f) uniform image2D prevDepthImage;
layout(binding = 5, set = 0, rgba32f) uniform image2D prevNormalImage;

layout(binding = 6, set = 0, r32f) uniform image2D curDepthImage;
layout(binding = 7, set = 0, rgba32f) uniform image2D curNormalImage;

layout(binding = 8, set = 0) uniform FrameData{
    mat4 currentInvView;        // 当前帧矩阵信息
    mat4 currentInvProj;
    mat4 prevViewProj;          // 上一帧矩阵信息
    vec4 forward;
    uint frame;
    float zNear;
    float zFar;
} frameData;

layout(location = 0) rayPayloadEXT RayPayload hitValue;

vec2 getPrevUV(vec2 uv)
{
    ivec2 sc = ivec2(uv.x * float(WIDTH), uv.y * float(HEIGHT));
    float ndcZ = imageLoad(curDepthImage, sc).r;
    if(ndcZ >= 0.99f) return vec2(-1.0);

    vec2 ndcXY = uv * 2.0f - 1.0f;
    vec4 ndc = vec4(ndcXY, ndcZ, 1.0f);
    vec4 worldPos = frameData.currentInvView * frameData.currentInvProj * ndc;
    worldPos /= worldPos.w;
    vec4 prevClip = frameData.prevViewProj * worldPos;
    vec4 prevNDC = vec4(prevClip.xyz / prevClip.w, 1.0f);
    vec2 prevUV = (prevNDC.xy + 1.0f) * .5f;
    return prevUV;
}

uint getSeed()
{
    return tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, frameData.frame);
}

Ray getRayFromCamera(float tmin, float tmax, inout uint seed, bool jitter)
{
    float r1 = rnd(seed);
    float r2 = rnd(seed);

    vec2 subpixel_jitter = !jitter || frameData.frame == 0 ? vec2(0.5f, 0.5f) : vec2(r1, r2);
    const vec2 pixelCenter = vec2(gl_LaunchIDEXT.xy) + subpixel_jitter;
    const vec2 inUV = pixelCenter / vec2(gl_LaunchSizeEXT.xy);
    vec2 d = inUV * 2.0 - 1.0;

    vec4 origin = frameData.currentInvView * vec4(0, 0, 0, 1);
    vec4 target = frameData.currentInvProj * vec4(d.x, d.y, 1, 1);
    vec4 direction = frameData.currentInvView * vec4(normalize(target.xyz), 0.0);

    Ray ray;
    ray.origin = origin.xyz;
    ray.direction = direction.xyz;
    ray.tmin = tmin;
    ray.tmax = tmax;
    return ray;
}

bool isValidReprojection(ivec2 prevSC)
{
    if(frameData.frame == 0 || prevSC.x < 0 || prevSC.x >= WIDTH || prevSC.y < 0 || prevSC.y >= HEIGHT)
        return false;

    float curDepth = imageLoad(curDepthImage, ivec2(gl_LaunchIDEXT.xy)).r;
    vec3 curNormal = decodeNormal(imageLoad(curNormalImage, ivec2(gl_LaunchIDEXT.xy)).xyz);

    float prevDepth = imageLoad(prevDepthImage, prevSC).r;
    vec3 prevNormal = decodeNormal(imageLoad(prevNormalImage, prevSC).xyz);

    if(abs(curDepth - prevDepth) > 0.05f)return false;
    if(dot(curNormal, prevNormal) < 0.906307787f)return false;
    return true;
}

ivec2 getPrevSC(uvec2 sc)
{
    vec2 uv = (vec2(sc) + 0.5f) / vec2(WIDTH, HEIGHT);
    vec2 prevUV = getPrevUV(uv);
    ivec2 prevSC = ivec2(prevUV * vec2(WIDTH, HEIGHT));
    return prevSC;
}

bool isGeometricSimilar(ivec2 curPixel, ivec2 prevPixel)
{
    // TODO: Implement
    // 注意判断prevPixel坐标是否越界
    return true;
}

uvec2 randomlyChooseNeighbor(uvec2 center, inout uint seed)
{
    // TODO: Implement
    // 需要保证结果在边界内
    return uvec2(center);
}

float calcJacobian(Reservoir q, Reservoir r)
{
    // TODO: Implement
    return 1.0f;
}

bool isVisibleAB(vec3 pos_a, vec3 pos_b)
{
    Ray ray;
    ray.origin = pos_a;
    ray.direction = normalize(pos_b - pos_a);
    ray.tmin = 0.001f;
    ray.tmax = 10000.0f;
    uint rayFlags = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsSkipClosestHitShaderEXT | gl_RayFlagsOpaqueEXT;
    hitValue.dis = 1.0f;
    traceRayEXT(topLevelAS, rayFlags, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);
    return hitValue.dis > 0.0f;
}

void main() {
    uvec2 pixel_q = gl_LaunchIDEXT.xy;
    uint idx_q = getCoord1D(pixel_q);
    Reservoir R_s = spatialReservoirBufferIn.data[idx_q];
    uint seed = getSeed();
    
    Reservoir Q[MAX_ITERATIONS];
    float p_qn_hat[MAX_ITERATIONS];
    
    uint cnt = 0;
    Q[cnt] = R_s;
    p_qn_hat[cnt++] = 1.0f;
    
    for(int i = 0; i < MAX_ITERATIONS; ++i){
        uvec2 pixel_qn = randomlyChooseNeighbor(pixel_q, seed);
        ivec2 prevPixel_qn = getPrevSC(pixel_qn);
        if(!isGeometricSimilar(ivec2(pixel_q), prevPixel_qn))
                continue;
        uint prevIdx_qn = getCoord1D(uvec2(prevPixel_qn));
        Reservoir R_n = temporalReservoirBufferIn.data[prevIdx_qn];
        float jacobian = calcJacobian(R_s, R_n);
        float pq_hat_prime = pq_hat(R_n.z) / jacobian;
        if(!isVisibleAB(R_s.z.x_v.xyz, R_n.z.x_s.xyz))
                pq_hat_prime = 0.0f;
        mergeReservoir(R_s, R_n, pq_hat_prime, seed);
        Q[cnt] = R_n;
        p_qn_hat[cnt++] = pq_hat_prime;
    }
    
    uint Z = 0;
    for(int i = 0; i < cnt; ++i){
        if(p_qn_hat[i] > 0) 
                Z = Z + Q[i].M;
    }
    R_s.W = R_s.W / (Z * pq_hat(R_s.z));
    spatialReservoirBufferOut.data[idx_q] = R_s;
}