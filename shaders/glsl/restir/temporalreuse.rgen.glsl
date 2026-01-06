#version 460
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_ray_tracing : require
#include "spcommon.glsl"
#include "restircommon.glsl"

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;

layout(binding = 1, set = 0) buffer InitialSampleBufferBuffer{
    Reservoir data[];
} initialSampleBuffer;

layout(binding = 2, set = 0) buffer TemporalReservoirBufferIn{
    Reservoir data[];
} temporalReservoirBufferIn;

layout(binding = 3, set = 0) buffer TemporalReservoirBufferOut{
    Reservoir data[];
} temporalReservoirBufferOut;


layout(binding = 4, set = 0, r32f) uniform image2D depthImage;
layout(binding = 5, set = 0, rgba32f) uniform image2D normalImage;

layout(binding = 6, set = 0) uniform FrameData{
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
    float ndcZ = imageLoad(depthImage, sc).r;
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

bool isValidReprojection(ivec2 prevSC, inout uint seed)
{
    if(frameData.frame == 0|| prevSC.x < 0 || prevSC.x >= WIDTH || prevSC.y < 0 || prevSC.y >= HEIGHT) return false;

    Ray ray = getRayFromCamera(0.001, 10000.0, seed, true);
    traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);
    if(hitValue.dis < 0.0f) return false;
    float cosTheta =  max(dot(ray.direction, frameData.forward.xyz), 0.0f);
    cosTheta = 1.0f;
    float curDepth = calcNDCZ(hitValue.dis * cosTheta, frameData.zNear, frameData.zFar);
    vec3 curNormal = hitValue.worldNormal;

    float prevDepth = imageLoad(depthImage, prevSC).r;
    vec3 prevNormal = decodeNormal(imageLoad(normalImage, prevSC).xyz);

    if(abs(curDepth - prevDepth) > 0.05f)return false;
    if(dot(curNormal, prevNormal) < 0.906307787f)return false;
    return true;
}

void main() {
    uvec2 pixel = gl_LaunchIDEXT.xy;
    if (pixel.x >= WIDTH || pixel.y >= HEIGHT) return;
    uint idx = getCoord1D(pixel);
    uint seed = getSeed();

    vec2 uv = (vec2(pixel) + 0.5f) / vec2(WIDTH, HEIGHT);
    vec2 prevUV = getPrevUV(uv);

    Reservoir S = initialSampleBuffer.data[idx];

    if(prevUV.x >= 0.0) {
        ivec2 prevSC = ivec2(prevUV * vec2(WIDTH, HEIGHT));

        if(isValidReprojection(prevSC, seed)) {
            uint prevIdx = getCoord1D(uvec2(prevSC));
            Reservoir R = temporalReservoirBufferIn.data[prevIdx];
            R.M = min(R.M, MAX_HISTORY);
            mergeReservoir(S, R, pq_hat(R), seed);
        }
    }

    if (S.M > MAX_HISTORY) {
        S.w *= float(MAX_HISTORY) / float(S.M); // 必须等比缩放总权重
        S.M = MAX_HISTORY;
    }
    float p_hat = pq_hat(S);
    if (p_hat <= 0.0 || S.M == 0) {
        S.W = 0.0;
        S.w = 0.0;
    } else {
        S.W = S.w / (float(S.M) * p_hat);
    }
    temporalReservoirBufferOut.data[idx] = S;
}