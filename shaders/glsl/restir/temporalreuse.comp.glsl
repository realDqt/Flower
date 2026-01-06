#version 460
#extension GL_GOOGLE_include_directive : require
#include "spcommon.glsl"
#include "restircommon.glsl"

layout(local_size_x = 16, local_size_y = 16) in;

layout(binding = 0, set = 0) buffer InitialSampleBufferBuffer{
    Reservoir data[];
} initialSampleBuffer;

layout(binding = 1, set = 0) buffer TemporalReservoirBufferIn{
    Reservoir data[];
} temporalReservoirBufferIn;

layout(binding = 2, set = 0) buffer TemporalReservoirBufferOut{
    Reservoir data[];
} temporalReservoirBufferOut;


layout(binding = 3, set = 0, r32f) readonly uniform image2D curDepthImage;
layout(binding = 4, set = 0, rgba32f) readonly uniform image2D curNormalImage;

layout(binding = 5, set = 0) uniform FrameData{
    mat4 currentInvViewProj;    // 当前帧矩阵信息
    mat4 prevViewProj;          // 上一帧矩阵信息
    uint frame;
} frameData;

layout(binding = 6, set = 0, r32f) readonly uniform image2D prevDepthImage;
layout(binding = 7, set = 0, rgba32f) readonly uniform image2D prevNormalImage;

vec2 getPrevUV(vec2 uv)
{
    ivec2 sc = ivec2(uv.x * float(WIDTH), uv.y * float(HEIGHT));
    float ndcZ = imageLoad(curDepthImage, sc).r;
    if(ndcZ >= 0.99f) return vec2(-1.0);
    
    vec2 ndcXY = uv * 2.0f - 1.0f;
    vec4 ndc = vec4(ndcXY, ndcZ, 1.0f);
    vec4 worldPos = frameData.currentInvViewProj * ndc;
    worldPos /= worldPos.w;
    vec4 prevClip = frameData.prevViewProj * worldPos;
    vec4 prevNDC = vec4(prevClip.xyz / prevClip.w, 1.0f);
    vec2 prevUV = (prevNDC.xy + 1.0f) * .5f;
    return prevUV;
}

uint getSeed()
{
    return tea(gl_GlobalInvocationID.y * gl_GlobalInvocationID.x + gl_GlobalInvocationID.x, frameData.frame);
}

bool isValidReprojection(ivec2 prevSC)
{
    if(prevSC.x < 0 || prevSC.x >= WIDTH || prevSC.y < 0 || prevSC.y >= HEIGHT)
            return false;
    
    float curDepth = imageLoad(curDepthImage, ivec2(gl_GlobalInvocationID.xy)).r;
    vec3 curNormal = decodeNormal(imageLoad(curNormalImage, ivec2(gl_GlobalInvocationID.xy)).xyz);
    
    float prevDepth = imageLoad(prevDepthImage, prevSC).r;
    vec3 prevNormal = decodeNormal(imageLoad(prevNormalImage, prevSC).xyz);
    
    if(abs(curDepth - prevDepth) > 0.05f)return false;
    if(dot(curNormal, prevNormal) < 0.906307787f)return false;
    return true;
}

void main() {
    uvec2 pixel = gl_GlobalInvocationID.xy;
    if (pixel.x >= WIDTH || pixel.y >= HEIGHT) return;
    uint idx = getCoord1D(pixel);
    uint seed = getSeed();

    vec2 uv = (vec2(pixel) + 0.5f) / vec2(WIDTH, HEIGHT);
    vec2 prevUV = getPrevUV(uv);
    
    Reservoir S = initialSampleBuffer.data[idx];

    if(prevUV.x >= 0.0) {
        ivec2 prevSC = ivec2(prevUV * vec2(WIDTH, HEIGHT));

        if(isValidReprojection(prevSC)) {
            uint prevIdx = getCoord1D(uvec2(prevSC));
            Reservoir R = temporalReservoirBufferIn.data[prevIdx];
            R.M = min(R.M, MAX_HISTORY);
            mergeReservoir(S, seed, R, pqHat(R));
        }
    }
    
    if (S.M > MAX_HISTORY) {
        S.w *= float(MAX_HISTORY) / float(S.M); // 必须等比缩放总权重
        S.M = MAX_HISTORY;
    }
    float p_hat = pqHat(S);
    if (p_hat <= 0.0 || S.M == 0) {
        S.W = 0.0;
        S.w = 0.0;
    } else {
        S.W = S.w / (float(S.M) * p_hat);
    }
    temporalReservoirBufferOut.data[idx] = S;
}