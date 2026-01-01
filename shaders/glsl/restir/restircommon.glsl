// 先include "spcommon.glsl"
struct Sample {
    vec4 x_v;
    vec4 n_v;
    vec4 x_s;
    vec4 n_s;
    vec4 Lo;       // .xyz = Lo, .w = unused
    vec4 baseColor_v;
    uint Random;   // Offset 96
    uint _pad[3];  // 显式占位，防止隐式 padding
};

struct Reservoir {
    Sample z;
    float w;
    uint M;
    float W;
    uint _pad;
};

void UpdateReservoir(inout Reservoir rDest, inout uint seed, Sample s_new, float w_new)
{
    rDest.w = rDest.w + w_new;
    rDest.M = rDest.M + 1;
    if(rnd(seed) < w_new / rDest.w){
        rDest.z = s_new;
    }
}

void MergeReservoir(inout Reservoir rDest, inout uint seed, Reservoir rSrc, float p_hat)
{
    uint M0 = rDest.M;
    UpdateReservoir(rDest, seed, rSrc.z, p_hat * rSrc.W * rSrc.M);
    rDest.M = M0 + rSrc.M;
}

float pq(Reservoir r)
{
    vec3 sampleDir = normalize(r.z.x_s.xyz - r.z.x_v.xyz);
    return max(dot(r.z.n_v.xyz, sampleDir), 0.0f) / M_PI;
}

float luminance(vec3 color)
{
    // 权重：R=0.2126, G=0.7152, B=0.0722
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float pqHat(Reservoir r)
{
    return luminance(r.z.Lo.rgb);
}
