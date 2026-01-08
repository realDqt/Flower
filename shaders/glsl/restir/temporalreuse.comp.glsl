#version 460
#extension GL_GOOGLE_include_directive : require
#include "spcommon.glsl"
#include "restircommon.glsl"

layout(local_size_x = 16, local_size_y = 16) in;

layout(binding = 0, set = 0) buffer InitialSampleBuffer{
    Sample data[];
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
    if(frameData.frame == 0 || prevSC.x < 0 || prevSC.x >= WIDTH || prevSC.y < 0 || prevSC.y >= HEIGHT)
            return false;
    
    float curDepth = imageLoad(curDepthImage, ivec2(gl_GlobalInvocationID.xy)).r;
    vec3 curNormal = decodeNormal(imageLoad(curNormalImage, ivec2(gl_GlobalInvocationID.xy)).xyz);
    
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

void main() {
    //return;
    uvec2 pixel = gl_GlobalInvocationID.xy;
    if (pixel.x >= WIDTH || pixel.y >= HEIGHT) return;
    uint idx = getCoord1D(pixel);
    uint seed = getSeed();
    
    Sample S = initialSampleBuffer.data[idx];
    float w = pq_hat(S) / max(pq(S), 0.0001f);
    ivec2 prevSC = getPrevSC(pixel);
    bool validHistory = isValidReprojection(prevSC);

    Reservoir R;

    if(validHistory && frameData.frame > 0) {
        uint prevIdx = getCoord1D(uvec2(prevSC));
        R = temporalReservoirBufferIn.data[prevIdx];
        if(R.M > MAX_HISTORY) {
            R.w *= float(MAX_HISTORY) / float(R.M); 
            R.M = MAX_HISTORY;
        }
        updateReservoir(R, S, w, seed);
    }else {
        R.z = S;
        R.w = w;
        R.M = 1;
        R.W = 0.0f; 
    }
    
    float pHat = pq_hat(R.z);
    if(pHat <= 0.0f || R.M == 0) {
        R.W = 0.0f;
    } else {
        R.W = R.w / (float(R.M) * pHat);
    }
    temporalReservoirBufferOut.data[idx] = R;
}