#ifndef UTILS_GLSL
#define UTILS_GLSL
#include "Common.glsl"
vec3 getNormal01(vec3 v)
{
    v = (v + vec3(1.0)) * vec3(0.5);
    return v;
}

bool hasEmission(Material mat)
{
    return dot(mat.emission, vec3(1.0)) > 0.01;
}

vec3 getTriNormalFromTriPositions(vec3 triPositions[3])
{
    return normalize(cross(triPositions[1] - triPositions[0], triPositions[2] - triPositions[1]));
}

vec3 evalDiffuseBRDF(vec3 wi, vec3 wo, vec3 normal, Material mat)
{
    float cosalpha = dot(wo, normal);
    if(cosalpha > 0.0){
        return mat.baseColor.rgb / M_PI;
    }else{
        return vec3(0.0);
    }
}

vec3 evalDiffuseBRDF(vec3 wi, vec3 wo, vec3 normal, vec3 baseColor)
{
    float cosalpha = dot(wo, normal);
    return baseColor / M_PI * max(cosalpha, 0.f);
}

vec3 toWorld(vec3 a, vec3 n)
{
    vec3 b, c;
    if(abs(n.x) > abs(n.y)){
        float invLen = 1.0f / length(vec2(n.x, n.z));
        c = vec3(n.z * invLen, 0.0, -n.x * invLen);
    }else{
        float invLen = 1.0f / length(vec2(n.y, n.z));
        c = vec3(0.0, n.z * invLen, -n.y * invLen);
    }
    b = cross(c, n);
    return a.x * b + a.y * c + a.z * n;
}

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

void uniformSampleHemisphere(vec3 normal, inout uint seed, out vec3 sampleDir, out float pdf)
{
    float x_1 = rnd(seed);
    float x_2 = rnd(seed);
    float z = abs(1.0f - 2.0f * x_1);
    float r = sqrt(1.0f - z * z), phi = 2.0f * M_PI * x_2;
    vec3 localRay = vec3(r * cos(phi), r * sin(phi), z);
    sampleDir =  toWorld(localRay, normal);
    pdf = 1.0f / 2.0f / M_PI;
}

void cosineSampleHemisphere(vec3 normal, inout uint seed, out vec3 sampleDir, out float pdf)
{
    float r1 = rnd(seed);
    float r2 = rnd(seed);
    float r = sqrt(r1);
    float theta = 2.0 * M_PI * r2;

    // 在切线空间生成射线
    float x = r * cos(theta);
    float y = r * sin(theta);
    float z = sqrt(max(0.0, 1.0 - x*x - y*y)); // Z 轴对齐法线

    sampleDir = toWorld(vec3(x, y, z), normal);
    pdf = dot(sampleDir, normal) / M_PI;
}

void buildOrthonormalBasis(vec3 n, out vec3 t, out vec3 b)
{
    float sign = n.z >= 0.0 ? 1.0 : -1.0;
    float a = -1.0 / (sign + n.z);
    float b_val = n.x * n.y * a;

    t = vec3(1.0 + sign * n.x * n.x * a, sign * b_val, -sign * n.x);
    b = vec3(b_val, sign + n.y * n.y * a, -n.y);
}

void sampleSpecular(vec3 normal, vec3 incidentDir, out vec3 sampleDir, out float pdf)
{
    sampleDir = reflect(incidentDir, normal);
    pdf = 1.0f;
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

bool nearEqual(float a, float b, float eps)
{
    return abs(a - b) < eps;
}

bool isSpecularMat(Material mat)
{
    return nearEqual(mat.metallic, 1.0f, 0.00001f);
}

vec3 encodeNormal(vec3 v)
{
    v = (v + vec3(1.0)) * vec3(0.5);
    return v;
}

vec3 decodeNormal(vec3 v)
{
    v = v * 2.0f - 1.0f;
    return v;
}

DirectionalLight getGlobalDirectionalLight()
{
    DirectionalLight light;
    light.lightDir = -vec3(1.0, -1.0, 0.8);
    light.lightIntensity = vec3(6.0, 6.0, 6.0);
    return light;
}

/**
 * Rotate vector v with quaternion q.
 */
vec3 QuaternionRotate(vec3 v, vec4 q)
{
    vec3 b = q.xyz;
    float b2 = dot(b, b);
    return (v * (q.w * q.w - b2) + b * (dot(v, b) * 2.f) + cross(b, v) * (q.w * 2.f));
}

/**
 * Computes a low discrepancy spherically distributed direction on the unit sphere,
 * for the given index in a set of samples. Each direction is unique in
 * the set, but the set of directions is always the same.
 */
vec3 SphericalFibonacci(float sampleIndex, float numSamples)
{
    const float b = (sqrt(5.f) * 0.5f + 0.5f) - 1.f;
    float phi = M_2PI * fract(sampleIndex * b);
    float cosTheta = 1.f - (2.f * sampleIndex + 1.f) * (1.f / numSamples);
    float sinTheta = sqrt(clamp(1.f - (cosTheta * cosTheta), 0.f, 1.f));

    return vec3((cos(phi) * sinTheta), (sin(phi) * sinTheta), cosTheta);
}

/**
 * Quaternion conjugate.
 * For unit quaternions, conjugate equals inverse.
 * Use this to create a quaternion that rotates in the opposite direction.
 */
vec4 QuaternionConjugate(vec4 q)
{
    return vec4(-q.xyz, q.w);
}

float saturate(float v)
{
    return clamp(v, 0.f, 1.f);
}

vec3 saturate(vec3 v)
{
    return vec3(saturate(v.x), saturate(v.y), saturate(v.z));
}

/**
 * Returns the largest component of the vector.
 */
float MaxComponent(vec3 a)
{
    return max(a.x, max(a.y, a.z));
}

/**
 * Returns either -1 or 1 based on the sign of the input value.
 * If the input is zero, 1 is returned.
 */
float SignNotZero(float v)
{
    return (v >= 0.f) ? 1.f : -1.f;
}

/**
 * 2-component version of RTXGISignNotZero.
 */
vec2 SignNotZero(vec2 v)
{
    return vec2(SignNotZero(v.x), SignNotZero(v.y));
}

/**
 * Convert Linear RGB value to Luminance
 */
float LinearRGBToLuminance(vec3 rgb)
{
    const vec3 LuminanceWeights = vec3(0.2126, 0.7152, 0.0722);
    return dot(rgb, LuminanceWeights);
}
#endif