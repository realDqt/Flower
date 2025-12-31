// 先include "spcommon.glsl"
struct Sample {
    vec4 x_v;
    vec4 n_v;
    vec4 x_s;
    vec4 n_s;
    vec4 Lo;       // .xyz = Lo, .w = unused
    uint Random;   // Offset 80
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
