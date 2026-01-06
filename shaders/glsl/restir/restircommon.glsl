// 先include "spcommon.glsl"
#define MAX_HISTORY 20
#define MAX_ITERATIONS 10
#define SPATIAL_RADIUS 30.0

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

void updateReservoir(inout Reservoir rDest, Sample s_new, float w_new, inout uint seed)
{
    rDest.w = rDest.w + w_new;
    rDest.M = rDest.M + 1;
    if(rnd(seed) < w_new / rDest.w){
        rDest.z = s_new;
    }
}

void mergeReservoir(inout Reservoir rDest, Reservoir rSrc, float p_hat, inout uint seed)
{
    uint M0 = rDest.M;
    updateReservoir(rDest, rSrc.z, p_hat * rSrc.W * rSrc.M, seed);
    rDest.M = M0 + rSrc.M;
}

float pq(Sample z)
{
    vec3 sampleDir = normalize(z.x_s.xyz - z.x_v.xyz);
    return max(dot(z.n_v.xyz, sampleDir), 0.0f) / M_PI;
}

float luminance(vec3 color)
{
    // 权重：R=0.2126, G=0.7152, B=0.0722
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float pq_hat(Sample z)
{
    return luminance(z.Lo.rgb);
}

float pq_hat(vec3 pos_q, vec3 norm_q, Sample s) {
    vec3 L = normalize(s.x_s.xyz - pos_q);
    if(dot(-L, s.n_s.xyz) < 0.0f) return 0.0f;
    float cosTheta = max(dot(norm_q, L), 0.0);
    return pq_hat(s) * cosTheta;
}
